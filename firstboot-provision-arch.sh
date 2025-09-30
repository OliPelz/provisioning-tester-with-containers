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

if [[ ! -f "$MARKER" ]]; then
  log "No marker present; nothing to do."
  exit 0
fi

# --- Load proxy env (validate first to avoid silent parse bombs) -------------
if [[ -r "$ENVFILE" ]]; then
  log "Loading runtime proxy env: $ENVFILE"
  # Normalize line endings (protects against CRLF)
  if file "$ENVFILE" | grep -qi 'CRLF'; then
    tr -d '\r' < "$ENVFILE" > "${ENVFILE}.unix" && mv -f "${ENVFILE}.unix" "$ENVFILE"
  fi
  if ! bash -n "$ENVFILE"; then
    err "Syntax error in $ENVFILE. Showing with line numbers:"
    nl -ba "$ENVFILE" | sed -n '1,200p' >&2
    exit 2
  fi
  set -a; set +u
  # shellcheck disable=SC1090
  . "$ENVFILE"
  set -u; set +a
else
  log "No $ENVFILE found; proceeding without proxy env."
fi

# Ensure wrapper is executable
chmod +x /usr/local/bin/package-mgr-v2 || true

# --- Preflight: proxy reachability (best-effort) -----------------------------
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

# --- 1) Reset pacman GnuPG & init (offline) ---------------------------------
log "Resetting pacman gnupg & initializing..."
rm -rf /etc/pacman.d/gnupg/* /var/lib/pacman/sync || true
pacman-key --init

# --- 2) Local (offline) install of new archlinux-keyring ---------------------
log "Installing archlinux-keyring from local file..."
/usr/local/bin/seed-arch-keyring-local-file.sh --pkg /opt/archlinux-keyring.pkg.tar.zst

# --- 3) Online refresh & full update via proxy wrapper -----------------------
log "Refreshing keyring online..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" -Sy --noconfirm archlinux-keyring || true

log "Full system update via package-mgr-v2..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" -Syyu --noconfirm

# --- 4) Base packages (override with PACKAGES in env) ------------------------
DEFAULT_PKGS=(
  systemd openssh firewalld cronie python bash vim sudo rsync curl
  ca-certificates ca-certificates-utils
)

# Build PKGS correctly
if [[ -n ${PACKAGES:-} ]]; then
  # split PACKAGES env on whitespace into an array
  read -r -a PKGS <<<"$PACKAGES"
else
  # use defaults, preserving word boundaries
  PKGS=("${DEFAULT_PKGS[@]}")
fi

log "Installing packages: ${PKGS[*]} ..."
/usr/local/bin/package-mgr-v2 --load-env-file="$ENVFILE" -Sy --noconfirm "${PKGS[@]}"

# --- 5) Enable/start services ------------------------------------------------
log "Enabling services..."
systemctl enable sshd cronie || true
systemctl restart sshd || true
systemctl restart cronie || true

# --- 6) Mark complete --------------------------------------------------------
touch "$DONE"
rm -f "$MARKER"
log "First-boot provisioning complete."
exit 0

