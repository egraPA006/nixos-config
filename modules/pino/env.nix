{ config, lib, pkgs, ... }:
let
  declared = config.pino.environments;
  environments = lib.mapAttrs (name: packages: pkgs.buildEnv {
    name = "pino-env-${name}";
    paths = packages;
  }) declared;
  declaredCases = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path:
    "${lib.escapeShellArg name}) printf '%s\\n' ${lib.escapeShellArg (toString path)} ;;") environments);
  declaredNames = lib.concatStringsSep " " (map lib.escapeShellArg (builtins.attrNames declared));
  presets = {
    empty = [ ];
    cpp = [ "gcc" "clang" "clang-tools" "cmake" "meson" "ninja" "pkg-config" "gdb" ];
    python = [ "python3" "python3Packages.pip" "python3Packages.virtualenv" ];
    verilog = [ "iverilog" "verilator" "gtkwave" ];
  };
  presetCases = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: packages: "${name}) packages=(${lib.concatStringsSep " " packages}) ;;") presets);
  presetList = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: packages: "printf '%-12s %s\\n' ${lib.escapeShellArg name} ${lib.escapeShellArg (if packages == [ ] then "(empty)" else lib.concatStringsSep " " packages)}") presets);
in
{
  options.pino.environments = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.package);
    default = { };
    description = "Named, system-declared package environments; changes apply on rebuild.";
    example = lib.literalExpression ''{ cpp = with pkgs; [ gcc cmake ]; }'';
  };

  config = {
    assertions = lib.mapAttrsToList (name: _: {
      assertion = builtins.match "[A-Za-z0-9][A-Za-z0-9_-]{0,63}" name != null;
      message = "Invalid pino.environments name: ${name}";
    }) declared;
    pino.subcommands.os.commands.env = {
      description = "Manage named user and declarative package environments";
      commands = {
        list.description = "List declarative and local environments";
        templates.description = "List environment templates and their packages";
        create = { description = "Create a local environment"; usage = "<name> [empty|cpp|python|verilog]"; };
        enter = { description = "Enter an environment"; usage = "<name>"; };
        add = { description = "Add a package to a local environment"; usage = "<name> <nixpkgs-package>"; };
        remove = { description = "Remove a package from a local environment"; usage = "<name> <nixpkgs-package>"; };
        delete = { description = "Delete a local environment"; usage = "<name>"; };
      };
      helpText = ''
        Declare pino.environments.<name> as a list of Nix packages and rebuild.
        Declarative environments cannot be changed with create/add/remove/delete.
        Local environments live in ~/.local/share/pino/envs and do not require rebuild.
        Environments change PATH; they do not isolate files, processes or networking.
      '';
      script = ''
        env_root="''${XDG_DATA_HOME:-$HOME/.local/share}/pino/envs"
        valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; }
        valid_package() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; }
        env_path() { printf '%s/%s\n' "$env_root" "$1"; }
        declared_path() {
          case "$1" in
            ${declaredCases}
            *) return 1 ;;
          esac
        }
        require_local() {
          valid_name "$1" || { echo "Invalid environment name." >&2; exit 1; }
          if declared_path "$1" >/dev/null; then
            echo "Environment $1 is declarative; change pino.environments and rebuild." >&2; exit 1
          fi
          [ -d "$(env_path "$1")" ] || { echo "Environment does not exist: $1" >&2; exit 1; }
        }
        add_package() {
          local name="$1" package="$2" target
          require_local "$name"
          valid_package "$package" || { echo "Invalid nixpkgs package." >&2; exit 1; }
          target="$(env_path "$name")"
          if ${pkgs.gnugrep}/bin/grep -qxF "$package" "$target/packages"; then
            echo "$package is already present in $name."; return
          fi
          ${pkgs.nix}/bin/nix profile add --profile "$target/profile" "nixpkgs#$package"
          printf '%s\n' "$package" >> "$target/packages"
          echo "Added $package to $name."
        }
        case "''${1:-}" in
          templates)
            ${presetList}
            ;;
          list)
            for name in ${declaredNames}; do printf '%-20s %s\n' "$name" declarative; done
            if [ -d "$env_root" ]; then
              while IFS= read -r name; do
                if declared_path "$name" >/dev/null; then
                  printf '%-20s %s\n' "$name" 'local (name conflict)'
                else
                  printf '%-20s %s\n' "$name" local
                fi
              done < <(${pkgs.findutils}/bin/find "$env_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | ${pkgs.coreutils}/bin/sort)
            fi
            ;;
          create)
            name="''${2:-}"; preset="''${3:-empty}"
            valid_name "$name" || { echo 'Usage: pino os env create <name> [preset]' >&2; exit 1; }
            if declared_path "$name" >/dev/null; then echo "Environment $name is declarative." >&2; exit 1; fi
            case "$preset" in ${presetCases} *) echo "Unknown preset: $preset" >&2; exit 1 ;; esac
            target="$(env_path "$name")"
            [ ! -e "$target" ] || { echo "Environment already exists: $name" >&2; exit 1; }
            ${pkgs.coreutils}/bin/mkdir -p "$target"
            : > "$target/packages"
            for package in "''${packages[@]}"; do add_package "$name" "$package"; done
            echo "Created $name. Enter it with: pino os env enter $name"
            ;;
          enter)
            name="''${2:-}"
            valid_name "$name" || { echo 'Usage: pino os env enter <name>' >&2; exit 1; }
            if target="$(declared_path "$name")"; then
              [ ! -d "$(env_path "$name")" ] || { echo "Local and declarative environments share name $name; resolve the conflict." >&2; exit 1; }
            else
              require_local "$name"
              target="$(env_path "$name")/profile"
            fi
            export PINO_ENV="$name"
            export PATH="$target/bin:$PATH"
            echo "Entering $name. Exit the shell to leave."
            exec "''${SHELL:-${pkgs.bashInteractive}/bin/bash}"
            ;;
          add|remove)
            [ "$#" -eq 3 ] || { echo 'Usage: pino os env <add|remove> <name> <package>' >&2; exit 1; }
            name="$2"; package="$3"
            if [ "$1" = add ]; then add_package "$name" "$package"; else
              require_local "$name"
              valid_package "$package" || { echo 'Invalid nixpkgs package.' >&2; exit 1; }
              target="$(env_path "$name")"
              ${pkgs.gnugrep}/bin/grep -qxF "$package" "$target/packages" || { echo "Package not in $name: $package" >&2; exit 1; }
              ${pkgs.nix}/bin/nix profile remove --profile "$target/profile" "$package"
              ${pkgs.gnugrep}/bin/grep -vxF "$package" "$target/packages" > "$target/packages.new" || true
              ${pkgs.coreutils}/bin/mv "$target/packages.new" "$target/packages"
              echo "Removed $package from $name."
            fi
            ;;
          delete)
            name="''${2:-}"; require_local "$name"
            read -r -p "Type 'delete $name' to remove its local package profile: " answer
            [ "$answer" = "delete $name" ] || { echo 'Cancelled.'; exit 0; }
            ${pkgs.coreutils}/bin/rm -rf -- "$(env_path "$name")"
            echo "Deleted $name."
            ;;
          *) echo "Run 'pino os env help' for usage." >&2; exit 1 ;;
        esac
      '';
    };
  };
}
