#!/usr/bin/env bash
set -euo pipefail

host="${1:-}"
[ -n "$host" ] && [ -d "hosts/$host" ] || { echo "Usage: $0 <host>" >&2; exit 1; }
findmnt --mountpoint /mnt >/dev/null || { echo "/mnt is not mounted." >&2; exit 1; }
nixos-generate-config --root /mnt --show-hardware-config --no-filesystems > "hosts/$host/hardware.nix"
echo "Generated hosts/$host/hardware.nix from /mnt."
