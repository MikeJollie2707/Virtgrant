#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 DISK BOX_NAME" >&2
    echo "Packages DISK as a libvirt Vagrant box named BOX_NAME." >&2
    exit 2
}

require_commands() {
    local command

    for command in cp mktemp tar vagrant; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "Required command not found: $command" >&2
            exit 1
        fi
    done
}

cleanup() {
    rm -rf -- "$BUILD_DIR"
    rm -f -- "$BOX_ARCHIVE"
}

[[ $# -eq 2 ]] || usage

DISK=$1
BOX_NAME=$2
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
METADATA_FILE="$SCRIPT_DIR/config/metadata.json"
BUILD_DIR=
BOX_ARCHIVE=

[[ -f "$DISK" ]] || {
    echo "Disk does not exist: $DISK" >&2
    exit 1
}
[[ -f "$METADATA_FILE" ]] || {
    echo "Metadata file does not exist: $METADATA_FILE" >&2
    exit 1
}

require_commands

BUILD_DIR=$(mktemp -d)
BOX_ARCHIVE=$(mktemp --suffix=.box)
trap cleanup EXIT

echo "Packaging..."
cp -- "$DISK" "$BUILD_DIR/box.img"
cp -- "$METADATA_FILE" "$BUILD_DIR/metadata.json"
tar -C "$BUILD_DIR" -czf "$BOX_ARCHIVE" box.img metadata.json

echo "Replacing local libvirt box: $BOX_NAME"
vagrant box remove "$BOX_NAME" --provider=libvirt --all >/dev/null 2>&1 || true
vagrant box add --name "$BOX_NAME" --provider=libvirt --force "$BOX_ARCHIVE"

echo "Added local libvirt box: $BOX_NAME"
