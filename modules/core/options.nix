{ config, lib, ... }:

let
  cfg = config.pino;
in
{
  options.pino = {
    user = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "pino";
        description = "Primary user managed by Pino";
      };
      home = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user.name}";
        description = "Home directory of the primary Pino user";
      };
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.user.home}/nixos-config";
      description = "Working checkout used by Pino OS commands";
    };
  };
}
