#!/bin/bash
/usr/local/bin/configure.sh

# systemd must be run with PID 1
exec /usr/lib/systemd/systemd "$@"
