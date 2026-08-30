#!/usr/bin/env bash
set -euo pipefail

host="${1:-mosk}"
disk="${2:-/dev/vda}"
case "$host" in mosk|halos) ;; *) echo "Usage: sudo $0 <mosk|halos> [disk]" >&2; exit 1 ;; esac
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$repo_dir/scripts/partition.sh" "$host" "$disk"
"$repo_dir/scripts/install.sh" "$host"
