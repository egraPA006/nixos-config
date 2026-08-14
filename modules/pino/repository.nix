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

    # Keep repository transport independent of mutable files below ~/.ssh.
    # The systemd proxy include is unused and OpenSSH rejects its Nix-store
    # ownership on this installation before processing normal host aliases.
    programs.ssh = {
      systemd-ssh-proxy.enable = false;
      knownHosts = {
        github = {
          hostNames = [ "github.com" ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };
        mosk = {
          hostNames = [ "vpn.egrapa.com" ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAw0tfFljIj9B01V+DobuszzUVprcVT0SmUux5AwtKuY";
        };
      };
    };

    pino.subcommands.repo = {
      description = "Maintain GitHub, server, and offline configuration copies";
      commands = {
        status.description = "Show repository state and configured mirrors";
        pull.description = "Fast-forward the configuration checkout";
        push.description = "Push the current committed branch and tags to every mirror";
        remote = {
          description = "Inspect and configure repository remotes";
          commands = {
            list.description = "List configured repository remotes";
            configure.description = "Install or update configured mirror remotes";
          };
        };
        inputs = {
          description = "Manage flake inputs";
          commands.update.description = "Update flake.lock without rebuilding";
        };
        bundle = {
          description = "Manage self-contained offline Git bundles";
          commands.create = { description = "Create and verify an offline Git bundle"; usage = "<path>"; };
        };
      };
      helpText = ''
        GitHub remains canonical, but every configured server receives the same
        committed branch. `bundle create` creates an installation source that works
        without GitHub or any network connection. Uncommitted files are never
        copied by `push`.
      '';
      script = ''
        CONFIG_DIR=${lib.escapeShellArg configDir}
        PINO_USER=${lib.escapeShellArg config.pino.user.name}
        if [ "$(${pkgs.coreutils}/bin/id -u)" -eq 0 ]; then
          exec ${pkgs.util-linux}/bin/runuser -u "$PINO_USER" -- /run/current-system/sw/bin/pino repo "$@"
        fi
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
          pull)
            if [ -n "$(${pkgs.git}/bin/git status --porcelain --untracked-files=no)" ]; then
              echo "Tracked changes prevent a safe pull:" >&2
              ${pkgs.git}/bin/git status --short --untracked-files=no >&2
              exit 1
            fi
            ${pkgs.git}/bin/git pull --ff-only
            ;;
          remote)
            case "''${2:-}" in
              list) ${pkgs.git}/bin/git remote -v ;;
              configure)
                configure_mirrors
                ${pkgs.git}/bin/git remote -v
                ;;
              *) echo "Run 'pino repo remote help' for usage." >&2; exit 1 ;;
            esac
            ;;
          push)
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
          inputs)
            case "''${2:-}" in
              update) ${pkgs.nix}/bin/nix flake update --flake "$CONFIG_DIR" ;;
              *) echo "Run 'pino repo inputs help' for usage." >&2; exit 1 ;;
            esac
            ;;
          bundle)
            [ "''${2:-}" = create ] || { echo "Run 'pino repo bundle help' for usage." >&2; exit 1; }
            output="''${3:-}"
            [ -n "$output" ] || {
              echo "Usage: pino repo bundle create <path>" >&2
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
