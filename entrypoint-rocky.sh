#!/usr/bin/env bash
set -Eeuo pipefail

/usr/local/bin/configure.sh

# Stream first-boot logs
mkdir -p /var/log
touch /var/log/firstboot.log
tail -n 0 -F /var/log/firstboot.log &

# Locate systemd across common paths
for cand in /sbin/init /usr/lib/systemd/systemd /lib/systemd/systemd; do
  if [ -x "$cand" ]; then
    exec "$cand" "$@"
  fi
done

echo "[entrypoint] ERROR: systemd not found" >&2
ls -l /sbin/init /usr/lib/systemd/systemd /lib/systemd/systemd 2>/dev/null || true
exit 1

