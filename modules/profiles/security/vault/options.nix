{ lib, ... }:
{
  options.pino.vault = {
    provisionedDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pino/secrets";
    };
    secrets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          source = lib.mkOption { type = lib.types.str; default = name; };
          target = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          owner = lib.mkOption { type = lib.types.str; default = "root"; };
          group = lib.mkOption { type = lib.types.str; default = "root"; };
          mode = lib.mkOption { type = lib.types.str; default = "0600"; };
          directoryMode = lib.mkOption { type = lib.types.str; default = "0700"; };
          restartUnits = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      }));
    };
  };
}
