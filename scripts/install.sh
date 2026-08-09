#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NIX_STORE_ARGS=()
NIXOS_INSTALL_STORE_ARGS=()
if [ -n "${PINO_INSTALL_NIX_STORE:-}" ]; then
  NIX_STORE_ARGS=(--store "$PINO_INSTALL_NIX_STORE")
  NIXOS_INSTALL_STORE_ARGS=(--option store "$PINO_INSTALL_NIX_STORE")
elif findmnt --mountpoint /mnt >/dev/null 2>&1; then
  # Partitioning gives evaluations a large target-backed store
  # instead of the installer ISO's small writable tmpfs.
  NIX_STORE_ARGS=(--store /mnt)
  NIXOS_INSTALL_STORE_ARGS=(--option store /mnt)
fi
NIX_EVAL=(nix "${NIX_STORE_ARGS[@]}" --extra-experimental-features 'nix-command flakes' eval --raw)
BOOTSTRAP_MOUNT="${PINO_BOOTSTRAP_MOUNT:-/run/pino-bootstrap}"
BOOTSTRAP_LABEL="${PINO_VAULT_LABEL:-}"
BOOTSTRAP_MAPPER="pino-install-vault"
BOOTSTRAP_MOUNTED=false
BOOTSTRAP_OPENED=false
SECRETS_PROVISIONED=false
DATA_MOUNT="${PINO_DATA_MOUNT:-/run/pino-install-data}"
DATA_SELECTOR="${PINO_DATA_LABEL:-${PINO_DATA_DISK:-}}"
DATA_MOUNTED=false
DATA_RESTORED=false
PASSWORD_CONFIGURED=false

cleanup_bootstrap() {
  if [ "$DATA_MOUNTED" = true ]; then
    sudo umount "$DATA_MOUNT" || true
  fi
  if [ "$BOOTSTRAP_MOUNTED" = true ]; then
    sudo umount "$BOOTSTRAP_MOUNT" || true
  fi
  if [ "$BOOTSTRAP_OPENED" = true ]; then
    sudo cryptsetup close "$BOOTSTRAP_MAPPER" || true
  fi
}

mount_data_backup() {
  local selector="$DATA_SELECTOR"
  local data_label existing_mount
  local -a devices

  if [ -n "$selector" ]; then
    [[ "$selector" == pino-data-* ]] && data_label="$selector" || data_label="pino-data-$selector"
    mapfile -t devices < <(lsblk -rpn -o NAME,LABEL,FSTYPE | awk -v label="$data_label" '$2 == label && $3 == "exfat" { print $1 }')
  else
    mapfile -t devices < <(lsblk -rpn -o NAME,LABEL,FSTYPE | awk '$2 ~ /^pino-data-/ && $3 == "exfat" { print $1 }')
  fi
  if [ "${#devices[@]}" -ne 1 ]; then
    echo "No unique ${data_label:-pino-data-*} partition found; skipping data restore." >&2
    return 1
  fi

  existing_mount="$(findmnt -rn -S "${devices[0]}" -o TARGET | head -n 1)"
  if [ -n "$existing_mount" ]; then
    DATA_MOUNT="$existing_mount"
  else
    sudo mkdir -p "$DATA_MOUNT"
    sudo mount -o ro,nodev,nosuid,noexec "${devices[0]}" "$DATA_MOUNT"
    DATA_MOUNTED=true
    trap cleanup_bootstrap EXIT
  fi
}

restore_data_backup() {
  local requested="${PINO_RESTORE_DATA:-}"
  local datasets_json name local_path scope medium_path answer
  local -a available=() selected=()
  declare -A local_paths=() medium_paths=()

  datasets_json="$(nix "${NIX_STORE_ARGS[@]}" --extra-experimental-features 'nix-command flakes' eval --json \
    "path:$REPO_DIR#nixosConfigurations.${HOST}.config.pino.data.datasets")"
  while IFS=$'\t' read -r name local_path scope; do
    [ -n "$name" ] || continue
    if [ "$scope" = shared ]; then
      medium_path="$DATA_MOUNT/pino/datasets/shared/$name"
    else
      medium_path="$DATA_MOUNT/pino/datasets/hosts/$HOST/$name"
    fi
    if [ -d "$medium_path" ]; then
      available+=("$name")
      local_paths["$name"]="$local_path"
      medium_paths["$name"]="$medium_path"
    fi
  done < <(printf '%s\n' "$datasets_json" | jq -r 'to_entries[] | [.key, .value.localPath, .value.scope] | @tsv')

  if [ "${#available[@]}" -eq 0 ]; then
    echo "No configured datasets for $HOST exist on the selected data medium; continuing." >&2
    return
  fi
  echo "Datasets available for $HOST:"
  for name in "${available[@]}"; do
    printf '  %-18s %s -> %s\n' "$name" "${medium_paths[$name]}" "${local_paths[$name]}"
  done

  if [ -z "$requested" ] && [ -t 0 ]; then
    read -r -p "Restore which datasets? [all/none/comma-separated names] (all): " answer
    requested="${answer:-all}"
  fi
  case "$requested" in
    ""|0|no|none) return ;;
    all) selected=("${available[@]}") ;;
    *) IFS=',' read -r -a selected <<< "$requested" ;;
  esac

  for name in "${selected[@]}"; do
    if [ -z "${medium_paths[$name]:-}" ]; then
      echo "Dataset '$name' is not configured or absent on the medium; skipping." >&2
      continue
    fi
    echo "Restoring $name exactly to ${local_paths[$name]}..."
    sudo mkdir -p "/mnt${local_paths[$name]}"
    sudo rsync -rt --delete --modify-window=1 \
      "${medium_paths[$name]}/" "/mnt${local_paths[$name]}/"
    DATA_RESTORED=true
  done
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

if [ ! -d "$REPO_DIR/hosts/$HOST" ]; then
  echo "Error: hosts/$HOST does not exist"
  exit 1
fi

PINO_USER="$("${NIX_EVAL[@]}" "path:$REPO_DIR#nixosConfigurations.${HOST}.config.pino.user.name")"
PINO_HOME="$("${NIX_EVAL[@]}" "path:$REPO_DIR#nixosConfigurations.${HOST}.config.pino.user.home")"
PINO_CONFIG_DIR="$("${NIX_EVAL[@]}" "path:$REPO_DIR#nixosConfigurations.${HOST}.config.pino.configDir")"
INSTALL_CONFIG_DIR="/mnt$PINO_CONFIG_DIR"

echo "Copying repo to $INSTALL_CONFIG_DIR..."
sudo mkdir -p "/mnt$PINO_HOME" "$INSTALL_CONFIG_DIR"
tar \
  --exclude='./secrets' \
  --exclude='./result' \
  --exclude='./result-*' \
  -C "$REPO_DIR" -cf - . \
  | sudo tar --no-same-owner -C "$INSTALL_CONFIG_DIR" -xf -

# The working secrets directory may contain untracked private material, so it
# is excluded above. Restore only files committed in the public repository
# (currently placeholder examples) to keep the installed Git tree clean.
if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO_DIR" archive --format=tar HEAD -- secrets \
    | sudo tar --no-same-owner -C "$INSTALL_CONFIG_DIR" -xf -
fi

if mount_bootstrap; then
  if ! sudo test -d "$BOOTSTRAP_MOUNT/bootstrap/shared" \
    && ! sudo test -d "$BOOTSTRAP_MOUNT/bootstrap/hosts/$HOST"; then
    echo "$BOOTSTRAP_LABEL has no installation secrets for $HOST; continuing without them." >&2
    echo "Expected bootstrap/shared or bootstrap/hosts/$HOST." >&2
  else
    echo "Provisioning $HOST secrets from $BOOTSTRAP_LABEL..."
    sudo install -d -m 0700 -o root -g root /mnt/var/lib/pino/secrets
    if sudo test -d "$BOOTSTRAP_MOUNT/bootstrap/shared"; then
      sudo cp -a "$BOOTSTRAP_MOUNT/bootstrap/shared/." /mnt/var/lib/pino/secrets/
    fi
    if sudo test -d "$BOOTSTRAP_MOUNT/bootstrap/hosts/$HOST"; then
      sudo cp -a "$BOOTSTRAP_MOUNT/bootstrap/hosts/$HOST/." /mnt/var/lib/pino/secrets/
    fi
    sudo find /mnt/var/lib/pino/secrets -type d -exec chmod 0700 {} +
    sudo find /mnt/var/lib/pino/secrets -type f -exec chmod 0600 {} +
    SECRETS_PROVISIONED=true
  fi
fi

if mount_data_backup; then
  restore_data_backup
fi

echo "Installing NixOS for $HOST..."
sudo nixos-install "${NIXOS_INSTALL_STORE_ARGS[@]}" --flake "$INSTALL_CONFIG_DIR#$HOST"

installed_user_uid="$(awk -F: -v user="$PINO_USER" '$1 == user { print $3 }' /mnt/etc/passwd)"
installed_user_gid="$(awk -F: -v user="$PINO_USER" '$1 == user { print $4 }' /mnt/etc/passwd)"
[ -n "$installed_user_uid" ] && [ -n "$installed_user_gid" ] || {
  echo "Installed user $PINO_USER was not found." >&2
  exit 1
}
sudo chown -R "$installed_user_uid:$installed_user_gid" "/mnt$PINO_HOME"

if [ -f /mnt/var/lib/pino/secrets/user-password-hash ]; then
  echo "Applying the provisioned $PINO_USER password hash..."
  PASSWORD_HASH="$(sudo head -n 1 /mnt/var/lib/pino/secrets/user-password-hash)"
  printf '%s:%s\n' "$PINO_USER" "$PASSWORD_HASH" | sudo chpasswd --root /mnt --encrypted
  PASSWORD_CONFIGURED=true
elif [ -t 0 ]; then
  echo "No provisioned password hash exists for $PINO_USER. Set a local password before rebooting."
  sudo nixos-enter --root /mnt -c "passwd $PINO_USER"
  PASSWORD_CONFIGURED=true
fi

echo ""
if [ "$SECRETS_PROVISIONED" = true ]; then
  echo "Done. Vault-backed system secrets were provisioned from $BOOTSTRAP_LABEL."
else
  echo "Done without vault-backed installation secrets."
fi
if [ "$PASSWORD_CONFIGURED" = false ]; then
  echo "The $PINO_USER password is not configured. Before rebooting, run:"
  echo "  sudo nixos-enter --root /mnt -c 'passwd $PINO_USER'"
fi
if [ "$DATA_RESTORED" = true ]; then
  echo "Non-secret profile data was restored from the selected pino-data medium."
fi
