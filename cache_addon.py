# version 0.0.4 - Robust writes + filename-based caching for Arch/Ubuntu package data

import os
import re
import hashlib
import json
import time
import threading
from urllib.parse import urlparse, urlunparse
from mitmproxy import http
from mitmproxy.http import Response

# Use absolute cache dir; allow override via env
CACHE_DIR = os.path.abspath(os.environ.get("CACHE_DIR", "./the_cache_dir"))

# ------------------------------------------------------------------------------
# Helpers for "cache by filename" coverage
# ------------------------------------------------------------------------------

# Arch repo db/files patterns: core.db, extra.files, community.db.tar.gz, ... with optional .sig
_ARCH_DB_RE = re.compile(
    r'^(core|extra|community|multilib)\.(db|files)'
    r'(?:\.tar\.(gz|xz|zst))?'
    r'(?:\.sig)?$',
    re.IGNORECASE,
)

# Recognize Debian/Ubuntu APT metadata basenames (with optional compression)
# e.g. Packages, Packages.gz, Packages.xz, Sources{,.gz,.xz}, Contents-*.gz, etc.,
# plus Release / InRelease / Release.gpg.
_APT_META_BASE = (
    "release", "inrelease", "release.gpg",
)
_APT_PREFIXES = (
    "packages", "sources", "contents-",
)
_COMPRESSED_SUFFIXES = ("", ".gz", ".xz", ".bz2", ".lz4", ".zst")

# File extensions that should always be cached by filename (package artifacts)
_ALWAYS_BY_FILENAME_EXTS = (
    ".rpm",
    ".deb", ".ddeb",
    ".pkg.tar.zst", ".pkg.tar.zst.sig",
    ".sig",  # keep .sig by filename (common for both Arch & APT)
)

def _is_arch_or_apt_filename(url_norm: str) -> bool:
    """
    Decide whether this URL points to Arch/Ubuntu package data we want to cache by filename.
    """
    path = urlparse(url_norm).path
    bn = os.path.basename(path)
    bn_l = bn.lower()

    # 1) Obvious artifacts by extension
    for ext in _ALWAYS_BY_FILENAME_EXTS:
        if bn_l.endswith(ext):
            return True

    # 2) Arch repository DB/files family (with optional tar.* and .sig)
    if _ARCH_DB_RE.match(bn_l):
        return True

    # 3) APT metadata: Release/InRelease/Release.gpg
    if bn_l in _APT_META_BASE:
        return True

    # 4) APT metadata: Packages*, Sources*, Contents-*, possibly compressed
    # We match basenames starting with our prefixes and ending with any known compression suffix (or none).
    for prefix in _APT_PREFIXES:
        if bn_l.startswith(prefix):
            # No further filter: filename-only caching as requested
            # (beware: "Packages.gz" collisions across different suites/arches are possible)
            return True

    return False

# ------------------------------------------------------------------------------
# Core cache helpers
# ------------------------------------------------------------------------------

# Per-URL locks to avoid concurrent writes
_locks = {}
_locks_guard = threading.Lock()
def _lock_for(key: str) -> threading.Lock:
    h = hashlib.sha256(key.encode()).hexdigest()
    with _locks_guard:
        if h not in _locks:
            _locks[h] = threading.Lock()
        return _locks[h]

def normalize_url(url: str) -> str:
    parsed = urlparse(url)
    # drop fragments; leave query intact
    path = parsed.path or ""
    if path.endswith("/"):
        path += "index.html"
    new_parsed = parsed._replace(path=path, fragment="")
    return urlunparse(new_parsed)

def _hashed_name(url_norm: str, suffix: str) -> str:
    """
    Return the on-disk name (without directory) for a given normalized URL.

    For Arch & Ubuntu package data we cache by filename to maximize reuse across mirrors.
    For everything else we use a hash of the full URL.
    """
    parsed = urlparse(url_norm)
    filename = os.path.basename(parsed.path)

    if _is_arch_or_apt_filename(url_norm):
        # Cache by filename only (risk of collisions is accepted per user request).
        return f"{filename}{suffix}"

    # Fallback: URL-hash-based name
    return f"{hashlib.sha256(url_norm.encode()).hexdigest()}{suffix}"

def cache_path(url: str) -> str:
    return os.path.join(CACHE_DIR, _hashed_name(normalize_url(url), ".cache"))

def headers_path(url: str) -> str:
    return os.path.join(CACHE_DIR, _hashed_name(normalize_url(url), ".headers.json"))

def _ensure_parent(path: str):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent, exist_ok=True)

# ------------------------------------------------------------------------------
# Addon
# ------------------------------------------------------------------------------

class CacheAddon:
    def __init__(self):
        self.cache_dir = CACHE_DIR
        os.makedirs(self.cache_dir, exist_ok=True)  # ensure at init
        print(f"[CACHE ADDON] Initialized with cache dir: {self.cache_dir}")

    def client_connected(self, client):
        print(f"[CLIENT CONNECT] {client.peername} connected at {time.strftime('%H:%M:%S')}")

    def client_disconnected(self, client):
        print(f"[CLIENT DISCONNECT] {client.peername} disconnected at {time.strftime('%H:%M:%S')}")

    def server_connected(self, data):
        print(f"[SERVER CONNECT] Successfully connected to {data.server.peername} at {time.strftime('%H:%M:%S')}")

    def error(self, flow):
        print(f"[ERROR] {flow.error} at {time.strftime('%H:%M:%S')}")
        if hasattr(flow, 'request') and flow.request:
            print(f"[ERROR] Request was: {flow.request.method} {flow.request.url}")

    def request(self, flow: http.HTTPFlow):
        if flow.request.method.upper() != "GET":
            print(f"[NON-GET] Skipping {flow.request.method} {flow.request.url}")
            return

        url_norm = normalize_url(flow.request.url)
        body_path = cache_path(flow.request.url)
        hdrs_path = headers_path(flow.request.url)

        print(f"[REQUEST] {time.strftime('%H:%M:%S')} Checking cache: {url_norm}")
        print(f"[REQUEST] Cache path: {body_path}")

        if os.path.exists(body_path) and os.path.exists(hdrs_path):
            try:
                with open(body_path, "rb") as f:
                    cached_data = f.read()
                with open(hdrs_path, "r") as f:
                    cached_headers = json.load(f)

                # Normalize headers and mark HIT
                cached_headers = {k: v for k, v in cached_headers.items()}
                cached_headers["x-cache-status"] = "HIT"

                flow.response = Response.make(200, cached_data, cached_headers)
                flow.metadata["from_cache"] = True
                print(f"[CACHE HIT] {url_norm} ({len(cached_data)} bytes)")
                return
            except Exception as e:
                print(f"[CACHE ERROR] Read failed for {url_norm}: {e} — fetching from server")

        print(f"[CACHE MISS] {url_norm} — fetching from server")

    def response(self, flow: http.HTTPFlow):
        if flow.request.method.upper() != "GET":
            return

        if flow.metadata.get("from_cache", False):
            print(f"[CACHE] Skipping re-cache for {flow.request.url}")
            return

        if not flow.response:
            return

        if flow.response.status_code != 200:
            print(f"[RESPONSE] Non-200 {flow.response.status_code} for {flow.request.url} — not caching")
            return

        url_norm = normalize_url(flow.request.url)
        body_path = cache_path(flow.request.url)
        hdrs_path = headers_path(flow.request.url)
        lock = _lock_for(url_norm)

        print(f"[RESPONSE] {time.strftime('%H:%M:%S')} Caching: {url_norm} ({len(flow.response.content)} bytes)")

        try:
            with lock:
                # Ensure parent dir for both tmp files (robust against pruning/races)
                tmp_body = body_path + ".tmp"
                _ensure_parent(tmp_body)
                with open(tmp_body, "wb") as f:
                    f.write(flow.response.content)
                os.replace(tmp_body, body_path)

                headers_to_save = dict(flow.response.headers)
                # Strip hop-by-hop headers
                for h in ["Content-Length", "Transfer-Encoding", "Connection", "Keep-Alive",
                          "Proxy-Authenticate", "Proxy-Authorization", "TE", "Trailer", "Upgrade"]:
                    headers_to_save.pop(h, None)
                headers_to_save["x-cache-status"] = "MISS"

                tmp_hdrs = hdrs_path + ".tmp"
                _ensure_parent(tmp_hdrs)
                with open(tmp_hdrs, "w") as f:
                    json.dump(headers_to_save, f)
                os.replace(tmp_hdrs, hdrs_path)

                flow.response.headers["x-cache-status"] = "MISS"
                print(f"[CACHE SAVED] {url_norm}")
        except Exception as e:
            print(f"[CACHE ERROR] Write failed for {url_norm}: {e}")

addons = [CacheAddon()]

