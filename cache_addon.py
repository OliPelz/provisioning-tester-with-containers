# version 0.1.0 — Safe cache keys for APT & Arch + robust writes

import os
import re
import hashlib
import json
import time
import threading
from urllib.parse import urlparse, urlunparse
from mitmproxy import http
from mitmproxy.http import Response

# Config -----------------------------------------------------------------------
CACHE_DIR = os.path.abspath(os.environ.get("CACHE_DIR", "./the_cache_dir"))
os.makedirs(CACHE_DIR, exist_ok=True)

# Patterns ---------------------------------------------------------------------
# Arch repo db/files like: .../<repo>/os/<arch>/(core|extra|community|multilib).(db|files)[.tar.{gz,xz,zst}][.sig]
_ARCH_REPO_RE = re.compile(
    r"/(?P<repo>core|extra|community|multilib)/os/(?P<arch>[^/]+)/(?P<file>(?:core|extra|community|multilib)\.(?:db|files)(?:\.tar\.(?:gz|xz|zst))?(?:\.sig)?)$",
    re.IGNORECASE,
)

# APT metadata basenames (case-insensitive)
_APT_META_BASE = {"release", "inrelease", "release.gpg"}
_APT_META_PREFIXES = ("packages", "sources", "contents-")
_COMPRESSED_SUFFIXES = ("", ".gz", ".xz", ".bz2", ".lz4", ".zst")

# Artifacts that are safe to cache by filename
_ALWAYS_BY_FILENAME_EXTS = (
    ".deb", ".ddeb",
    ".rpm",
    ".pkg.tar.zst", ".pkg.tar.zst.sig",
    ".sig",
)

# Locks ------------------------------------------------------------------------
_locks = {}
_locks_guard = threading.Lock()
def _lock_for(key: str) -> threading.Lock:
    h = hashlib.sha256(key.encode()).hexdigest()
    with _locks_guard:
        if h not in _locks:
            _locks[h] = threading.Lock()
        return _locks[h]

# Helpers ----------------------------------------------------------------------
def normalize_url(url: str) -> str:
    p = urlparse(url)
    path = p.path or ""
    if path.endswith("/"):
        path += "index.html"
    return urlunparse(p._replace(path=path, fragment=""))

def _sha(url_norm: str) -> str:
    return hashlib.sha256(url_norm.encode("utf-8")).hexdigest()

def _ensure_parent(path: str):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent, exist_ok=True)

def _is_pkg_artifact(basename_lower: str) -> bool:
    return any(basename_lower.endswith(ext) for ext in _ALWAYS_BY_FILENAME_EXTS)

def _is_apt_metadata_basename(basename_lower: str) -> bool:
    if basename_lower in _APT_META_BASE:
        return True
    for pref in _APT_META_PREFIXES:
        if basename_lower.startswith(pref):
            # suffix check optional — allow any compression/no-compression
            return True
    return False

def _apt_rel_subpath(path: str) -> str | None:
    """
    Return a safe cache subpath for APT metadata:
      - Prefer path under '.../dists/...'
      - Keep 'by-hash/...' intact (unique)
    Returns None if not an apt dists path.
    """
    low = path.lower()
    i = low.find("/dists/")
    if i == -1:
        return None
    return path[i+1:]  # drop leading slash, keep 'dists/...'

def _arch_rel_subpath(path: str) -> str | None:
    """
    Return 'arch/<repo>/<arch>/<file>' for Arch db/files, else None.
    """
    m = _ARCH_REPO_RE.search(path)
    if not m:
        return None
    repo = m.group("repo")
    arch = m.group("arch")
    file = m.group("file")
    return os.path.join("arch", repo, arch, file)

def _cache_relpath_for(url_norm: str) -> str:
    """
    Build a relative path (under CACHE_DIR) that avoids APT basename collisions
    but still allows reuse across mirrors for safe cases.
    """
    p = urlparse(url_norm)
    path = p.path or "/"
    bn = os.path.basename(path)
    bn_l = bn.lower()

    # 1) Package artifacts: by filename only (versioned).
    if _is_pkg_artifact(bn_l):
        return os.path.join("pkg", bn)

    # 2) Arch repo db/files: repo+arch+filename
    arch_rel = _arch_rel_subpath(path)
    if arch_rel:
        return arch_rel

    # 3) APT metadata under /dists/...
    #    - by-hash paths unique already
    #    - other metadata: use the subpath under /dists/ to encode suite/component/arch
    if _is_apt_metadata_basename(bn_l) or any(bn_l.startswith(pref) for pref in _APT_META_PREFIXES):
        apt_rel = _apt_rel_subpath(path)
        if apt_rel:
            return os.path.join("apt", apt_rel)

    # 4) Fallback: hash of full normalized URL
    return os.path.join("misc", _sha(url_norm))

def _body_path(url: str) -> str:
    return os.path.join(CACHE_DIR, _cache_relpath_for(normalize_url(url)) + ".cache")

def _headers_path(url: str) -> str:
    return os.path.join(CACHE_DIR, _cache_relpath_for(normalize_url(url)) + ".headers.json")

# Addon ------------------------------------------------------------------------
class CacheAddon:
    def __init__(self):
        self.cache_dir = CACHE_DIR
        os.makedirs(self.cache_dir, exist_ok=True)
        print(f"[CACHE ADDON] Initialized with cache dir: {self.cache_dir}")

    # Log helpers
    def client_connected(self, client):
        print(f"[CLIENT CONNECT] {client.peername} connected at {time.strftime('%H:%M:%S')}")

    def client_disconnected(self, client):
        print(f"[CLIENT DISCONNECT] {client.peername} disconnected at {time.strftime('%H:%M:%S')}")

    def server_connected(self, data):
        try:
            peer = getattr(data.server, "peername", None)
            print(f"[SERVER CONNECT] Successfully connected to {peer} at {time.strftime('%H:%M:%S')}")
        except Exception:
            pass

    def error(self, flow):
        print(f"[ERROR] {flow.error} at {time.strftime('%H:%M:%S')}")
        if hasattr(flow, "request") and flow.request:
            print(f"[ERROR] Request was: {flow.request.method} {flow.request.url}")

    def request(self, flow: http.HTTPFlow):
        if flow.request.method.upper() != "GET":
            return

        url_norm = normalize_url(flow.request.url)
        body_path = _body_path(flow.request.url)
        hdrs_path = _headers_path(flow.request.url)

        print(f"[REQUEST] {time.strftime('%H:%M:%S')} Checking cache: {url_norm}")
        print(f"[REQUEST] Cache path: {body_path}")

        if os.path.exists(body_path) and os.path.exists(hdrs_path):
            try:
                with open(body_path, "rb") as f:
                    cached_data = f.read()
                with open(hdrs_path, "r") as f:
                    cached_headers = json.load(f)

                # Keep server headers except hop-by-hop; add HIT marker
                headers = {k: v for k, v in cached_headers.items()}
                headers["x-cache-status"] = "HIT"

                flow.response = Response.make(200, cached_data, headers)
                flow.metadata["from_cache"] = True
                print(f"[CACHE HIT] {url_norm} ({len(cached_data)} bytes)")
                return
            except Exception as e:
                print(f"[CACHE ERROR] Read failed for {url_norm}: {e} — fetching from server")

        print(f"[CACHE MISS] {url_norm} — fetching from server")

    def response(self, flow: http.HTTPFlow):
        if flow.request.method.upper() != "GET":
            return
        if not flow.response:
            return
        if flow.metadata.get("from_cache", False):
            print(f"[CACHE] Skipping re-cache for {flow.request.url}")
            return
        if flow.response.status_code != 200:
            print(f"[RESPONSE] Non-200 {flow.response.status_code} for {flow.request.url} — not caching")
            return

        url_norm = normalize_url(flow.request.url)
        body_path = _body_path(flow.request.url)
        hdrs_path = _headers_path(flow.request.url)
        lock = _lock_for(url_norm)

        content = flow.response.get_content(strict=False)  # safe for encoded bodies

        print(f"[RESPONSE] {time.strftime('%H:%M:%S')} Caching: {url_norm} ({len(content)} bytes)")
        try:
            with lock:
                # Body (atomic)
                tmp_body = body_path + ".tmp"
                _ensure_parent(tmp_body)
                with open(tmp_body, "wb") as f:
                    f.write(content)
                os.replace(tmp_body, body_path)

                # Headers (atomic) — preserve server headers, strip hop-by-hop
                headers_to_save = dict(flow.response.headers)
                for h in [
                    "Content-Length", "Transfer-Encoding", "Connection", "Keep-Alive",
                    "Proxy-Authenticate", "Proxy-Authorization", "TE", "Trailer", "Upgrade",
                ]:
                    headers_to_save.pop(h, None)
                headers_to_save["x-cache-status"] = "MISS"

                tmp_hdrs = hdrs_path + ".tmp"
                _ensure_parent(tmp_hdrs)
                with open(tmp_hdrs, "w") as f:
                    json.dump(headers_to_save, f)
                os.replace(tmp_hdrs, hdrs_path)

                # Mark outgoing response
                flow.response.headers["x-cache-status"] = "MISS"
                print(f"[CACHE SAVED] {url_norm}")
        except Exception as e:
            print(f"[CACHE ERROR] Write failed for {url_norm}: {e}")

addons = [CacheAddon()]

