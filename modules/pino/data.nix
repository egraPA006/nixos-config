{ config, lib, pkgs, ... }:

let
  datasets = config.pino.data.datasets;
  names = builtins.attrNames datasets;
  shellArray = values: lib.concatStringsSep " " (map lib.escapeShellArg values);
  mergeTool = pkgs.writeScript "pino-data-merge" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./data-merge.py}
  '';
  script = builtins.replaceStrings
    [ "@datasetNames@" "@datasetPaths@" "@datasetScopes@" "@hostName@" "@mergeTool@" ]
    [
      (shellArray names)
      (shellArray (map (name: datasets.${name}.localPath) names))
      (shellArray (map (name: datasets.${name}.scope) names))
      (lib.escapeShellArg config.networking.hostName)
      (lib.escapeShellArg mergeTool)
    ]
    (builtins.readFile ./data.sh);
in
{
  options.pino.data.datasets = lib.mkOption {
    default = { };
    description = "Plain, portable datasets mapped to host-specific local paths";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        localPath = lib.mkOption {
          type = lib.types.str;
          description = "Absolute path of this dataset on the current host";
        };
        scope = lib.mkOption {
          type = lib.types.enum [ "shared" "host" ];
          default = "host";
          description = "Whether the medium copy is shared or specific to this host";
        };
      };
    });
  };

  config = {
    assertions = lib.mapAttrsToList (name: dataset: {
      assertion = lib.hasPrefix "/" dataset.localPath
        && !builtins.elem dataset.localPath [ "/" "/nix" "/data/secrets" ];
      message = "pino.data.datasets.${name}.localPath must be a safe absolute data path";
    }) datasets;

    pino.subcommands.data = {
      description = "Manage portable, non-secret datasets";
      helpText = ''
        pino data — plain datasets on a pino-data-* medium
          pino data list
          pino data disks
          pino data backup  [disk] <dataset>  Make the medium exactly match local
          pino data restore [disk] <dataset>  Make local exactly match the medium
          pino data merge   [disk] <dataset>  Interactively merge medium into local

        A disk selector is a suffix (for example 1) or full pino-data-* label.
        It is optional when exactly one pino-data-* partition is connected.

        backup and restore delete files on the destination that do not exist at the
        source. Both show an rsync preview and require typing the dataset name.
        merge never changes the medium and never deletes local-only files.
      '';
      script = script;
      fishCompletions = ''
        set -l data_cmds list disks backup restore merge
        complete -c pino -f -n '__fish_seen_subcommand_from data; and not __fish_seen_subcommand_from $data_cmds' -a list -d 'List datasets'
        complete -c pino -f -n '__fish_seen_subcommand_from data; and not __fish_seen_subcommand_from $data_cmds' -a disks -d 'List media'
        complete -c pino -f -n '__fish_seen_subcommand_from data; and not __fish_seen_subcommand_from $data_cmds' -a backup -d 'Replace medium from local'
        complete -c pino -f -n '__fish_seen_subcommand_from data; and not __fish_seen_subcommand_from $data_cmds' -a restore -d 'Replace local from medium'
        complete -c pino -f -n '__fish_seen_subcommand_from data; and not __fish_seen_subcommand_from $data_cmds' -a merge -d 'Merge medium into local'
        complete -c pino -f -n '__fish_seen_subcommand_from backup restore merge' -a '${lib.concatStringsSep " " names}' -d 'Dataset'
      '';
    };

    environment.systemPackages = [ pkgs.rsync ];
  };
}
