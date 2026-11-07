{ config, lib, pkgs, ... }:
let
  manifest = pkgs.writeText "pino-artifacts.json" (builtins.toJSON config.pino.artifacts);
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
  config.pino.subcommands.artifacts = {
    description = "Import saved installers from an unlocked external disk";
    commands = {
      list.description = "Show external folder names and local destinations";
      import = {
        description = "Copy installer folders; refuse conflicts and symlinks";
        usage = "<external-artifacts-directory> [--dry-run]";
      };
    };
    helpText = ''
      The external directory contains one folder per active declaration.
      Run list to see the mapping. Import checks every folder before copying;
      identical files are skipped and different existing files are never replaced.
      Run as the normal desktop user. Install applications separately afterwards.
    '';
    script = ''exec ${pkgs.python3}/bin/python3 ${../../scripts/artifacts.py} ${manifest} "$@"'';
  };
}
