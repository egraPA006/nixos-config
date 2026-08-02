{ ... }:
{
  pino.subcommands = {
    os = {
      description = "Rebuild, update, roll back, and clean NixOS";
      commands = {
        list.description = "List system generations";
        rebuild.description = "Confirm, rebuild, and switch the flake";
        update.description = "Confirm, update inputs, and rebuild";
        rollback = {
          description = "Select and activate a system generation";
          usage = "[generation]";
        };
        gc.description = "Keep current and previous; collect the rest";
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
        pino os — manage the NixOS system
          pino os list             List system generations
          pino os rebuild          Confirm, rebuild, and switch the flake
          pino os update           Confirm, update inputs, and rebuild
          pino os rollback [N]     Select and activate a system generation
          pino os gc               Keep current + previous; collect the rest

        All state-changing operations are interactive. Rollback switches the
        selected system profile generation directly and does not evaluate a
        legacy NIX_PATH configuration.
      '';
      script = builtins.readFile ./os.sh;
      fishCompletions = ''
        set -l os_cmds list rebuild update rollback gc
        complete -c pino -f -n '__fish_seen_subcommand_from os; and not __fish_seen_subcommand_from $os_cmds' -a list -d 'List generations'
        complete -c pino -f -n '__fish_seen_subcommand_from os; and not __fish_seen_subcommand_from $os_cmds' -a rebuild -d 'Rebuild and switch'
        complete -c pino -f -n '__fish_seen_subcommand_from os; and not __fish_seen_subcommand_from $os_cmds' -a update -d 'Update inputs and rebuild'
        complete -c pino -f -n '__fish_seen_subcommand_from os; and not __fish_seen_subcommand_from $os_cmds' -a rollback -d 'Activate a generation'
        complete -c pino -f -n '__fish_seen_subcommand_from os; and not __fish_seen_subcommand_from $os_cmds' -a gc -d 'Keep current and previous'
      '';
    };
  };
}
