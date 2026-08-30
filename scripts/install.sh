#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: sudo $0 [install|repair] <host>" >&2
}

[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
case "${1:-}" in
  install|repair) operation="$1"; host="${2:-}" ;;
  *) operation=install; host="${1:-}" ;;
esac
[ -n "$host" ] || { usage; exit 1; }

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
host_dir="$repo_dir/hosts/$host"
[ -d "$host_dir" ] || { echo "Unknown host: $host" >&2; exit 1; }
findmnt --mountpoint /mnt >/dev/null || {
  echo "/mnt is not mounted. Run scripts/partition.sh or mount the system first." >&2
  exit 1
}

if [ "$operation" = install ]; then
  echo "Generating $host_dir/hardware.nix from the mounted target..."
  hardware_owner="$(stat -c '%u:%g' "$host_dir/hardware.nix")"
  hardware_tmp="$(mktemp "$host_dir/hardware.nix.XXXXXX")"
  trap 'rm -f "$hardware_tmp"' EXIT
  nixos-generate-config --root /mnt --show-hardware-config --no-filesystems > "$hardware_tmp"
  mv "$hardware_tmp" "$host_dir/hardware.nix"
  chown "$hardware_owner" "$host_dir/hardware.nix"
  trap - EXIT
fi

flake="path:$repo_dir#nixosConfigurations.$host.config"
pino_user="$(nix --extra-experimental-features 'nix-command flakes' eval --raw "$flake.pino.user.name")"
pino_home="$(nix --extra-experimental-features 'nix-command flakes' eval --raw "$flake.pino.user.home")"
config_dir="$(nix --extra-experimental-features 'nix-command flakes' eval --raw "$flake.pino.configDir")"

ssh_key=""
if [ "$operation" = install ]; then
  read -r -p "SSH public key for $pino_user (empty to skip): " ssh_key
  if [[ "$host" = mosk || "$host" = halos ]] && [ -z "$ssh_key" ]; then
    echo "An SSH public key is required for a passwordless server." >&2
    exit 1
  fi
  case "$ssh_key" in
    ""|ssh-ed25519\ *|ssh-rsa\ *|sk-ssh-ed25519@openssh.com\ *) ;;
    *) echo "Unsupported SSH public key." >&2; exit 1 ;;
  esac
fi

echo "Installing $host from $repo_dir..."
nixos-install --flake "path:$repo_dir#$host" --no-root-passwd

echo "Copying the Git checkout to /mnt$config_dir..."
install -d "/mnt$pino_home" "/mnt$config_dir"
rsync -a --delete \
  --exclude result --exclude 'result-*' \
  "$repo_dir/" "/mnt$config_dir/"

uid="$(awk -F: -v user="$pino_user" '$1 == user { print $3 }' /mnt/etc/passwd)"
gid="$(awk -F: -v user="$pino_user" '$1 == user { print $4 }' /mnt/etc/passwd)"
[ -n "$uid" ] && [ -n "$gid" ] || { echo "Installed user not found: $pino_user" >&2; exit 1; }
chown -R "$uid:$gid" "/mnt$pino_home"

if [ "$operation" = install ]; then
  if [ -n "$ssh_key" ]; then
    install -d -o "$uid" -g "$gid" -m 0700 "/mnt$pino_home/.ssh"
    printf '%s\n' "$ssh_key" > "/mnt$pino_home/.ssh/authorized_keys"
    chown "$uid:$gid" "/mnt$pino_home/.ssh/authorized_keys"
    chmod 0600 "/mnt$pino_home/.ssh/authorized_keys"
  fi
  echo "Set the local password for $pino_user:"
  nixos-enter --root /mnt -c "passwd $pino_user"
fi

echo "$host $operation complete. The bootloader was installed from the current configuration."
