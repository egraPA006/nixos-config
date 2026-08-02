#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_MOUNT="${PINO_BOOTSTRAP_MOUNT:-/run/pino-bootstrap}"
BOOTSTRAP_LABEL="${PINO_VAULT_LABEL:-}"
BOOTSTRAP_MAPPER="pino-install-vault"
BOOTSTRAP_MOUNTED=false
BOOTSTRAP_OPENED=false
SECRETS_PROVISIONED=false

cleanup_bootstrap() {
  if [ "$BOOTSTRAP_MOUNTED" = true ]; then
    sudo umount "$BOOTSTRAP_MOUNT" || true
  fi
  if [ "$BOOTSTRAP_OPENED" = true ]; then
    sudo cryptsetup close "$BOOTSTRAP_MAPPER" || true
  fi
}

mount_bootstrap() {
  if mountpoint -q "$BOOTSTRAP_MOUNT"; then
    return
  fi

  local device
  local -a labels devices
  mapfile -t labels < <(lsblk -rno LABEL,FSTYPE | awk '$2 == "crypto_LUKS" && $1 ~ /^pino-vault-/ { print $1 }')
  if [ -z "$BOOTSTRAP_LABEL" ]; then
    case "${#labels[@]}" in
      1) BOOTSTRAP_LABEL="${labels[0]}" ;;
      0) echo "No connected pino-vault-* disk found; continuing without vault secrets." >&2; return 1 ;;
      *)
        echo "Error: several vault disks are connected; select one with PINO_VAULT_LABEL:" >&2
        printf '  %s\n' "${labels[@]}" >&2
        return 1
        ;;
    esac
  elif [[ "$BOOTSTRAP_LABEL" != pino-vault-* ]]; then
    BOOTSTRAP_LABEL="pino-vault-$BOOTSTRAP_LABEL"
  fi
  mapfile -t devices < <(lsblk -rpn -o NAME,LABEL,FSTYPE | awk -v label="$BOOTSTRAP_LABEL" '$2 == label && $3 == "crypto_LUKS" { print $1 }')
  if [ "${#devices[@]}" -ne 1 ]; then
    echo "Error: expected exactly one LUKS partition labelled '$BOOTSTRAP_LABEL'" >&2
    return 1
  fi
  device="${devices[0]}"
  sudo cryptsetup open --readonly "$device" "$BOOTSTRAP_MAPPER"
  device="/dev/mapper/$BOOTSTRAP_MAPPER"
  BOOTSTRAP_OPENED=true

  sudo mkdir -p "$BOOTSTRAP_MOUNT"
  sudo mount -o ro,nodev,nosuid,noexec "$device" "$BOOTSTRAP_MOUNT"
  BOOTSTRAP_MOUNTED=true
  trap cleanup_bootstrap EXIT
}

if [ ! -d "hosts/$HOST" ]; then
  echo "Error: hosts/$HOST does not exist"
  exit 1
fi

echo "Copying repo to /mnt/home/egrapa/nixos-config..."
sudo mkdir -p /mnt/home/egrapa/
sudo mkdir -p /mnt/home/egrapa/nixos-config
tar \
  --exclude='./secrets/*.conf' \
  --exclude='./secrets/keys' \
  -C "$REPO_DIR" -cf - . \
  | sudo tar -C /mnt/home/egrapa/nixos-config -xf -

if mount_bootstrap; then
  if [ ! -d "$BOOTSTRAP_MOUNT/bootstrap/shared" ] && [ ! -d "$BOOTSTRAP_MOUNT/bootstrap/hosts/$HOST" ]; then
    echo "$BOOTSTRAP_LABEL has no installation secrets for $HOST; continuing without them." >&2
  else
    echo "Provisioning $HOST secrets from $BOOTSTRAP_LABEL..."
    sudo install -d -m 0700 -o root -g root /mnt/var/lib/pino/secrets
    if [ -d "$BOOTSTRAP_MOUNT/bootstrap/shared" ]; then
      sudo cp -a "$BOOTSTRAP_MOUNT/bootstrap/shared/." /mnt/var/lib/pino/secrets/
    fi
    if [ -d "$BOOTSTRAP_MOUNT/bootstrap/hosts/$HOST" ]; then
      sudo cp -a "$BOOTSTRAP_MOUNT/bootstrap/hosts/$HOST/." /mnt/var/lib/pino/secrets/
    fi
    sudo find /mnt/var/lib/pino/secrets -type d -exec chmod 0700 {} +
    sudo find /mnt/var/lib/pino/secrets -type f -exec chmod 0600 {} +
    SECRETS_PROVISIONED=true
  fi
fi

echo "Installing NixOS for $HOST..."
sudo nixos-install --flake "/mnt/home/egrapa/nixos-config#$HOST"

if [ -f /mnt/var/lib/pino/secrets/user-password-hash ]; then
  echo "Applying the provisioned egrapa password hash..."
  sudo sh -c '{ printf "egrapa:"; head -n 1 /mnt/var/lib/pino/secrets/user-password-hash; } | chpasswd --root /mnt --encrypted'
fi

echo ""
if [ "$SECRETS_PROVISIONED" = true ]; then
  echo "Done. Vault-backed system secrets were provisioned from $BOOTSTRAP_LABEL."
else
  echo "Done without vault secrets. Set the egrapa password with: passwd egrapa"
fi
