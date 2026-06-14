#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"
TARGET="hosts/$HOST/hardware.nix"

if [ ! -d "hosts/$HOST" ]; then
  echo "Error: hosts/$HOST does not exist"
  exit 1
fi

echo "Generating hardware config for $HOST..."
nixos-generate-config --show-hardware-config --no-filesystems > "$TARGET"
echo "Written to $TARGET"
