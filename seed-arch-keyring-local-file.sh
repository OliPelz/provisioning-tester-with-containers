#!/usr/bin/env bash
set -Eeuo pipefail

: '
seed-arch-keyring-local-file.sh

ShortDesc:
  Install archlinux-keyring from a local *.pkg.tar.zst file (no network).
  Optionally perform a normal pacman -Sy / -Syyu afterwards (proxy/CA aware).

PARAMETERS
  --pkg <path>               Path to archlinux-keyring*.pkg.tar.zst (required unless a positional path is given)
  [positional <path>]        You may also pass the package path as the first positional argument
  --also-update              After local install, run: pacman -Sy archlinux-keyring && pacman -Syyu
  --load-env-file <path>     Source env before running (overrides current env), useful for proxy/CA vars
  -h|--help                  Show this help

Honors environment (only used if you pass --also-update):
  MY_PROXY_URL               e.g. http://proxy:3128
  MY_NO_PROXY_STR            e.g. 127.0.0.1,localhost
  USE_MITM_INTERCEPT_PROXY_CERT  "true" or "1" → extract leaf cert via proxy for curl/pacman XferCommand
  MY_DISABLE_IPV6_BOOL       "true" or "1" → curl/pacman XferCommand uses IPv4

What it does:
  1) Create a temp pacman.conf with:
       LocalFileSigLevel = Optional TrustAll
     so a *local file* keyring can be installed without preexisting keys.
     without LocalFileSigLevel we cannot install it because it will not be allowed.
  2) pacman --config <temp> -U <your .pkg.tar.zst> --noconfirm
  3) If --also-update:
       Create another temp pacman.conf injecting curl-based XferCommand that
       honors proxy/CA/IPv4 knobs, then:
         pacman --config <temp-net> -Sy archlinux-keyring
         pacman --config <temp-net> -Syyu

Exit codes:
  0 on success; non-zero on failure.
'

log() { printf '[seed-local-file] %s\n' "$*" >&2; }
err() { printf '[seed-local-file][ERROR] %s\n' "$*" >&2; }

# ---------------- arg parsing ----------------
PKG_PATH=""
ALSO_UPDATE=0
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkg)           PKG_PATH="${2:-}"; shift 2 ;;
    --also-update)   ALSO_UPDATE=1; shift ;;
    --load-env-file)
      ENV_FILE="${2:-}"; shift 2 ;;
    --load-env-file=*)
      ENV_FILE="${1#*=}"; shift ;;
    -h|--help)
      sed -n '1,/^$/p' "$0"; exit 0 ;;
    *)
      # first non-flag becomes positional package path (if not set)
      if [[ -z "$PKG_PATH" ]]; then PKG_PATH="$1"; shift; else log "Ignoring arg: $1"; shift; fi
      ;;
  esac
done

# ---------- load env file first (optional) ----------
if [[ -n "$ENV_FILE" ]]; then
  [[ -r "$ENV_FILE" ]] || { err "--load-env-file: unreadable '$ENV_FILE'"; exit 2; }
  log "Loading env from $ENV_FILE (overrides current environment)"
  set -a; set +u; . "$ENV_FILE"; set -u; set +a
fi

# ---------- validate package path ----------
if [[ -z "${PKG_PATH:-}" ]]; then
  err "Missing package path. Use: --pkg /opt/archlinux-keyring.pkg.tar.zst  (or pass it as positional arg)"
  exit 2
fi
[[ -f "$PKG_PATH" ]] || { err "Package file not found: $PKG_PATH"; exit 2; }

# ---------- temp files + cleanup ----------
TMP_PACCONF_LOCAL=""
TMP_PACCONF_NET=""
TMP_CA=""

cleanup() {
  [[ -n "${TMP_PACCONF_LOCAL:-}" && -f "${TMP_PACCONF_LOCAL:-}" ]] && rm -f "${TMP_PACCONF_LOCAL}" || true
  [[ -n "${TMP_PACCONF_NET:-}"   && -f "${TMP_PACCONF_NET:-}"   ]] && rm -f "${TMP_PACCONF_NET}"   || true
  [[ -n "${TMP_CA:-}"            && -f "${TMP_CA:-}"            ]] && rm -f "${TMP_CA}"            || true
}
trap cleanup EXIT

# ---------- build local-only pacman.conf ----------
make_temp_pacman_conf_local() {
  TMP_PACCONF_LOCAL="$(mktemp)"
  cat >"$TMP_PACCONF_LOCAL" <<'EOF'
[options]
# Relax local file signature checks ONLY for this run:
LocalFileSigLevel = Optional TrustAll
SigLevel = Required DatabaseOptional
EOF
  printf '%s\n' "$TMP_PACCONF_LOCAL"
}

# ---------- optional: build net pacman.conf honoring proxy/CA/IPv4 ----------
make_temp_pacman_conf_net() {
  TMP_PACCONF_NET="$(mktemp)"
  # Prepare curl flags for pacman XferCommand
  local -a cf=(-L -C - --retry 3 --retry-delay 3 --connect-timeout 600 --max-time 600)
  [[ "${MY_DISABLE_IPV6_BOOL:-}" =~ ^(true|1)$ ]] && cf+=(--ipv4)
  [[ -n "${MY_PROXY_URL:-}"    ]] && cf=(--proxy "${MY_PROXY_URL}" "${cf[@]}")

  # --- NEW: optional MITM cert extraction via proxy (uses extract_cert_via_proxy) ---
  if [[ "${USE_MITM_INTERCEPT_PROXY_CERT:-}" =~ ^([Tt][Rr][Uu][Ee]|1)$ ]] && [[ -n "${MY_PROXY_URL:-}" ]]; then
    # strip scheme for openssl s_client -proxy
    local _px="${MY_PROXY_URL#http://}"; _px="${_px#https://}"
    # try to detect a probe site from mirrorlist, else fallback
    local _site=""
    if [[ -r /etc/pacman.d/mirrorlist ]]; then
      _site="$(awk '/^[[:space:]]*Server[[:space:]]*=/ {print $3; exit}' /etc/pacman.d/mirrorlist 2>/dev/null || true)"
    fi
    [[ -z "$_site" ]] && _site="https://geo.mirror.pkgbuild.com"

    if type extract_cert_via_proxy >/dev/null 2>&1; then
      if TMP_CA="$(extract_cert_via_proxy "$_site" "$_px")"; then
        chmod 600 "$TMP_CA" || true
        cf=(--cacert "${TMP_CA}" "${cf[@]}")
        log "Injected --cacert from MITM-extracted cert for XferCommand"
      else
        log "extract_cert_via_proxy failed; continuing without --cacert"
      fi
    else
      log "extract_cert_via_proxy not found in PATH; continuing without --cacert"
    fi
  fi
  # ---------------------------------------------------------------------------

  {
    echo "[options]"
    echo "SigLevel = Required DatabaseOptional"
    echo "# Injected by seed-arch-keyring-local-file"
    echo "XferCommand = /usr/bin/curl ${cf[*]} -o %o %u"
  } >"$TMP_PACCONF_NET"

  # Also export proxy envs so libcurl/child tools see them
  if [[ -n "${MY_PROXY_URL:-}" ]]; then
    export http_proxy="$MY_PROXY_URL" https_proxy="$MY_PROXY_URL" HTTP_PROXY="$MY_PROXY_URL" HTTPS_PROXY="$MY_PROXY_URL"
    log "Proxy exported from MY_PROXY_URL=$MY_PROXY_URL"
  fi
  if [[ -n "${MY_NO_PROXY_STR:-}" ]]; then
    export no_proxy="$MY_NO_PROXY_STR" NO_PROXY="$MY_NO_PROXY_STR"
    log "NO_PROXY exported from MY_NO_PROXY_STR=$MY_NO_PROXY_STR"
  fi

  printf '%s\n' "$TMP_PACCONF_NET"
}

# ---------- 1) local install (no network) ----------
make_temp_pacman_conf_local >/dev/null
log "Installing keyring from local file:"
log "  pacman --config $TMP_PACCONF_LOCAL -U --noconfirm $PKG_PATH"
pacman --config "$TMP_PACCONF_LOCAL" -U --noconfirm "$PKG_PATH"
log "Local keyring install complete."

# ---------- 2) optional normal update (network) ----------
if (( ALSO_UPDATE )); then
  make_temp_pacman_conf_net >/dev/null
  log "Running: pacman --config $TMP_PACCONF_NET -Sy archlinux-keyring"
  pacman --config "$TMP_PACCONF_NET" -Sy --noconfirm archlinux-keyring
  log "Running: pacman --config $TMP_PACCONF_NET -Syyu"
  pacman --config "$TMP_PACCONF_NET" -Syyu --noconfirm
  log "Pacman update finished."
else
  log "Skipping network update (no --also-update)."
fi

log "All done."

