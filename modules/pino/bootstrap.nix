{ config, lib, pkgs, ... }:

let
  cfg = config.pino.bootstrap;
  runBootstrap = operation: ''
    set -- ${lib.escapeShellArg operation} "$@"
    BOOTSTRAP_CONFIG_DIR=${lib.escapeShellArg config.pino.configDir}
    BOOTSTRAP_REPOSITORY=https://github.com/egraPA006/nixos-config.git
    ${builtins.readFile ./bootstrap.sh}
  '';
  prepareSecrets = pkgs.writeShellScript "pino-server-secrets" ''
    export PINO_PROXY_SETTINGS=${../../resources/mosk-proxies.json}
    export PINO_HALOS_PROXY_SETTINGS=${../../resources/halos-proxies.json}
    export PATH=${lib.makeBinPath [ pkgs.amneziawg-tools pkgs.git pkgs.bitwarden-cli ]}:"$PATH"
    exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../scripts/server-secrets.py} "$@"
  '';
in
{
  options.pino.bootstrap.enable = lib.mkEnableOption "remote Pino server installation";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ git openssh ];

    pino.subcommands.os.commands = {
      provision.commands.prepare = {
        description = "Prepare or explicitly rotate server credentials";
        usage = "<mosk|halos> [new-output-directory] [--bitwarden] [--rotate galene|vpn | --repair-galene]";
        script = ''exec ${prepareSecrets} "$@"'';
      };
      install = {
        description = "Install a server from Ubuntu/Debian over SSH";
        usage = "<mosk|halos> <user@address> <public-key-file>";
        helpText = ''
          Boots the pinned NixOS RAM installer, installs /dev/vda after
          confirmation, reboots and provisions existing Bitwarden secrets.
          The public key selects its matching private key beside it.
        '';
        script = runBootstrap "install";
      };
      rescue = {
        description = "Install a server from an already running NixOS rescue";
        usage = "<mosk|halos> <root@address> <public-key-file>";
        helpText = "Erases /dev/vda after confirmation and provisions existing Bitwarden secrets.";
        script = runBootstrap "rescue";
      };
    };
  };
}
