#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "hosts/$HOST" ]; then
  echo "Error: hosts/$HOST does not exist"
  exit 1
fi

echo "Copying repo to /mnt/etc/nixos..."
sudo cp -r "$REPO_DIR" /mnt/etc/nixos

echo "Installing NixOS for $HOST..."
sudo nixos-install --flake "/mnt/etc/nixos#$HOST"

echo ""
echo "Done. Reboot and set password with: passwd egrapa"
