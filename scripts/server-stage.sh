#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: sudo $0 <host> <whole-disk-device> [direct|disko]" >&2
  echo "Example: sudo $0 mosk /dev/vda direct" >&2
}

[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage; exit 1; }

HOST="$1"
DISK="$2"
PARTITION_METHOD="${3:-}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST_DIR="$REPO_DIR/hosts/$HOST"
DISKO_FILE="$HOST_DIR/disko.nix"
HARDWARE_FILE="$HOST_DIR/hardware.nix"

[ -d "$HOST_DIR" ] || { echo "Unknown host: $HOST" >&2; exit 1; }
[ -b "$DISK" ] || { echo "Not a block device: $DISK" >&2; exit 1; }
[ "$(lsblk -ndo TYPE "$DISK")" = disk ] || { echo "Select a whole disk, not a partition: $DISK" >&2; exit 1; }
findmnt --mountpoint /mnt >/dev/null 2>&1 && { echo "/mnt is already mounted; unmount it first." >&2; exit 1; }

if [ -z "$PARTITION_METHOD" ]; then
  read -r -p "Partition with [direct/disko] (direct): " PARTITION_METHOD
  PARTITION_METHOD="${PARTITION_METHOD:-direct}"
fi
case "$PARTITION_METHOD" in
  direct)
    [ "$HOST" = mosk ] || {
      echo "The direct layout is currently defined only for mosk; use Disko for $HOST." >&2
      exit 1
    }
    ;;
  disko) ;;
  *) echo "Partition method must be 'direct' or 'disko'." >&2; exit 1 ;;
esac

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

partition_direct() {
  local command partition
  local -a missing=() existing_partitions=() partitions=()
  for command in parted partprobe udevadm wipefs mkfs.btrfs btrfs mount umount; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  if [ "${#missing[@]}" -ne 0 ]; then
    echo "The direct method needs tools already present on the installer ISO:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Use a fuller NixOS ISO, temporarily add the missing tools, or select Disko." >&2
    return 1
  fi

  mapfile -t existing_partitions < <(lsblk -nrpo NAME,TYPE "$DISK" | awk '$2 == "part" { print $1 }')
  for partition in "${existing_partitions[@]}"; do
    if findmnt -rn -S "$partition" >/dev/null 2>&1; then
      echo "Refusing to overwrite mounted partition: $partition" >&2
      return 1
    fi
  done

  echo "Creating the hard-coded Mosk GPT/BIOS/Btrfs layout on $DISK..."
  wipefs --all --force "$DISK"
  parted --script --align optimal "$DISK" mklabel gpt
  parted --script --align optimal "$DISK" mkpart disk-system-BIOS 1MiB 2MiB
  parted --script "$DISK" set 1 bios_grub on
  parted --script --align optimal "$DISK" mkpart disk-system-root btrfs 2MiB 100%
  partprobe "$DISK"
  udevadm settle

  for _ in {1..10}; do
    mapfile -t partitions < <(lsblk -nrpo NAME,TYPE "$DISK" | awk '$2 == "part" { print $1 }')
    [ "${#partitions[@]}" -eq 2 ] && break
    sleep 1
  done
  if [ "${#partitions[@]}" -ne 2 ]; then
    echo "Expected two partitions on $DISK, found ${#partitions[@]}." >&2
    return 1
  fi

  mkfs.btrfs -f -L nixos "${partitions[1]}"
  mount "${partitions[1]}" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@nix
  btrfs subvolume create /mnt/@home
  umount /mnt

  mount -o subvol=@,compress=zstd,noatime "${partitions[1]}" /mnt
  install -d /mnt/boot /mnt/nix /mnt/home
  mount -o subvol=@nix,compress=zstd,noatime "${partitions[1]}" /mnt/nix
  mount -o subvol=@home,compress=zstd,noatime "${partitions[1]}" /mnt/home
}

if [ "$PARTITION_METHOD" = direct ]; then
  partition_direct
  echo "Evaluating $HOST in the target-backed Nix store..."
  nix --store /mnt --extra-experimental-features 'nix-command flakes' \
    eval --raw "path:$REPO_DIR#nixosConfigurations.$HOST.config.system.build.toplevel.drvPath" >/dev/null
  PINO_INSTALL_NIX_STORE=/mnt "$REPO_DIR/scripts/install.sh" "$HOST"
  NIX_STORE_ARGS=(--store /mnt)
else
  echo "Evaluating $HOST before touching the disk..."
  nix --extra-experimental-features 'nix-command flakes' \
    eval --raw "path:$REPO_DIR#nixosConfigurations.$HOST.config.system.build.toplevel.drvPath" >/dev/null
  echo "Partitioning $DISK with Disko..."
  nix --extra-experimental-features 'nix-command flakes' \
    run github:nix-community/disko -- --mode disko "$DISKO_FILE"
  "$REPO_DIR/scripts/install.sh" "$HOST"
  NIX_STORE_ARGS=()
fi

PINO_USER="$(nix "${NIX_STORE_ARGS[@]}" --extra-experimental-features 'nix-command flakes' eval --raw \
  "path:$REPO_DIR#nixosConfigurations.$HOST.config.pino.user.name")"
PINO_HOME="$(nix "${NIX_STORE_ARGS[@]}" --extra-experimental-features 'nix-command flakes' eval --raw \
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
