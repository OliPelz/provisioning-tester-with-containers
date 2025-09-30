#!/usr/bin/env bash
set -Eeuo pipefail

/usr/local/bin/configure.sh

# Stream first-boot logs to container stdout so `podman logs` shows them
mkdir -p /var/log
touch /var/log/firstboot.log
# start tail before handing off to systemd
tail -n 0 -F /var/log/firstboot.log &

exec /usr/lib/systemd/systemd "$@"

