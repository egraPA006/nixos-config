#!/usr/bin/env bash
set -euo pipefail

mapper="/dev/mapper/$SECRET_MAPPING"

require_user() {
  [ "$(id -un)" = "$SECRET_USER" ] || {
    echo "Run pino as $SECRET_USER, not with sudo." >&2
    exit 1
  }
}

is_mounted() {
  findmnt --mountpoint "$SECRET_MOUNT_POINT" >/dev/null 2>&1
}

is_open() {
  [ -e "$mapper" ]
}

require_expected_mount() {
  local source_device
  source_device="$(findmnt -nro SOURCE --target "$SECRET_MOUNT_POINT")"
  [ "$(readlink -f "$source_device")" = "$(readlink -f "$mapper")" ] || {
    echo "$SECRET_MOUNT_POINT is mounted from an unexpected device: $source_device" >&2
    exit 1
  }
}

initialize_vault() {
  ! is_mounted || {
    echo "Refusing to initialize: $SECRET_MOUNT_POINT is already mounted." >&2
    exit 1
  }
  ! is_open || {
    echo "Refusing to initialize: $mapper already exists." >&2
    exit 1
  }

  echo "Creating the local LUKS2 recovery container at $SECRET_CONTAINER"
  mkdir -p "$(dirname "$SECRET_CONTAINER")" "$SECRET_MOUNT_POINT"
  chmod 0700 "$(dirname "$SECRET_CONTAINER")" "$SECRET_MOUNT_POINT"
  fallocate -l "$SECRET_SIZE" "$SECRET_CONTAINER"
  chmod 0600 "$SECRET_CONTAINER"
  if ! sudo cryptsetup luksFormat --type luks2 --verify-passphrase "$SECRET_CONTAINER"; then
    rm -f "$SECRET_CONTAINER"
    exit 1
  fi

  sudo cryptsetup open "$SECRET_CONTAINER" "$SECRET_MAPPING"
  cleanup_init() {
    sudo umount "$SECRET_MOUNT_POINT" 2>/dev/null || true
    sudo cryptsetup close "$SECRET_MAPPING" 2>/dev/null || true
  }
  trap cleanup_init EXIT INT TERM
  sudo mkfs.ext4 -q -L pino-secrets "$mapper"
  sudo mount -o nodev,nosuid,noexec "$mapper" "$SECRET_MOUNT_POINT"
  sudo chown "$SECRET_USER:users" "$SECRET_MOUNT_POINT"
  chmod 0700 "$SECRET_MOUNT_POINT"
  trap - EXIT INT TERM
  echo "Recovery folder initialized and unlocked at $SECRET_MOUNT_POINT"
}

unlock_vault() {
  local opened_here=false
  if [ ! -f "$SECRET_CONTAINER" ]; then
    initialize_vault
    return
  fi
  if is_mounted; then
    require_expected_mount
    echo "Recovery folder already unlocked at $SECRET_MOUNT_POINT"
    return
  fi

  if ! is_open; then
    sudo cryptsetup open "$SECRET_CONTAINER" "$SECRET_MAPPING"
    opened_here=true
  fi
  if ! sudo mount -o nodev,nosuid,noexec "$mapper" "$SECRET_MOUNT_POINT"; then
    if [ "$opened_here" = true ]; then
      sudo cryptsetup close "$SECRET_MAPPING" || true
    fi
    exit 1
  fi
  sudo chown "$SECRET_USER:users" "$SECRET_MOUNT_POINT"
  chmod 0700 "$SECRET_MOUNT_POINT"
  echo "Recovery folder unlocked at $SECRET_MOUNT_POINT"
}

lock_vault() {
  if is_mounted; then
    require_expected_mount
    sudo umount "$SECRET_MOUNT_POINT"
  fi
  if is_open; then
    sudo cryptsetup close "$SECRET_MAPPING"
  fi
  echo "Recovery folder locked"
}

require_user
case "${1:-}" in
  unlock) unlock_vault ;;
  lock) lock_vault ;;
  *) echo "Run 'pino secret help' for usage." >&2; exit 1 ;;
esac
