#!/usr/bin/env bash
set -Eeuo pipefail

# ssh_run_cmd.sh
# Run a command on a remote host via SSH, preserving quoting/args.
#
# Preferred usage: send the full script/command via STDIN.
#
# Examples:
#   printf '%s' 'echo "$PATH"' | scripts/ssh_run_cmd.sh -H localhost -P 2222 -u myuser -i ~/.ssh/id_ed25519
#   printf '%s' 'export PATH=/x:/$PATH && /path/to/script' | scripts/ssh_run_cmd.sh -H ... -P ... -u ... -i ...
#
# If you really want argv-style, use --argv-mode (best-effort; control operators like && can be tricky).
#   scripts/ssh_run_cmd.sh -H ... --argv-mode -- echo "hello" "world"

host="localhost"
port="22"
user="${USER:-root}"
identity=""
verbose="false"
argv_mode="false"

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)     host="${2:-}"; shift 2 ;;
    -P|--port)     port="${2:-}"; shift 2 ;;
    -u|--user)     user="${2:-}"; shift 2 ;;
    -i|--identity) identity="${2:-}"; shift 2 ;;
    -v|--verbose)  verbose="true"; shift ;;
    --argv-mode)   argv_mode="true"; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

[[ -z "$host" || -z "$port" || -z "$user" ]] && die "host/port/user missing"
[[ -n "$identity" && ! -r "$identity" ]] && die "identity file not readable: $identity"

# Build payload:
payload=""
if [[ "$argv_mode" == "true" ]]; then
  # Best-effort: join argv with spaces (control operators may not behave as you expect).
  # Prefer piping via STDIN (default mode) to avoid this.
  if [[ $# -gt 0 ]]; then
    payload="$*"
  else
    payload="$(cat)"
  fi
else
  # Default: read entire STDIN as-is (no splitting).
  payload="$(cat)"
fi

ssh_args=( -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$port" )
[[ -n "$identity" ]] && ssh_args+=( -i "$identity" )

# Robust remote runner:
#  - writes payload to a temp file
#  - executes with bash if available (explicit paths first), else sh
remote_runner='
tmp=$(mktemp /tmp/sshcmd.XXXXXX) || exit 127
cat >"$tmp"
if [ -x /usr/bin/bash ]; then
  /usr/bin/bash "$tmp"; rc=$?
elif [ -x /bin/bash ]; then
  /bin/bash "$tmp"; rc=$?
elif command -v bash >/dev/null 2>&1; then
  bash "$tmp"; rc=$?
else
  /bin/sh "$tmp"; rc=$?
fi
rm -f "$tmp"
exit $rc
'

if [[ "$verbose" == "true" ]]; then
  echo "[INFO] host=$host port=$port user=$user identity=${identity:-<none>}" >&2
  echo "[INFO] payload:" >&2
  printf '%s\n' "$payload" >&2
fi

# Send the payload via stdin so we avoid any quoting problems entirely.
printf '%s' "$payload" | ssh "${ssh_args[@]}" "$user@$host" -- "$remote_runner"

