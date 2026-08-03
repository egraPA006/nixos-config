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

    pino.subcommands.storage.commands.data = {
      description = "Manage portable, non-secret datasets";
      commands = {
        list.description = "List configured datasets";
        disks.description = "List connected data media";
        backup = { description = "Make medium exactly match local"; usage = "[disk] <dataset|all>"; };
        restore = { description = "Make local exactly match medium"; usage = "[disk] <dataset>"; };
        merge = { description = "Interactively merge medium into local"; usage = "[disk] <dataset>"; };
      };
      helpText = ''
        pino storage data — plain datasets on a pino-data-* medium
          pino storage data list
          pino storage data disks
          pino storage data backup  [disk] <dataset|all>
                                                Make medium copies exactly match local
          pino storage data restore [disk] <dataset>  Make local exactly match the medium
          pino storage data merge   [disk] <dataset>  Interactively merge medium into local

        A disk selector is a suffix (for example 1) or full pino-data-* label.
        It is optional when exactly one pino-data-* partition is connected.

        backup and restore delete files on the destination that do not exist at the
        source. Both show an rsync preview and require typing the dataset name.
        The backup target 'all' processes every configured dataset with the same
        preview and confirmation rules, mounting the medium only once.
        merge never changes the medium and never deletes local-only files.
      '';
      script = script;
      fishCompletions = ''
        complete -c pino -f \
          -n '__fish_pino_at_path storage data backup; or __fish_pino_at_path storage data restore; or __fish_pino_at_path storage data merge' \
          -a '${lib.concatStringsSep " " names}' -d 'Dataset'
        complete -c pino -f -n '__fish_pino_at_path storage data backup' \
          -a all -d 'Every configured dataset'
      '';
    };

    environment.systemPackages = [
      pkgs.exfatprogs
      pkgs.rsync
    ];
  };
}
