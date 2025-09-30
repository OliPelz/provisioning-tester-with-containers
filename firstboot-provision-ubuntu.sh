#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /var/log
exec > >(tee -a /var/log/firstboot.log) 2>&1

log() { printf '[firstboot] %s\n' "$*"; }
err() { printf '[firstboot][ERROR] %s\n' "$*" >&2; }

MARKER="/var/lib/firstboot/needed"
DONE="/var/lib/firstboot/done"
ENVFILE="/usr/local/bin/proxy.env"

[ -f "$MARKER" ] || { log "No marker present; nothing to do."; exit 0; }

# Load proxy env if present
if [[ -r "$ENVFILE" ]]; then
  log "Loading runtime proxy env: $ENVFILE"
  # Normalize CRLF
  #if file "$ENVFILE" | grep -qi 'CRLF'; then
  #  tr -d '\r' < "$ENVFILE" > "${ENVFILE}.unix" && mv -f "${ENVFILE}.unix" "$ENVFILE"
  #fi
  if ! bash -n "$ENVFILE"; then
    err "Syntax error in $ENVFILE"; nl -ba "$ENVFILE" | sed -n '1,200p' >&2; exit 2
  fi
  set -a; set +u
  # shellcheck disable=SC1090
  . "$ENVFILE"
  set -u; set +a
fi

chmod +x /usr/local/bin/package-mgr-v2 || true

# Optional: best-effort proxy reachability check
_proxy="${MY_PROXY_URL:-}"
if [[ -n "$_proxy" ]]; then
  host="${_proxy#http://}"; host="${host#https://}"
  host="${host%%:*}"; port="${_proxy##*:}"
  log "Waiting for proxy ${host}:${port} to become reachable..."
  for i in {1..15}; do
    if timeout 3 bash -lc 'exec 3<>/dev/tcp/'"$host"'/'"$port"' 2>/dev/null'; then
      log "Proxy reachable."
      break
    fi
    sleep 3
  done
fi

# --- Update & install packages via wrapper (apt) ---
log "apt update via package-mgr-v2..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" update -y

DEFAULT_PKGS=(
  systemd openssh-server firewalld cron python3 bash vim sudo rsync curl ca-certificates
)

if [[ -n ${PACKAGES:-} ]]; then
  read -r -a PKGS <<<"$PACKAGES"
else
  PKGS=("${DEFAULT_PKGS[@]}")
fi

log "Installing packages: ${PKGS[*]}..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" install -y "${PKGS[@]}"

# Ensure systemd services enabled where applicable
log "Enabling services..."
systemctl enable ssh || true       # Ubuntu service name 'ssh'
systemctl enable cron || true
systemctl enable firewalld || true

systemctl restart ssh || true
systemctl restart cron || true
systemctl restart firewalld || true

touch "$DONE"
rm -f "$MARKER"
log "First-boot provisioning complete."
exit 0

