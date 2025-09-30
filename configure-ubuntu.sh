#!/bin/bash
#set -x

MY_SSH_USER=${MY_SSH_USER:-podmanuser}
PUB_KEY=${PUB_KEY:-}

# Ensure user exists (Ubuntu: useradd works; adduser also ok)
if ! id "${MY_SSH_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${MY_SSH_USER}"
    mkdir -p /home/${MY_SSH_USER}/.ssh
    chown ${MY_SSH_USER}:${MY_SSH_USER} /home/${MY_SSH_USER}/.ssh
    chmod 700 /home/${MY_SSH_USER}/.ssh
    install -d -m 0750 /etc/sudoers.d
    printf '%s\n' "${MY_SSH_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${MY_SSH_USER}
    chmod 0440 /etc/sudoers.d/${MY_SSH_USER}
fi

mkdir -p /root/.ssh

if [ -n "${PUB_KEY}" ]; then
    echo "${PUB_KEY}" > /home/${MY_SSH_USER}/.ssh/authorized_keys
    chown ${MY_SSH_USER}:${MY_SSH_USER} /home/${MY_SSH_USER}/.ssh/authorized_keys
    chmod 600 /home/${MY_SSH_USER}/.ssh/authorized_keys

    # also add the same key to root user
    echo "${PUB_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /home/${MY_SSH_USER}/.ssh/authorized_keys
    
else
    echo "No pubkey ${PUB_KEY} provided...bailing out, because can not connect via ssh"
    exit 1
fi

