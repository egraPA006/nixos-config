#!/usr/bin/env bash
set -euo pipefail

host="${1:-mosk}"
disk="${2:-/dev/vda}"
ssh_key_file="${3:-}"
case "$host" in mosk|halos) ;; *) echo "Usage: sudo $0 <mosk|halos> [disk] [public-key-file]" >&2; exit 1 ;; esac
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$repo_dir/scripts/partition.sh" "$host" "$disk"
if [ -n "$ssh_key_file" ]; then
  "$repo_dir/scripts/install.sh" "$host" --ssh-key-file "$ssh_key_file" --keep-hardware
else
  "$repo_dir/scripts/install.sh" "$host"
fi
