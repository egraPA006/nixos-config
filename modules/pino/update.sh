#!/usr/bin/env bash
# pino update — delete old pre-update snapshots, snapshot, flake update, rebuild
CONFIG_DIR="/home/egrapa/nixos-config"


echo "Removing old pre-update snapshots..."
for cfg in root home; do
  ids=$(sudo snapper -c "$cfg" list --columns number,description 2>/dev/null \
        | awk '$2 == "pre-update" {print $1}') || true
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    sudo snapper -c "$cfg" delete $ids
  fi
done

echo "Snapshotting root + home (pre-update)..."
sudo snapper -c root create -d pre-update
sudo snapper -c home create -d pre-update

echo "Updating flake inputs..."
nix flake update "$CONFIG_DIR"

echo "Rebuilding..."
sudo nixos-rebuild switch --flake "$CONFIG_DIR#$(hostname)"
