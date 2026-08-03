#!/usr/bin/env bash
set -euo pipefail

report_error() {
  local status="$1" line="$2" command="$3"
  echo "Failed at line $line (exit $status): $command" >&2
  exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

DEVICE="${1:-}"
VAULT_SIZE="${2:-8GiB}"
DISK_ID="${3:-1}"
VAULT_LABEL="pino-vault-$DISK_ID"
DATA_LABEL="pino-data-$DISK_ID"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [ -z "$DEVICE" ] || [ "$(lsblk -dnro TYPE "$DEVICE" 2>/dev/null || true)" != disk ]; then
  echo "Usage: sudo $0 <whole-disk-device> [vault-size] [disk-id]" >&2
  echo "Example: sudo $0 /dev/sdb 16GiB 1" >&2
  exit 1
fi

if [[ ! "$VAULT_SIZE" =~ ^[1-9][0-9]*GiB$ ]]; then
  echo "Vault size must use the form <positive-integer>GiB, for example 8GiB or 16GiB." >&2
  exit 1
fi
if [[ ! "$DISK_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Disk ID must be a positive integer, for example 1 or 2." >&2
  exit 1
fi

for command in fdisk mkfs.exfat cryptsetup mkfs.ext4 lsblk findmnt umount; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing command: $command" >&2
    exit 1
  fi
done

ROOT_SOURCE="$(findmnt -nro SOURCE /)"
ROOT_SOURCE="${ROOT_SOURCE%%\[*}"
ROOT_DISK="$(lsblk -nrpo NAME,PKNAME | awk -v root="$ROOT_SOURCE" '$1 == root { print $2; exit }')"
if [ -z "$ROOT_DISK" ]; then
  echo "Unable to identify the disk containing /; refusing to continue." >&2
  exit 1
fi
if [ "$DEVICE" = "$ROOT_DISK" ]; then
  echo "Refusing to erase the disk containing /: $DEVICE" >&2
  exit 1
fi

echo "This will permanently erase the complete disk:"
lsblk -d -o NAME,PATH,VENDOR,MODEL,SERIAL,SIZE,TRAN "$DEVICE"
echo
echo "New layout:"
echo "  data / exFAT '$DATA_LABEL': all but the final $VAULT_SIZE"
echo "  LUKS2 '$VAULT_LABEL':      final $VAULT_SIZE, containing ext4"
echo
read -r -p "Type the full device path ($DEVICE) to continue: " CONFIRM
if [ "$CONFIRM" != "$DEVICE" ]; then
  echo "Cancelled."
  exit 1
fi

while read -r partition; do
  if findmnt -rn -S "$partition" >/dev/null 2>&1; then
    umount "$partition"
  fi
done < <(lsblk -nrpo NAME "$DEVICE" | tail -n +2)

MICROSOFT_BASIC_DATA="EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
LINUX_LUKS="CA7D7CCB-63ED-4C53-861C-1742536059CC"
printf 'g\nn\n1\n\n-%s\nt\n%s\nn\n2\n\n\nt\n2\n%s\nw\n' \
  "$VAULT_SIZE" "$MICROSOFT_BASIC_DATA" "$LINUX_LUKS" | fdisk "$DEVICE"

partitions=()
for _ in {1..20}; do
  mapfile -t partitions < <(lsblk -nrpo NAME,TYPE "$DEVICE" | awk '$2 == "part" { print $1 }')
  [ "${#partitions[@]}" -eq 2 ] && break
  sleep 0.25
done
if [ "${#partitions[@]}" -ne 2 ]; then
  echo "Failed to discover the newly created partitions." >&2
  exit 1
fi
DATA_PARTITION="${partitions[0]}"
VAULT_PARTITION="${partitions[1]}"

mkfs.exfat -n "$DATA_LABEL" "$DATA_PARTITION"

echo
echo "Create the LUKS password for $VAULT_LABEL when prompted."
cryptsetup luksFormat --type luks2 --label "$VAULT_LABEL" "$VAULT_PARTITION"
cryptsetup open "$VAULT_PARTITION" pino-vault-init
trap 'cryptsetup close pino-vault-init 2>/dev/null || true' EXIT
mkfs.ext4 -L "$VAULT_LABEL" /dev/mapper/pino-vault-init
cryptsetup close pino-vault-init
trap - EXIT

echo
echo "Vault disk initialized successfully:"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS "$DEVICE"
