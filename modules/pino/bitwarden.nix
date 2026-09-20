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
  publicKeys = config.pino.provision.publicKeys;
  installCommands = lib.concatMapStringsSep "\n" (key:
    "provision_step ${lib.escapeShellArg key.item} install_public_key ${lib.escapeShellArg key.item} ${lib.escapeShellArg key.target}"
  ) publicKeys + "\n" + lib.concatMapStringsSep "\n" (secret:
    "provision_step ${lib.escapeShellArg secret.item} install_note ${lib.concatStringsSep " " (map lib.escapeShellArg ([ secret.item secret.target ] ++ secret.units))}"
  ) secrets;
  afterInstall = lib.optionalString (lib.any (key: lib.hasSuffix "/.ssh/github.pub" key.target) publicKeys)
    ''if ! switch_github_remote ${lib.escapeShellArg config.pino.configDir}; then failed_items+=("git origin"); fi'';
in
{
  options.pino.provision.secrets = lib.mkOption {
    type = lib.types.listOf secretType;
    default = [ ];
    description = "Runtime files installed locally from Bitwarden for active profiles";
  };
  options.pino.provision.publicKeys = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        item = lib.mkOption { type = lib.types.str; description = "Bitwarden SSH Key item name"; };
        target = lib.mkOption { type = lib.types.str; description = "Public key path below ~/.ssh"; };
      };
    });
    default = [ ];
    description = "SSH public key selectors installed locally from Bitwarden";
  };

  config = {
    environment.systemPackages = [ pkgs.bitwarden-cli ];

    pino.subcommands.provision = {
      description = "Provision runtime configuration from Bitwarden Secure Notes";
      commands = {
        install = {
          description = "Install all declared files, or one Secure Note";
          usage = "[item absolute-target [systemd-unit ...]]";
        };
        send = {
          description = "Install a Secure Note on an SSH host";
          usage = "<item> <host> <absolute-target> [systemd-unit ...]";
        };
      };
      helpText = ''
        Store each complete runtime file in a uniquely named Bitwarden Secure Note.
        Pino prompts for Bitwarden login or unlock when needed, syncs before
        reading an item, and never
        writes secret contents to a temporary file. With no arguments, `install`
        installs every secret and SSH public key declared by active profiles.
        It continues past individual failures and reports them at the end.
        On a desktop, it switches the Git origin to SSH after verifying access.
      '';
      script = builtins.replaceStrings [ "@declaredCount@" "@declaredSecrets@" "@afterDeclared@" ]
        [ (toString (builtins.length secrets + builtins.length publicKeys)) installCommands afterInstall ]
        (builtins.readFile ./bitwarden.sh);
    };
  };
}
