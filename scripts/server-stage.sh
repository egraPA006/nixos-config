#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: sudo $0 <host> <whole-disk-device>" >&2
  echo "Example: sudo $0 mosk /dev/vda" >&2
}

[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
[ "$#" -eq 2 ] || { usage; exit 1; }

HOST="$1"
DISK="$2"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST_DIR="$REPO_DIR/hosts/$HOST"
DISKO_FILE="$HOST_DIR/disko.nix"
HARDWARE_FILE="$HOST_DIR/hardware.nix"

[ -d "$HOST_DIR" ] || { echo "Unknown host: $HOST" >&2; exit 1; }
[ -b "$DISK" ] || { echo "Not a block device: $DISK" >&2; exit 1; }
[ "$(lsblk -ndo TYPE "$DISK")" = disk ] || { echo "Select a whole disk, not a partition: $DISK" >&2; exit 1; }
findmnt --mountpoint /mnt >/dev/null 2>&1 && { echo "/mnt is already mounted; unmount it first." >&2; exit 1; }

echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL,SERIAL
echo
echo "WARNING: staging $HOST will erase all data on $DISK."
read -r -p "Type the exact device path '$DISK' to continue: " confirmation
[ "$confirmation" = "$DISK" ] || { echo "Aborted."; exit 1; }

read -r -p "Paste the SSH public key for the remote administrator: " SSH_PUBLIC_KEY
case "$SSH_PUBLIC_KEY" in
  ssh-ed25519\ *|ssh-rsa\ *|sk-ssh-ed25519@openssh.com\ *) ;;
  *) echo "Unsupported or malformed SSH public key." >&2; exit 1 ;;
esac

if [ -e "/dev/disk/by-id" ]; then
  stable_disk="$(find -L /dev/disk/by-id -maxdepth 1 -type b -samefile "$DISK" \
    ! -name '*-part*' -printf '%p\n' | sort | head -n 1)"
else
  stable_disk=""
fi
stable_disk="${stable_disk:-$DISK}"
echo "Using installation disk identity: $stable_disk"

escaped_disk="${stable_disk//\\/\\\\}"
escaped_disk="${escaped_disk//\"/\\\"}"
sed "s|device = \"[^\"]*\";|device = \"$escaped_disk\";|" \
  "$DISKO_FILE" > "$DISKO_FILE.tmp"
mv "$DISKO_FILE.tmp" "$DISKO_FILE"

echo "Generating hardware configuration..."
nixos-generate-config --show-hardware-config --no-filesystems > "$HARDWARE_FILE"

echo "Evaluating $HOST before touching the disk..."
nix --extra-experimental-features 'nix-command flakes' \
  eval --raw "path:$REPO_DIR#nixosConfigurations.$HOST.config.system.build.toplevel.drvPath" >/dev/null

echo "Partitioning $DISK..."
nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko -- --mode disko "$DISKO_FILE"

"$REPO_DIR/scripts/install.sh" "$HOST"

PINO_USER="$(nix --extra-experimental-features 'nix-command flakes' eval --raw \
  "path:$REPO_DIR#nixosConfigurations.$HOST.config.pino.user.name")"
PINO_HOME="$(nix --extra-experimental-features 'nix-command flakes' eval --raw \
  "path:$REPO_DIR#nixosConfigurations.$HOST.config.pino.user.home")"
user_uid="$(awk -F: -v user="$PINO_USER" '$1 == user { print $3 }' /mnt/etc/passwd)"
user_gid="$(awk -F: -v user="$PINO_USER" '$1 == user { print $4 }' /mnt/etc/passwd)"
[ -n "$user_uid" ] && [ -n "$user_gid" ] || { echo "Installed user $PINO_USER was not found." >&2; exit 1; }
chown -R "$user_uid:$user_gid" "/mnt$PINO_HOME"
install -d -m 0755 /mnt/etc/ssh/authorized_keys.d
printf '%s\n' "$SSH_PUBLIC_KEY" > "/mnt/etc/ssh/authorized_keys.d/$PINO_USER"
chmod 0644 "/mnt/etc/ssh/authorized_keys.d/$PINO_USER"

bootstrap_code="$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
expires="$(( $(date +%s) + 3600 ))"
install -d -m 0700 /mnt/var/lib/pino/bootstrap
printf '%s %s\n' "$bootstrap_code" "$expires" > /mnt/var/lib/pino/bootstrap/pending
chmod 0600 /mnt/var/lib/pino/bootstrap/pending

echo
echo "Mosk staging is complete. Initial bootstrap expires in one hour."
echo "Bootstrap code: $bootstrap_code"
if [ -f /mnt/etc/ssh/ssh_host_ed25519_key.pub ]; then
  echo "SSH host fingerprint:"
  ssh-keygen -lf /mnt/etc/ssh/ssh_host_ed25519_key.pub -E sha256
else
  echo "The SSH host key will be generated at first boot. Verify its fingerprint on the server console with:"
  echo "  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256"
fi
echo "After reboot, run from the vault machine:"
echo "  pino bootstrap server apply $HOST <server-address>"
