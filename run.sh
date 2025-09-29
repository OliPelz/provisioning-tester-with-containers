#!/bin/bash
set -euo pipefail
#./update_from_provisioning.sh && ./run_tests.sh --workflow install --filter-machine ubuntu
./update_from_provisioning.sh && ./run_tests.sh --workflow install 
