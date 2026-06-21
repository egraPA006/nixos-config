{ config, lib, pkgs, ... }:
let
  cfg   = config.pino;
  names = builtins.attrNames cfg.subcommands;

  # Generate: echo 'line1'; echo 'line2'; ... for each line of helpText
  mkHelpPrint = helpText:
    lib.concatMapStringsSep "\n" (line: "echo ${lib.escapeShellArg line}")
      (lib.splitString "\n" helpText);

  mkCaseEntry = name:
    let sub = cfg.subcommands.${name};
    in ''
      ${name})
        if [ "''${1:-}" = "help" ]; then
          ${mkHelpPrint sub.helpText}
        else
          ${sub.script}
        fi
        ;;
    '';

  caseEntries = lib.concatStringsSep "\n" (map mkCaseEntry names);

  helpLines = lib.concatStringsSep "\n" (map (name:
    let desc = lib.escapeShellArg cfg.subcommands.${name}.description;
    in "printf '  %-10s  %s\\n' '${name}' ${desc}"
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
          subcmd="''${1:-}"
          if [ -n "$subcmd" ]; then
            exec "$0" "$subcmd" help
          fi
          echo "pino — system CLI for $(hostname)"
          echo ""
          echo "COMMANDS"
          ${helpLines}
          echo ""
          echo "Run 'pino <command> help' or 'pino help <command>' for details."
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
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        description = lib.mkOption {
          type        = lib.types.str;
          description = "One-liner shown in 'pino help'";
        };
        helpText = lib.mkOption {
          type        = lib.types.lines;
          description = "Detailed text shown by 'pino <command> help' — auto-handled, no case needed in script";
        };
        script = lib.mkOption {
          type        = lib.types.lines;
          description = "Bash fragment. \$1..\$n are subcommand args. The 'help' arg is pre-intercepted.";
        };
      };
    });
    default     = {};
    description = "Subcommands contributed to pino by any NixOS module";
  };

  config.environment.systemPackages = [ pino ];
}
