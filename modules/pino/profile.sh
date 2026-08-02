HOSTNAME_VAL=$(hostname)
CONFIG_DIR="${NIXOS_CONFIG_DIR:-/home/egrapa/nixos-config}"
PROFILES_FILE="${CONFIG_DIR}/hosts/${HOSTNAME_VAL}/active-profiles.nix"
VALID_PROFILES=(@validProfiles@)
PROFILE_GROUPS=(@profileGroups@)

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

profile_group() {
  local profile="$1" entry group members member
  local -a group_profiles
  for entry in "${PROFILE_GROUPS[@]}"; do
    group="${entry%%:*}"
    members="${entry#*:}"
    IFS=',' read -r -a group_profiles <<< "$members"
    for member in "${group_profiles[@]}"; do
      [ "$member" = "$profile" ] && { printf '%s\n' "$group"; return; }
    done
  done
  printf 'unknown\n'
}

list_profiles() {
  local entry group members profile
  local -a group_profiles
  for entry in "${PROFILE_GROUPS[@]}"; do
    group="${entry%%:*}"
    members="${entry#*:}"
    printf '%s\n' "$group"
    IFS=',' read -r -a group_profiles <<< "$members"
    for profile in "${group_profiles[@]}"; do
      printf '  %s\n' "$profile"
    done
  done
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
    list_profiles
    ;;
  status)
    mapfile -t active < <(get_active)
    if [ "${#active[@]}" -eq 0 ]; then
      echo "No active profiles on $HOSTNAME_VAL"
    else
      printf '%-14s %s\n' "GROUP" "PROFILE"
      for profile in "${active[@]}"; do
        printf '%-14s %s\n' "$(profile_group "$profile")" "$profile"
      done
    fi
    ;;
  *)
    usage
    [ -z "$command" ] || exit 1
    ;;
esac
