HOSTNAME_VAL=$(hostname)
CONFIG_DIR="${NIXOS_CONFIG_DIR:-/home/egrapa/nixos-config}"
PROFILES_FILE="${CONFIG_DIR}/hosts/${HOSTNAME_VAL}/active-profiles.nix"
VALID_PROFILES=(@validProfiles@)

usage() {
  echo "Usage: pino profile <command> [profile]"
  echo
  echo "Commands:"
  echo "  enable <profile>   Enable a profile and rebuild"
  echo "  disable <profile>  Disable a profile and rebuild"
  echo "  list               List available profiles"
  echo "  status             Show active profiles"
}

is_valid() {
  local profile="$1" candidate
  for candidate in "${VALID_PROFILES[@]}"; do
    [ "$candidate" = "$profile" ] && return 0
  done
  return 1
}

get_active() {
  grep -oP '"\K[^"]+(?=")' "$PROFILES_FILE" 2>/dev/null | grep -v '^\s*$' || true
}

write_profiles() {
  {
    printf '# Managed by pino profile. Do not edit manually.\n'
    if [ "$#" -eq 0 ]; then
      printf '[]\n'
    else
      printf '['
      printf ' "%s"' "$@"
      printf ' ]\n'
    fi
  } > "$PROFILES_FILE"
}

rebuild() {
  echo "Rebuilding NixOS (this requires sudo)..."
  sudo nixos-rebuild switch --flake "${CONFIG_DIR}#${HOSTNAME_VAL}"
}

command="${1:-}"
case "$command" in
  enable)
    profile="${2:-}"
    [ -n "$profile" ] || { usage; exit 1; }
    is_valid "$profile" || { echo "Unknown profile: $profile"; exit 1; }
    mapfile -t active < <(get_active)
    for candidate in "${active[@]}"; do
      [ "$candidate" = "$profile" ] && { echo "Profile '$profile' is already enabled"; exit 0; }
    done
    active+=("$profile")
    write_profiles "${active[@]}"
    rebuild
    ;;
  disable)
    profile="${2:-}"
    [ -n "$profile" ] || { usage; exit 1; }
    mapfile -t active < <(get_active)
    remaining=()
    found=false
    for candidate in "${active[@]}"; do
      if [ "$candidate" = "$profile" ]; then
        found=true
      else
        remaining+=("$candidate")
      fi
    done
    [ "$found" = true ] || { echo "Profile '$profile' is not enabled"; exit 0; }
    write_profiles "${remaining[@]}"
    rebuild
    ;;
  list)
    printf '%s\n' "${VALID_PROFILES[@]}"
    ;;
  status)
    mapfile -t active < <(get_active)
    if [ "${#active[@]}" -eq 0 ]; then
      echo "No active profiles on $HOSTNAME_VAL"
    else
      printf '%s\n' "${active[@]}"
    fi
    ;;
  *)
    usage
    [ -z "$command" ] || exit 1
    ;;
esac
