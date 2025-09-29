#!/bin/bash

if [ -n "${http_proxy}" ]; then
    echo "export http_proxy=${http_proxy}" >> /home/${SSH_USER}/.bashrc
    echo "export https_proxy=${http_proxy}" >> /home/${SSH_USER}/.bashrc
    echo "export HTTP_PROXY=${http_proxy}" >> /home/${SSH_USER}/.bashrc
    echo "export HTTPS_PROXY=${http_proxy}" >> /home/${SSH_USER}/.bashrc
fi

if [ -n "${no_proxy}" ]; then
    echo "export no_proxy=${no_proxy}" >> /home/${SSH_USER}/.bashrc
    echo "export NO_PROXY=${no_proxy}" >> /home/${SSH_USER}/.bashrc
fi

if [ -n "${http_proxy}" ]; then
    echo "export http_proxy=${http_proxy}" >> /root/.bashrc
    echo "export https_proxy=${http_proxy}" >> /root/.bashrc
    echo "export HTTP_PROXY=${http_proxy}" >> /root/.bashrc
    echo "export HTTPS_PROXY=${http_proxy}" >> /root/.bashrc
fi

if [ -n "${no_proxy}" ]; then
    echo "export no_proxy=${no_proxy}" >> /root/.bashrc
    echo "export NO_PROXY=${no_proxy}" >> /root/.bashrc
fi

TODO no_proxy, NO_PROXY and CERT_BASE64_STRING
