DATA_LABEL_PREFIX=pino-data-
HOST_NAME=@hostName@
MERGE_TOOL=@mergeTool@
DATASET_NAMES=(@datasetNames@)
DATASET_PATHS=(@datasetPaths@)
DATASET_SCOPES=(@datasetScopes@)

dataset_index() {
  local requested="$1" index
  for index in "${!DATASET_NAMES[@]}"; do
    if [ "${DATASET_NAMES[$index]}" = "$requested" ]; then
      printf '%s\n' "$index"
      return
    fi
  done
  echo "Unknown dataset: $requested" >&2
  echo "Run 'pino storage data list' to see configured datasets." >&2
  return 1
}

dataset_medium_path() {
  local mount_point="$1" index="$2" name scope
  name="${DATASET_NAMES[$index]}"
  scope="${DATASET_SCOPES[$index]}"
  if [ "$scope" = shared ]; then
    printf '%s/pino/datasets/shared/%s\n' "$mount_point" "$name"
  else
    printf '%s/pino/datasets/hosts/%s/%s\n' "$mount_point" "$HOST_NAME" "$name"
  fi
}

list_datasets() {
  local index state medium
  printf '%-18s %-8s %-8s %-38s %s\n' NAME SCOPE STATE LOCAL MEDIUM
  for index in "${!DATASET_NAMES[@]}"; do
    if [ -d "${DATASET_PATHS[$index]}" ]; then state=present; else state=missing; fi
    if [ "${DATASET_SCOPES[$index]}" = shared ]; then
      medium="shared/${DATASET_NAMES[$index]}"
    else
      medium="hosts/$HOST_NAME/${DATASET_NAMES[$index]}"
    fi
    printf '%-18s %-8s %-8s %-38s %s\n' \
      "${DATASET_NAMES[$index]}" "${DATASET_SCOPES[$index]}" "$state" \
      "${DATASET_PATHS[$index]}" "$medium"
  done
}

data_devices() {
  lsblk -rpn -o NAME,LABEL,FSTYPE \
    | awk '$2 ~ /^pino-data-/ && $3 == "exfat" { print $1 }'
}

select_data_device() {
  local requested="${1:-}" data_label
  local -a devices=()
  if [ -n "$requested" ]; then
    case "$requested" in
      "$DATA_LABEL_PREFIX"*) data_label="$requested" ;;
      *) data_label="$DATA_LABEL_PREFIX$requested" ;;
    esac
    mapfile -t devices < <(
      lsblk -rpn -o NAME,LABEL,FSTYPE \
        | awk -v label="$data_label" '$2 == label && $3 == "exfat" { print $1 }'
    )
  else
    mapfile -t devices < <(data_devices)
  fi
  case "${#devices[@]}" in
    1) DATA_DEVICE="${devices[0]}" ;;
    0) echo "No connected exFAT partition labelled ${data_label:-pino-data-*} was found." >&2; return 1 ;;
    *)
      echo "Several pino-data-* partitions are connected; specify one by label or suffix:" >&2
      lsblk -rno PATH,LABEL,FSTYPE | awk '$2 ~ /^pino-data-/ && $3 == "exfat" { printf "  %s  %s\n", $1, $2 }' >&2
      return 1
      ;;
  esac
}

with_data_disk() {
  local mode="$1" operation="$2" requested="${3:-}"
  local mount_point operation_status mounted=false existing_mount uid gid
  shift 3
  select_data_device "$requested"
  existing_mount="$(findmnt -rn -S "$DATA_DEVICE" -o TARGET | head -n 1)"
  if [ -n "$existing_mount" ]; then
    mount_point="$existing_mount"
    if [ "$mode" = rw ] && ! findmnt -rn -S "$DATA_DEVICE" -o OPTIONS | grep -qw rw; then
      echo "$DATA_DEVICE is mounted read-only at $mount_point." >&2
      return 1
    fi
  else
    mount_point="/run/pino-data-$(basename "$DATA_DEVICE")"
    uid="$(id -u)"
    gid="$(id -g)"
    sudo mkdir -p "$mount_point"
    if [ "$mode" = ro ]; then
      sudo mount -o "ro,nodev,nosuid,noexec,uid=$uid,gid=$gid,umask=0022" "$DATA_DEVICE" "$mount_point"
    else
      sudo mount -o "rw,nodev,nosuid,noexec,uid=$uid,gid=$gid,umask=0022" "$DATA_DEVICE" "$mount_point"
    fi
    mounted=true
  fi
  cleanup_data_disk() {
    if [ "$mounted" = true ]; then sudo umount "$mount_point" || true; fi
  }
  trap cleanup_data_disk EXIT INT TERM
  if "$operation" "$mount_point" "$@"; then operation_status=0; else operation_status=$?; fi
  cleanup_data_disk
  trap - EXIT INT TERM
  return "$operation_status"
}

reject_symlinks() {
  local source="$1"
  if find "$source" -type l -print -quit | grep -q .; then
    echo "Dataset contains symbolic links, which cannot be represented safely on exFAT:" >&2
    find "$source" -type l -print | head -n 10 >&2
    return 1
  fi
}

exact_copy() {
  local direction="$1" source="$2" destination="$3" dataset="$4" confirmation preview
  if [ ! -d "$source" ]; then
    echo "Source dataset does not exist: $source" >&2
    return 1
  fi
  reject_symlinks "$source"
  mkdir -p "$destination"
  preview="$(rsync -rt --delete --modify-window=1 --itemize-changes --dry-run "$source/" "$destination/")"
  if [ -z "$preview" ]; then
    echo "$dataset is already identical in the $direction direction."
    return
  fi
  echo "$preview"
  echo
  echo "WARNING: $direction makes the destination exactly match the source."
  echo "  source:      $source"
  echo "  destination: $destination"
  echo "Destination-only files shown above will be deleted."
  read -r -p "Type '$dataset' to continue: " confirmation
  if [ "$confirmation" != "$dataset" ]; then
    echo "$direction cancelled."
    return 1
  fi
  rsync -rt --delete --modify-window=1 --info=progress2 "$source/" "$destination/"
  echo "$direction completed for $dataset"
}

run_dataset_operation() {
  local mount_point="$1" operation="$2" dataset="$3" index local_path medium_path
  index="$(dataset_index "$dataset")"
  local_path="${DATASET_PATHS[$index]}"
  medium_path="$(dataset_medium_path "$mount_point" "$index")"
  case "$operation" in
    backup) exact_copy backup "$local_path" "$medium_path" "$dataset" ;;
    restore) exact_copy restore "$medium_path" "$local_path" "$dataset" ;;
    merge)
      if [ ! -d "$medium_path" ]; then
        echo "Dataset does not exist on the medium: $medium_path" >&2
        return 1
      fi
      mkdir -p "$local_path"
      "$MERGE_TOOL" "$medium_path" "$local_path"
      ;;
  esac
}

parse_dataset_operation() {
  local operation="$1" first="${2:-}" second="${3:-}" selector dataset mode
  if [ -n "$second" ]; then
    selector="$first"
    dataset="$second"
  else
    selector=""
    dataset="$first"
  fi
  if [ -z "$dataset" ]; then
    echo "Usage: pino storage data $operation [disk] <dataset>" >&2
    return 1
  fi
  dataset_index "$dataset" >/dev/null
  if [ "$operation" = backup ]; then mode=rw; else mode=ro; fi
  with_data_disk "$mode" run_dataset_operation "$selector" "$operation" "$dataset"
}

case "${1:-}" in
  list) list_datasets ;;
  disks)
    mapfile -t devices < <(data_devices)
    if [ "${#devices[@]}" -eq 0 ]; then
      echo "No connected exFAT partitions labelled pino-data-* found"
    else
      for device in "${devices[@]}"; do
        lsblk -dno LABEL "$device"
      done
    fi
    ;;
  backup|restore|merge) parse_dataset_operation "$1" "${2:-}" "${3:-}" ;;
  "") echo "Usage: pino storage data <list|disks|backup|restore|merge>" ;;
  *) echo "pino storage data: unknown command '$1'" >&2; exit 1 ;;
esac
