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
    [ "@datasetNames@" "@datasetPaths@" "@mergeTool@" ]
    [
      (shellArray names)
      (shellArray (map (name: datasets.${name}) names))
      (lib.escapeShellArg mergeTool)
    ]
    (builtins.readFile ./data.sh);
in
{
  options.pino.data.datasets = lib.mkOption {
    default = { };
    description = "Plain, portable datasets mapped to local paths";
    type = lib.types.attrsOf lib.types.str;
  };

  config = {
    assertions = lib.mapAttrsToList (name: localPath: {
      assertion = lib.hasPrefix "/" localPath
        && !builtins.elem localPath [ "/" "/nix" ];
      message = "pino.data.datasets.${name} must be a safe absolute data path";
    }) datasets;

    pino.subcommands.storage.commands.dataset = {
      description = "Manage portable, non-secret datasets";
      commands = {
        list.description = "List configured datasets";
        disks.description = "List connected data media";
        backup = { description = "Make medium exactly match local"; usage = "[disk] <dataset|all>"; };
        restore = { description = "Make local exactly match medium"; usage = "[disk] <dataset>"; };
        merge = { description = "Interactively merge medium into local"; usage = "[disk] <dataset>"; };
      };
      helpText = ''
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
          -n '__fish_pino_at_path storage dataset backup; or __fish_pino_at_path storage dataset restore; or __fish_pino_at_path storage dataset merge' \
          -a '${lib.concatStringsSep " " names}' -d 'Dataset'
        complete -c pino -f -n '__fish_pino_at_path storage dataset backup' \
          -a all -d 'Every configured dataset'
      '';
    };

    environment.systemPackages = [
      pkgs.exfatprogs
      pkgs.rsync
    ];
  };
}
