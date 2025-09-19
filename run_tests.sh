#!/bin/bash
set -euo pipefail
CONTAINER_NAME="test-container"
SSH_PORT="2222"
LOCAL_KEY="./id_ed25519.pub"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse parameters
ONLY_LIST=""
SKIP_LIST=""
DO_TESTS=true
RUN_LIST="_run_list_all"
MASTER_NODE=rreeimreg002

for arg in "$@"; do
    case $arg in
        --only=*)
            ONLY_LIST="${arg#--only=}"
            ;;
        --skip=*)
            SKIP_LIST="${arg#--skip=}"
            ;;
        --run-list=*)
            RUN_LIST="${arg#--run-list=}"
            ;;
        --no-tests)
            DO_TESTS=false
            ;;
        *)
            echo -e "${RED}Unknown argument: $arg${NC}" >&2
            exit 1
            ;;
    esac
done

if [[ -n "$ONLY_LIST" && -n "$SKIP_LIST" ]]; then
    echo -e "${RED}Error: --only and --skip cannot be used at the same time.${NC}" >&2
    exit 1
fi

RUN_LIST="/init-scripts/${RUN_LIST:-_run_list_all}"

# Convert comma-separated lists to arrays
IFS=',' read -r -a ONLY <<< "$ONLY_LIST"
IFS=',' read -r -a SKIP <<< "$SKIP_LIST"


# Run setup scripts
echo -e "${BLUE}Running setup scripts in container...${NC}" >&2

#run_list=$(make ssh_run_cmd MYHOSTNAME=$MASTER_NODE CMD="cat $RUN_LIST | grep -v '#' | awk 'NF'")
run_list=$(cat .$RUN_LIST | grep -v '#' | awk 'NF')


# Process each line of the run_list properly
while IFS= read -r script_with_args; do
   for hostname in rreeimreg002 oreeimreg002 xreeimreg002; do
        # Extract the script name (first word) and preserve the arguments
        script_name=$(echo "$script_with_args" | awk '{print $1}')
        script_args=$(echo "$script_with_args" | awk '{$1=""; print $0}' | sed 's/^ *//')

        # Filtering logic
        if [[ ${#ONLY[@]} -gt 0 ]]; then
            [[ " ${ONLY[*]} " != *" $script_name "* ]] && continue
        elif [[ ${#SKIP[@]} -gt 0 ]]; then
            [[ " ${SKIP[*]} " == *" $script_name "* ]] && continue
        fi

        # Adjust logging to handle "no arguments" case
        if [[ -z "$script_args" ]]; then
            echo -e "${YELLOW}Running $script_name with no arguments...${NC}" >&2
        else
            echo -e "${YELLOW}Running $script_name with arguments: $script_args...${NC}" >&2
        fi

        # Run the script 2x to test for idempotency
        # make ssh_run_cmd MYHOSTNAME=$hostname CMD="bash -c 'source /init-scripts/_env && bash /data/roles/$script_name $script_args'"
        make ssh_run_cmd MYHOSTNAME=$hostname CMD="RUN_STAGE=lab bash /data/roles/$script_name $script_args"
        if [ "$DO_TESTS" = "true" ]; then
            # make ssh_run_cmd MYHOSTNAME=$hostname CMD="bash -c 'source /init-scripts/_env && bats --verbose-run /data/roles/tests/test_$(basename "$script_name" .sh).sh'"
            make ssh_run_cmd MYHOSTNAME=$hostname CMD="RUN_STAGE=lab bash /data/roles/tests/test_$(basename "$script_name" .sh).sh $script_args"
        fi
   done
done <<< "$run_list"

echo -e "${GREEN}All tests completed${NC}"

