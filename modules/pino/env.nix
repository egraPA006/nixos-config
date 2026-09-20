{ lib, pkgs, ... }:

let
  mkTemplate = name: packages: pkgs.writeText "pino-env-${name}-flake.nix" ''
    {
      description = "Pino ${name} development environment";
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      outputs = { nixpkgs, ... }: let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in {
        devShells.x86_64-linux.default = pkgs.mkShell {
          packages = with pkgs; [ ${lib.concatStringsSep " " packages} ];
        };
      };
    }
  '';
  presets = {
    empty = [ ];
    cpp = [ "gcc" "clang" "clang-tools" "cmake" "meson" "ninja" "pkg-config" "gdb" ];
    python = [ "python3" "python3Packages.pip" "python3Packages.virtualenv" ];
    verilog = [ "iverilog" "verilator" "gtkwave" ];
  };
  templates = lib.mapAttrs (name: packages: mkTemplate name packages)
    (lib.removeAttrs presets [ "empty" ]);
  presetNames = builtins.attrNames presets;
  projectPresetNames = builtins.attrNames templates;
  presetCases = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: packages: "${name}) packages=(${lib.concatStringsSep " " packages}) ;;") presets);
  templateCases = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: path: "${name}) template=${lib.escapeShellArg path} ;;") templates);
in
{
  pino.subcommands.env = {
    description = "Manage isolated package environments and project dev shells";
    commands = {
      list.description = "List personal package environments";
      create = {
        description = "Create a persistent package environment";
        usage = "<name> [empty|cpp|python|verilog]";
      };
      enter = {
        description = "Enter a personal package environment";
        usage = "<name>";
      };
      add = {
        description = "Add a persistent package to an environment";
        usage = "[name] <nixpkgs-package>";
      };
      delete = {
        description = "Delete an environment and its packages";
        usage = "<name>";
      };
      export = {
        description = "Export an environment as a dev-shell flake";
        usage = "<name> [path]";
      };
      init = {
        description = "Create a preset project dev-shell flake";
        usage = "<cpp|python|verilog> [path]";
      };
    };
    helpText = ''
      Personal environments isolate package profiles, not files, processes, or
      networking. Inside one, `pino env add <package>` adds only to that
      environment. Export writes its package list as a reusable flake.nix.
    '';
    script = ''
      env_root="''${XDG_DATA_HOME:-$HOME/.local/share}/pino/envs"

      valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; }
      valid_package() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; }
      env_path() { printf '%s/%s\n' "$env_root" "$1"; }
      require_env() {
        [ -d "$(env_path "$1")" ] || {
          echo "Environment does not exist: $1" >&2
          exit 1
        }
      }
      add_package() {
        local name="$1" package="$2" target profile manifest
        valid_name "$name" || { echo "Invalid environment name: $name" >&2; exit 1; }
        valid_package "$package" || { echo "Invalid nixpkgs package: $package" >&2; exit 1; }
        require_env "$name"
        target="$(env_path "$name")"
        profile="$target/profile"
        manifest="$target/packages"
        if ${pkgs.gnugrep}/bin/grep -qxF "$package" "$manifest"; then
          echo "$package is already present in $name."
          return
        fi
        ${pkgs.nix}/bin/nix profile add --profile "$profile" "nixpkgs#$package"
        printf '%s\n' "$package" >> "$manifest"
        echo "Added $package to $name."
      }

      case "''${1:-}" in
        list)
          if [ -d "$env_root" ]; then
            ${pkgs.findutils}/bin/find "$env_root" -mindepth 1 -maxdepth 1 \
              -type d -printf '%f\n' | ${pkgs.coreutils}/bin/sort
          fi
          ;;
        create)
          name="''${2:-}"
          preset="''${3:-empty}"
          valid_name "$name" || {
            echo "Usage: pino env create <name> [${lib.concatStringsSep "|" presetNames}]" >&2
            exit 1
          }
          case "$preset" in
            ${presetCases}
            *) echo "Unknown preset: $preset" >&2; exit 1 ;;
          esac
          target="$(env_path "$name")"
          [ ! -e "$target" ] || { echo "Environment already exists: $name" >&2; exit 1; }
          ${pkgs.coreutils}/bin/mkdir -p "$target"
          : > "$target/packages"
          for package in "''${packages[@]}"; do add_package "$name" "$package"; done
          echo "Created $name. Enter it with: pino env enter $name"
          ;;
        enter)
          name="''${2:-}"
          valid_name "$name" || { echo "Usage: pino env enter <name>" >&2; exit 1; }
          require_env "$name"
          target="$(env_path "$name")"
          export PINO_ENV="$name"
          export PINO_ENV_ROOT="$target"
          export PATH="$target/profile/bin:$PATH"
          echo "Entering $name (package isolation only). Exit the shell to leave."
          exec "''${SHELL:-${pkgs.bashInteractive}/bin/bash}"
          ;;
        add)
          if [ -n "''${PINO_ENV:-}" ] && [ "$#" -eq 2 ]; then
            name="$PINO_ENV"
            package="$2"
          else
            name="''${2:-}"
            package="''${3:-}"
            [ "$#" -eq 3 ] || { echo "Usage: pino env add [name] <nixpkgs-package>" >&2; exit 1; }
          fi
          add_package "$name" "$package"
          ;;
        delete)
          name="''${2:-}"
          valid_name "$name" || { echo "Usage: pino env delete <name>" >&2; exit 1; }
          require_env "$name"
          target="$(env_path "$name")"
          read -r -p "Type 'delete $name' to remove its package profile: " answer
          [ "$answer" = "delete $name" ] || { echo "Cancelled."; exit 0; }
          ${pkgs.coreutils}/bin/rm -rf -- "$target"
          echo "Deleted $name. Project files were not touched."
          ;;
        export)
          name="''${2:-}"
          valid_name "$name" || { echo "Usage: pino env export <name> [path]" >&2; exit 1; }
          require_env "$name"
          source="$(env_path "$name")/packages"
          target="''${3:-./$name-env}"
          [ ! -e "$target/flake.nix" ] || {
            echo "Refusing to overwrite $target/flake.nix" >&2
            exit 1
          }
          ${pkgs.coreutils}/bin/mkdir -p "$target"
          {
            printf '{\n'
            printf '  description = "Exported Pino environment %s";\n' "$name"
            printf '  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";\n'
            printf '  outputs = { nixpkgs, ... }: let\n'
            printf '    pkgs = nixpkgs.legacyPackages.x86_64-linux;\n'
            printf '  in {\n'
            printf '    devShells.x86_64-linux.default = pkgs.mkShell {\n'
            printf '      packages = with pkgs; [\n'
            while IFS= read -r package; do printf '        %s\n' "$package"; done < "$source"
            printf '      ];\n'
            printf '    };\n'
            printf '  };\n'
            printf '}\n'
          } > "$target/flake.nix"
          echo "Exported $name to $target/flake.nix"
          ;;
        init)
          preset="''${2:-}"
          case "$preset" in
            ${templateCases}
            *) echo "Usage: pino env init <${lib.concatStringsSep "|" projectPresetNames}> [path]" >&2; exit 1 ;;
          esac
          target="''${3:-.}"
          [ ! -e "$target/flake.nix" ] || {
            echo "Refusing to overwrite $target/flake.nix" >&2
            exit 1
          }
          ${pkgs.coreutils}/bin/mkdir -p "$target"
          ${pkgs.coreutils}/bin/cp "$template" "$target/flake.nix"
          echo "Created $preset dev shell at $target/flake.nix"
          echo "Enter it with: nix develop $target"
          ;;
        *) echo "Run 'pino env help' for usage." >&2; exit 1 ;;
      esac
    '';
    fishCompletions = ''
      complete -c pino -f -n '__fish_pino_at_path env create' \
        -a '${lib.concatStringsSep " " presetNames}' -d 'Environment preset'
      complete -c pino -f -n '__fish_pino_at_path env init' \
        -a '${lib.concatStringsSep " " projectPresetNames}' -d 'Development environment preset'
    '';
  };
}
