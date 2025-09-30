#!/usr/bin/env bash
set -Eeuo pipefail

/usr/local/bin/configure.sh

# Stream first-boot logs to container stdout
mkdir -p /var/log
touch /var/log/firstboot.log
tail -n 0 -F /var/log/firstboot.log &

exec /lib/systemd/systemd "$@"

