{ config, lib, pkgs, ... }:

let
  cfg = config.pino.repository;
  configDir = config.pino.configDir;
  mirrorCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: url: ''
    if ${pkgs.git}/bin/git remote get-url ${lib.escapeShellArg "pino-${name}"} >/dev/null 2>&1; then
      ${pkgs.git}/bin/git remote set-url ${lib.escapeShellArg "pino-${name}"} ${lib.escapeShellArg url}
    else
      ${pkgs.git}/bin/git remote add ${lib.escapeShellArg "pino-${name}"} ${lib.escapeShellArg url}
    fi
  '') cfg.mirrors);
  pushCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: ''
    echo "Pushing $branch to ${name}..."
    ${pkgs.git}/bin/git push ${lib.escapeShellArg "pino-${name}"} \
      "refs/heads/$branch:refs/heads/$branch"
    ${pkgs.git}/bin/git push ${lib.escapeShellArg "pino-${name}"} --tags
  '') cfg.mirrors);
in
{
  options.pino.repository = {
    github = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/egraPA006/nixos-config.git";
      description = "Canonical public Git repository";
    };
    mirrors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        mosk = "mosk:/var/lib/pino/git/nixos-config.git";
      };
      description = "Writable SSH Git mirrors updated by trusted clients";
    };
    publicMirrors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://git.egrapa.com/nixos-config.git" ];
      description = "Read-only clone fallbacks for installation";
    };
  };

  config = {
    environment.systemPackages = [ pkgs.git ];

    pino.subcommands.repo = {
      description = "Maintain GitHub, server, and offline configuration copies";
      commands = {
        status.description = "Show repository state and configured mirrors";
        configure.description = "Install or update local mirror remotes";
        sync.description = "Push the current committed branch and tags to every mirror";
        bundle = { description = "Create a self-contained offline Git bundle"; usage = "<path>"; };
      };
      helpText = ''
        GitHub remains canonical, but every configured server receives the same
        committed branch. `bundle` creates an installation source that works
        without GitHub or any network connection. Uncommitted files are never
        copied by `sync`.
      '';
      script = ''
        CONFIG_DIR=${lib.escapeShellArg configDir}
        cd "$CONFIG_DIR"

        configure_mirrors() {
          if ! ${pkgs.git}/bin/git remote get-url origin >/dev/null 2>&1; then
            ${pkgs.git}/bin/git remote add origin ${lib.escapeShellArg cfg.github}
          fi
          ${mirrorCommands}
        }

        case "''${1:-}" in
          status)
            ${pkgs.git}/bin/git status --short --branch
            echo
            ${pkgs.git}/bin/git remote -v
            ;;
          configure)
            configure_mirrors
            ${pkgs.git}/bin/git remote -v
            ;;
          sync)
            configure_mirrors
            branch="$(${pkgs.git}/bin/git branch --show-current)"
            [ -n "$branch" ] || {
              echo "Cannot synchronize from a detached HEAD." >&2
              exit 1
            }
            if [ -n "$(${pkgs.git}/bin/git status --porcelain)" ]; then
              echo "Working tree has uncommitted changes; only committed objects will be mirrored." >&2
            fi
            echo "Pushing $branch to GitHub..."
            ${pkgs.git}/bin/git push origin "refs/heads/$branch:refs/heads/$branch"
            ${pkgs.git}/bin/git push origin --tags
            ${pushCommands}
            ;;
          bundle)
            output="''${2:-}"
            [ -n "$output" ] || {
              echo "Usage: pino repo bundle <path>" >&2
              exit 1
            }
            ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$output")"
            ${pkgs.git}/bin/git bundle create "$output" --all
            ${pkgs.git}/bin/git bundle verify "$output"
            echo "Offline repository bundle created at $output"
            ;;
          *) echo "Run 'pino repo help' for usage." >&2; exit 1 ;;
        esac
      '';
    };
  };
}
