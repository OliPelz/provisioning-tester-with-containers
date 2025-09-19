# version 0.0.2 - Enhanced with debugging
import os
import hashlib
import json
import time
from urllib.parse import urlparse, urlunparse
from mitmproxy import http
from mitmproxy.http import Response

CACHE_DIR = "./the_cache_dir"
os.makedirs(CACHE_DIR, exist_ok=True)
SPECIAL_EXTENSIONS = [".rpm"]  # Add more extensions here if needed

def normalize_url(url: str) -> str:
    parsed = urlparse(url)
    path = parsed.path
    if path == "" or path.endswith("/"):
        path = path + "index.html"
    new_parsed = parsed._replace(path=path, fragment="")
    return urlunparse(new_parsed)

def get_cache_filename(url: str) -> str:
    url_norm = normalize_url(url)
    parsed = urlparse(url_norm)
    filename = os.path.basename(parsed.path)
    if any(filename.lower().endswith(ext.lower()) for ext in SPECIAL_EXTENSIONS):
        return filename + ".cache"
    else:
        h = hashlib.sha256(url_norm.encode()).hexdigest()
        return f"{h}.cache"

def get_headers_filename(url: str) -> str:
    url_norm = normalize_url(url)
    parsed = urlparse(url_norm)
    filename = os.path.basename(parsed.path)
    if any(filename.lower().endswith(ext.lower()) for ext in SPECIAL_EXTENSIONS):
        return filename + ".headers.json"
    else:
        h = hashlib.sha256(url_norm.encode()).hexdigest()
        return f"{h}.headers.json"

def cache_path(url: str) -> str:
    return os.path.join(CACHE_DIR, get_cache_filename(url))

def headers_path(url: str) -> str:
    return os.path.join(CACHE_DIR, get_headers_filename(url))

class CacheAddon:
    def __init__(self):
        self.cache_dir = CACHE_DIR
        print(f"[CACHE ADDON] Initialized with cache dir: {self.cache_dir}")
    
    def client_connected(self, client):
        print(f"[CLIENT CONNECT] {client.peername} connected at {time.strftime('%H:%M:%S')}")

    def client_disconnected(self, client):  
        print(f"[CLIENT DISCONNECT] {client.peername} disconnected at {time.strftime('%H:%M:%S')}")

    def server_connected(self, data):
        print(f"[SERVER CONNECT] Successfully connected to {data.server.peername} at {time.strftime('%H:%M:%S')}") 
    def error(self, flow):
        """Log any errors that occur"""
        print(f"[ERROR] {flow.error} at {time.strftime('%H:%M:%S')}")
        if hasattr(flow, 'request') and flow.request:
            print(f"[ERROR] Request was: {flow.request.method} {flow.request.url}")
    
    def request(self, flow: http.HTTPFlow):
        if flow.request.method.upper() != "GET":
            print(f"[NON-GET] Skipping {flow.request.method} request to {flow.request.url}")
            return
        
        url_norm = normalize_url(flow.request.url)
        path = cache_path(flow.request.url)
        headers_file = headers_path(flow.request.url)
        
        print(f"[REQUEST] {time.strftime('%H:%M:%S')} Checking cache for URL: {url_norm}")
        print(f"[REQUEST] Cache path: {path}")
        
        if os.path.exists(path) and os.path.exists(headers_file):
            try:
                with open(path, "rb") as f:
                    cached_data = f.read()
                with open(headers_file, "r") as f:
                    cached_headers = json.load(f)
                
                cached_headers["x-cache-status"] = "HIT"
                flow.response = Response.make(
                    200,
                    cached_data,
                    cached_headers
                )
                flow.metadata["from_cache"] = True  # Flag to skip caching again
                print(f"[CACHE HIT] {url_norm} - Served from cache ({len(cached_data)} bytes)")
                return  # Stop the request from going to server
            
            except (OSError, IOError, json.JSONDecodeError) as e:
                print(f"[CACHE ERROR] Error reading cache for {url_norm}: {e}")
                # Continue to fetch from server if cache read fails
        
        print(f"[CACHE MISS] {url_norm} - Will fetch from server")
    
    def response(self, flow: http.HTTPFlow):
        if flow.request.method.upper() != "GET":
            return
        
        # Use dict get, not getattr, to check flag
        if flow.metadata.get("from_cache", False):
            # This response was served from cache — skip re-caching
            print(f"[CACHE] Skipping re-caching for {flow.request.url}")
            return
        
        if flow.response and flow.response.status_code == 200:
            url_norm = normalize_url(flow.request.url)
            path = cache_path(flow.request.url)
            headers_file = headers_path(flow.request.url)
            
            print(f"[RESPONSE] {time.strftime('%H:%M:%S')} Caching response for URL: {url_norm}")
            print(f"[RESPONSE] Status: {flow.response.status_code}, Size: {len(flow.response.content)} bytes")
            
            try:
                # Ensure directory exists
                os.makedirs(os.path.dirname(path), exist_ok=True)
                
                with open(path, "wb") as f:
                    f.write(flow.response.content)
                
                headers_to_save = dict(flow.response.headers)
                for h in ["Content-Length", "Transfer-Encoding", "Connection", "Keep-Alive",
                          "Proxy-Authenticate", "Proxy-Authorization", "TE", "Trailers", "Upgrade"]:
                    headers_to_save.pop(h, None)
                headers_to_save["x-cache-status"] = "MISS"
                
                with open(headers_file, "w") as f:
                    json.dump(headers_to_save, f)
                
                flow.response.headers["x-cache-status"] = "MISS"
                print(f"[CACHE SAVED] Successfully cached {url_norm}")
            
            except (OSError, IOError) as e:
                print(f"[CACHE ERROR] Error caching response for {url_norm}: {e}")
                # Continue without caching if write fails
        elif flow.response:
            print(f"[RESPONSE] Non-200 status {flow.response.status_code} for {flow.request.url} - not caching")

addons = [
    CacheAddon()
]
