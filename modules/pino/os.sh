#!/usr/bin/env bash
CONFIG_DIR=@configDir@
PINO_USER=@pinoUser@
RUNUSER=@runuser@
SYSTEM_PROFILE="/nix/var/nix/profiles/system"
HOST_NAME="$(hostname)"
VAULT_ENABLED=@vaultEnabled@

# Git checkout and flake updates belong to the configured user. When invoked
# from a recovery root console, delegate first and let individual operations
# elevate only the system mutation they require.
if [ "$(id -u)" -eq 0 ]; then
  exec "$RUNUSER" -u "$PINO_USER" -- /run/current-system/sw/bin/pino os "$@"
fi

confirm() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) echo "Cancelled."; return 1 ;;
  esac
}

list_generations() {
  sudo nix-env --profile "$SYSTEM_PROFILE" --list-generations
}

current_generation() {
  list_generations | awk '$NF == "(current)" { print $1; exit }'
}

maybe_populate_vault() {
  local answer
  [ "$VAULT_ENABLED" = true ] || return 0
  read -r -p "Populate system secrets from the mounted vault before rebuilding? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      if ! pino vault secrets populate; then
        echo "Vault population failed; rebuild cancelled." >&2
        return 1
      fi
      ;;
    *) echo "Using the existing provisioned secret copies." ;;
  esac
}

rebuild_os() {
  echo "Host:   $HOST_NAME"
  echo "Flake:  $CONFIG_DIR#$HOST_NAME"
  confirm "Rebuild and switch this system?" || return
  maybe_populate_vault || return
  sudo nixos-rebuild switch --flake "$CONFIG_DIR#$HOST_NAME"
}

rollback_os() {
  local generation="${1:-}" old_generation confirmation
  list_generations
  if [ -z "$generation" ]; then
    echo
    read -r -p "Generation to activate: " generation
  fi
  case "$generation" in
    ""|*[!0-9]*) echo "Generation must be a number." >&2; return 1 ;;
  esac
  if [ ! -e "$SYSTEM_PROFILE-$generation-link" ]; then
    echo "System generation $generation does not exist." >&2
    return 1
  fi
  old_generation="$(current_generation)"
  if [ "$generation" = "$old_generation" ]; then
    echo "Generation $generation is already current."
    return
  fi
  read -r -p "Type '$generation' to activate system generation $generation: " confirmation
  if [ "$confirmation" != "$generation" ]; then
    echo "Generation switch cancelled."
    return 1
  fi
  sudo nix-env --profile "$SYSTEM_PROFILE" --switch-generation "$generation"
  if ! sudo "$SYSTEM_PROFILE/bin/switch-to-configuration" switch; then
    echo "Activation failed; restoring profile generation $old_generation." >&2
    sudo nix-env --profile "$SYSTEM_PROFILE" --switch-generation "$old_generation"
    return 1
  fi
  echo "System generation $generation is now active."
}

gc_os() {
  local current previous confirmation generation
  local -a generations=() delete=()
  mapfile -t generations < <(list_generations | awk '$1 ~ /^[0-9]+$/ { print $1 }')
  current="$(current_generation)"
  if [ -z "$current" ]; then
    echo "Unable to determine the current system generation." >&2
    return 1
  fi
  for generation in "${generations[@]}"; do
    if [ "$generation" -lt "$current" ]; then previous="$generation"; fi
  done
  for generation in "${generations[@]}"; do
    if [ "$generation" != "$current" ] && [ "$generation" != "${previous:-}" ]; then
      delete+=("$generation")
    fi
  done

  echo "Keep current generation:  $current"
  if [ -n "${previous:-}" ]; then
    echo "Keep previous generation: $previous"
  else
    echo "Previous generation:      none"
  fi
  if [ "${#delete[@]}" -eq 0 ]; then
    echo "No older system generations need deleting."
    return
  fi
  echo "Delete generations:       ${delete[*]}"
  echo "Then garbage-collect all unreferenced Nix store paths."
  read -r -p "Type 'gc' to continue: " confirmation
  if [ "$confirmation" != gc ]; then
    echo "Generation cleanup cancelled."
    return 1
  fi
  sudo nix-env --profile "$SYSTEM_PROFILE" --delete-generations "${delete[@]}"
  sudo "$SYSTEM_PROFILE/bin/switch-to-configuration" boot
  sudo nix-store --gc
  echo "Kept system generations $current${previous:+ and $previous}."
}

case "${1:-}" in
  rebuild) rebuild_os ;;
  generation)
    case "${2:-}" in
      list) list_generations ;;
      switch) rollback_os "${3:-}" ;;
      clean) gc_os ;;
      *) echo "Run 'pino os generation help' for usage." >&2; exit 1 ;;
    esac
    ;;
  "")
    echo "pino os — manage the NixOS system"
    echo
    echo "  rebuild          Confirm, rebuild, and switch the flake"
    echo "  generation       List, activate, and clean generations"
    ;;
  *) echo "pino os: unknown command '$1'" >&2; exit 1 ;;
esac
