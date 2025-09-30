# provisioning-tester-with-containers

testing bash-provisioner on multiple platforms


# 0) init

make prereqs

configure local registry using http:

```bash
mkdir -p ~/.config/containers/registries.conf.d
cat > ~/.config/containers/registries.conf.d/localhost-5000-insecure.conf <<'EOF'
# containers-registries.conf v2
[[registry]]
prefix   = "localhost:5000"
location = "localhost:5000"
insecure = true
blocked  = false
EOF

```

# 1) Start the registry (persists data in ./registry_data)
make registry-up

# 2) Run your containers as usual (images are already in the local registry)
make setup-network

make build_webproxycache
make run-webproxycache


# 2) Build everything and push to the local registry automatically
make build_all_images

make run-arch
# ...or create all:
make create_all



## prepare arch image

since arch is rolling update, the image contains old GPG keys and outdated
mirrorlist.
in order to regenerage latest mirrorlist lets install all the GPG keychain
from the latest arch keyring package we download using this instruction:  
DOWNLOAD_ARCH_PACKAGE.md
Note: you should download the latest package from time to time when you rebuild the arch image.

Also we need to get latest mirrorlist, as it can contain outdated mirrors from time to time, 
so everytime you rebuild the image you should fetch latest mirrorlist first:
 
 goto official mirrorlist generator:

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
