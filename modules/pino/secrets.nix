{ config, lib, pkgs, ... }:

let
  cfg = config.pino.secrets;
  entries = cfg.entries;
  deployEntry = name: secret:
    let
      source = "${cfg.provisionedDir}/${secret.source}";
      targetDirectory = if secret.recursive then secret.target else
        lib.optionalString (secret.target != null) (builtins.dirOf secret.target);
    in lib.optionalString (secret.target != null) (if secret.recursive then ''
      if [ -d ${lib.escapeShellArg source} ]; then
        ${pkgs.coreutils}/bin/install -d -o ${lib.escapeShellArg secret.owner} \
          -g ${lib.escapeShellArg secret.group} -m ${lib.escapeShellArg secret.directoryMode} \
          ${lib.escapeShellArg secret.target}
        ${pkgs.rsync}/bin/rsync -a --delete \
          --chown=${lib.escapeShellArg "${secret.owner}:${secret.group}"} \
          --chmod=${lib.escapeShellArg "D${secret.directoryMode},F${secret.mode}"} \
          ${lib.escapeShellArg "${source}/"} ${lib.escapeShellArg "${secret.target}/"}
      fi
    '' else ''
      if [ -f ${lib.escapeShellArg source} ]; then
        ${pkgs.coreutils}/bin/install -d -o ${lib.escapeShellArg secret.owner} \
          -g ${lib.escapeShellArg secret.group} -m ${lib.escapeShellArg secret.directoryMode} \
          ${lib.escapeShellArg targetDirectory}
        ${pkgs.coreutils}/bin/install -o ${lib.escapeShellArg secret.owner} \
          -g ${lib.escapeShellArg secret.group} -m ${lib.escapeShellArg secret.mode} \
          ${lib.escapeShellArg source} ${lib.escapeShellArg secret.target}
      fi
    '');
  deployScript = pkgs.writeShellApplication {
    name = "pino-secrets-deploy";
    runtimeInputs = [ pkgs.coreutils pkgs.rsync pkgs.systemd ];
    text = ''
      set -euo pipefail
      restart=false
      [ "''${1:-}" != --restart ] || restart=true
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList deployEntry entries)}
      if [ "$restart" = true ]; then
        ${lib.concatMapStringsSep "\n" (unit:
          "${pkgs.systemd}/bin/systemctl reload-or-restart ${lib.escapeShellArg unit}")
          (lib.unique (lib.concatMap (entry: entry.restartUnits) (lib.attrValues entries)))}
      fi
    '';
  };
in
{
  assertions = lib.concatMap (name:
    let secret = entries.${name}; in [
      {
        assertion = secret.source != "" && !(lib.hasPrefix "/" secret.source)
          && !(lib.hasInfix ".." secret.source) && !(lib.hasInfix "\n" secret.source);
        message = "pino.secrets.entries.${name}.source must be a safe relative path";
      }
      {
        assertion = !secret.recursive || secret.target != null;
        message = "pino.secrets.entries.${name}.target is required for recursive deployment";
      }
    ]) (builtins.attrNames entries);

  environment.systemPackages = [ deployScript ];
  systemd.tmpfiles.rules = [
    "d ${cfg.provisionedDir} 0700 root root -"
  ];
  system.activationScripts.pino-secrets = {
    deps = [ "users" "groups" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${lib.escapeShellArg cfg.provisionedDir}
      ${deployScript}/bin/pino-secrets-deploy
    '';
  };
}
