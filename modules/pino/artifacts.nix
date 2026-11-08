{ config, lib, pkgs, ... }:
let
  syncManifest = pkgs.writeText "pino-artifact-sync.json" (builtins.toJSON {
    kind = "artifacts"; entries = config.pino.artifacts;
  });
  sync = "${pkgs.python3}/bin/python3 ${../../scripts/data_sync.py} ${syncManifest}";
in {
  options.pino.artifacts = lib.mkOption {
    default = {};
    description = "Installer folders imported from an external disk; contributed by active profiles.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        target = lib.mkOption { type = lib.types.str; };
        requiredMount = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Filesystem that must be mounted before importing.";
        };
      };
    });
  };
  config.pino.subcommands.backup.commands.artifacts = lib.mkIf (config.pino.artifacts != {}) {
    description = "Compare and back up installer folders to disk/pino/artifacts";
    usage = "[name] <external-disk> [--mode update|mirror] [--dry-run]";
    script = ''exec ${sync} backup "$@"'';
  };
  config.pino.subcommands.restore.commands.artifacts = lib.mkIf (config.pino.artifacts != {}) {
    description = "Compare and restore available installer folders";
    usage = "[name] <external-disk> [--dry-run]";
    helpText = ''
      Reads pino/artifacts below the disk root. Missing folders are reported;
      available folders are processed. Conflicts require a choice and the final
      plan requires confirmation. Local extras are never deleted.
      Use pino os populate to also provision secrets and set up applications.
    '';
    script = ''exec ${sync} restore --allow-missing "$@"'';
  };
}
