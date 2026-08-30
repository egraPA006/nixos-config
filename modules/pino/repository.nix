{ config, lib, pkgs, ... }:

let
  configDir = config.pino.configDir;
in
{
  options.pino.repository.github = lib.mkOption {
    type = lib.types.str;
    default = "git@github.com:egraPA006/nixos-config.git";
    description = "Canonical configuration repository";
  };

  config = {
    environment.systemPackages = [ pkgs.git ];

    programs.ssh = {
      systemd-ssh-proxy.enable = false;
      knownHosts.github = {
        hostNames = [ "github.com" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
    };

    pino.subcommands.repo = {
      description = "Maintain the GitHub configuration checkout";
      commands = {
        status.description = "Show checkout and remote state";
        pull.description = "Fast-forward from GitHub";
        push.description = "Push the current branch and tags to GitHub";
        inputs = {
          description = "Manage flake inputs";
          commands.update.description = "Update flake.lock without rebuilding";
        };
      };
      helpText = ''
        GitHub is the only repository. Push and pull never copy uncommitted
        files or runtime secrets.
      '';
      script = ''
        CONFIG_DIR=${lib.escapeShellArg configDir}
        PINO_USER=${lib.escapeShellArg config.pino.user.name}
        if [ "$(${pkgs.coreutils}/bin/id -u)" -eq 0 ]; then
          exec ${pkgs.util-linux}/bin/runuser -u "$PINO_USER" -- /run/current-system/sw/bin/pino repo "$@"
        fi
        cd "$CONFIG_DIR"

        ensure_origin() {
          if ${pkgs.git}/bin/git remote get-url origin >/dev/null 2>&1; then
            ${pkgs.git}/bin/git remote set-url origin ${lib.escapeShellArg config.pino.repository.github}
          else
            ${pkgs.git}/bin/git remote add origin ${lib.escapeShellArg config.pino.repository.github}
          fi
        }

        case "''${1:-}" in
          status)
            ${pkgs.git}/bin/git status --short --branch
            ${pkgs.git}/bin/git remote -v
            ;;
          pull)
            [ -z "$(${pkgs.git}/bin/git status --porcelain --untracked-files=no)" ] || {
              echo "Tracked changes prevent a safe pull." >&2
              exit 1
            }
            ensure_origin
            ${pkgs.git}/bin/git pull --ff-only
            ;;
          push)
            ensure_origin
            branch="$(${pkgs.git}/bin/git branch --show-current)"
            [ -n "$branch" ] || { echo "Detached HEAD cannot be pushed." >&2; exit 1; }
            ${pkgs.git}/bin/git push origin "refs/heads/$branch:refs/heads/$branch"
            ${pkgs.git}/bin/git push origin --tags
            ;;
          inputs)
            [ "''${2:-}" = update ] || { echo "Run 'pino repo inputs help' for usage." >&2; exit 1; }
            ${pkgs.nix}/bin/nix flake update --flake "$CONFIG_DIR"
            ;;
          *) echo "Run 'pino repo help' for usage." >&2; exit 1 ;;
        esac
      '';
    };
  };
}
