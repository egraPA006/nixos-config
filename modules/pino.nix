{ config, lib, pkgs, ... }:
let
  cfg   = config.pino;
  names = builtins.attrNames cfg.subcommands;

  mkCaseEntry = name:
    name + ")\n" + cfg.subcommands.${name}.script + "\n;;";

  caseEntries = lib.concatStringsSep "\n\n" (map mkCaseEntry names);

  helpLines = lib.concatStringsSep "\n" (map (name:
    "printf '  %-10s  %s\\n' '${name}' '${cfg.subcommands.${name}.description}'"
  ) names);

  pino = pkgs.writeShellApplication {
    name = "pino";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      cmd="''${1:-}"
      shift || true

      case "$cmd" in

      ${caseEntries}

        help|--help|-h|"")
          echo "pino — system CLI for $(hostname)"
          echo ""
          echo "COMMANDS"
          ${helpLines}
          echo ""
          echo "Run 'pino <command> help' for details."
          ;;

        *)
          echo "pino: unknown command '$cmd'"
          echo "Run 'pino help' for usage."
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.pino.subcommands = lib.mkOption {
    type    = lib.types.attrsOf (lib.types.submodule {
      options = {
        description = lib.mkOption {
          type        = lib.types.str;
          description = "One-line description shown in pino help";
        };
        script = lib.mkOption {
          type        = lib.types.lines;
          description = "Bash fragment. After dispatch, \\$1..\\$n are the subcommand args.";
        };
      };
    });
    default     = {};
    description = "Subcommands contributed to pino by any NixOS module";
  };

  config.environment.systemPackages = [ pino ];
}
