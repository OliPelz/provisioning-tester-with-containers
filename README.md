# provisioning-tester-with-containers

testing bash-provisioner on multiple platforms


## prepare arch image

since arch is rolling update, the image contains old GPG keys and outdated
mirrorlist.
in order to regen mirrorlist goto official mirrorlist generator:

https://archlinux.org/mirrorlist/

gen your list, uncomment server name lines aka remove '#' before servers
and save into arch_mirrorlist 
this will copied into image when running build_all_images later

## do only once
$ make prereqs
$ make setup-network

# run whenever images changes
$ make build_all_images


## first run global tests of included functions like package-mgr

./run_global_tests.sh

## then for first time usage
./init.sh && ./run.sh

## if you change something in ./bash-provisioner, just do

./run.sh
