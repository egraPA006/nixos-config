{ config, lib, pkgs, ... }:

let
  cfg = config.pino.secretVault;
  user = config.pino.user;
in
{
  options.pino.secretVault = {
    enable = lib.mkEnableOption "the local LUKS recovery folder";
    container = lib.mkOption {
      type = lib.types.str;
      default = "${user.home}/.local/share/pino/secrets.luks";
      description = "LUKS2 container file stored on the main filesystem";
    };
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "${user.home}/secrets";
      description = "Directory where the secrets container is mounted";
    };
    size = lib.mkOption {
      type = lib.types.strMatching "[1-9][0-9]*[MG]";
      default = "1G";
      description = "Size allocated on the first pino secret unlock";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = builtins.match "[a-z_][a-z0-9_-]*" user.name != null;
      message = "pino.secretVault requires a safe primary user name";
    }];

    environment.systemPackages = with pkgs; [
      cryptsetup
      e2fsprogs
      util-linux
    ];

    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.container} 0700 ${user.name} users -"
      "d ${cfg.mountPoint} 0700 ${user.name} users -"
    ];

    pino.subcommands.secret = {
      description = "Lock or unlock the local LUKS recovery folder";
      commands = {
        unlock.description = "Create if needed, then unlock and mount ~/secrets";
        lock.description = "Unmount and lock ~/secrets";
      };
      helpText = ''
        The encrypted container is ${cfg.container} and mounts at ${cfg.mountPoint}.
        It is a normal file on the main filesystem, not a separate partition.
        It stores recovery material only. The first `unlock` initializes it.
        Runtime configuration is provisioned from Bitwarden instead.
      '';
      script = ''
        SECRET_CONTAINER=${lib.escapeShellArg cfg.container}
        SECRET_MOUNT_POINT=${lib.escapeShellArg cfg.mountPoint}
        SECRET_MAPPING=${lib.escapeShellArg "pino-secrets-${user.name}"}
        SECRET_USER=${lib.escapeShellArg user.name}
        SECRET_SIZE=${lib.escapeShellArg cfg.size}
        ${builtins.readFile ./secrets.sh}
      '';
    };
  };
}
