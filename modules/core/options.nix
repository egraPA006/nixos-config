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
    bootstrap = {
      vaultRoot = lib.mkOption {
        type = lib.types.str;
        default = "/data/secrets/system/hosts";
        description = "Local vault directory containing per-host bootstrap payloads";
      };
      secrets = lib.mkOption {
        default = { };
        description = "Files accepted by the constrained remote bootstrap receiver";
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options = {
            source = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Path relative to the host's vault bootstrap directory";
            };
            target = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/pino/secrets/${name}";
              description = "Root-owned destination on the target host";
            };
            owner = lib.mkOption {
              type = lib.types.str;
              default = "root";
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
            };
            mode = lib.mkOption {
              type = lib.types.str;
              default = "0600";
            };
            restartUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
        }));
      };
    };
  };
}
