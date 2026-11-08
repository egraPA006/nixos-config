{ pkgs, ... }: {
  pino.subcommands.backup.commands.bitwarden = {
    description = "Back up personal Bitwarden items as portable encrypted JSON";
    usage = "<external-disk-directory>";
    helpText = ''
      Prompts for login/unlock and a separate export password. Shows excluded
      content and asks before replacing pino/bitwarden/vault.encrypted.json.
      Attachments, organization items, trash, Sends and account recovery settings
      are not included. Import the file as Bitwarden JSON using its export password.
    '';
    script = ''
      export PATH=${pkgs.bitwarden-cli}/bin:"$PATH"
      exec ${pkgs.python3}/bin/python3 ${../../scripts/backup-bitwarden.py} "$@"
    '';
  };
}
