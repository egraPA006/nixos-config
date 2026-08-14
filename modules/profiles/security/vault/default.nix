{ config, lib, pkgs, ... }:

let
  user = config.pino.user.name;
  home = config.pino.user.home;
  databaseDir = "${home}/.local/share/pino/identity";
  databaseFile = "${databaseDir}/identity.kdbx";
  infrastructureDatabaseFile = "${databaseDir}/infra.kdbx";
  sync = config.pino.vault.sync;
  syncDevices = lib.optionalAttrs (sync.serverId != null) {
    ${sync.serverName} = {
      id = sync.serverId;
      addresses = [ sync.serverAddress ];
    };
  } // lib.mapAttrs (_: mirror: {
    id = mirror.id;
    addresses = [ mirror.address ];
  }) sync.mirrors;
  syncDeviceNames = builtins.attrNames syncDevices;
  keepassxcIdentity = pkgs.writeShellScript "keepassxc-identity" ''
    if [ -f ${lib.escapeShellArg databaseFile} ]; then
      exec ${pkgs.keepassxc}/bin/keepassxc ${lib.escapeShellArg databaseFile}
    fi
    exec ${pkgs.keepassxc}/bin/keepassxc
  '';
  keepassxcInfrastructure = pkgs.writeShellScript "keepassxc-infrastructure" ''
    [ -f ${lib.escapeShellArg infrastructureDatabaseFile} ] || {
      echo "Infrastructure database does not exist: ${infrastructureDatabaseFile}" >&2
      exit 1
    }
    exec ${pkgs.keepassxc}/bin/keepassxc ${lib.escapeShellArg infrastructureDatabaseFile}
  '';
in
{
  imports = [ ./options.nix ./portable.nix ];

  # KeePassXC is the single Secret Service provider used by Cryptomator.
  services.gnome.gnome-keyring.enable = lib.mkForce false;

  services.syncthing = {
    enable = true;
    inherit user;
    group = "users";
    dataDir = "${home}/.local/share/syncthing";
    configDir = "${home}/.config/syncthing";
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = false;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices = syncDevices;
      folders = lib.optionalAttrs (syncDeviceNames != [ ]) {
        keepass = {
          label = "KeePass identity databases";
          path = databaseDir;
          devices = syncDeviceNames;
          versioning = {
            type = "simple";
            params.keep = "2";
          };
        };
      };
      options = {
        listenAddresses = [ ];
        localAnnounceEnabled = false;
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${home}/.local/share/pino 0700 ${user} users -"
    "d ${databaseDir} 0700 ${user} users -"
  ];

  home-manager.users.${user} = {
    programs = {
      keepassxc = {
        enable = true;
        settings = {
          Browser = {
            Enabled = true;
            UpdateBinaryPath = false;
          };
          SSHAgent.Enabled = true;
          FdoSecrets = {
            Enabled = true;
            ShowNotification = true;
            ConfirmDeleteItem = true;
            ConfirmAccessItem = true;
            UnlockBeforeSearch = true;
          };
          GUI = {
            ShowTrayIcon = true;
            MinimizeToTray = true;
          };
        };
      };
      chromium = {
        enable = true;
        package = null;
        extensions = [
          "oboonakemofpalcgghocfoadofidjkkk"
        ];
      };
    };

    xdg.configFile."keepassxc/keepassxc.ini".force = true;
    xdg.dataFile."dbus-1/services/org.freedesktop.secrets.service".text = ''
      [D-BUS Service]
      Name=org.freedesktop.secrets
      Exec=${keepassxcIdentity}
    '';

    systemd.user.services.keepassxc-identity = {
      Unit = {
        Description = "KeePassXC identity database";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = keepassxcIdentity;
        Restart = "no";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  pino.subcommands.identity = {
    description = "Open and inspect synchronized KeePass identity databases";
    commands = {
      open.description = "Open the normal identity database";
      infra.description = "Open the infrastructure database manually";
      files.description = "List synchronized KeePass database files";
      sync = {
        description = "Inspect or restart identity synchronization";
        commands = {
          status.description = "Show Syncthing service status";
          restart.description = "Restart identity synchronization";
          id.description = "Print this client's public Syncthing device ID";
        };
      };
    };
    helpText = ''
      identity.kdbx is the everyday database. infra.kdbx uses an independent
      master password and is opened manually. Both synchronize only as KDBX
      ciphertext; never store the infrastructure master password in identity.
    '';
    script = ''
      case "''${1:-}" in
        open) ${pkgs.systemd}/bin/systemctl --user start keepassxc-identity.service ;;
        infra) exec ${keepassxcInfrastructure} ;;
        files)
          ${pkgs.findutils}/bin/find ${lib.escapeShellArg databaseDir} \
            -maxdepth 1 -type f -name '*.kdbx' -printf '%f\n' | ${pkgs.coreutils}/bin/sort
          ;;
        sync)
          case "''${2:-}" in
            status) ${pkgs.systemd}/bin/systemctl status syncthing.service --no-pager ;;
            restart) sudo ${pkgs.systemd}/bin/systemctl restart syncthing.service ;;
            id)
              sudo -u ${lib.escapeShellArg user} ${pkgs.syncthing}/bin/syncthing cli \
                --home=${lib.escapeShellArg "${home}/.config/syncthing"} \
                show system | ${pkgs.jq}/bin/jq -r .myID
              ;;
            *) echo "Run 'pino identity sync help' for usage." >&2; exit 1 ;;
          esac
          ;;
        *) echo "Run 'pino identity help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
