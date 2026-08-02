#!/usr/bin/env bash
# Host-configurable Snapper frontend used by the snapshots profile.

SYSTEM_CONFIGS=(@systemConfigs@)
DATA_CONFIGS=(@dataConfigs@)

contains() {
  local wanted="$1" candidate
  shift
  for candidate in "$@"; do
    [ "$candidate" = "$wanted" ] && return 0
  done
  return 1
}

create_all() {
  local label="$1" config
  shift
  for config in "$@"; do
    sudo snapper -c "$config" create -d "$label"
  done
}

list_all() {
  local config
  for config in "$@"; do
    printf '=== %s ===\n' "$config"
    sudo snapper -c "$config" list
  done
}

delete_all() {
  local number="$1" config
  shift
  for config in "$@"; do
    sudo snapper -c "$config" delete "$number"
  done
}

undo_all() {
  local number="$1" config
  shift
  for config in "$@"; do
    sudo snapper -c "$config" undochange "$number..0"
  done
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
    undo_all "$1" "${SYSTEM_CONFIGS[@]}"
    ;;
  rm)
    require_number "${1:-}" || exit 1
    delete_all "$1" "${SYSTEM_CONFIGS[@]}"
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
        delete_all "$1" "${DATA_CONFIGS[@]}"
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
        create_all "$data_command" "${DATA_CONFIGS[@]}"
        echo "Created data snapshot: $data_command"
        ;;
    esac
    ;;
  "")
    echo "Run 'pino storage snap help' for usage." >&2
    exit 1
    ;;
  *)
    create_all "$subcommand" "${SYSTEM_CONFIGS[@]}"
    echo "Created system snapshot: $subcommand"
    ;;
esac
