#!/bin/bash
set -euo pipefail
set -x


# prepare current env to work with the test_run.sh script
# and overwrite critical envs and credentials with mock values
#cat $PWD/../awx-harbor-cluster-v2/bash_scripts/env/* \
#   | grep -v '#' | grep -v 'set ' | sed -r '/^\s*$/d' \
#   | sed 's#export ##g' | sed -E 's#(.*)#export \1#g' \
#   | sed 's#10\.6\.109\.32#10\.6\.107\.8#g' \
#   | sed 's#S3_ACCESSKEY=.*#S3_ACCESSKEY=harbormock_access#g' \
#   | sed 's#S3_SECRETKEY=.*#S3_SECRETKEY=harbormock_secret#g' \
#   | sed 's#S3_REGION=.*#S3_REGION=harbormock_region#g' \
#   | sed 's#S3_REGION_ENDPOINT=.*#S3_REGION_ENDPOINT=https://s3storage:9000#g' \
#   | sed 's#S3_BUCKET=.*#S3_BUCKET=harbormockbucket#g' \
#   | sed 's#S3_BUCKET_PATH=.*#S3_BUCKET_PATH=harbormock_stage#g' \
#   | sed 's#EXTERNAL_DB_PASSWORD=.*#EXTERNAL_DB_PASSWORD=harbormock_db_password#g' \
#> $PWD/init-scripts/_env


#rm -rf /tmp/awx-harbor-cluster-v2/*
#rsync -rav ../awx-harbor-cluster-v2/ /tmp/awx-harbor-cluster-v2/

# sync all to the temp place we use for our local docker container
# inplace is important because if new inodes, local changes can not guarentee to be seen in the docker container
rsync --inplace --exclude .git -avh "$PWD/../awx-harbor-cluster-v2/" /tmp/awx-harbor-cluster-v2/

sed -i -e 's#10\.6\.109\.32#10\.6\.107\.8#g' \
       -e 's#S3_ACCESSKEY=.*#S3_ACCESSKEY=harbormock_access#g' \
       -e 's#S3_SECRETKEY=.*#S3_SECRETKEY=harbormock_secret#g' \
       -e 's#S3_REGION=.*#S3_REGION=harbormock_region#g' \
       -e 's#S3_REGION_ENDPOINT=.*#S3_REGION_ENDPOINT=https://s3storage:9000#g' \
       -e 's#S3_BUCKET=.*#S3_BUCKET=harbormockbucket#g' \
       -e 's#S3_BUCKET_PATH=.*#S3_BUCKET_PATH=harbormock_stage#g' \
       -e 's#EXTERNAL_DB_PASSWORD=.*#EXTERNAL_DB_PASSWORD=harbormock_db_password#g' \
       /tmp/awx-harbor-cluster-v2/bash_scripts/env/*.sh

# firewalld does not work in WSL2 based podman containers, as we need it in our
# provisioning i quick fix with offline command

sed -i -e 's#firewall-cmd --state #true #g' /tmp/awx-harbor-cluster-v2/bash_scripts/roles/*.sh
sed -i -e 's#firewall-cmd #firewall-offline-cmd #g' /tmp/awx-harbor-cluster-v2/bash_scripts/roles/*.sh
sed -i -e 's#firewall-cmd --state #true #g' /tmp/awx-harbor-cluster-v2/bash_scripts/roles/tests/*.sh
sed -i -e 's#firewall-cmd #firewall-offline-cmd #g' /tmp/awx-harbor-cluster-v2/bash_scripts/roles/tests/*.sh


# echo "export DRY_RUN=false" >> $PWD/init-scripts/_env
echo "export DRY_RUN=false" >> /tmp/awx-harbor-cluster-v2/bash_scripts/env/global_env.sh

# some things need to be tweaked for running in a local rocky vm container vs. real RHEL box

# our local host nginx is running on port 8443, but harbor internally runs on 443 which does not like the host header with 8443
# so we need to tweak

sed -i -E 's#external_url: https://registry-\$\{STAGE\}.rz.bankenit.de#external_url: https://registry-\$\{STAGE\}.rz.bankenit.de:8443#g' /tmp/awx-harbor-cluster-v2/bash_scripts/templates/*/harbor.yml.tpl

# harbor by default uses AWS S3, I use MinIO for mockup
# With AWS S3: encrypt: true works without keyid.
# With MinIO: encrypt: true requires a KMS key (MINIO_KMS_SECRET_KEY + matching keyid).
# If you don’t configure a KMS, you must set encrypt: false in Harbor.
sed -i -E  's#    encrypt: true#    encrypt: false#g' /tmp/awx-harbor-cluster-v2/bash_scripts/templates/*/harbor.yml.tpl

# rocky package names can be different than rhel 
sed -i 's#postgresql15#postgresql-contrib#g' /tmp/awx-harbor-cluster-v2/bash_scripts/roles/tests/*.sh /tmp/awx-harbor-cluster-v2/bash_scripts/roles/*.sh
