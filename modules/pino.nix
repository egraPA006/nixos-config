{ config, lib, pkgs, ... }:

let
  cfg = config.pino;

  commandType = lib.types.submodule ({ ... }: {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "One-line command description";
      };
      usage = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Arguments shown after the command path in generated help";
      };
      helpText = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional help shown after generated usage and child commands";
      };
      script = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "Bash handler receiving arguments remaining after this command path";
      };
      commands = lib.mkOption {
        type = lib.types.attrsOf commandType;
        default = { };
        description = "Nested subcommands; metadata-only leaves delegate to the nearest handler";
      };
      fishCompletions = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional Fish completions for dynamic arguments";
      };
    };
  });

  root = {
    description = "System CLI";
    usage = "";
    helpText = "";
    script = null;
    commands = cfg.subcommands;
    fishCompletions = "";
  };

  functionName = path:
    if path == [ ] then "pino_dispatch_root"
    else "pino_dispatch_${lib.concatStringsSep "__" (map (builtins.replaceStrings [ "-" ] [ "_" ]) path)}";

  commandPath = path:
    if path == [ ] then "pino" else "pino ${lib.concatStringsSep " " path}";

  printLines = value:
    lib.concatMapStringsSep "\n" (line: "printf '%s\\n' ${lib.escapeShellArg line}")
      (lib.splitString "\n" value);

  helpBody = path: node:
    let
      names = builtins.attrNames node.commands;
      usageSuffix = lib.optionalString (node.usage != "") " ${node.usage}";
      commandLines = lib.concatMapStringsSep "\n" (name:
        "printf '  %-16s %s\\n' ${lib.escapeShellArg name} ${lib.escapeShellArg node.commands.${name}.description}"
      ) names;
    in ''
      printf 'Usage: %s%s\n' ${lib.escapeShellArg (commandPath path)} ${lib.escapeShellArg usageSuffix}
      printf '%s\n' ${lib.escapeShellArg node.description}
      ${lib.optionalString (names != [ ]) ''
        printf '\nCOMMANDS\n'
        ${commandLines}
      ''}
      ${lib.optionalString (node.helpText != "") ''
        printf '\n'
        ${printLines node.helpText}
      ''}
      ${lib.optionalString (names != [ ]) ''
        printf '\nRun %s for command help.\n' ${lib.escapeShellArg "${commandPath path} <command> help"}
      ''}
    '';

  generateDispatcher = path: node: delegatedScript:
    let
      names = builtins.attrNames node.commands;
      function = functionName path;
      ownScript = node.script;
      effectiveScript = if ownScript != null then ownScript else delegatedScript;
      childCases = lib.concatMapStringsSep "\n" (name: ''
        ${lib.escapeShellArg name})
          shift
          ${functionName (path ++ [ name ])} "$@"
          return
          ;;
      '') names;
      delegatedInvocation = lib.optionalString (effectiveScript != null) (
        if ownScript != null then ownScript
        else ''
          set -- ${lib.escapeShellArg (lib.last path)} "$@"
          ${effectiveScript}
        ''
      );
      children = lib.concatMapStringsSep "\n" (name:
        generateDispatcher (path ++ [ name ]) node.commands.${name} effectiveScript
      ) names;
    in ''
      ${function}() {
        local command="''${1:-}"
        case "$command" in
          help)
            shift || true
            if [ -n "''${1:-}" ]; then
              echo "${commandPath path}: 'help' must be the final argument" >&2
              return 1
            fi
            ${helpBody path node}
            ;;
          ${childCases}
          "")
            ${if names != [ ] then helpBody path node else delegatedInvocation}
            ;;
          *)
            ${if effectiveScript != null then delegatedInvocation else ''
              echo "${commandPath path}: unknown command '$command'" >&2
              echo "Run '${commandPath path} help' for usage." >&2
              return 1
            ''}
            ;;
        esac
      }

      ${children}
    '';

  dispatcher = generateDispatcher [ ] root null;

  completionForNode = path: node:
    let
      names = builtins.attrNames node.commands;
      pathArgs = lib.concatStringsSep " " (map lib.escapeShellArg path);
      completionsAt = condition:
        lib.concatMapStringsSep "\n" (name:
          "complete -c pino -f -n '${condition}' -a '${name}' -d '${builtins.replaceStrings [ "'" ] [ "'\\''" ] node.commands.${name}.description}'"
        ) names;
      own = lib.concatMapStringsSep "\n" (name:
        completionsAt name
      ) [ "__fish_pino_at_path ${pathArgs}" ];
      help = "complete -c pino -f -n '__fish_pino_at_path ${pathArgs}' -a help -d 'Show help'";
      nested = lib.concatMapStringsSep "\n" (name:
        completionForNode (path ++ [ name ]) node.commands.${name}
      ) names;
    in lib.concatStringsSep "\n" [ own help node.fishCompletions nested ];

  pinoFish = pkgs.writeTextFile {
    name = "pino-fish-completions";
    destination = "/share/fish/vendor_completions.d/pino.fish";
    text = ''
      # Generated from the recursive pino command registry.
      function __fish_pino_at_path
        set -l tokens (commandline -opc)
        set -e tokens[1]
        test (count $tokens) -eq (count $argv); or return 1
        for index in (seq 1 (count $argv))
          test "$tokens[$index]" = "$argv[$index]"; or return 1
        end
      end

      complete -c pino -f
      ${completionForNode [ ] root}
    '';
  };

  pino = pkgs.writeShellApplication {
    name = "pino";
    runtimeInputs = with pkgs; [ coreutils gnugrep jq ];
    text = ''
      ${dispatcher}
      pino_dispatch_root "$@"
    '';
  };
in
{
  options.pino.subcommands = lib.mkOption {
    type = lib.types.attrsOf commandType;
    default = { };
    description = "Recursive Pino command tree contributed by NixOS modules";
  };

  config.environment.systemPackages = [ pino pinoFish ];
}
