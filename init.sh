#!/bin/bash
set -euo pipefail
#set -x

#echo "This will remove all postgres AND S3 storage data, are you sure?"
#echo -n "Are you sure? [y/N] " && read ans && [ ${ans:-N} = y ]
#sudo rm -rf pgeek027_data
#sudo rm -rf s3storage_data

./update_from_provisioning.sh

export LOCAL_VOLUME_MOUNT_STR="/tmp/bash-provisioner:/data/bash-provisioner"

make remove_all create_all
