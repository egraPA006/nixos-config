#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  sudo $0 re-1 [--keep-data] <system-disk> <fast-disk> <slow-disk>
  sudo $0 la1n <system-disk>
  sudo $0 mosk <system-disk>
  sudo $0 halos <system-disk>
EOF
}

[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
host="${1:-}"
shift || true
keep_data=false
if [ "${1:-}" = --keep-data ]; then
  [ "$host" = re-1 ] || { usage; exit 1; }
  keep_data=true
  shift
fi
case "$host:$#" in
  re-1:3|la1n:1|mosk:1|halos:1) ;;
  *) usage; exit 1 ;;
esac

for command in sgdisk wipefs partprobe udevadm mkfs.vfat mkfs.ext4 lsblk findmnt mount; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done
if [ "$host" = la1n ]; then
  command -v cryptsetup >/dev/null || { echo "Missing command: cryptsetup" >&2; exit 1; }
fi

declare -A seen_disks=()
for disk in "$@"; do
  [ -b "$disk" ] && [ "$(lsblk -dnro TYPE "$disk")" = disk ] || {
    echo "Not a whole block device: $disk" >&2
    exit 1
  }
  canonical="$(readlink -f "$disk")"
  [ -z "${seen_disks[$canonical]:-}" ] || { echo "A disk was selected more than once." >&2; exit 1; }
  seen_disks[$canonical]=1
  devices="$(lsblk -nrpo NAME "$disk")"
  [ -n "$devices" ] || { echo "Cannot enumerate $disk; refusing to continue." >&2; exit 1; }
  while IFS= read -r part; do
    if findmnt -rn -S "$part" >/dev/null; then
      echo "$part is mounted; refusing to continue." >&2
      exit 1
    fi
  done <<< "$devices"
done
if findmnt --mountpoint /mnt >/dev/null; then
  echo "/mnt is already mounted; refusing to partition." >&2; exit 1
fi
if [[ "$host" = mosk || "$host" = halos ]] && [ "$1" != /dev/vda ]; then
  echo "$host is configured to install GRUB on /dev/vda; selected disk is $1." >&2
  exit 1
fi

partition_by_label() {
  local disk="$1" label="$2"
  lsblk -nrpo NAME,PARTLABEL "$disk" | awk -v label="$label" '$2 == label { print $1; exit }'
}

if [ "$keep_data" = true ]; then
  fast_part="$(partition_by_label "$2" pino-fast)"
  slow_part="$(partition_by_label "$3" pino-slow)"
  for part in "$fast_part" "$slow_part"; do
    [ -n "$part" ] && [ "$(lsblk -dnro FSTYPE "$part")" = ext4 ] || {
      echo "--keep-data needs existing ext4 partitions labelled pino-fast and pino-slow on the selected data disks." >&2
      exit 1
    }
  done
  [ "$(lsblk -dnro LABEL "$fast_part")" = pino-fast ] &&
    [ "$(lsblk -dnro LABEL "$slow_part")" = pino-slow ] || {
      echo "Data filesystem labels must match pino-fast and pino-slow before reinstalling." >&2
      exit 1
    }
fi

echo "Target host: $host"
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL "$@"
if [ "$keep_data" = true ]; then
  echo "SYSTEM DISK $1 WILL BE ERASED. Existing fast and slow data partitions will be mounted without formatting."
else
  echo "ALL DATA ON THE LISTED DISKS WILL BE ERASED."
fi
read -r -p "Type 'erase $host' to continue: " confirmation
[ "$confirmation" = "erase $host" ] || { echo "Cancelled."; exit 1; }

settle() {
  partprobe "$@"
  udevadm settle
}

mount_desktop() {
  local root="$1" boot="$2"
  mount -t ext4 -o noatime "$root" /mnt
  install -d /mnt/boot
  mount -t vfat -o umask=0077 "$boot" /mnt/boot
}

case "$host" in
  re-1)
    system="$1"; fast="$2"; slow="$3"
    erase_disks=("$system")
    [ "$keep_data" = true ] || erase_disks+=("$fast" "$slow")
    for disk in "${erase_disks[@]}"; do wipefs --all --force "$disk"; sgdisk --zap-all "$disk"; done
    sgdisk -n 1:1MiB:+1GiB -t 1:EF00 -c 1:pino-boot "$system"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:pino-root "$system"
    if [ "$keep_data" = false ]; then
      sgdisk -n 1:1MiB:0 -t 1:8300 -c 1:pino-fast "$fast"
      sgdisk -n 1:1MiB:0 -t 1:8300 -c 1:pino-slow "$slow"
    fi
    settle "$system" "$fast" "$slow"
    boot_part="$(partition_by_label "$system" pino-boot)"
    root_part="$(partition_by_label "$system" pino-root)"
    fast_part="$(partition_by_label "$fast" pino-fast)"
    slow_part="$(partition_by_label "$slow" pino-slow)"
    mkfs.vfat -F 32 -n PINO_BOOT "$boot_part"
    mkfs.ext4 -F -L pino-root "$root_part"
    if [ "$keep_data" = false ]; then
      mkfs.ext4 -F -L pino-fast "$fast_part"
      mkfs.ext4 -F -L pino-slow "$slow_part"
    fi
    mount_desktop "$root_part" "$boot_part"
    install -d /mnt/data/fast /mnt/data/slow
    mount -t ext4 -o noatime "$fast_part" /mnt/data/fast
    mount -t ext4 -o noatime "$slow_part" /mnt/data/slow
    ;;
  la1n)
    system="$1"
    wipefs --all --force "$system"; sgdisk --zap-all "$system"
    sgdisk -n 1:1MiB:+1GiB -t 1:EF00 -c 1:pino-boot "$system"
    sgdisk -n 2:0:0 -t 2:8309 -c 2:pino-cryptroot "$system"
    settle "$system"
    boot_part="$(partition_by_label "$system" pino-boot)"
    crypt_part="$(partition_by_label "$system" pino-cryptroot)"
    mkfs.vfat -F 32 -n PINO_BOOT "$boot_part"
    cryptsetup luksFormat --type luks2 "$crypt_part"
    cryptsetup open "$crypt_part" cryptroot
    mkfs.ext4 -F -L pino-root /dev/mapper/cryptroot
    mount_desktop /dev/mapper/cryptroot "$boot_part"
    ;;
  mosk|halos)
    system="$1"
    wipefs --all --force "$system"; sgdisk --zap-all "$system"
    sgdisk -n 1:1MiB:+1MiB -t 1:EF02 -c 1:pino-bios "$system"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:pino-root "$system"
    settle "$system"
    root_part="$(partition_by_label "$system" pino-root)"
    mkfs.ext4 -F -L pino-root "$root_part"
    mount -t ext4 -o noatime "$root_part" /mnt
    ;;
esac

echo "Storage for $host is formatted and mounted at /mnt."
echo "Next: sudo scripts/install.sh $host"
