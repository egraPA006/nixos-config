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

    info = {
      description = "Show system info with Pino art";
      helpText = ''
        pino info — neofetch-style system info with Pino art
          Art source: modules/pino/pino-art.sh  (paste any chafa printf here)
      '';
      script = ''
        mapfile -t _art < <(
        ${builtins.readFile ../pino/pino-art.sh}
        )
      '' + builtins.readFile ../pino/pino-info.sh;
    };

    snap = {
      description = "Manage btrfs snapshots";
      usage = "<label>";
      commands = {
        ls.description = "List root and home snapshots";
        rb = { description = "Undo root and home changes"; usage = "<N>"; };
        rm = { description = "Delete a root and home snapshot"; usage = "<N>"; };
        data = {
          description = "Manage /data snapshots";
          usage = "<label>";
          commands = {
            ls.description = "List fast and slow data snapshots";
            rb-fast = { description = "Undo /data/fast changes"; usage = "<N>"; };
            rb-slow = { description = "Undo /data/slow changes"; usage = "<N>"; };
            rm = { description = "Delete fast and slow snapshots"; usage = "<N>"; };
          };
        };
      };
      helpText = ''
        pino snap — btrfs snapshot management (root + home)
          pino snap <label>          Create snapshot of root + home
          pino snap ls               List snapshots
          pino snap rb <N>           Roll back root + home to snapshot N
          pino snap rm <N>           Delete snapshot N
          pino snap data <...>       Data disk snapshots  (pino snap data help)
      '';
      script = builtins.readFile ../pino/snap.sh;
      fishCompletions = ''
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and not __fish_seen_subcommand_from data' -a ls -d 'List snapshots'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and not __fish_seen_subcommand_from data' -a rb -d 'Roll back to snapshot N'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and not __fish_seen_subcommand_from data' -a rm -d 'Delete snapshot N'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and not __fish_seen_subcommand_from data' -a data -d '/data snapshots'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and __fish_seen_subcommand_from data' -a ls -d 'List data snapshots'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and __fish_seen_subcommand_from data' -a rb-fast -d 'Roll back /data/fast to N'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and __fish_seen_subcommand_from data' -a rb-slow -d 'Roll back /data/slow to N'
        complete -c pino -f -n '__fish_seen_subcommand_from snap; and __fish_seen_subcommand_from data' -a rm -d 'Delete data snapshot N'
      '';
    };
  };
}
