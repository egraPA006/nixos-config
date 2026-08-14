{ config, lib, pkgs, ... }:
let
  osScript = builtins.replaceStrings
    [ "@configDir@" "@pinoUser@" "@runuser@" "@vaultEnabled@" ]
    [
      (lib.escapeShellArg config.pino.configDir)
      (lib.escapeShellArg config.pino.user.name)
      "${pkgs.util-linux}/bin/runuser"
      (if config.pino ? portableVaults && config.pino.portableVaults.enable then "true" else "false")
    ]
    (builtins.readFile ./os.sh);
in
{
  pino.subcommands = {
    os = {
      description = "Rebuild NixOS and manage system generations";
      commands = {
        rebuild.description = "Confirm, rebuild, and switch the flake";
        generation = {
          description = "List, activate, and clean system generations";
          commands = {
            list.description = "List system generations";
            switch = {
              description = "Select and activate a system generation";
              usage = "[generation]";
            };
            clean.description = "Keep current and previous; collect the rest";
          };
        };
        info = {
          description = "Show system info with Pino art";
          helpText = ''
            pino os info — neofetch-style system info with Pino art
              Art source: modules/pino/pino-art.sh  (paste any chafa printf here)
          '';
          script = ''
            mapfile -t _art < <(
            ${builtins.readFile ../pino/pino-art.sh}
            )
          '' + builtins.readFile ../pino/pino-info.sh;
        };
      };
      helpText = ''
        All state-changing operations are interactive. Generation switching
        activates the selected system profile generation directly and does not
        evaluate a legacy NIX_PATH configuration. Root invocations delegate to
        the configured Pino user and elevate only the system mutation itself.
      '';
      script = osScript;
    };
  };
}
