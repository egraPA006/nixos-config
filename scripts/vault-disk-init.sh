#!/usr/bin/env bash
set -euo pipefail

report_error() {
  local status="$1" line="$2" command="$3"
  echo "Failed at line $line (exit $status): $command" >&2
  exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

DEVICE="${1:-}"
VAULT_LABEL="${2:-pino-vault-1}"
DATA_LABEL="${3:-pino-data-${VAULT_LABEL#pino-vault-}}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [ -z "$DEVICE" ] || [ "$(lsblk -dnro TYPE "$DEVICE" 2>/dev/null || true)" != disk ]; then
  echo "Usage: sudo $0 <whole-disk-device> [pino-vault-label] [pino-data-label]" >&2
  exit 1
fi

case "$VAULT_LABEL" in
  pino-vault-*) ;;
  *)
    echo "Vault label must start with pino-vault-" >&2
    exit 1
    ;;
esac

case "$DATA_LABEL" in
  pino-data-*) ;;
  *)
    echo "Data label must start with pino-data-" >&2
    exit 1
    ;;
esac

for command in sgdisk partprobe udevadm mkfs.exfat cryptsetup mkfs.ext4 lsblk findmnt umount; do
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
echo "  data / exFAT '$DATA_LABEL': all but the final 8 GiB"
echo "  LUKS2 '$VAULT_LABEL':      final 8 GiB, containing ext4"
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

sgdisk --zap-all "$DEVICE"
sgdisk --new=1:0:-8GiB --typecode=1:0700 --change-name=1:data "$DEVICE"
sgdisk --new=2:0:0 --typecode=2:8309 --change-name=2:"$VAULT_LABEL" "$DEVICE"
partprobe "$DEVICE"
udevadm settle

DATA_PARTITION="$(lsblk -nrpo NAME,PARTLABEL "$DEVICE" | awk '$2 == "data" { print $1; exit }')"
VAULT_PARTITION="$(lsblk -nrpo NAME,PARTLABEL "$DEVICE" | awk -v label="$VAULT_LABEL" '$2 == label { print $1; exit }')"
if [ -z "$DATA_PARTITION" ] || [ -z "$VAULT_PARTITION" ]; then
  echo "Failed to discover the newly created partitions." >&2
  exit 1
fi

mkfs.exfat -F -n "$DATA_LABEL" "$DATA_PARTITION"

echo
echo "Create the LUKS password for $VAULT_LABEL when prompted."
cryptsetup luksFormat --type luks2 --label "$VAULT_LABEL" "$VAULT_PARTITION"
cryptsetup open "$VAULT_PARTITION" pino-vault-init
trap 'cryptsetup close pino-vault-init 2>/dev/null || true' EXIT
mkfs.ext4 -L "$VAULT_LABEL" /dev/mapper/pino-vault-init
cryptsetup close pino-vault-init
trap - EXIT

udevadm settle
echo
echo "Vault disk initialized successfully:"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS "$DEVICE"
