{ activeProfiles, lib, ... }:

let
  validProfiles = [
    "gaming-lite" "gaming-full"
    "virt-general" "virt-osdev"
    "music-lite" "music-full"
    "dev-cpp"
  ];

  profileScript = ''
    HOSTNAME_VAL=$(hostname)
    CONFIG_DIR="''${NIXOS_CONFIG_DIR:-/home/egrapa/nixos-config}"
    PROFILES_FILE="''${CONFIG_DIR}/hosts/''${HOSTNAME_VAL}/active-profiles.nix"

    VALID_PROFILES=(${lib.concatStringsSep " " validProfiles})

    usage() {
      echo "Usage: pino profile <command> [profile]"
      echo ""
      echo "Commands:"
      echo "  enable <profile>   Enable a profile and rebuild"
      echo "  disable <profile>  Disable a profile and rebuild"
      echo "  list               List all available profiles"
      echo "  status             Show currently active profiles"
    }

    is_valid() {
      local profile="$1" p
      for p in "''${VALID_PROFILES[@]}"; do
        [[ "$p" == "$profile" ]] && return 0
      done
      return 1
    }

    get_active() {
      grep -oP '"\K[^"]+(?=")' "$PROFILES_FILE" 2>/dev/null | grep -v '^\s*$' || true
    }

    write_profiles() {
      {
        printf '# Managed by pino profile. Do not edit manually.\n'
        if [[ $# -eq 0 ]]; then
          printf '[]\n'
        else
          printf '['
          local p
          for p in "$@"; do
            printf ' "%s"' "$p"
          done
          printf ' ]\n'
        fi
      } > "$PROFILES_FILE"
    }

    rebuild() {
      echo "Rebuilding NixOS (this requires sudo)..."
      sudo nixos-rebuild switch --flake "''${CONFIG_DIR}#''${HOSTNAME_VAL}"
    }

    cmd="''${1:-}"
    case "$cmd" in
      enable)
        profile="''${2:-}"
        [[ -z "$profile" ]] && { usage; exit 1; }
        is_valid "$profile" || { echo "Unknown profile: $profile"; echo "Valid: ''${VALID_PROFILES[*]}"; exit 1; }

        mapfile -t active < <(get_active)
        for p in "''${active[@]}"; do
          [[ "$p" == "$profile" ]] && { echo "Profile '$profile' is already enabled"; exit 0; }
        done

        active+=("$profile")
        write_profiles "''${active[@]}"
        echo "Enabled: $profile"
        rebuild
        ;;

      disable)
        profile="''${2:-}"
        [[ -z "$profile" ]] && { usage; exit 1; }

        mapfile -t active < <(get_active)
        new_active=()
        found=false
        for p in "''${active[@]}"; do
          if [[ "$p" == "$profile" ]]; then
            found=true
          else
            new_active+=("$p")
          fi
        done

        [[ "$found" == false ]] && { echo "Profile '$profile' is not enabled"; exit 0; }

        cleanup_dir=""
        case "$profile" in
          music-lite)
            cleanup_dir=$(nix eval --raw "path:''${CONFIG_DIR}#nixosConfigurations.''${HOSTNAME_VAL}.config.musicLite.localDir" 2>/dev/null || true)
            ;;
        esac

        if [[ ''${#new_active[@]} -eq 0 ]]; then
          write_profiles
        else
          write_profiles "''${new_active[@]}"
        fi
        echo "Disabled: $profile"

        if [[ -n "$cleanup_dir" && -d "$cleanup_dir" ]]; then
          echo "Removing profile data: $cleanup_dir"
          rm -rf "$cleanup_dir"
        fi

        rebuild
        ;;

      list)
        echo "Available profiles:"
        for p in "''${VALID_PROFILES[@]}"; do
          echo "  $p"
        done
        ;;

      status)
        mapfile -t active < <(get_active)
        echo "Active profiles on ''${HOSTNAME_VAL}:"
        if [[ ''${#active[@]} -eq 0 ]]; then
          echo "  (none)"
        else
          for p in "''${active[@]}"; do
            echo "  $p"
          done
        fi
        ;;

      *)
        usage
        [[ -z "$cmd" ]] && exit 0 || exit 1
        ;;
    esac
  '';
in
{
  imports = map (p: ./. + "/${p}.nix") activeProfiles;

  options.musicLite.localDir = lib.mkOption {
    type        = lib.types.str;
    default     = "/home/egrapa/music-lite";
    description = "Host-local path for music-lite data. Override per-host when using a faster disk.";
  };

  config = {
  assertions = map (p: {
    assertion = lib.elem p validProfiles;
    message = "Unknown profile '${p}' in active-profiles.nix. Valid: ${lib.concatStringsSep ", " validProfiles}";
  }) activeProfiles;

  pino.subcommands.profile = {
    description = "Manage NixOS profiles  (gaming, dev-cpp, ...)";
    helpText = ''
      pino profile — manage NixOS profiles
        pino profile list               List available profiles
        pino profile status             Show active profiles on this machine
        pino profile enable  <name>     Enable a profile and rebuild
        pino profile disable <name>     Disable a profile and rebuild

        Active profiles: hosts/<hostname>/active-profiles.nix
    '';
    script = profileScript;
    fishCompletions = ''
      complete -c pino -f -n '__fish_seen_subcommand_from profile' -a list    -d 'List available profiles'
      complete -c pino -f -n '__fish_seen_subcommand_from profile' -a status  -d 'Show active profiles'
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and __fish_seen_subcommand_from enable disable' -a '${lib.concatStringsSep " " validProfiles}' -d 'Profile name'
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list status enable disable' -a enable  -d 'Enable a profile and rebuild'
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list status enable disable' -a disable -d 'Disable a profile and rebuild'
    '';
  };
  }; # config
}
