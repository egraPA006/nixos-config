{ config, lib, pkgs, ... }:

let
  user = config.pino.user.name;
  home = config.pino.user.home;
  databaseDir = "${home}/.local/share/pino/identity";
  databaseFile = "${databaseDir}/identity.kdbx";
  infrastructureDatabaseFile = "${databaseDir}/infra.kdbx";
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
  imports = [ ./portable.nix ./manual.nix ];

  # KeePassXC is the single Secret Service provider for desktop applications.
  services.gnome.gnome-keyring.enable = lib.mkForce false;

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

  pino.subcommands.vault = {
    description = "Manage portable encrypted identity and secret data";
    commands = {
      identity = {
        description = "Open and inspect synchronized KeePass databases";
        commands = {
          open.description = "Open the normal identity database";
          infra.description = "Open the infrastructure database manually";
          files.description = "List synchronized KeePass database files";
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
            *) echo "Run 'pino vault identity help' for usage." >&2; exit 1 ;;
          esac
        '';
      };
    };
  };
}
