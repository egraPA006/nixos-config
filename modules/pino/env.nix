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
  templates = {
    cpp = mkTemplate "C/C++" [ "gcc" "clang" "clang-tools" "cmake" "meson" "ninja" "pkg-config" "gdb" ];
    python = mkTemplate "Python" [ "python3" "python3Packages.pip" "python3Packages.virtualenv" ];
    verilog = mkTemplate "Verilog" [ "iverilog" "verilator" "gtkwave" ];
  };
  templateCases = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: path: "${name}) template=${lib.escapeShellArg path} ;;") templates);
in
{
  pino.subcommands.env = {
    description = "Create and enter project development shells";
    commands = {
      list.description = "List personal development environments";
      init = {
        description = "Create a development flake without overwriting files";
        usage = "<cpp|python|verilog> [path]";
      };
      enter = {
        description = "Enter a project path or personal environment";
        usage = "[path|name]";
      };
    };
    helpText = ''
      With no path, `init` creates ~/.config/pino/envs/<preset>. With a path,
      it creates a normal project flake. Existing flakes are never replaced.
    '';
    script = ''
      env_root="''${XDG_CONFIG_HOME:-$HOME/.config}/pino/envs"
      case "''${1:-}" in
        list)
          if [ -d "$env_root" ]; then
            ${pkgs.findutils}/bin/find "$env_root" -mindepth 1 -maxdepth 1 \
              -type d -printf '%f\n' | ${pkgs.coreutils}/bin/sort
          fi
          ;;
        init)
          preset="''${2:-}"
          case "$preset" in
            ${templateCases}
            *) echo "Usage: pino env init <cpp|python|verilog> [path]" >&2; exit 1 ;;
          esac
          target="''${3:-$env_root/$preset}"
          [ ! -e "$target/flake.nix" ] || {
            echo "Refusing to overwrite $target/flake.nix" >&2
            exit 1
          }
          ${pkgs.coreutils}/bin/mkdir -p "$target"
          ${pkgs.coreutils}/bin/cp "$template" "$target/flake.nix"
          echo "Created $preset environment at $target"
          echo "Enter it with: pino env enter $target"
          ;;
        enter)
          target="''${2:-.}"
          if [ -d "$env_root/$target" ]; then target="$env_root/$target"; fi
          [ -f "$target/flake.nix" ] || { echo "No flake.nix at $target" >&2; exit 1; }
          exec ${pkgs.nix}/bin/nix develop "$target"
          ;;
        *) echo "Run 'pino env help' for usage." >&2; exit 1 ;;
      esac
    '';
    fishCompletions = ''
      complete -c pino -f -n '__fish_pino_at_path env init' \
        -a 'cpp python verilog' -d 'Development environment preset'
    '';
  };
}
