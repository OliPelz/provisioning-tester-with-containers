#!/usr/bin/env bash
#set -euo pipefail

MY_SSH_USER=${MY_SSH_USER:-podmanuser}
PUB_KEY=${PUB_KEY:-}

if ! id "${MY_SSH_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${MY_SSH_USER}"
    install -d -m 0700 -o "${MY_SSH_USER}" -g "${MY_SSH_USER}" "/home/${MY_SSH_USER}/.ssh"
    install -d -m 0750 /etc/sudoers.d
    printf '%s\n' "${MY_SSH_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${MY_SSH_USER}"
    chmod 0440 "/etc/sudoers.d/${MY_SSH_USER}"
fi

install -d -m 0700 /root/.ssh

if [ -n "${PUB_KEY}" ]; then
    echo "${PUB_KEY}" > "/home/${MY_SSH_USER}/.ssh/authorized_keys"
    chown "${MY_SSH_USER}:${MY_SSH_USER}" "/home/${MY_SSH_USER}/.ssh/authorized_keys"
    chmod 600 "/home/${MY_SSH_USER}/.ssh/authorized_keys"

    echo "${PUB_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
else
    echo "No pubkey provided (PUB_KEY='${PUB_KEY}'). Bailing out."
    exit 1
fi

