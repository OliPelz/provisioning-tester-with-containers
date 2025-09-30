#!/usr/bin/env bash
set -Eeuo pipefail

# log to file and stdout/stderr (journald will capture stdout/stderr)
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
  if file "$ENVFILE" | grep -qi 'CRLF'; then
    tr -d '\r' < "$ENVFILE" > "${ENVFILE}.unix" && mv -f "${ENVFILE}.unix" "$ENVFILE"
  fi
  if ! bash -n "$ENVFILE"; then
    err "Syntax error in $ENVFILE"; nl -ba "$ENVFILE" | sed -n '1,200p' >&2; exit 2
  fi
  set -a; set +u
  # shellcheck disable=SC1090
  . "$ENVFILE"
  set -u; set +a
fi

chmod +x /usr/local/bin/package-mgr-v2 || true

# Optional: check proxy reachability
_proxy="${MY_PROXY_URL:-}"
if [[ -n "$_proxy" ]]; then
  host="${_proxy#http://}"; host="${host#https://}"
  host="${host%%:*}"; port="${_proxy##*:}"
  log "Waiting for proxy ${host}:${port}..."
  for _ in {1..15}; do
    if timeout 3 bash -lc 'exec 3<>/dev/tcp/'"$host"'/'"$port"' 2>/dev/null'; then
      log "Proxy reachable."
      break
    fi
    sleep 3
  done
fi

# ---- Use your wrapper exactly as you wrote it: it expects the PM name ----
log "dnf makecache via package-mgr-v2..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" -y makecache

DEFAULT_PKGS=(
  systemd openssh-server firewalld cronie python3 bash vim sudo rsync curl ca-certificates
)
if [[ -n ${PACKAGES:-} ]]; then
  read -r -a PKGS <<<"$PACKAGES"
else
  PKGS=("${DEFAULT_PKGS[@]}")
fi

# --allowerasing e.g. to get rid of curl-minimal
log "Installing packages: ${PKGS[*]}..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" --allowerasing -y install "${PKGS[@]}"

log "Enabling services..."
systemctl enable sshd || true
systemctl enable crond || true
systemctl enable firewalld || true

systemctl restart sshd || true
systemctl restart crond || true
systemctl restart firewalld || true

touch "$DONE"
rm -f "$MARKER"
log "First-boot provisioning complete."
exit 0

