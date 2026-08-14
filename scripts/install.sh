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
DATA_MOUNT="${PINO_DATA_MOUNT:-/run/pino-install-data}"
DATA_SELECTOR="${PINO_DATA_LABEL:-${PINO_DATA_DISK:-}}"
DATA_MOUNTED=false
DATA_RESTORED=false
PASSWORD_CONFIGURED=false
BOOTSTRAP_SSH_KEY="${PINO_BOOTSTRAP_SSH_KEY:-}"
BOOTSTRAP_READY=false

cleanup_install_media() {
  if [ "$DATA_MOUNTED" = true ]; then
    sudo umount "$DATA_MOUNT" || true
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
    trap cleanup_install_media EXIT
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

restore_portable_backup() {
  local portable="$DATA_MOUNT/pino/portable-backup/current"
  if [ ! -d "$portable" ]; then
    echo "No portable Pino backup exists on the selected data medium; continuing." >&2
    return
  fi
  echo "Restoring encrypted identity and portable vault backing data..."
  sudo mkdir -p \
    "/mnt$PINO_HOME/.local/share/pino/identity" \
    "/mnt$PINO_HOME/.local/share/pino/encrypted"
  if [ -d "$portable/identity" ]; then
    sudo rsync -rt --delete \
      "$portable/identity/" "/mnt$PINO_HOME/.local/share/pino/identity/"
  fi
  if [ -d "$portable/encrypted" ]; then
    sudo rsync -rt --delete \
      "$portable/encrypted/" "/mnt$PINO_HOME/.local/share/pino/encrypted/"
  fi
  sudo find "/mnt$PINO_HOME/.local/share/pino/identity" \
    "/mnt$PINO_HOME/.local/share/pino/encrypted" -type d -exec chmod 0700 {} +
  sudo find "/mnt$PINO_HOME/.local/share/pino/identity" \
    "/mnt$PINO_HOME/.local/share/pino/encrypted" -type f -exec chmod 0600 {} +
  DATA_RESTORED=true
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
  --exclude='./result' \
  --exclude='./result-*' \
  -C "$REPO_DIR" -cf - . \
  | sudo tar --no-same-owner -C "$INSTALL_CONFIG_DIR" -xf -

if mount_data_backup; then
  restore_portable_backup
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

if [ -z "$BOOTSTRAP_SSH_KEY" ] && [ -t 0 ]; then
  echo "A public SSH key lets a trusted Pino client send this host's first secret projection."
  read -r -p "Bootstrap SSH public key (leave empty for local Cryptomator population): " BOOTSTRAP_SSH_KEY
fi
if [ -n "$BOOTSTRAP_SSH_KEY" ]; then
  case "$BOOTSTRAP_SSH_KEY" in
    ssh-ed25519\ *|ssh-rsa\ *|sk-ssh-ed25519@openssh.com\ *) ;;
    *) echo "Unsupported SSH public-key format." >&2; exit 1 ;;
  esac
  sudo install -d -m 0755 /mnt/etc/ssh/authorized_keys.d
  printf '%s\n' "$BOOTSTRAP_SSH_KEY" | sudo tee "/mnt/etc/ssh/authorized_keys.d/$PINO_USER" >/dev/null
  sudo chmod 0644 "/mnt/etc/ssh/authorized_keys.d/$PINO_USER"
  sudo install -d -m 0700 /mnt/var/lib/pino/bootstrap
  bootstrap_code="$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  bootstrap_expires="$(( $(date +%s) + 3600 ))"
  printf '%s %s\n' "$bootstrap_code" "$bootstrap_expires" \
    | sudo tee /mnt/var/lib/pino/bootstrap/pending >/dev/null
  sudo chmod 0600 /mnt/var/lib/pino/bootstrap/pending
  BOOTSTRAP_READY=true
fi

if [ -t 0 ]; then
  echo "Set a local password for $PINO_USER before rebooting."
  sudo nixos-enter --root /mnt -c "passwd $PINO_USER"
  PASSWORD_CONFIGURED=true
fi

echo ""
echo "Done. No plaintext secret source was opened by the installer."
if [ "$BOOTSTRAP_READY" = true ]; then
  echo "One-time bootstrap code (valid for one hour): $bootstrap_code"
  echo "After first boot, run on a trusted client:"
  echo "  pino bootstrap host apply $HOST <new-host-address>"
else
  echo "After first desktop login, unlock hosts/$HOST and run: pino secrets populate"
fi
if [ "$PASSWORD_CONFIGURED" = false ]; then
  echo "The $PINO_USER password is not configured. Before rebooting, run:"
  echo "  sudo nixos-enter --root /mnt -c 'passwd $PINO_USER'"
fi
if [ "$DATA_RESTORED" = true ]; then
  echo "Non-secret profile data was restored from the selected pino-data medium."
fi
