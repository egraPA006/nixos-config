{ activeProfiles, config, lib, pkgs, ... }:

let
  cfg = config.pino.server.passwordSync;
  deviceNames = builtins.attrNames cfg.devices;
in
{
  services.syncthing = {
    enable = true;
    user = "syncthing";
    group = "syncthing";
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/config";
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = false;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices = cfg.devices;
      folders.keepass = {
        label = "KeePass identity database";
        path = cfg.folder;
        devices = deviceNames;
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      options = {
        listenAddresses = [ "tcp://0.0.0.0:22000" ];
        localAnnounceEnabled = false;
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${cfg.folder} 0700 syncthing syncthing -"
  ];

  assertions = [
    {
      assertion = builtins.elem "server-vpn" activeProfiles;
      message = "server-password-sync requires server-vpn";
    }
    {
      assertion = deviceNames != [ ];
      message = "server-password-sync requires at least one pino.server.passwordSync.devices entry";
    }
  ];

  pino.subcommands.server.commands.passwords = {
    description = "Inspect KeePass database synchronization";
    commands = {
      status.description = "Show Syncthing service status";
      id.description = "Print the server Syncthing device ID";
      files.description = "List synchronized KeePass files";
      logs.description = "Show recent synchronization logs";
    };
    helpText = ''
      Only ${cfg.folder} is synchronized. The rest of the identity/system vault
      is never exposed through Syncthing. Syncthing listens on the VPN-trusted
      interface through port 22000; discovery, relays, NAT traversal, and the
      public GUI are disabled.
    '';
    script = ''
      case "''${1:-}" in
        status) systemctl status syncthing --no-pager ;;
        id)
          sudo -u syncthing ${pkgs.syncthing}/bin/syncthing \
            cli --home=/var/lib/syncthing/config show system | jq -r .myID
          ;;
        files) sudo -u syncthing ${pkgs.coreutils}/bin/ls -lah ${lib.escapeShellArg cfg.folder} ;;
        logs) journalctl -u syncthing -n 100 --no-pager ;;
        *) echo "Run 'pino server passwords help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
