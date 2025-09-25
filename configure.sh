#!/bin/bash
#set -x


# Configure SSH access in firewalld *offline*
firewall-offline-cmd --add-service=ssh || true

# Reload later (via systemd once firewalld is running). We don’t call firewall-cmd here.

# Configure SSH user and public key based on environment variables
SSH_USER=${SSH_USER:-podmanuser}
PUB_KEY=${PUB_KEY:-}

# Ensure user exists
if ! id "${SSH_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${SSH_USER}"
    mkdir -p /home/${SSH_USER}/.ssh
    chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.ssh
    chmod 700 /home/${SSH_USER}/.ssh
fi

mkdir -p /root/.ssh

# Copy public key if provided
if [ -n "${PUB_KEY}" ]; then
    echo "${PUB_KEY}" > /home/${SSH_USER}/.ssh/authorized_keys
    chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.ssh/authorized_keys
    chmod 600 /home/${SSH_USER}/.ssh/authorized_keys

    # also add the same key to root user
    echo "${PUB_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /home/${SSH_USER}/.ssh/authorized_keys
    
else
    echo "No pubkey ${PUB_KEY} provided...bailing out, because can not connect via ssh"
    exit 1
fi
