#!/usr/bin/env bash
set -euo pipefail

device="${1:-}"
[ "$(id -u)" -eq 0 ] || { echo "Run this script as root." >&2; exit 1; }
[ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] || {
  echo "Run this script with sudo from the desktop user that will own the disk." >&2
  exit 1
}
[ -b "$device" ] && [ "$(lsblk -dnro TYPE "$device")" = disk ] || {
  echo "Usage: sudo $0 <whole-disk-device>" >&2
  exit 1
}
for command in sgdisk wipefs partprobe udevadm cryptsetup mkfs.ext4 lsblk findmnt mount umount; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

device="$(readlink -f "$device")"
root_source="$(findmnt -nro SOURCE /)"
root_disk="$(lsblk -s -nro NAME,TYPE "$root_source" | awk '$2 == "disk" { print "/dev/" $1; exit }')"
[ -z "$root_disk" ] || [ "$device" != "$(readlink -f "$root_disk")" ] || {
  echo "Refusing to erase the disk containing /." >&2
  exit 1
}
if lsblk -nrpo NAME "$device" | tail -n +2 | while read -r part; do findmnt -rn -S "$part"; done | grep -q .; then
  echo "A partition on $device is mounted." >&2
  exit 1
fi

echo "This permanently erases $device and creates one LUKS2-encrypted ext4 filesystem."
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL "$device"
read -r -p "Type the full device path '$device' to continue: " answer
[ "$answer" = "$device" ] || { echo "Cancelled."; exit 0; }

wipefs --all --force "$device"
sgdisk --zap-all "$device"
sgdisk -n 1:1MiB:0 -t 1:8309 -c 1:pino-encrypted "$device"
partprobe "$device"
udevadm settle
partition="$(lsblk -nrpo NAME,PARTLABEL "$device" | awk '$2 == "pino-encrypted" { print $1; exit }')"
[ -n "$partition" ] || { echo "Unable to find the new encrypted partition." >&2; exit 1; }

cryptsetup luksFormat --type luks2 --verify-passphrase "$partition"
mapping="pino-external-init-$$"
mountpoint="$(mktemp -d /tmp/pino-external-init.XXXXXX)"
cleanup() {
  umount "$mountpoint" 2>/dev/null || true
  cryptsetup close "$mapping" 2>/dev/null || true
  rmdir "$mountpoint" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
cryptsetup open "$partition" "$mapping"
mkfs.ext4 -L pino-external "/dev/mapper/$mapping"
mount "/dev/mapper/$mapping" "$mountpoint"
chown "$(id -u "$SUDO_USER"):$(id -g "$SUDO_USER")" "$mountpoint"
chmod 0700 "$mountpoint"
umount "$mountpoint"
cryptsetup close "$mapping"
rmdir "$mountpoint"
trap - EXIT INT TERM

echo "Initialized $partition. Reconnect it and unlock it with the desktop disk prompt."
