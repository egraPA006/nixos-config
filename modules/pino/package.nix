{ pkgs, ... }:
{
  # Packages installed here persist until explicitly removed with `pino package remove`.
  # The profile lives outside the NixOS config so no rebuild is needed.
  programs.fish.shellInit = ''
    set -gx PATH $HOME/.local/share/pino-pkgs/bin $PATH
  '';

  environment.systemPackages = [ pkgs.nix-index ];

  pino.subcommands.package = {
    description = "Manage temporary packages (no rebuild needed)";
    helpText = ''
      pino package — manage per-user temporary packages

        pino package list              List installed packages
        pino package search <query>    Search nixpkgs (top-level only)
        pino package locate <pattern>  Find packages containing a file
        pino package index             Rebuild the local nix-locate database
        pino package install <name>    Install nixpkgs#<name>
        pino package remove  <name>    Remove package by name

      Packages are stored in ~/.local/share/pino-pkgs and are available
      immediately after install — no NixOS rebuild required.
      Remove a package with 'pino package remove <name>' when done.
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
          [ -z "$query" ] && { echo "Usage: pino package search <query>"; exit 1; }
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
          [ -z "$pattern" ] && { echo "Usage: pino package locate <pattern>"; exit 1; }
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
          [ -z "$pkg" ] && { echo "Usage: pino package install <name>"; exit 1; }
          nix profile install "nixpkgs#$pkg" --profile "$PROFILE"
          echo "Installed $pkg — available in new shells and after PATH reload."
          ;;

        remove)
          pkg="''${1:-}"
          [ -z "$pkg" ] && { echo "Usage: pino package remove <name>"; exit 1; }
          nix profile remove "$pkg" --profile "$PROFILE"
          echo "Removed $pkg."
          ;;

        "")
          echo "pino package — manage per-user temporary packages"
          echo ""
          echo "  list              List installed packages"
          echo "  search <query>    Search nixpkgs"
          echo "  locate <pattern>  Find packages containing a file"
          echo "  index             Rebuild the nix-locate database"
          echo "  install <name>    Install nixpkgs#<name>"
          echo "  remove  <name>    Remove package by name"
          echo ""
          echo "Run 'pino package help' for more details."
          ;;

        *)
          echo "pino package: unknown subcommand '$subcmd'"
          echo "Run 'pino package help' for usage."
          exit 1
          ;;
      esac
    '';
    fishCompletions = ''
      set -l pkg_cmds list search locate index install remove
      complete -c pino -f -n '__fish_seen_subcommand_from package; and not __fish_seen_subcommand_from $pkg_cmds' -a list    -d 'List installed packages'
      complete -c pino -f -n '__fish_seen_subcommand_from package; and not __fish_seen_subcommand_from $pkg_cmds' -a search  -d 'Search nixpkgs'
      complete -c pino -f -n '__fish_seen_subcommand_from package; and not __fish_seen_subcommand_from $pkg_cmds' -a locate  -d 'Find packages containing a file'
      complete -c pino -f -n '__fish_seen_subcommand_from package; and not __fish_seen_subcommand_from $pkg_cmds' -a index   -d 'Rebuild nix-locate database'
      complete -c pino -f -n '__fish_seen_subcommand_from package; and not __fish_seen_subcommand_from $pkg_cmds' -a install -d 'Install a package'
      complete -c pino -f -n '__fish_seen_subcommand_from package; and not __fish_seen_subcommand_from $pkg_cmds' -a remove  -d 'Remove a package'
    '';
  };
}
