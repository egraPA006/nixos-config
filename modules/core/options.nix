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
    secrets = {
      knownHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "re-1" "la1n" "mosk" "phone" ];
        description = "Independent host-secret scopes known to trusted clients and ciphertext mirrors";
      };
      sourceRoot = lib.mkOption {
        type = lib.types.str;
        default = "/run/pino-secrets/hosts";
        description = "Unlocked directory containing one runtime-secret projection per host";
      };
      provisionedDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/pino/secrets";
        description = "Root-only cache populated before declared secrets are deployed";
      };
      entries = lib.mkOption {
        default = { };
        description = "Runtime secrets accepted by bootstrap and deployed by Pino";
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options = {
            source = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Path relative to the host's vault bootstrap directory";
            };
            target = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Final destination; null keeps the file only in the root cache";
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
            directoryMode = lib.mkOption {
              type = lib.types.str;
              default = "0700";
            };
            recursive = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Deploy the complete source directory to the target directory";
            };
            restartUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            startUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Units to start after provisioning, including units previously skipped for a missing secret";
            };
          };
        }));
      };
    };
  };
}
