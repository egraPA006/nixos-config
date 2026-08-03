#!/usr/bin/env bash
# Host-configurable Snapper frontend used by the snapshots profile.

SYSTEM_CONFIGS=(@systemConfigs@)
DATA_CONFIGS=(@dataConfigs@)
SET_ROOT=/var/lib/pino/snapshot-sets

contains() {
  local wanted="$1" candidate
  shift
  for candidate in "$@"; do
    [ "$candidate" = "$wanted" ] && return 0
  done
  return 1
}

create_set() {
  local group="$1" label="$2" config number primary_number="" records=""
  shift 2
  for config in "$@"; do
    number="$(sudo snapper -c "$config" create --print-number -d "$label")"
    require_number "$number" || return 1
    [ -n "$primary_number" ] || primary_number="$number"
    records+="${config}:${number}"$'\n'
  done
  sudo install -d -m 0700 "$SET_ROOT/$group"
  printf '%s' "$records" | sudo tee "$SET_ROOT/$group/$primary_number" >/dev/null
  sudo chmod 0600 "$SET_ROOT/$group/$primary_number"
  printf '%s\n' "$primary_number"
}

list_all() {
  local config
  for config in "$@"; do
    printf '=== %s ===\n' "$config"
    sudo snapper -c "$config" list
  done
}

resolve_set() {
  local group="$1" number="$2"
  shift 2
  if [ "$#" -eq 1 ]; then
    printf '%s:%s\n' "$1" "$number"
    return
  fi
  if ! sudo test -f "$SET_ROOT/$group/$number"; then
    echo "Snapshot $number predates logical snapshot sets; refusing an ambiguous multi-volume operation." >&2
    return 1
  fi
  sudo cat "$SET_ROOT/$group/$number"
}

operate_set() {
  local operation="$1" group="$2" number="$3" config snapshot records
  shift 3
  records="$(resolve_set "$group" "$number" "$@")" || return 1
  while IFS=: read -r config snapshot; do
    [ -n "$config" ] || continue
    case "$operation" in
      delete) sudo snapper -c "$config" delete "$snapshot" ;;
      undo) sudo snapper -c "$config" undochange "$snapshot..0" ;;
    esac
  done <<< "$records"
  if [ "$operation" = delete ] && sudo test -f "$SET_ROOT/$group/$number"; then
    sudo rm -f "$SET_ROOT/$group/$number"
  fi
}

require_number() {
  case "${1:-}" in
    ""|*[!0-9]*) echo "Snapshot number must be numeric." >&2; return 1 ;;
  esac
}

subcommand="${1:-}"
shift || true

case "$subcommand" in
  ls)
    list_all "${SYSTEM_CONFIGS[@]}"
    ;;
  rb)
    require_number "${1:-}" || exit 1
    operate_set undo system "$1" "${SYSTEM_CONFIGS[@]}"
    ;;
  rm)
    require_number "${1:-}" || exit 1
    operate_set delete system "$1" "${SYSTEM_CONFIGS[@]}"
    ;;
  data)
    if [ "${#DATA_CONFIGS[@]}" -eq 0 ]; then
      echo "This host has no data snapshot configurations." >&2
      exit 1
    fi
    data_command="${1:-}"
    shift || true
    case "$data_command" in
      ls)
        list_all "${DATA_CONFIGS[@]}"
        ;;
      rm)
        require_number "${1:-}" || exit 1
        operate_set delete data "$1" "${DATA_CONFIGS[@]}"
        ;;
      rb-*)
        config="${data_command#rb-}"
        contains "$config" "${DATA_CONFIGS[@]}" || {
          echo "Unknown data snapshot configuration: $config" >&2
          exit 1
        }
        require_number "${1:-}" || exit 1
        sudo snapper -c "$config" undochange "$1..0"
        ;;
      "")
        echo "Run 'pino storage snap data help' for usage." >&2
        exit 1
        ;;
      *)
        set_number="$(create_set data "$data_command" "${DATA_CONFIGS[@]}")"
        echo "Created data snapshot set $set_number: $data_command"
        ;;
    esac
    ;;
  "")
    echo "Run 'pino storage snap help' for usage." >&2
    exit 1
    ;;
  *)
    set_number="$(create_set system "$subcommand" "${SYSTEM_CONFIGS[@]}")"
    echo "Created system snapshot set $set_number: $subcommand"
    ;;
esac
