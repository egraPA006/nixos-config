#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: sudo $0 [install|repair] <host> [--ssh-key-file <public-key>] [--keep-hardware]" >&2
}

[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
case "${1:-}" in
  install|repair) operation="$1"; shift ;;
  *) operation=install ;;
esac
host="${1:-}"
[ -n "$host" ] || { usage; exit 1; }
shift || true
ssh_key_file=""
keep_hardware=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ssh-key-file)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      ssh_key_file="$2"
      shift 2
      ;;
    --keep-hardware)
      keep_hardware=true
      shift
      ;;
    *) usage; exit 1 ;;
  esac
done

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
host_dir="$repo_dir/hosts/$host"
[ -d "$host_dir" ] || { echo "Unknown host: $host" >&2; exit 1; }
findmnt --mountpoint /mnt >/dev/null || {
  echo "/mnt is not mounted. Run scripts/partition.sh or mount the system first." >&2
  exit 1
}

if [ "$operation" = install ] && [ "$keep_hardware" = false ]; then
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
  if [ -n "$ssh_key_file" ]; then
    [ -f "$ssh_key_file" ] || { echo "SSH public key file not found: $ssh_key_file" >&2; exit 1; }
    ssh_key="$(tr -d '\r' < "$ssh_key_file")"
    [[ "$ssh_key" != *$'\n'* ]] || { echo "SSH public key file must contain exactly one key." >&2; exit 1; }
  else
    read -r -p "SSH public key for $pino_user (empty to skip): " ssh_key
  fi
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

if [[ "$host" = mosk || "$host" = halos ]]; then
  install -d -m 0755 /mnt/etc/ssh
  ssh-keygen -A -f /mnt
fi

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
  if [[ "$host" != mosk && "$host" != halos ]]; then
    echo "Set the local password for $pino_user:"
    nixos-enter --root /mnt -c "passwd $pino_user"
  fi
fi

echo "$host $operation complete. The bootloader was installed from the current configuration."
