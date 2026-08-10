#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 USER IP" >&2
    echo "Waits for SSH, cleans cloud-init state, and shuts down the VM." >&2
    exit 2
}

require_commands() {
    local command

    for command in nc ssh; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "Required command not found: $command" >&2
            exit 1
        fi
    done
}

wait_for_ssh() {
    local ip=$1
    local attempts=0

    until nc -z -w 3 "$ip" 22; do
        attempts=$((attempts + 1))
        if (( attempts % 30 == 0 )); then
            echo "Still waiting for SSH at $ip..." >&2
        fi
        sleep 1
    done
}

[[ $# -eq 2 ]] || usage

USER_NAME=$1
IP_ADDRESS=$2
SSH_CONNECTION="$USER_NAME@$IP_ADDRESS"

require_commands
wait_for_ssh "$IP_ADDRESS"

ssh \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "~/.ssh/id_ed25519_nopass" \
    -- "$SSH_CONNECTION" \
    'cloud-init status --wait && sudo cloud-init clean --logs --machine-id && sudo poweroff'
