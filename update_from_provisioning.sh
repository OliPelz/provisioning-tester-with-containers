#!/bin/bash
set -euo pipefail
#set -x


# sync all to the temp place we use for our local docker container
# inplace is important because if new inodes, local changes can not guarentee to be seen in the docker container
rsync --inplace --exclude .git -avh "$PWD/bash-provisioner/" /tmp/bash-provisioner/

# example to alter some content

#sed -i -e 's#10\.6\.110\.11#10\.6\.120\.9#g' \
#       -e 's#XXXX=.*#XXXX=harbormock_access#g' \
#       -e 's#YYY=.*#YYY=harbormock_secret#g' \
#       /tmp/bash-provisioner/provisions/*.sh

# firewalld does not work in WSL2 based podman containers, as we need it in our
# provisioning i quick fix with offline command

sed -i -e 's#firewall-cmd --state #true #g' /tmp/bash-provisioner/provisions/*.sh
sed -i -e 's#firewall-cmd #firewall-offline-cmd #g' /tmp/bash-provisioner/provisions/*.sh
sed -i -e 's#firewall-cmd --state #true #g' /tmp/bash-provisioner/provisions/*.sh
sed -i -e 's#firewall-cmd #firewall-offline-cmd #g' /tmp/bash-provisioner/provisions/*.sh

# echo "export DRY_RUN=false" >> $PWD/init-scripts/_env
echo "export DRY_RUN=false" >> /tmp/bash-provisioner/provisions/env/global_env.sh

# other things need to be tweaked for running in a local docker container v.s. real VM

exit 0
