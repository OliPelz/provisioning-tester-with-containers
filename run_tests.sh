#!/usr/bin/env bash
set -euo pipefail
#set -x
this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- config ------------------------------------------------------------
LOCAL_KEY="keys_and_certs/id_ed25519_for_containers"  # used if your make target expects SSH_KEY
DEFAULT_WORKFLOW="install"
DEFAULT_HOSTS=("my-ubuntu-machine" "my-rocky-machine" "my-arch-machine")

# ---------- colors ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ---------- state (defaults) --------------------------------------------------
dry_run=0
filter=""
workflow="$DEFAULT_WORKFLOW"
run_tests_only=0
run_scripts_only=0
machine_filter=""
declare -a HOSTS=("${DEFAULT_HOSTS[@]}")

# ---------- helpers -----------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -d, --dry-run              Print actions without executing.
  -w, --workflow NAME        Workflow name (default: ${DEFAULT_WORKFLOW}).
  -f, --filter LIST          Comma-separated script names to run (exact match).
  -t, --run-test-only        Run tests only.
  -s, --run-script-only      Run scripts only.
  -H, --hosts LIST           Comma-separated hostnames (overrides defaults).
  -m, --filter-machine LIST  Comma-separated substrings; only hosts whose names
                             contain any of these will be targeted (case-insensitive).
  -k, --ssh-key PATH         SSH key path to pass as SSH_KEY to make (default: ${LOCAL_KEY}).
  -h, --help                 Show this help.

Example:
  $0 -d -w install -f "setup/os.sh,apps/docker.sh" -H "web-ubuntu-1,db-arch-2" -m "ubuntu,arch" -s
EOF
}

log()       { printf "%b\n" "${BLUE}[INFO]${NC} $*"; }
log_warn()  { printf "%b\n" "${YELLOW}[WARN]${NC} $*"; }
log_ok()    { printf "%b\n" "${GREEN}[OK]${NC}  $*"; }
log_error() { printf "%b\n" "${RED}[ERROR]${NC} $*" 1>&2; }
die() { log_error "$*"; exit 1; }
join_by() { local IFS="$1"; shift; echo "$*"; }

build_provision_args() {
  local -a args=()
  (( dry_run == 1 ))         && args+=("--dry-run")
  [[ -n "$filter" ]]         && args+=("--filter" "$filter")
  (( run_tests_only == 1 ))  && args+=("-t")
  (( run_scripts_only == 1 ))&& args+=("-s")
  args+=("-w" "$workflow")

  local out=""; local a
  for a in "${args[@]}"; do printf -v out "%s %q" "$out" "$a"; done
  echo "${out# }"
}

# ---------- arg parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)         dry_run=1; shift ;;
    -f|--filter)          filter="${2:-}"; shift 2 ;;
    -t|--run-test-only)   run_tests_only=1; shift ;;
    -s|--run-script-only) run_scripts_only=1; shift ;;
    -w|--workflow)        workflow="${2:-}"; shift 2 ;;
    -H|--hosts)           IFS=',' read -r -a HOSTS <<< "${2:-}"; shift 2 ;;
    -m|--filter-machine)  machine_filter="${2:-}"; shift 2 ;;
    -k|--ssh-key)         LOCAL_KEY="${2:-}"; shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    --)                   shift; break ;;
    *)                    die "Unknown option: $1" ;;
  esac
done

# ---------- validations & host filtering -------------------------------------
(( run_tests_only == 1 && run_scripts_only == 1 )) && \
  die "Choose only one of --run-test-only or --run-script-only."
[[ -z "$workflow" ]] && die "Workflow name cannot be empty."

if [[ ! -f "$LOCAL_KEY" ]]; then
  # Not fatal — your makefile may not require SSH_KEY.
  log_warn "SSH key not found at '${LOCAL_KEY}'. Proceeding without checking."
fi

if (( ${#HOSTS[@]} == 0 )); then
  die "No hosts provided. Use --hosts or set DEFAULT_HOSTS."
fi

# Apply machine substring filter (case-insensitive, comma-separated)
if [[ -n "$machine_filter" ]]; then
  IFS=',' read -r -a _patterns <<< "$machine_filter"
  declare -a _filtered=()
  for host in "${HOSTS[@]}"; do
    lh="${host,,}"
    for pat in "${_patterns[@]}"; do
      lp="${pat,,}"; lp="${lp//[[:space:]]/}"
      [[ -z "$lp" ]] && continue
      if [[ "$lh" == *"$lp"* ]]; then
        _filtered+=("$host"); break
      fi
    done
  done
  HOSTS=("${_filtered[@]}")
  (( ${#HOSTS[@]} == 0 )) && die "No hosts match --filter-machine '${machine_filter}'."
fi

# ---------- banner ------------------------------------------------------------
log "Wrapper starting with:"
log "  workflow       : ${workflow}"
log "  filter         : ${filter:-<none>}"
log "  machine filter : ${machine_filter:-<none>}"
log "  mode           : $( ((run_tests_only)) && echo 'tests only' || { ((run_scripts_only)) && echo 'scripts only' || echo 'scripts + tests'; } )"
log "  dry-run        : $dry_run"
log "  hosts          : $(join_by ', ' "${HOSTS[@]}")"
log "  ssh key        : ${LOCAL_KEY}"

# ---------- run ---------------------------------------------------------------
PROVISION_ESCAPED_ARGS="$(build_provision_args)"

for host in "${HOSTS[@]}"; do
  printf -v REMOTE_CMD "cd %q && ./provision %s" "/data/bash-provisioner" "$PROVISION_ESCAPED_ARGS"

  MAKE_CMD=( make ssh_run_cmd MYHOSTNAME="$host" CMD="$REMOTE_CMD" )
  [[ -f "$LOCAL_KEY" ]] && MAKE_CMD+=( SSH_KEY="$LOCAL_KEY" )

  if (( dry_run == 1 )); then
    printf "%b\n" "${GREEN}[DRY_RUN]${NC} ${MAKE_CMD[*]}"
    continue
  fi
  
  log "Running on host '${host}'..."
  if "${MAKE_CMD[@]}"; then
    log_ok "Host '${host}' finished successfully."
  else
    log_error "Host '${host}' failed."
    exit 1  # uncomment to fail-fast
  fi
done

log_ok "All done."

