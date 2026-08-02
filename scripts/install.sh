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

echo "Copying repo to /mnt/home/egrapa/nixos-config..."
sudo mkdir -p /mnt/home/egrapa/
sudo cp -r "$REPO_DIR" /mnt/home/egrapa/nixos-config

echo "Installing NixOS for $HOST..."
sudo nixos-install --flake "/mnt/home/egrapa/nixos-config#$HOST"

echo ""
echo "Done. Reboot and set password with: passwd egrapa"
