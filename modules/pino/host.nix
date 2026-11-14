{ config, lib, pkgs, pinoProvisionSend, ... }:
{
  pino.subcommands.host = {
    description = "Run Pino on a configured host using its SSH alias";
    runWithoutArgs = true;
    usage = "[host] [pino-command ...]";
    commands = {
      install = {
        description = "Install and provision a server via SSH and kexec";
        usage = "<mosk|halos> <user@address> <public-key-file>";
        script = ''
          BOOTSTRAP_CONFIG_DIR=${lib.escapeShellArg config.pino.configDir}
          BOOTSTRAP_REPOSITORY=https://github.com/egraPA006/nixos-config.git
          export PINO_PROVISION_SEND=${pinoProvisionSend}
          export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.nix pkgs.bitwarden-cli pkgs.jq ]}:"$PATH"
          set -- install "$@"
          ${builtins.readFile ./bootstrap.sh}
        '';
      };
      rescue = {
        description = "Install and provision from a running NixOS rescue";
        usage = "<mosk|halos> <root@address> <public-key-file>";
        script = ''
          BOOTSTRAP_CONFIG_DIR=${lib.escapeShellArg config.pino.configDir}
          BOOTSTRAP_REPOSITORY=https://github.com/egraPA006/nixos-config.git
          export PINO_PROVISION_SEND=${pinoProvisionSend}
          export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.nix pkgs.bitwarden-cli pkgs.jq ]}:"$PATH"
          set -- rescue "$@"
          ${builtins.readFile ./bootstrap.sh}
        '';
      };
      provision = {
        description = "Provision a configured server from Bitwarden over SSH";
        usage = "<mosk|halos> [user@address]";
        script = ''
          export PINO_PROVISION_SEND=${pinoProvisionSend}
          export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.nix pkgs.bitwarden-cli pkgs.jq ]}:"$PATH"
          exec ${pinoProvisionSend} host "$@"
        '';
      };
    };
    helpText = ''
      Examples: pino host mosk server status
                pino host mosk server vpn mode set private
                pino host mosk server xray status
                pino host mosk os rebuild
      Uses your configured SSH identity and normal host-key verification.
      Hosts are discovered from nixosConfigurations in this checkout. Configure
      an SSH alias for any host you want to reach.
      Secrets belong in Bitwarden, not command arguments.
      install/rescue require an SSH public-key file and ask before erasing /dev/vda.
    '';
    script = ''
      hosts="$(${pkgs.nix}/bin/nix eval --json --apply builtins.attrNames ${lib.escapeShellArg "path:${config.pino.configDir}#nixosConfigurations"})" || {
        echo 'Cannot read hosts from the configured NixOS checkout.' >&2; exit 1
      }
      host="''${1:-}"
      if [ -z "$host" ]; then
        echo 'Configured hosts:'
        printf '%s\n' "$hosts" | ${pkgs.jq}/bin/jq -r '.[]'
        echo 'Run pino host <host> <command>; an SSH alias is required.'
        exit 0
      fi
      [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo 'Invalid host name.' >&2; exit 1; }
      if ! printf '%s\n' "$hosts" | ${pkgs.jq}/bin/jq -e --arg host "$host" 'index($host) != null' >/dev/null; then
        echo "Unknown configured host: $host" >&2; exit 1
      fi
      shift
      [ "$#" -gt 0 ] || { echo "Specify a Pino command" >&2; exit 1; }
      remote=/run/current-system/sw/bin/pino
      for arg in "$@"; do
        [[ "$arg" =~ ^[A-Za-z0-9_./:@=-]+$ ]] || { echo "Unsupported remote argument" >&2; exit 1; }
        remote+=" $arg"
      done
      tty=()
      if [ -t 0 ] && [ -t 1 ]; then tty=(-t); fi
      exec ${pkgs.openssh}/bin/ssh "''${tty[@]}" "$host" "$remote"
    '';
  };
}
