{ ... }:
{
  pino.subcommands.data = {
    description = "Back up and restore data on an unlocked external disk";
    commands.backup.description = "Preview and update backups";
    commands.restore.description = "Preview and restore installers or personal data";
  };
}
