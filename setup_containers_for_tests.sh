#!/bin/bash
set -euo pipefail
set -x

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="test-container"
SSH_PORT="2222"
LOCAL_KEY="./keys_and_certs/id_ed25519_for_containers.pub"

SSH_USER="${SSH_USER:-xgthaboradm}"


#rm -rf /tmp/awx-harbor-cluster-v2
#rsync -rav $PWD/../awx-harbor-cluster-v2/. /tmp/awx-harbor-cluster-v2/
# postgresql client lib is called different on rocky and rhel
#export LOCAL_VOLUME_MOUNT_STR="/tmp/awx-harbor-cluster-v2/bash_scripts:/data,$(realpath "$PWD/init-scripts"):/init-scripts"

# restart the container
#make remove create

sleep 2  # Wait for SSH to come up

for i in rreeimreg002 oreeimreg002 xreeimreg002; do
   # now install some packages a normal RHEL machine will have by default but not in minimal rocky image
   # like envsubst, file etc
   make ssh_run_cmd MYHOSTNAME=$i CMD="sudo -E dnf install -y gettext file rsyslog rsyslog-gnutls firewalld"

   # Mocking company specific stuff in the VM to make it exactly as it needs to be
   make ssh_run_cmd MYHOSTNAME=$i CMD="bash -c 'source /init-scripts/_env && sudo -E bash /init-scripts/_thecompany_mockups.sh'"

   # mocking plswus firewall-specific systemd service file, which is a dummy
   make rsync_copy_cmd_sudo MYHOSTNAME=$i FROM="firewall-specific.service" TO="/etc/systemd/system/firewall-specific.service"
   
   # we mount /home/${SSH_USER}/ansible_temp as a volume, but its mounted as root in container, we need to change this 
   #make ssh_run_cmd MYHOSTNAME=$i CMD="sudo chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/ansible_temp"
done

# make a snapshot of current state after installation
make snapshot_all SNAPSHOT_NAME=vanilla_after_installation

echo -e "${GREEN}Containers started with example_tests directory mounted${NC}" >&2
