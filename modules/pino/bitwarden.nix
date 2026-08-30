{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.bitwarden-cli ];

  pino.subcommands.provision = {
    description = "Provision runtime configuration from Bitwarden Secure Notes";
    commands = {
      install = {
        description = "Install a Secure Note as a root-owned local file";
        usage = "<item> <absolute-target> [systemd-unit ...]";
      };
      send = {
        description = "Install a Secure Note on an SSH host";
        usage = "<item> <host> <absolute-target> [systemd-unit ...]";
      };
    };
    helpText = ''
      Store each complete runtime file in a uniquely named Bitwarden Secure Note.
      Unlock Bitwarden CLI once in the current shell:
        export BW_SESSION="$(bw unlock --raw)"

      Pino syncs before reading an item and never writes it to a temporary file.
    '';
    script = builtins.readFile ./bitwarden.sh;
  };
}
