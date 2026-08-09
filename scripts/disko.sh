#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISKO="$REPO_DIR/hosts/$HOST/disko.nix"

if [ ! -f "$DISKO" ]; then
  echo "Error: $DISKO not found"
  exit 1
fi

echo "WARNING: This will wipe disks defined in $DISKO"
echo "Check with 'lsblk' that device names match before proceeding."
read -rp "Type YES to continue: " confirm
if [ "$confirm" != "YES" ]; then
  echo "Aborted."
  exit 1
fi

# Disko performs the necessary evaluation itself. Do not evaluate the full host
# first: the live ISO's writable Nix store is intentionally small.
sudo nix --extra-experimental-features "nix-command flakes" \
  run github:nix-community/disko -- --mode disko "$DISKO"
