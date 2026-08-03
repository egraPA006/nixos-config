{ pkgs, ... }:
{
  # Packages installed here persist until explicitly removed with `pino os package remove`.
  # The profile lives outside the NixOS config so no rebuild is needed.
  programs.fish.shellInit = ''
    set -gx PATH $HOME/.local/share/pino-pkgs/bin $PATH
  '';

  environment.systemPackages = [ pkgs.nix-index ];

  pino.subcommands.os.commands.package = {
    description = "Manage temporary packages (no rebuild needed)";
    commands = {
      list.description = "List installed temporary packages";
      search = { description = "Search top-level nixpkgs packages"; usage = "<query>"; };
      locate = { description = "Find packages containing a file"; usage = "<pattern>"; };
      index.description = "Rebuild the local nix-locate database";
      install = { description = "Install a temporary package"; usage = "<name>"; };
      remove = { description = "Remove a temporary package"; usage = "<name>"; };
    };
    helpText = ''
      pino os package — manage per-user temporary packages

        pino os package list              List installed packages
        pino os package search <query>    Search nixpkgs (top-level only)
        pino os package locate <pattern>  Find packages containing a file
        pino os package index             Rebuild the local nix-locate database
        pino os package install <name>    Install nixpkgs#<name>
        pino os package remove  <name>    Remove package by name

      Packages are stored in ~/.local/share/pino-pkgs and are available
      immediately after install — no NixOS rebuild required.
      Remove a package with 'pino os package remove <name>' when done.
    '';
    script = ''
      PROFILE="$HOME/.local/share/pino-pkgs"
      subcmd="''${1:-}"
      shift || true

      case "$subcmd" in
        list)
          nix profile list --profile "$PROFILE"
          ;;

        search)
          query="''${1:-}"
          [ -z "$query" ] && { echo "Usage: pino os package search <query>"; exit 1; }
          echo "Searching nixpkgs for '$query' …" >&2
          nix search nixpkgs "$query" --json 2>/dev/null \
            | jq -r '
                to_entries
                | map(select(.key | test("^legacyPackages\\.x86_64-linux\\.[^.]+$")))
                | .[]
                | "[1m\(.value.pname)[0m (\(.value.version))\n  \(.value.description)\n"'
          ;;

        locate)
          pattern="''${1:-}"
          [ -z "$pattern" ] && { echo "Usage: pino os package locate <pattern>"; exit 1; }
          index_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-index"
          if ! compgen -G "$index_cache/files*" >/dev/null; then
            echo "No nix-locate database exists yet; building it now …" >&2
            nix-index
          fi
          nix-locate "$@"
          ;;

        index)
          echo "Rebuilding the nix-locate database …" >&2
          nix-index
          ;;

        install)
          pkg="''${1:-}"
          [ -z "$pkg" ] && { echo "Usage: pino os package install <name>"; exit 1; }
          nix profile install "nixpkgs#$pkg" --profile "$PROFILE"
          echo "Installed $pkg — available in new shells and after PATH reload."
          ;;

        remove)
          pkg="''${1:-}"
          [ -z "$pkg" ] && { echo "Usage: pino os package remove <name>"; exit 1; }
          nix profile remove "$pkg" --profile "$PROFILE"
          echo "Removed $pkg."
          ;;

        "")
          echo "pino os package — manage per-user temporary packages"
          echo ""
          echo "  list              List installed packages"
          echo "  search <query>    Search nixpkgs"
          echo "  locate <pattern>  Find packages containing a file"
          echo "  index             Rebuild the nix-locate database"
          echo "  install <name>    Install nixpkgs#<name>"
          echo "  remove  <name>    Remove package by name"
          echo ""
          echo "Run 'pino os package help' for more details."
          ;;

        *)
          echo "pino os package: unknown subcommand '$subcmd'"
          echo "Run 'pino os package help' for usage."
          exit 1
          ;;
      esac
    '';
  };
}
