# provisioning-tester-with-containers

## do only once
$ make prereqs
$ make setup-network

# run whenever images changes
$ make build_all_images

./init.sh && ./run.sh
