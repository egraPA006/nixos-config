#!/usr/bin/env bash
set -euo pipefail

report_error() {
  local status="$1" line="$2" command="$3"
  echo "Failed at line $line (exit $status): $command" >&2
  exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

DEVICE="${1:-}"
DISK_ID="${2:-1}"
DATA_LABEL="pino-data-$DISK_ID"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root." >&2
  exit 1
fi
if [ -z "$DEVICE" ] || [ "$(lsblk -dnro TYPE "$DEVICE" 2>/dev/null || true)" != disk ]; then
  echo "Usage: sudo $0 <whole-disk-device> [disk-id]" >&2
  echo "Example: sudo $0 /dev/sdb 1" >&2
  exit 1
fi
if [[ ! "$DISK_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Disk ID must be a positive integer." >&2
  exit 1
fi
for command in fdisk mkfs.exfat lsblk findmnt umount; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing command: $command" >&2
    exit 1
  }
done

ROOT_SOURCE="$(findmnt -nro SOURCE /)"
ROOT_SOURCE="${ROOT_SOURCE%%\[*}"
ROOT_DISK="$(lsblk -nrpo NAME,PKNAME | awk -v root="$ROOT_SOURCE" '$1 == root { print $2; exit }')"
[ -n "$ROOT_DISK" ] || { echo "Unable to identify the disk containing /." >&2; exit 1; }
[ "$DEVICE" != "$ROOT_DISK" ] || { echo "Refusing to erase the disk containing /." >&2; exit 1; }

echo "This permanently erases $DEVICE and creates one full-size exFAT partition labelled $DATA_LABEL."
echo "Passwords and host vaults remain encrypted inside KeePass/Cryptomator; the disk adds no second password."
lsblk -d -o NAME,PATH,VENDOR,MODEL,SERIAL,SIZE,TRAN "$DEVICE"
read -r -p "Type the full device path ($DEVICE) to continue: " confirmation
[ "$confirmation" = "$DEVICE" ] || { echo "Cancelled."; exit 1; }

while read -r partition; do
  if findmnt -rn -S "$partition" >/dev/null 2>&1; then
    umount "$partition"
  fi
done < <(lsblk -nrpo NAME "$DEVICE" | tail -n +2)

MICROSOFT_BASIC_DATA="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
printf 'g\nn\n1\n\n\nt\n%s\nw\n' "$MICROSOFT_BASIC_DATA" | fdisk "$DEVICE"

DATA_PARTITION=""
for _ in {1..20}; do
  DATA_PARTITION="$(lsblk -nrpo NAME,TYPE "$DEVICE" | awk '$2 == "part" { print $1; exit }')"
  [ -z "$DATA_PARTITION" ] || break
  sleep 0.25
done
[ -n "$DATA_PARTITION" ] || { echo "Failed to discover the new partition." >&2; exit 1; }
mkfs.exfat -n "$DATA_LABEL" "$DATA_PARTITION"

echo "Portable backup disk initialized:"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS "$DEVICE"
