{ config, lib, pkgs, ... }:

let
  cfg = config.pino.bootstrap;
  prepareSecrets = pkgs.writeShellScript "pino-server-secrets" ''
    export PATH=${lib.makeBinPath [ pkgs.amneziawg-tools pkgs.git pkgs.bitwarden-cli ]}:"$PATH"
    exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../scripts/server-secrets.py} "$@"
  '';
in
{
  options.pino.bootstrap.enable = lib.mkEnableOption "remote Pino server installation";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ git openssh ];

    pino.subcommands.bootstrap = {
      description = "Install a Pino server over SSH";
      commands = {
        prepare = {
          description = "Prepare VPN and Galene secrets locally or in Bitwarden";
          usage = "<mosk|halos> [new-output-directory] [--bitwarden] [--rotate galene|vpn | --repair-galene]";
        };
        install = {
          description = "Replace an existing Linux VPS using a kexec installer";
          usage = "<mosk|halos> <user@address> <public-key-file>";
        };
        rescue = {
          description = "Install from an already running NixOS rescue system";
          usage = "<mosk|halos> <root@address> <public-key-file>";
        };
      };
      helpText = ''
        The public key file selects a matching private key beside it, installed
        earlier by `pino provision install`. The private key is never copied to
        the installer or committed to Git.

        `install` starts from Ubuntu or another x86_64 Linux VPS, boots the pinned
        NixOS installer through kexec, installs /dev/vda, reboots, and provisions
        the enabled server services from Bitwarden Secure Notes.

        `rescue` performs the same installation after the provider has already
        booted a NixOS installer. Both flows erase /dev/vda after confirmation.
      '';
      script = ''
        if [ "''${1:-}" = prepare ]; then
          shift
          exec ${prepareSecrets} "$@"
        fi
        BOOTSTRAP_CONFIG_DIR=${lib.escapeShellArg config.pino.configDir}
        BOOTSTRAP_REPOSITORY=https://github.com/egraPA006/nixos-config.git
        ${builtins.readFile ./bootstrap.sh}
      '';
    };
  };
}
