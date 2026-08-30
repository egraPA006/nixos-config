#!/usr/bin/env bash
set -euo pipefail

operation="${1:-}"
case "$operation" in
  push|pull|status) shift ;;
  help|"") echo "Run 'pino backup help' for usage."; exit 0 ;;
  *) operation=push ;;
esac

disk="${1:-}"
[ -n "$disk" ] || { echo "A mounted backup disk is required." >&2; exit 1; }
shift || true

if [ -d "$disk" ]; then
  disk_root="$(findmnt -nro TARGET -T "$disk")"
elif [ -b "$disk" ]; then
  device="$(readlink -f "$disk")"
  disk_root="$(findmnt -nro TARGET -S "$device" | head -n 1)"
else
  echo "Not a mounted directory or block device: $disk" >&2
  exit 1
fi
[ -n "$disk_root" ] && [ -f "$disk_root/.pino-backup/version" ] || {
  echo "$disk is not a mounted Pino backup disk." >&2
  echo "Initialize a whole disk with scripts/backup-disk-init.sh first." >&2
  exit 1
}

disk_id="$(findmnt -nro UUID -T "$disk_root")"
disk_id="${disk_id//[^A-Za-z0-9_.-]/_}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/pino/backup/$disk_id"
store="$disk_root/.pino-backup/datasets"
mkdir -p "$state_root" "$store"

valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; }
refuse_unlocked_secrets() {
  local folder secret
  folder="$(realpath -m "$1")"
  secret="$(realpath -m "$BACKUP_SECRET_MOUNT_POINT")"
  if { [ "$secret" = "$folder" ] || [[ "$secret" = "$folder/"* ]]; } \
    && findmnt --mountpoint "$secret" >/dev/null 2>&1; then
    echo "Refusing to copy an unlocked secrets mount. Run: pino secret lock" >&2
    exit 1
  fi
}
latest_id() {
  local dataset="$1" link
  link="$(readlink "$dataset/latest" 2>/dev/null || true)"
  [ -n "$link" ] && basename "$link"
}

backup_push() {
  local folder="${1:-}" name="${2:-}" dataset latest remembered snapshot incoming
  [ -d "$folder" ] || { echo "Source folder does not exist: $folder" >&2; exit 1; }
  refuse_unlocked_secrets "$folder"
  valid_name "$name" || { echo "Invalid backup name: $name" >&2; exit 1; }
  dataset="$store/$name"
  mkdir -p "$dataset/snapshots"
  exec 9>"$dataset/lock"
  flock 9
  latest="$(latest_id "$dataset")"
  remembered="$(cat "$state_root/$name" 2>/dev/null || true)"
  if [ -n "$latest" ] && [ "$remembered" != "$latest" ]; then
    echo "Conflict for '$name': disk=$latest, this machine=${remembered:-never-synchronized}." >&2
    echo "Inspect status and pull the disk version before pushing." >&2
    exit 2
  fi

  snapshot="$(date -u +%Y%m%dT%H%M%S)-$(hostname)-$$"
  incoming="$dataset/snapshots/.incoming-$snapshot"
  mkdir "$incoming"
  cleanup() { rm -rf "$incoming"; }
  trap cleanup EXIT INT TERM
  rsync_args=(-a --one-file-system --delete)
  if [ -n "$latest" ]; then rsync_args+=(--link-dest="$dataset/snapshots/$latest"); fi
  rsync "${rsync_args[@]}" "$folder/" "$incoming/"
  {
    printf 'name=%s\n' "$name"
    printf 'host=%s\n' "$(hostname)"
    printf 'created=%s\n' "$(date -u --iso-8601=seconds)"
    printf 'source=%s\n' "$(realpath "$folder")"
  } > "$incoming/.pino-snapshot"
  mv "$incoming" "$dataset/snapshots/$snapshot"
  ln -sfn "snapshots/$snapshot" "$dataset/latest"
  printf '%s\n' "$snapshot" > "$state_root/$name"
  trap - EXIT INT TERM
  echo "Pushed '$name' as snapshot $snapshot."
}

backup_pull() {
  local folder="${1:-}" name="${2:-}" requested="${3:-}" dataset snapshot source answer
  [ -n "$folder" ] && [ "$folder" != / ] || { echo "Refusing unsafe restore target: $folder" >&2; exit 1; }
  refuse_unlocked_secrets "$folder"
  valid_name "$name" || { echo "Invalid backup name: $name" >&2; exit 1; }
  dataset="$store/$name"
  snapshot="${requested:-$(latest_id "$dataset")}"
  source="$dataset/snapshots/$snapshot"
  [ -d "$source" ] || { echo "Snapshot not found: $name/$snapshot" >&2; exit 1; }
  echo "This makes $folder exactly match $name/$snapshot and removes extra files."
  read -r -p "Type 'pull $name' to continue: " answer
  [ "$answer" = "pull $name" ] || { echo "Cancelled."; exit 0; }
  mkdir -p "$folder"
  rsync -a --delete --exclude .pino-snapshot "$source/" "$folder/"
  printf '%s\n' "$snapshot" > "$state_root/$name"
  echo "Pulled '$name' snapshot $snapshot into $folder."
}

backup_status() {
  local requested="${1:-}" dataset name latest remembered state
  printf '%-24s %-36s %-36s %s\n' NAME DISK THIS_MACHINE STATE
  shopt -s nullglob
  for dataset in "$store"/*; do
    [ -d "$dataset" ] || continue
    name="$(basename "$dataset")"
    [ -z "$requested" ] || [ "$requested" = "$name" ] || continue
    latest="$(latest_id "$dataset")"
    remembered="$(cat "$state_root/$name" 2>/dev/null || true)"
    if [ "$latest" = "$remembered" ]; then state=synchronized; else state=conflict; fi
    printf '%-24s %-36s %-36s %s\n' "$name" "${latest:--}" "${remembered:--}" "$state"
  done
}

case "$operation" in
  push) backup_push "${1:-}" "${2:-}" ;;
  pull) backup_pull "${1:-}" "${2:-}" "${3:-}" ;;
  status) backup_status "${1:-}" ;;
esac
