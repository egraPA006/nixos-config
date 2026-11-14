{ config, lib, pkgs, ... }:
let
  cfg = config.pino.populate;
  steps = lib.mapAttrs (name: step: {
    inherit (step) command requiresSession requiredMount;
    prerequisite = if step.prerequisite == "" then null else
      toString (pkgs.writeShellScript "populate-${name}-check" step.prerequisite);
  }) cfg.steps;
  manifest = pkgs.writeText "pino-populate.json" (builtins.toJSON {
    inherit steps;
    user = config.pino.user.name;
    artifacts = lib.attrByPath [ "pino" "artifacts" ] {} config != {};
  });
in {
  options.pino.populate.steps = lib.mkOption {
    default = {};
    description = "Repeatable application setup contributed by active profiles.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        command = lib.mkOption { type = lib.types.listOf lib.types.str; };
        prerequisite = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Read-only check: exit 0 when ready, 2 with an actionable message when pending; other exits mean error.";
        };
        requiresSession = lib.mkOption { type = lib.types.bool; default = false; };
        requiredMount = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      };
    });
  };
  config.pino.subcommands.os.commands.populate = {
    description = "Restore installers and set up ready applications";
    usage = "[external-disk-root]";
    helpText = ''
      Run as ${config.pino.user.name} after booting the installed system.
      With a disk, compare and import pino/artifacts before application setup.
      Without a disk, use the installers already present locally.
      Missing prerequisites do not stop unrelated work. Follow the reported
      instructions and run populate again; existing setup commands check their state.
      Personal datasets and Bitwarden secrets are handled separately.
      Exit status: 0 complete, 2 action required, 1 failed step.
    '';
    script = ''exec ${pkgs.python3}/bin/python3 ${../../scripts/populate.py} ${manifest} "$@"'';
  };
}
