{ config, lib, pkgs, ... }:
let
  manifest = pkgs.writeText "pino-datasets.json" (builtins.toJSON {
    kind = "datasets"; entries = config.pino.datasets;
  });
  sync = "${pkgs.python3}/bin/python3 ${../../scripts/data_sync.py} ${manifest}";
in {
  options.pino.datasets = lib.mkOption {
    default = {};
    description = "Named personal directories backed up to external disk/pino/datasets/name. Symlinks are rejected unless excluded.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        target = lib.mkOption {
          type = lib.types.str;
          description = "Absolute local directory to back up or restore.";
        };
        requiredMount = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Filesystem required before reading or writing the local directory.";
        };
        exclude = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Glob patterns against relative paths; matching directories prune their whole subtree on both sides. Excluded paths are never deleted.";
        };
      };
    });
  };
  config.pino.subcommands = {
    backup.commands.datasets = {
      description = "Compare and back up configured personal directories";
      usage = "[name] <external-disk> [--mode update|mirror] [--dry-run]";
      helpText = ''
        Update keeps destination-only files. Mirror explicitly lists their removal.
        Both modes ask about differing files and require final confirmation.
        Missing sources, missing required mounts and symlinks abort before copying.
        Configure pino.datasets.<name>.target and optional exclude/requiredMount.
      '';
      script = ''exec ${sync} backup "$@"'';
    };
    restore.commands.datasets = {
      description = "Compare and restore configured personal directories";
      usage = "[name] <external-disk> [--dry-run]";
      script = ''exec ${sync} restore "$@"'';
    };
  };
}
