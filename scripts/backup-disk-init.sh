#!/usr/bin/env bash
set -euo pipefail

device="${1:-}"
[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
[ -b "$device" ] && [ "$(lsblk -dnro TYPE "$device")" = disk ] || {
  echo "Usage: sudo $0 <whole-disk-device>" >&2
  exit 1
}
for command in sgdisk wipefs partprobe udevadm mkfs.ext4 lsblk findmnt; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

root_source="$(findmnt -nro SOURCE /)"
root_disk="$(lsblk -s -nro NAME,TYPE "$root_source" | awk '$2 == "disk" { print "/dev/" $1; exit }')"
[ -z "$root_disk" ] || [ "$(readlink -f "$device")" != "$(readlink -f "$root_disk")" ] || {
  echo "Refusing to erase the disk containing /." >&2
  exit 1
}
if lsblk -nrpo NAME "$device" | tail -n +2 | while read -r part; do findmnt -rn -S "$part"; done | grep -q .; then
  echo "A partition on $device is mounted." >&2
  exit 1
fi

echo "This permanently erases $device and creates one ext4 backup partition."
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL "$device"
read -r -p "Type the full device path '$device' to continue: " answer
[ "$answer" = "$device" ] || { echo "Cancelled."; exit 0; }

wipefs --all --force "$device"
sgdisk --zap-all "$device"
sgdisk -n 1:1MiB:0 -t 1:8300 -c 1:pino-backup "$device"
partprobe "$device"
udevadm settle
partition="$(lsblk -nrpo NAME,PARTLABEL "$device" | awk '$2 == "pino-backup" { print $1; exit }')"
[ -n "$partition" ] || { echo "Unable to find the new partition." >&2; exit 1; }
mkfs.ext4 -F -L pino-backup "$partition"
mountpoint="$(mktemp -d /tmp/pino-backup-init.XXXXXX)"
trap 'umount "$mountpoint" 2>/dev/null || true; rmdir "$mountpoint" 2>/dev/null || true' EXIT
mount "$partition" "$mountpoint"
install -d -m 0777 "$mountpoint/.pino-backup/datasets"
printf '1\n' > "$mountpoint/.pino-backup/version"
chmod 0644 "$mountpoint/.pino-backup/version"
sync
umount "$mountpoint"
rmdir "$mountpoint"
trap - EXIT
echo "Initialized $partition. Reconnect or mount it, then use pino backup."
