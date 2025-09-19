import os
import hashlib
import sys
import json
import time
from urllib.parse import urlparse, urlunparse

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

print(get_cache_filename(sys.argv[1]))
