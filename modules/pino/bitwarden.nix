{ config, lib, pkgs, ... }:
let
  secretType = lib.types.submodule {
    options = {
      item = lib.mkOption { type = lib.types.str; description = "Bitwarden Secure Note name"; };
      target = lib.mkOption { type = lib.types.str; description = "Absolute destination path"; };
      units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Systemd units to restart after installation";
      };
    };
  };
  secrets = config.pino.provision.secrets;
  sshKeys = config.pino.provision.sshKeys;
  installCommands = lib.concatMapStringsSep "\n" (key:
    "provision_step ${lib.escapeShellArg key.item} install_ssh_key ${lib.escapeShellArg key.item} ${lib.escapeShellArg key.target}"
  ) sshKeys + "\n" + lib.concatMapStringsSep "\n" (secret:
    "provision_step ${lib.escapeShellArg secret.item} install_note ${lib.concatStringsSep " " (map lib.escapeShellArg ([ secret.item secret.target ] ++ secret.units))}"
  ) secrets;
  provisionScript = builtins.replaceStrings [ "@declaredCount@" "@declaredSecrets@" "@afterDeclared@" "@configDir@" "@cmp@" ]
    [ (toString (builtins.length secrets + builtins.length sshKeys)) installCommands "" (lib.escapeShellArg config.pino.configDir) "${pkgs.diffutils}/bin/cmp" ]
    (builtins.readFile ./bitwarden.sh);
  provisionSend = pkgs.writeShellScript "pino-provision-send-internal" provisionScript;
in
{
  options.pino.provision.secrets = lib.mkOption {
    type = lib.types.listOf secretType;
    default = [ ];
    description = "Runtime files installed locally from Bitwarden for active profiles";
  };
  options.pino.provision.sshKeys = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        item = lib.mkOption { type = lib.types.str; description = "Bitwarden SSH Key item name"; };
        target = lib.mkOption { type = lib.types.str; description = "Private key path below ~/.ssh"; };
      };
    });
    default = [ ];
    description = "SSH key pairs installed locally from Bitwarden";
  };

  config = {
    _module.args.pinoProvisionSend = provisionSend;
    environment.systemPackages = [ pkgs.bitwarden-cli ];

    pino.subcommands.os.commands.provision = {
      description = "Install this host's declared Bitwarden secrets and SSH keys";
      helpText = ''
        Store each complete runtime file in a uniquely named Bitwarden Secure Note.
        Pino prompts for Bitwarden login or unlock when needed, syncs before
        reading an item, and never
        writes secret contents to a temporary file. Installs every secret and SSH
        key pair declared by active profiles on this host.
        It continues past individual failures and reports them at the end.
      '';
      script = ''set -- install; ${provisionScript}'';
    };
  };
}
