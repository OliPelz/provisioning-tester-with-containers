#!/bin/bash

set -e
mkdir /tmp/s3storage_test
cd $_
wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O mc;
chmod +x mc; 
unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; 
./mc alias set local https://s3storage:9000 harbormock_access harbormock_secret --api s3v4 --path on; 
./mc mb local/harbormockbucket || echo 'bucket exists'; 
echo 'hello world' > testfile.txt; 
./mc cp testfile.txt local/harbormockbucket/; 
./mc cp local/harbormockbucket/testfile.txt downloaded.txt; 
if [ "$(cat downloaded.txt)" = "hello world" ]; then 
   echo 'S3 test successful'; 
else 
   echo 'S3 test failed'; 
   exit 1; 
fi 
exit 0
