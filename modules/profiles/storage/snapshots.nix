{ config, lib, ... }:

let
  cfg = config.pino.snapshots;
  namesFor = group:
    builtins.attrNames (lib.filterAttrs (_: volume: volume.group == group) cfg.volumes);
  systemNames = namesFor "system";
  dataNames = namesFor "data";
  shellArray = names: lib.concatStringsSep " " (map lib.escapeShellArg names);
  dataRollbackCommands = builtins.listToAttrs (map (name: {
    name = "rb-${name}";
    value = {
      description = "Undo changes in ${cfg.volumes.${name}.subvolume}";
      usage = "<N>";
    };
  }) dataNames);
  script = builtins.replaceStrings
    [ "@systemConfigs@" "@dataConfigs@" ]
    [ (shellArray systemNames) (shellArray dataNames) ]
    (builtins.readFile ../../pino/snap.sh);
in
{
  options.pino.snapshots.volumes = lib.mkOption {
    default = { };
    description = "Snapper volumes managed by the snapshots profile";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        subvolume = lib.mkOption {
          type = lib.types.str;
          description = "Mounted Btrfs subvolume managed by this Snapper configuration";
        };
        group = lib.mkOption {
          type = lib.types.enum [ "system" "data" ];
          default = "system";
          description = "Pino snapshot command group";
        };
        allowUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ config.pino.user.name ];
        };
      };
    });
  };

  config = {
    assertions = [{
      assertion = systemNames != [ ];
      message = "The snapshots profile requires at least one system volume";
    }];

    services.snapper.configs = lib.mapAttrs (_: volume: {
      SUBVOLUME = volume.subvolume;
      ALLOW_USERS = volume.allowUsers;
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    }) cfg.volumes;

    pino.subcommands.storage.commands.snap = {
      description = "Manage configured Btrfs snapshots";
      usage = "<label>";
      commands = {
        ls.description = "List system snapshots";
        rb = { description = "Undo system changes"; usage = "<N>"; };
        rm = { description = "Delete a system snapshot"; usage = "<N>"; };
      } // lib.optionalAttrs (dataNames != [ ]) {
        data = {
          description = "Manage data-volume snapshots";
          usage = "<label>";
          commands = {
            ls.description = "List data snapshots";
            rm = { description = "Delete a data snapshot"; usage = "<N>"; };
          } // dataRollbackCommands;
        };
      };
      helpText = ''
        System configurations: ${lib.concatStringsSep ", " systemNames}
        ${lib.optionalString (dataNames != [ ]) "Data configurations: ${lib.concatStringsSep ", " dataNames}"}

        A label creates one snapshot in every configuration in that group.
      '';
      script = script;
    };
  };
}
