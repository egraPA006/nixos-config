{ config, lib, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ rsync util-linux ];

  pino.subcommands.backup = {
    description = "Push and pull named folders on an offline backup disk";
    commands = {
      push = { description = "Create an immutable snapshot"; usage = "<disk> <folder> <name>"; };
      pull = { description = "Restore the latest snapshot"; usage = "<disk> <folder> <name> [snapshot]"; };
      status = { description = "Show snapshots and conflicts"; usage = "<disk> [name]"; };
    };
    helpText = ''
      <disk> is a mounted backup root or mounted block device initialized with
      scripts/backup-disk-init.sh. Names are unique on a disk. Push refuses if
      the disk changed since this machine last synchronized that name.

      `pino backup <disk> <folder> <name>` is a shorthand for push.
    '';
    script = ''
      BACKUP_SECRET_MOUNT_POINT=${lib.escapeShellArg config.pino.secretVault.mountPoint}
      ${builtins.readFile ./backup.sh}
    '';
  };
}
