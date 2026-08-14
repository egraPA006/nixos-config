HOSTNAME_VAL=$(hostname)
CONFIG_DIR="${NIXOS_CONFIG_DIR:-@configDir@}"
PROFILES_FILE="${CONFIG_DIR}/hosts/${HOSTNAME_VAL}/active-profiles.nix"
VALID_PROFILES=(@validProfiles@)
PROFILE_GROUPS=(@profileGroups@)

usage() {
  echo "Usage: pino profile <command> [profile]"
  echo
  echo "Commands:"
  echo "  enable <profile>   Enable a profile and rebuild"
  echo "  disable <profile>  Disable a profile and rebuild"
  echo "  list               List profiles with enabled markers"
  echo "  list --enabled     Print enabled profile names only"
}

is_valid() {
  local profile="$1" candidate
  for candidate in "${VALID_PROFILES[@]}"; do
    [ "$candidate" = "$profile" ] && return 0
  done
  return 1
}

list_profiles() {
  local entry group members profile active_profile marker
  local -a group_profiles active_profiles
  active_profiles=("$@")
  for entry in "${PROFILE_GROUPS[@]}"; do
    group="${entry%%:*}"
    members="${entry#*:}"
    printf '%s:\n' "$group"
    IFS=',' read -r -a group_profiles <<< "$members"
    for profile in "${group_profiles[@]}"; do
      marker=' '
      for active_profile in "${active_profiles[@]}"; do
        if [ "$profile" = "$active_profile" ]; then
          marker='✓'
          break
        fi
      done
      printf '  [%s] %s\n' "$marker" "$profile"
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

apply_profiles() {
  local backup
  backup="$(mktemp "${PROFILES_FILE}.backup.XXXXXX")"
  cp -p "$PROFILES_FILE" "$backup"
  if write_profiles "$@" && rebuild; then
    rm -f "$backup"
    return 0
  fi
  mv -f "$backup" "$PROFILES_FILE"
  echo "Profile change failed; restored $PROFILES_FILE." >&2
  return 1
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
    apply_profiles "${active[@]}"
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
    apply_profiles "${remaining[@]}"
    ;;
  list)
    mapfile -t active < <(get_active)
    [ "$#" -le 2 ] || { echo "Usage: pino profile list [--enabled]" >&2; exit 1; }
    case "${2:-}" in
      "") list_profiles "${active[@]}" ;;
      --enabled)
        [ "${#active[@]}" -eq 0 ] || printf '%s\n' "${active[@]}"
        ;;
      *) echo "Usage: pino profile list [--enabled]" >&2; exit 1 ;;
    esac
    ;;
  *)
    usage
    [ -z "$command" ] || exit 1
    ;;
esac
