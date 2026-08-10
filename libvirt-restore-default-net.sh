#!/bin/bash
set -euo pipefail

DEFAULT_NETWORK=default
DEFAULT_NETWORK_XML=/usr/share/libvirt/networks/default.xml

require_commands() {
    if ! command -v sudo >/dev/null 2>&1; then
        echo "Required command not found: sudo" >&2
        exit 1
    fi

    if ! command -v virsh >/dev/null 2>&1; then
        echo "Required command not found: virsh" >&2
        exit 1
    fi
}

require_commands
[[ -f "$DEFAULT_NETWORK_XML" ]] || {
    echo "Default network definition does not exist: $DEFAULT_NETWORK_XML" >&2
    exit 1
}

sudo -v

if ! sudo virsh net-info "$DEFAULT_NETWORK" >/dev/null 2>&1; then
    sudo virsh net-define "$DEFAULT_NETWORK_XML"
fi

sudo virsh net-autostart "$DEFAULT_NETWORK"
sudo virsh net-start "$DEFAULT_NETWORK"

echo "Default libvirt network is active."
