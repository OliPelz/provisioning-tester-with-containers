#!/bin/bash
set -euo pipefail
./update_from_provisioning.sh
#make ssh_run_cmd MYHOSTNAME=my-ubuntu-machine CMD='export PATH=/data/bash-provisioner/include_bins/shunit2:$$PATH; /usr/bin/bash /data/bash-provisioner/provisions/tests/test_package-mgr'
#make ssh_run_cmd MYHOSTNAME=my-rocky-machine CMD='export PATH=/data/bash-provisioner/include_bins/shunit2:$$PATH; /usr/bin/bash /data/bash-provisioner/provisions/tests/test_package-mgr'
make ssh_run_cmd MYHOSTNAME=my-arch-machine CMD='export PATH=/data/bash-provisioner/include_bins/shunit2:$$PATH; /usr/bin/bash /data/bash-provisioner/provisions/tests/test_package-mgr'
