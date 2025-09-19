include ./makefile_colored_help.inc

RED_COLOR=[0;31m
GREEN_COLOR=[0;32m
YELLOW_COLOR=[1;33m
BLUE_COLOR=[0;34m
NO_COLOR=[0m # No Color

# Networking and Pod
NETWORK_NAME=mynet
SUBNET=10.6.107.0/24
GATEWAY=10.6.107.1

# Names / hostnames
NAME1=rreeimreg002
NAME2=oreeimreg002
NAME3=xreeimreg002
DB_NAME1=pgeek027
WEBPROXYCACHE_NAME1=webproxycache
RSYSLOG_NAME=rsyslog_server
LOADBALANCER_NAME=haproxy_loadbalancer
S3STORAGE_NAME=s3storage
ALL_CONTAINER_NAMES_STRING=$(NAME1) $(NAME2) $(NAME3) $(DB_NAME1) $(WEBPROXYCACHE_NAME1) $(RSYSLOG_NAME) $(LOADBALANCER_NAME) $(S3STORAGE_NAME)
ALL_CONTAINER_RUN_MAKE_TARGETS=run-app1 run-app2 run-app3 run-db run-webproxycache run-rsyslog run-loadbalancer run-s3storage
 
# Ports
SSH_PORT1=2222
SSH_PORT2=2223
SSH_PORT3=2224

# Static IPs
IP1=10.6.107.4
IP2=10.6.107.5
IP3=10.6.107.6
DB_IP1=10.6.107.8
WEBPROXYCACHE_IP1=10.6.107.9
RSYSLOG_IP=10.6.107.10
LOADBALANCER_IP=10.6.107.11
S3STORAGE_IP=10.6.107.12

# PostgreSQL credentials
DB_USER=harbor_dev
DB_PASS=harbormock_db_password
DB_NAME=harbor_dev

# Image names
IMAGE_NAME=my-rocky-systemd-ssh-vpn
WEBPROXYCACHE_IMAGE_NAME=webproxycache
RSYSLOG_IMAGE_NAME=my-rsyslog_server
POSTGRES_IMAGE_NAME=my-postgres_server
LOADBALANCER_IMAGE_NAME=my-loadbalancer_server
S3STORAGE_IMAGE_NAME=my-s3storage_server

# SSH
SSH_USER=$(shell echo "$${SSH_USER:-xgthaboradm}")
LOCAL_PODMAN_USER=$(shell echo "$${USER}")
LOCAL_KEY=$(PWD)
PUB_KEY_PATH=$(PWD)/keys_and_certs/id_ed25519_for_containers.pub
PRIV_KEY_PATH=$(subst .pub,,$(PUB_KEY_PATH))
LOCAL_VOLUME_MOUNT=$(shell if [ -n "$${LOCAL_VOLUME_MOUNT_STR}" ]; then echo "$${LOCAL_VOLUME_MOUNT_STR}" | tr ',' '\n' | while read -r mapping; do echo "-v $$mapping"; done; fi)

.DEFAULT_GOAL := help

PROXY_CERT_BASE_PATH=$(PWD)/keys_and_certs

##########################################################################################
## workflow:
all: build_all_images setup-network run  ## run complete workflow from build to run

##########################################################################################
## setup and build:
.PHONY: prompt_me
prompt_me:
	@echo -n "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]

.PHONY: prereqs
prereqs:  ### prerequesites for running podman
	@echo "$(BLUE_COLOR)Setting up subUID/subGID mappings for $(LOCAL_PODMAN_USER)...$(NC)" >&2
	@sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(LOCAL_PODMAN_USER) || { echo "$(RED_COLOR)Failed to set subUID/subGID mappings$(NC)" >&2; exit 1; }
	@echo "$(GREEN_COLOR)subUID/subGID mappings configured$(NC)" >&2
	@mkdir -p keys_and_certs

.PHONY: gen_all_certs
gen_all_certs: gen_ssh_container_keys gen_ssl_cert
.PHONY: gen_ssh_container_keys
gen_ssh_container_keys: ### generate local ssh keypair for connecting to containers
	@if [ -f $(PRIV_KEY_PATH) ] || [ -f $(PUB_KEY_PATH) ]; then \
		echo "$(YELLOW_COLOR)Local key pair already exists, skipping generation$(NC)" >&2; \
	else \
		ssh-keygen -t ed25519 -f $(PRIV_KEY_PATH) -N ""; \
		echo "$(GREEN_COLOR)Key generated$(NO_COLOR)"; \
	fi

# Note: s3storage cert needs to be a SAN cert
gen_ssl_cert: ### generate a self-signed ssl cert 
	@openssl req -x509 -newkey rsa:2048 -nodes \
	-keyout ./keys_and_certs/rsyslog-ssl-key.pem \
	-out ./keys_and_certs/rsyslog-ssl-cert.pem \
	-days 3650 \
	-subj "/CN=rsyslog-server"
	@openssl req -x509 -newkey rsa:2048 -nodes \
	-keyout ./keys_and_certs/loadbalancer-ssl-key.pem \
	-out ./keys_and_certs/loadbalancer-ssl-cert.pem \
	-days 3650 \
	-subj "/CN=loadbalancer-server"
	@cat keys_and_certs/loadbalancer-ssl-cert.pem keys_and_certs/loadbalancer-ssl-key.pem \
	> keys_and_certs/loadbalancer-ssl-combined.pem
	@openssl req -new -x509 -days 365 -nodes \
  	-text -out ./keys_and_certs/postgres_ssl_server.crt \
  	-keyout ./keys_and_certs/postgres_server.key \
  	-subj "/CN=postgres-server"
	@openssl req -newkey rsa:2048 -nodes \
	-keyout ./keys_and_certs/s3storage_server.key \
	-x509 -days 365 -out ./keys_and_certs/s3storage_ssl_server.crt \
	-subj "/CN=s3storage" \
	-addext "subjectAltName = DNS:s3storage,IP:127.0.0.1"

# Generate CA
.PHONY: get_proxy_cert
get_proxy_cert:
	@echo "==> Retrieving existing webproxycache SSL cert from built image"
	@podman run $(WEBPROXYCACHE_NAME1) cat /root/.mitmproxy/mitmproxy-ca-cert.pem > $(PWD)/keys_and_certs/mitmproxy-ca-cert.pem \
	     || { echo "$(RED_COLOR)Failed to run Proxycache container$(NO_COLOR)" >&2; exit 1; };

.PHONY: setup-network
setup-network:  ### setup podman network which holds all our containers
	@echo "🌐 Creating network $(NETWORK_NAME)..."
	@if ! podman network exists $(NETWORK_NAME); then \
		podman network create --subnet=$(SUBNET) --gateway=$(GATEWAY) $(NETWORK_NAME); \
	else \
		echo "Network $(NETWORK_NAME) already exists."; \
	fi

.PHONY: build_all_images
build_all_images:  gen_all_certs render_loadbalancer_template ### build vm alike container image
	@echo "🔨 Building custom Rocky image with systemd and sshd..."
	@podman build -f Dockerfile.webproxycache -t $(WEBPROXYCACHE_IMAGE_NAME) .
	@podman build -f Dockerfile.rsyslog -t $(RSYSLOG_IMAGE_NAME) .
	@podman build -f Dockerfile.postgres -t $(POSTGRES_IMAGE_NAME) .
	@podman build -f Dockerfile.loadbalancer -t $(LOADBALANCER_IMAGE_NAME) .
	@podman build -f Dockerfile.s3storage -t $(S3STORAGE_IMAGE_NAME) .
	@$(MAKE) get_proxy_cert
	@podman build -f Dockerfile --build-arg SSH_USER=$(SSH_USER) -t $(IMAGE_NAME) .

# Target to create necessary volume directories
make_volume_dirs:
	@echo "Creating volume directories..."
	mkdir -p $(PWD)/$(WEBPROXYCACHE_NAME1)_data
	mkdir -p $(PWD)/$(DB_NAME1)_data
	mkdir -p $(PWD)/$(S3STORAGE_NAME)_data
	@echo "Volume directories created successfully!"

render_loadbalancer_template:
	@source $(PWD)/make_functions.sh; \
	NAME1=$(NAME1) NAME2=$(NAME2) NAME3=$(NAME3) \
	render_template $(PWD)/loadbalancer.conf.tpl $(PWD)/loadbalancer.conf

##########################################################################################
## container lifecycle tasks:


# Target to run the load balancer container
run-loadbalancer: 
	podman run -d \
		--name $(LOADBALANCER_NAME) \
		--network $(NETWORK_NAME) \
		--ip $(LOADBALANCER_IP) \
		--hostname $(LOADBALANCER_NAME) \
		-p 8080:8080 \
		-p 8443:8443 \
		-p 7000:7000 \
		$(LOADBALANCER_IMAGE_NAME)	
	@echo "Load balancer container started successfully!"

# Target to run the rsyslog container
run-rsyslog:
	podman run -d --name $(RSYSLOG_NAME) \
		--network $(NETWORK_NAME) \
		--ip $(RSYSLOG_IP) \
		--hostname $(RSYSLOG_NAME) \
		-e DNS_SERVER=8.8.8.8 \
		-p 3128 \
		-v $(PWD)/$(WEBPROXYCACHE_NAME1)_data:/app/the_cache_dir \
		$(RSYSLOG_IMAGE_NAME)
	@echo "Rsyslog container started successfully!"

# Target to run the web proxy cache container
run-webproxycache:
	podman run -d --name $(WEBPROXYCACHE_NAME1) \
		--network $(NETWORK_NAME) \
		--ip $(WEBPROXYCACHE_IP1) \
		--hostname $(WEBPROXYCACHE_NAME1) \
		-e DNS_SERVER=8.8.8.8 \
		-p 3128 \
		-v $(PWD)/$(WEBPROXYCACHE_NAME1)_data:/app/the_cache_dir \
		$(WEBPROXYCACHE_IMAGE_NAME)
	@echo "Web proxy cache container started successfully!"

# Target to run the application container (NAME1)
run-app1:
	podman run -d --name $(NAME1) \
		--network $(NETWORK_NAME) \
		--ip $(IP1) \
		--hostname $(NAME1) \
		--privileged \
		--systemd=always \
		-p $(SSH_PORT1):22 \
		-v /sys/fs/cgroup:/sys/fs/cgroup:rw \
		$(LOCAL_VOLUME_MOUNT) \
		-e SSH_USER=$(SSH_USER) \
		-e PUB_KEY="$$(cat $(PUB_KEY_PATH))" \
		--userns=host \
		--cap-add=SYS_ADMIN \
		--security-opt label=disable \
		$(IMAGE_NAME)
	@echo "Application container $(NAME1) started successfully!"

# Target to run the application container (NAME2)
run-app2:
	podman run -d --name $(NAME2) \
		--network $(NETWORK_NAME) \
		--ip $(IP2) \
		--hostname $(NAME2) \
		--privileged \
		--systemd=always \
		-p $(SSH_PORT2):22 \
		-v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		$(LOCAL_VOLUME_MOUNT) \
		-e SSH_USER=$(SSH_USER) \
		-e PUB_KEY="$$(cat $(PUB_KEY_PATH))" \
		$(IMAGE_NAME)
	@echo "Application container $(NAME2) started successfully!"

# Target to run the application container (NAME3)
run-app3:
	podman run -d --name $(NAME3) \
		--network $(NETWORK_NAME) \
		--ip $(IP3) \
		--hostname $(NAME3) \
		--privileged \
		--systemd=always \
		-p $(SSH_PORT3):22 \
		-v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		$(LOCAL_VOLUME_MOUNT) \
		-e SSH_USER=$(SSH_USER) \
		-e PUB_KEY="$$(cat $(PUB_KEY_PATH))" \
		$(IMAGE_NAME)
	@echo "Application container $(NAME3) started successfully!"

# Target to run the database container
run-db:
	podman run -d --name $(DB_NAME1) \
		--network $(NETWORK_NAME) \
		--ip $(DB_IP1) \
		--hostname $(DB_NAME1) \
		--privileged \
		-e POSTGRES_USER=$(DB_USER) \
		-e POSTGRES_PASSWORD=$(DB_PASS) \
		-e POSTGRES_DB=$(DB_NAME) \
		-v $(PWD)/$(DB_NAME1)_data:/var/lib/postgresql/data:Z \
		$(POSTGRES_IMAGE_NAME)
	@echo "Database container started successfully!"

# Target to run the database container
#	$(MAKE) create_s3_mock_bucket 
run-s3storage:
	podman run -d --name $(S3STORAGE_NAME) \
		--network $(NETWORK_NAME) \
		--ip $(S3STORAGE_IP) \
		--hostname $(S3STORAGE_NAME) \
		-p 9000:9000 \
		-v $(PWD)/$(S3STORAGE_NAME)_data:/data:Z \
		$(S3STORAGE_IMAGE_NAME)
	@echo "S3 storage container started successfully!"



# Target to create and start all containers
.PHONY: create_all
create_all: make_volume_dirs  #### create and start all containers
	$(MAKE) $(ALL_CONTAINER_RUN_MAKE_TARGETS)
	@echo "All containers created and started successfully!"

.PHONY: remove_all
remove_all: stop_all #### remove all running containers
	@echo "$(BLUE_COLOR)🔍 Removing any containers...$(NO_COLOR)"
	@podman rm -f $(ALL_CONTAINER_NAMES_STRING) || true

.PHONY: remove_all_nonrunning
remove_all_nonrunning:  #### removes all non-running containers (exited etc)
	@echo "$(BLUE_COLOR)🔍 Removing ALL NON-RUNNING containers...$(NO_COLOR)"
	@podman rm -f $$(podman ps -a | awk '{print $$1}' | xargs) || true

# Target to reinitialize the database container
reinit_db_data_dir:  #### remove and reinit persistent layer for db
	@echo "Do you want to remove FULL database data dir (all db data will be lost!)"
	$(MAKE) prompt_me
	@echo "Stopping and removing the existing container..."
	-podman stop $(DB_NAME1)
	-podman rm $(DB_NAME1)
	@echo "Removing local data directory..."
	sudo rm -rf $(PWD)/$(DB_NAME1)_data
	@echo "Recreating local data directory..."
	mkdir -p $(PWD)/$(DB_NAME1)_data
	@echo "Container reinitialized successfully!"
	@echo "Now you can restart your db container..."


##########################################################################################
## container runtime tasks
## (already created before):
.PHONY: start_all
start_all:  ## start all stopped (but already created) containers
	@echo "🛑 Stopping containers..."
	-@podman start $(ALL_CONTAINER_NAMES_STRING) || true

.PHONY: stop_all
stop_all:  ## stop all (already existing) containers
	@echo "🛑 Stopping containers..."
	@podman stop $(ALL_CONTAINER_NAMES_STRING) 2>/dev/null || true

.PHONY: restart_all
restart_all:  stop run ## restart = stop and start

.PHONY: clean_force
##########################################################################################
## housekeeping:
clean_all: remove  ## forcefull clean and remove all
	@echo "🧹 Removing containers and networks FORCEFULLY..."
	-@podman network rm -f $(NETWORK_NAME) || true

# this next condition bock is for the ssh_login and run_cmd target:
# its only important for $(NAME*) hosts
ifeq ($(MYHOSTNAME),$(NAME1))
  NAME := $(NAME1)
  SSH_PORT := $(SSH_PORT1)
  IP := $(IP1)
endif
ifeq ($(MYHOSTNAME),$(NAME2))
  NAME := $(NAME2)
  SSH_PORT := $(SSH_PORT2)
  IP := $(IP2)
endif
ifeq ($(MYHOSTNAME),$(NAME3))
  NAME := $(NAME3)
  SSH_PORT := $(SSH_PORT3)
  IP := $(IP3)
endif

# Log in to the container via SSH
# example:
# $(MAKE) ssh_login MYHOSTNAME=hostname1
.PHONY: ssh_login
##########################################################################################
## ssh specific tasks:
ssh_login:  ### login to containers via ssh, use MYHOSTNAME= variable
	@if [ -z "$(MYHOSTNAME)" ]; then \
		echo "$(RED_COLOR)Error: MYHOSTNAME variable is not set. Use MYHOSTNAME=hostname1 or hostname3 or hostname2$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ "$(PUB_KEY_PATH)" = "none" ]; then \
		echo "$(RED_COLOR)Error: No SSH public key found. Run 'make gen_ssh_container_keys' or ensure $(PUB_KEY_PATH) exists$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(SSH_PORT)" ]; then \
		echo "$(RED_COLOR)Error: PORT variable is not set. This is likey a non existant MYHOSTNAME which you set to $(MYHOSTNAME)" >&2; \
		exit 1; \
	fi
	@echo "$(BLUE_COLOR)Logging into container $(MYHOSTNAME) via SSH on port $(SSH_PORT)...$(NO_COLOR)" >&2
	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $(PRIV_KEY_PATH) -p $(SSH_PORT) $(SSH_USER)@localhost || { echo "$(RED_COLOR)Failed to log in via SSH$(NO_COLOR)" >&2; exit 1; }

.PHONY: ssh_run_cmd 
# example:
# check if port 22 is open on container1 from container 2
# $ make ssh_run_cmd MYHOSTNAME=hostname1 CMD="nc -vz $(make ssh_run_cmd MY HOSTNAME=hostname2 CMD=hostname) 22"
# Note: Instead of relying on inline quotes, base64 encode the command locally and decode it remotely.
ssh_run_cmd:  ### run cmd on container via ssh, MYHOSTNAME= and CMD=
	@if [ -z "$(MYHOSTNAME)" ]; then \
		echo "$(RED_COLOR)Error: MYHOSTNAME variable is not set. Use MYHOSTNAME=hostname1 or hostname3 or hostname2$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(CMD)" ]; then \
		echo "$(RED_COLOR)Error: CMD variable is not set. Use make run_cmd MYHOSTNAME=$(NUM) CMD=\"your command\"$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ "$(PUB_KEY_PATH)" = "none" ]; then \
		echo "$(RED_COLOR)Error: No SSH public key found. Run 'make gen_ssh_container_keys' or ensure $(PUB_KEY_PATH) exists$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(SSH_PORT)" ]; then \
		echo "$(RED_COLOR)Error: PORT variable is not set. This is likey a non existant MYHOSTNAME which you set to $(MYHOSTNAME)" >&2; \
		exit 1; \
	fi
	@echo "$(BLUE_COLOR)Running command on container $(MYHOSTNAME) via SSH on port $(SSH_PORT)...$(NO_COLOR)" >&2
	@ENCODED_CMD=$$(printf "%s" "$(CMD)" | base64 -w0) && \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	   -i $(PRIV_KEY_PATH) \
	   -p $(SSH_PORT) $(SSH_USER)@localhost \
	   -- "base64 -d | bash" <<< "$$ENCODED_CMD" \
	|| { echo "$(RED_COLOR)Failed to run command$(NO_COLOR)" >&2; exit 1; }
	@echo "$(GREEN_COLOR)Command executed successfully$(NO_COLOR)" >&2

.PHONY: get_all_files_and_folders
print_all_files_and_folders:  ### print all important files and folders on a linux system
	@if [ -z "$(MYHOSTNAME)" ]; then \
		echo "$(RED_COLOR)Error: MYHOSTNAME variable is not set. Use MYHOSTNAME=hostname1 or hostname3 or hostname2$(NO_COLOR)" >&2; \
		exit 1; \
	fi; \
	$(MAKE) ssh_run_cmd MYHOSTNAME=$(MYHOSTNAME) CMD="find / -xdev \( -path /tmp -o -path /var/tmp -o -path /dev/shm -o -path /run -o -path /proc -o -path /sys \) -prune -o -printf '%y %p\n' 2>/dev/null | sort"


.PHONY: rsync_copy_cmd_sudo
rsync_copy_cmd_sudo:  ### privileged rsync for MYHOSTNAME= with FROM= and TO=
	@if [ -z "$(MYHOSTNAME)" ]; then \
		echo "$(RED_COLOR)Error: MYHOSTNAME variable is not set. Use MYHOSTNAME=hostname1 or hostname3 or hostname2$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(FROM)" ]; then \
		echo "$(RED_COLOR)Error: FROM variable is not set. Use make run_cmd MYHOSTNAME=$(NUM) FROM=\"your command\"$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(TO)" ]; then \
		echo "$(RED_COLOR)Error: FROM variable is not set. Use make run_cmd MYHOSTNAME=$(NUM) TO=\"your command\"$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ "$(PUB_KEY_PATH)" = "none" ]; then \
		echo "$(RED_COLOR)Error: No SSH public key found. Run 'make gen_ssh_container_keys' or ensure $(PUB_KEY_PATH) exists$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(SSH_PORT)" ]; then \
		echo "$(RED_COLOR)Error: PORT variable is not set. This is likey a non existant MYHOSTNAME which you set to $(MYHOSTNAME)" >&2; \
		exit 1; \
	fi
	@echo "$(BLUE_COLOR)Copying from $(FROM) to $(TO) on $(MYHOSTNAME) via SSH on port $(SSH_PORT)...$(NO_COLOR)" >&2
	rsync -rav -e "ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -p $(SSH_PORT) \
	         -i $(PRIV_KEY_PATH)" \
	      $(FROM) root@localhost:$(TO) \
	|| { echo "$(RED_COLOR)Failed to run command$(NO_COLOR)" >&2; exit 1; }
	@echo "$(GREEN_COLOR)Command executed successfully$(NO_COLOR)" >&2

.PHONY: run_ansible_provisioning
run_ansible_provisioning:
	@if [ -z "$(ANSIBLE_PLAYBOOK)" ]; then \
		echo "$(RED_COLOR)Error: ANSIBLE_PLAYBOOK variable is not set.$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(ANSIBLE_PLAYBOOK)" ]; then \
		echo "$(RED_COLOR)Error: The Ansible playbook file $(ANSIBLE_PLAYBOOK) does not exist.$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(WORKFLOW_NAME)" ]; then \
		echo "$(RED_COLOR)Error: The parameter WORKFLOW_NAME (install|update|remove) does not exist.$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(RUN_STAGE)" ]; then \
		echo "$(RED_COLOR)Error: The parameter RUN_STAGE (lab|dev|inte|zka|zms) does not exist.$(NO_COLOR)" >&2; \
		exit 1; \
	fi
	base_path=$$(dirname $(ANSIBLE_PLAYBOOK) | sed 's/\/playbooks$$//'); \
	playbook=$$(basename $(ANSIBLE_PLAYBOOK)); \
	echo "$(BLUE_COLOR)Changing to base directory $$base_path and running playbook playbooks/$$playbook on nodes $(NAME1), $(NAME2), $(NAME3)...$(NO_COLOR)" >&2; \
        INV_PATH=$$PWD/inventory; \
	cd $$base_path && ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/$$playbook -i $$INV_PATH \
		-e "ansible_ssh_private_key_file=$(PRIV_KEY_PATH)" \
		-e "ansible_ssh_user=$(SSH_USER)" \
		-e "workflow_name=$(WORKFLOW_NAME)" \
		-e "RUN_STAGE=$(RUN_STAGE)" \
		|| { echo "$(RED_COLOR)Failed to run Ansible playbook$(NO_COLOR)" >&2; exit 1; }

##########################################################################################
## snapshot specific tasks:
# Create a snapshot with the provided SNAPSHOT_NAME
.PHONY: snapshot_all
snapshot_all: ## create container snapshot only for our app containers, using SNAPSHOT_NAME e.g "vanilla-install"
	@if [ -z "$(SNAPSHOT_NAME)" ]; then \
		echo "$(RED_COLOR)Error: SNAPSHOT_NAME variable is not set. Use make snapshot SNAPSHOT_NAME=\"snapshot_name\"$(NC)" >&2; \
		exit 1; \
	fi
	@echo "$(BLUE_COLOR)Creating snapshot $(SNAPSHOT_NAME)...$(NC)" >&2
	@for myname in $(NAME1) $(NAME2) $(NAME3); do \
	     podman commit $$myname $$myname:snapshot_$(SNAPSHOT_NAME) || { echo "$(RED_COLOR)Failed to create snapshot $(SNAPSHOT_NAME)$(NC)" >&2; exit 1; }; \
	     echo  "$(GREEN_COLOR)Snapshot $$myname:snapshot_$(SNAPSHOT_NAME) created successfully$(NC)" >&2; \
	done;

# Revert to a snapshot with the provided SNAPSHOT_NAME
.PHONY: revert_all_to
revert_all_to: ## revert to a snaphsot using its FULL_SNAPSHOT_NAME (e.g.localhost/rreeimreg002:snapshot_vanilla)
	@if [ -z "$(FULL_SNAPSHOT_NAME)" ]; then \
		echo "$(RED_COLOR)Error: FULL_SNAPSHOT_NAME variable is not set. Use make revert_to FULL_SNAPSHOT_NAME=\"bla/name:snapshot_name\"$(NC)" >&2; \
		exit 1; \
	fi
	@echo "$(BLUE_COLOR)Reverting to snapshot $(FULL_SNAPSHOT_NAME) for $(NAME1) $(NAME2) $(NAME3)...$(NC)" >&2
	$(MAKE) remove
	@if ! podman container inspect $(NAME1) --format '{{.State.Status}}' 2>/dev/null | grep -q "^running"; then \
	   podman run -d --name $(NAME1) \
		       --network $(NETWORK_NAME) \
		       --ip $(IP1) \
		       --hostname $(NAME1) \
		       --privileged \
		       --systemd=always \
		       -p $(SSH_PORT1):22 \
		       -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		       $(LOCAL_VOLUME_MOUNT) \
		       -e SSH_USER=$(SSH_USER) \
		       -e PUB_KEY="$$(cat $(PUB_KEY_PATH))" \
		       $(FULL_SNAPSHOT_NAME) || { echo "$(RED_COLOR)Failed to run container$(NO_COLOR)" >&2; exit 1; } \
	fi
	@if ! podman container inspect $(NAME2) --format '{{.State.Status}}' 2>/dev/null | grep -q "^running"; then \
	   podman run -d --name $(NAME2) \
		       --network $(NETWORK_NAME) \
		       --ip $(IP2) \
		       --hostname $(NAME2) \
		       --privileged \
		       --systemd=always \
		       -p $(SSH_PORT2):22 \
		       -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		       $(LOCAL_VOLUME_MOUNT) \
		       -e SSH_USER=$(SSH_USER) \
		       -e PUB_KEY="$$(cat $(PUB_KEY_PATH))" \
		       $(FULL_SNAPSHOT_NAME) || { echo "$(RED_COLOR)Failed to run container$(NO_COLOR)" >&2; exit 1; } \
	fi
	@if ! podman container inspect $(NAME3) --format '{{.State.Status}}' 2>/dev/null | grep -q "^running"; then \
	   podman run -d --name $(NAME3) \
		       --network $(NETWORK_NAME) \
		       --ip $(IP3) \
		       --hostname $(NAME3) \
		       --privileged \
		       --systemd=always \
		       -p $(SSH_PORT3):22 \
		       -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		       $(LOCAL_VOLUME_MOUNT) \
		       -e SSH_USER=$(SSH_USER) \
		       -e PUB_KEY="$$(cat $(PUB_KEY_PATH))" \
		       $(FULL_SNAPSHOT_NAME) || { echo "$(RED_COLOR)Failed to run container$(NO_COLOR)" >&2; exit 1; } \
	fi
	@echo "$(GREEN_COLOR)Reverted to snapshot $(SNAPSHOT_NAME) for $(NAME1) $(NAME2) $(NAME3) successfully$(NC)" >&2

# Show all snapshots for the image
.PHONY: list_all_snapshots
list_all_snapshots: ## show all snapshots by name
	@echo "$(BLUE_COLOR)Listing all snapshots for $(NAME1) $(NAME2) $(NAME3)...$(NC)" >&2
	@for myname in $(NAME1) $(NAME2) $(NAME3); do \
	    podman images --format "table {{.Repository}}:{{.Tag}} {{.ID}} {{.Created}} {{.Size}}" $$myname  || { echo "$(RED_COLOR)Failed to list snapshots$(NC)" >&2; exit 1; }; \
	done;
	@echo "$(GREEN_COLOR)Snapshot list displayed successfully$(NC)" >&2
.PHONY: container_status

# Remove all snapshots
.PHONY: remove_all_snapshots
remove_all_snapshots: ## remove all snapshots for containers
	@echo "$(BLUE_COLOR)Removing all snapshots for $(NAME1) $(NAME2) $(NAME3)...$(NC)" >&2
	$(MAKE) remove
	@for myname in $(NAME1) $(NAME2) $(NAME3); do \
		echo "removing all snapshots for $$myname"; \
		all_snapshot_names=$$(podman images --format "{{.ID}} {{.Repository}}:{{.Tag}}" | grep $$myname | grep ':snapshot_' |  awk '{print $$2}'); \
		for snapshot_name in $$all_snapshot_names; do \
			echo "$(YELLOW_COLOR)Removing snapshot: $$snapshot_name$(NC)"; \
			podman rmi -f "$$snapshot_name" || echo "$(RED_COLOR)Failed to remove $$img$(NC)"; \
		done \
	done
	@echo "$(GREEN_COLOR)All snapshots removed successfully$(NC)" >&2

# Remove a specific snapshot by name (e.g. make remove_snapshot NAME=my-rocky-systemd-ssh:latest)
.PHONY: remove_snapshot
remove_snapshot: ## remove a specific snapshot: SNAPSHOT_NAME=full/this:name
	@if [ -z "$(SNAPSHOT_NAME)" ]; then \
		echo "$(RED_COLOR)Error: SNAPSHOT_NAME is required (e.g., SNAPSHOT_NAME=localhost/blabliblub:latest)$(NC)" >&2; \
		exit 1; \
	fi
	@echo "$(BLUE_COLOR)Removing snapshot $(SNAPSHOT_NAME)...$(NC)" >&2
	@podman rmi "$(SNAPSHOT_NAME)" || echo "$(RED_COLOR)Failed to remove snapshot $(SNAPSHOT_NAME)$(NC)"
	@echo "$(GREEN_COLOR)Snapshot removal completed$(NC)" >&2

##########################################################################################
## database specific:

.PHONY: login_postgres_ssl
login_postgres_ssl: ### lets login to postgres using SSL
	@podman exec -it $$(podman ps -a | grep 'postgres'| awk '{print $$1}') psql "sslmode=require host=localhost port=5432 dbname=harbor_dev user=harbor_dev password=$(DB_PASS)"


##########################################################################################
## healthchecks:

.PHONY: webproxycache_logs
logs_webproxycache:  #### open logs for webproxycache container
	@podman logs -f $$(podman ps -a | grep 'localhost/webproxycache'| awk '{print $$1}')

.PHONY: logs_rsyslogd 
logs_rsyslogd:  #### open logs for rsyslogd container
	@podman logs -f $$(podman ps -a | grep 'rsyslogd'| awk '{print $$1}')

.PHONY: logs_loadbalancer
logs_loadbalancer:  #### open logs for rsyslogd container
	@podman logs -f $$(podman ps -a | grep 'loadbalancer'| awk '{print $$1}')

.PHONY: logs_s3storage
logs_s3storage:  #### open logs for s3storage container
	@podman logs -f $$(podman ps -a | grep 's3storage'| awk '{print $$1}')


.PHONY: is_running 
is_running:  #### get if all my containers are running
	@echo "$(BLUE_COLOR)🔍 Checking container statuses...$(NO_COLOR)"
	@RC=0; \
	for container in $(ALL_CONTAINER_NAMES_STRING); do \
		if podman container inspect $$container --format '{{.State.Status}}' 2>/dev/null | grep -q running; then \
			echo "✅  $$container is running"; \
		else \
			echo "❌  $$container is NOT running"; \
			RC=1; \
		fi; \
	done; \
	exit $$RC;

.PHONY: test_proxy_cache
test_proxy_cache: #### test proxy connections working on harbor clients
	@echo "\n-- Testing proxy cache..."
	@for myname in $(NAME1) $(NAME2) $(NAME3); do \
	   echo "\n-- Removing cached files before test"; \
	   for cached_file in 7a9d29f73e30526bcab0ff6515991229237a7239b7ddcbfebcc8300ca94dffc9.cache 7a9d29f73e30526bcab0ff6515991229237a7239b7ddcbfebcc8300ca94dffc9.headers.json a91b9506684339ea6369494a4d59e1a50d3e6e52cc2c1841c29c77258b196768.cache a91b9506684339ea6369494a4d59e1a50d3e6e52cc2c1841c29c77258b196768.headers.json accel-config-libs-3.4.2-2.el9.i686.rpm.cache accel-config-libs-3.4.2-2.el9.i686.rpm.headers.json d66845f0786072148d6e510c024e2f7c3a0c0793b583449aa241875c0f30b274.cache d66845f0786072148d6e510c024e2f7c3a0c0793b583449aa241875c0f30b274.headers.json dc62f229ff73aab1db1714b6551a206fecb1607ec77dc750a9dfef546c788e14.cache dc62f229ff73aab1db1714b6551a206fecb1607ec77dc750a9dfef546c788e14.headers.json; do \
	        rm -f webproxycache_data/$$cached_file; \
	   done; \
	   $(MAKE) ssh_run_cmd MYHOSTNAME=$$myname \
	        CMD="/tests/test_mitmproxy_script.sh" \
	        && echo "$(GREEN_COLOR)proxy web cache is working ✅$(NC)"  \
	        || (echo "$(RED_COLOR)proxy web cache IS NOT working ❌$(NC)" && exit 1); \
		sleep 6; \
	done

test_s3storage_connect: #### test if we can connect, store and download a file from harbor containers to s3storage container
	@echo "\n-- Testing S3 storage..."
	@for myname in $(NAME1) $(NAME2) $(NAME3); do \
	   $(MAKE) ssh_run_cmd MYHOSTNAME=$$myname \
	        CMD="/tests/test_s3storage_script.sh" \
	        && echo "$(GREEN_COLOR)S3 storage connection and upload/download is working ✅$(NC)"  \
	        || (echo "$(RED_COLOR)S3 storage connection IS NOT working ❌$(NC)" && exit 1); \
		sleep 3; \
	done
	

.PHONY: test_ca_trust
test_ca_trust: #### Test if CA certificate is in trust store
	@echo "\n-- Checking for CA certificate in /etc/pki/ca-trust/source/anchors/"
	@for myname in $(NAME1) $(NAME2) $(NAME3); do \
	   for cert_name in mitmproxy rsyslog loadbalancer postgres s3storage; do
	      $(MAKE) ssh_run_cmd MYHOSTNAME=$$myname \
	           CMD="grep -q ${cert_name} /etc/ssl/keys_and_certs/ca-bundle.crt" \
		   && echo "$(GREEN_COLOR)web proxy cache cert detected in OS truststore ✅$(NC)"  \
	           || (echo "$(RED_COLOR)web proxy cache cert NOT detected in OS truststore ❌$(NC)" && exit 1) \
	   done \
	done;


.PHONY: debug
debug:
	@make remove && rm -rf webproxycache_data && make build_all_images && make build_all_images && make create; podman logs -f $$(podman ps -a | grep 'localhost/webproxycache'| awk '{print $$1}')

debug_squidproxy_DEPRECATED:
	   podman run --name $(WEBPROXYCACHE_NAME1) \
		       --network $(NETWORK_NAME) \
		       --ip $(WEBPROXYCACHE_IP1) \
		       --hostname $(WEBPROXYCACHE_NAME1) \
		       -p 3128:3128 \
	               -it \
		       docker.io/salrashid123/squidproxy@sha256:latest /bin/bash 
