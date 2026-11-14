#!/usr/bin/env bash
set -euo pipefail

host="${1:-mosk}"
disk="${2:-/dev/vda}"
ssh_key_file="${3:-}"
case "$host" in mosk|halos) ;; *) echo "Usage: sudo $0 <mosk|halos> [disk] [public-key-file]" >&2; exit 1 ;; esac
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$repo_dir/scripts/partition.sh" "$host" "$disk"
swap_file=/mnt/.pino-install.swap
memory_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
swap_kib="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
created_swap=false
if [[ "$memory_kib" =~ ^[0-9]+$ && "$swap_kib" =~ ^[0-9]+$ ]] &&
   [ "$memory_kib" -lt 3145728 ] && [ "$swap_kib" -eq 0 ]; then
  [ ! -e "$swap_file" ] && [ ! -L "$swap_file" ] || {
    echo "Temporary swap path already exists: $swap_file" >&2; exit 1
  }
  available_kib="$(df -Pk /mnt | awk 'NR == 2 {print $4}')"
  [[ "$available_kib" =~ ^[0-9]+$ ]] && [ "$available_kib" -ge 5242880 ] || {
    echo 'Not enough space to create a 2 GiB temporary swap and install the system.' >&2; exit 1
  }
  echo 'Enabling 2 GiB temporary swap on the installation disk.'
  umask 077
  fallocate -l 2G "$swap_file"
  chmod 0600 "$swap_file"
  mkswap "$swap_file" >/dev/null
  swapon "$swap_file"
  created_swap=true
fi
if [ -n "$ssh_key_file" ]; then
  "$repo_dir/scripts/install.sh" "$host" --ssh-key-file "$ssh_key_file" --keep-hardware
else
  "$repo_dir/scripts/install.sh" "$host"
fi
if [ "$created_swap" = true ]; then
  if swapoff "$swap_file"; then
    rm -f -- "$swap_file"
    echo 'Temporary installer swap removed.'
  else
    echo "Installation succeeded, but temporary swap remains active: $swap_file" >&2
    echo 'Remove it after reboot when it is no longer active.' >&2
  fi
fi
