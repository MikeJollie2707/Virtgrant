#!/bin/bash
set -euo pipefail

usage() {
    local exit_code=${1:-2}

    printf '%s\n' "Usage: $0 --src-img SOURCE_IMAGE --dest-img DEST_IMAGE --disk-size SIZE [OPTIONS]" >&2
    printf '%s\n' "" >&2
    printf '%s\n' "Required options:" >&2
    printf '%s\n' "  --src-img PATH       Source cloud image" >&2
    printf '%s\n' "  --dest-img PATH      Destination VM disk" >&2
    printf '%s\n' "  --disk-size SIZE     Destination disk size, for example 30G" >&2
    printf '%s\n' "" >&2
    printf '%s\n' "Optional overrides:" >&2
    printf '%s\n' "  --memory MB          Memory in MiB (default: MEMORY_MB or 2048)" >&2
    printf '%s\n' "  --vcpu COUNT         Virtual CPU count (default: VCPUS or 2)" >&2
    printf '%s\n' "  --network NAME       Libvirt network (default: NETWORK or default)" >&2
    printf '%s\n' "  --vm-name NAME       Libvirt VM name (default: VM_NAME or destination name)" >&2
    printf '%s\n' "  --user USER          SSH user for post-launch cleanup (default: debian)" >&2
    printf '%s\n' "  --help               Show this help" >&2
    exit "$exit_code"
}

require_option_value() {
    local option=$1

    if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "Option requires a value: $option" >&2
        usage
    fi
}

require_commands() {
    local command

    for command in cp mktemp mv qemu-img rm virsh virt-install; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "Required command not found: $command" >&2
            exit 1
        fi
    done
}

remove_vm() {
    local vm_name=$1

    if virsh dominfo "$vm_name" >/dev/null 2>&1; then
        virsh destroy "$vm_name" >/dev/null 2>&1 || true
        virsh undefine "$vm_name" --managed-save >/dev/null 2>&1 || \
            virsh undefine "$vm_name" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    local status=$?

    rm -f -- "$TEMP_IMAGE"
    if (( status != 0 )); then
        echo "Build failed; removing VM and disk artifacts." >&2
        remove_vm "$VM_NAME"
        rm -f -- "$DEST_IMAGE"
    fi

    exit "$status"
}

get_vm_ip() {
    local vm_name=$1
    local ip_address

    # Match IPv4 records and exclude loopback addresses from virsh output.
    ip_address=$(virsh domifaddr "$vm_name" --source agent 2>/dev/null |
        awk '$3 == "ipv4" && $4 !~ /^127\./ {
            split($4, address, "/")
            print address[1]
            exit
        }')

    if [[ -n "$ip_address" ]]; then
        printf '%s\n' "$ip_address"
        return
    fi

    # Match the first IPv4 DHCP lease returned by libvirt.
    virsh domifaddr "$vm_name" --source lease 2>/dev/null |
        awk '$3 == "ipv4" {
            split($4, address, "/")
            print address[1]
            exit
        }'
}

wait_for_vm_ip() {
    local vm_name=$1
    local attempts=0
    local ip_address

    while :; do
        if ! virsh dominfo "$vm_name" >/dev/null 2>&1; then
            echo "VM no longer exists while waiting for an IP address: $vm_name" >&2
            return 1
        fi

        ip_address=$(get_vm_ip "$vm_name")
        if [[ -n "$ip_address" ]]; then
            printf '%s\n' "$ip_address"
            return
        fi

        attempts=$((attempts + 1))
        if (( attempts % 30 == 0 )); then
            echo "Still waiting for an IP address from $vm_name..." >&2
        fi
        sleep 1
    done
}

SOURCE_IMAGE=
DEST_IMAGE=
DISK_SIZE=
MEMORY_MB=${MEMORY_MB:-2048}
VCPUS=${VCPUS:-2}
NETWORK=${NETWORK:-default}
VM_NAME=${VM_NAME:-}
GUEST_USER=debian

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-img)
            require_option_value "$@"
            SOURCE_IMAGE=$2
            shift 2
            ;;
        --dest-img)
            require_option_value "$@"
            DEST_IMAGE=$2
            shift 2
            ;;
        --disk-size)
            require_option_value "$@"
            DISK_SIZE=$2
            shift 2
            ;;
        --memory)
            require_option_value "$@"
            MEMORY_MB=$2
            shift 2
            ;;
        --vcpu)
            require_option_value "$@"
            VCPUS=$2
            shift 2
            ;;
        --network)
            require_option_value "$@"
            NETWORK=$2
            shift 2
            ;;
        --vm-name)
            require_option_value "$@"
            VM_NAME=$2
            shift 2
            ;;
        --user)
            require_option_value "$@"
            GUEST_USER=$2
            shift 2
            ;;
        --help)
            usage 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

[[ -n "$SOURCE_IMAGE" ]] || {
    echo "Missing required option: --src-img" >&2
    usage
}
[[ -n "$DEST_IMAGE" ]] || {
    echo "Missing required option: --dest-img" >&2
    usage
}
[[ -n "$DISK_SIZE" ]] || {
    echo "Missing required option: --disk-size" >&2
    usage
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
USER_DATA="$SCRIPT_DIR/config/user-data.yml"
META_DATA="$SCRIPT_DIR/config/meta-data.yml"
NETWORK_CONFIG="$SCRIPT_DIR/config/network-config.yml"
POST_LAUNCH_SCRIPT="$SCRIPT_DIR/post-launch.sh"
DEST_DIR=$(dirname -- "$DEST_IMAGE")
if [[ -z "$VM_NAME" ]]; then
    VM_NAME=$(basename -- "$DEST_IMAGE")
    VM_NAME=${VM_NAME%.qcow2}
    VM_NAME=${VM_NAME%.img}
fi
TEMP_IMAGE=

[[ -f "$SOURCE_IMAGE" ]] || {
    echo "Source image does not exist: $SOURCE_IMAGE" >&2
    exit 1
}
[[ -d "$DEST_DIR" && -w "$DEST_DIR" ]] || {
    echo "Destination directory is not writable: $DEST_DIR" >&2
    exit 1
}
for input_file in "$USER_DATA" "$META_DATA" "$NETWORK_CONFIG" "$POST_LAUNCH_SCRIPT"; do
    [[ -f "$input_file" ]] || {
        echo "Required file does not exist: $input_file" >&2
        exit 1
    }
done
[[ -x "$POST_LAUNCH_SCRIPT" ]] || {
    echo "Post-launch script is not executable: $POST_LAUNCH_SCRIPT" >&2
    exit 1
}
if [[ -e "$DEST_IMAGE" && "$SOURCE_IMAGE" -ef "$DEST_IMAGE" ]]; then
    echo "Source and destination image must differ: $SOURCE_IMAGE" >&2
    exit 1
fi

require_commands
remove_vm "$VM_NAME"
rm -f -- "$DEST_IMAGE"

TEMP_IMAGE=$(mktemp --tmpdir="$DEST_DIR" ".${VM_NAME}.XXXXXX.qcow2")
trap cleanup EXIT

cp -- "$SOURCE_IMAGE" "$TEMP_IMAGE"
qemu-img resize "$TEMP_IMAGE" "$DISK_SIZE"
mv -- "$TEMP_IMAGE" "$DEST_IMAGE"
TEMP_IMAGE=

virt-install \
    --name "$VM_NAME" \
    --memory "$MEMORY_MB" \
    --vcpus "$VCPUS" \
    --import \
    --disk "path=$DEST_IMAGE,format=qcow2,bus=virtio" \
    --network "network=$NETWORK,model=virtio" \
    --os-variant debian13 \
    --graphics none \
    --console pty,target_type=serial \
    --cloud-init "user-data=$USER_DATA,meta-data=$META_DATA,network-config=$NETWORK_CONFIG" \
    --noautoconsole \
    --noreboot

echo "Waiting for an address (this takes a while)..."
IP_ADDRESS=$(wait_for_vm_ip "$VM_NAME")
echo "VM IP address: $IP_ADDRESS"
"$POST_LAUNCH_SCRIPT" "$GUEST_USER" "$IP_ADDRESS"

trap - EXIT
echo "Disk ready for packaging: $DEST_IMAGE"
