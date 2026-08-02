{ pkgs, ... }:

let
  vaultDevice = "/dev/disk/by-partlabel/secrets";
  vaultMapper = "secrets";
  vaultMountPoint = "/data/secrets";
  databaseDir = "${vaultMountPoint}/keepass";
  databaseFile = "${databaseDir}/identity.kdbx";
  keepassxcVault = pkgs.writeShellScript "keepassxc-vault" ''
    if [ -f ${databaseFile} ]; then
      exec ${pkgs.keepassxc}/bin/keepassxc ${databaseFile}
    else
      exec ${pkgs.keepassxc}/bin/keepassxc
    fi
  '';
in
{
  home-manager.users.egrapa = {
    programs = {
      keepassxc.enable = true;

      chromium = {
        enable = true;
        package = null;
        extensions = [
          "oboonakemofpalcgghocfoadofidjkkk" # KeePassXC-Browser
        ];
      };
    };

    systemd.user.services.keepassxc-vault = {
      Unit = {
        Description = "KeePassXC identity vault";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = keepassxcVault;
        Restart = "no";
      };
    };
  };

  pino.subcommands.vault = {
    description = "Open and close the KeePassXC identity vault";
    helpText = ''
      pino vault — manage the local KeePassXC identity vault
        pino vault status    Show whether the vault is open and mounted
        pino vault open      Unlock and mount the vault
        pino vault keepass   Open the vault database in KeePassXC
        pino vault close     Unmount and lock the vault

      Vault device: ${vaultDevice}
      Mount point:  ${vaultMountPoint}
      Database:     ${databaseFile}
    '';
    script = ''
      DEVICE=${vaultDevice}
      MAPPER=${vaultMapper}
      MAPPER_DEVICE="/dev/mapper/$MAPPER"
      MOUNT_POINT=${vaultMountPoint}
      DATABASE_DIR=${databaseDir}
      DATABASE_FILE=${databaseFile}

      is_open() {
        [ -e "$MAPPER_DEVICE" ]
      }

      is_mounted() {
        ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_POINT" >/dev/null 2>&1
      }

      case "''${1:-}" in
        status)
          if is_open; then
            echo "LUKS mapping: open ($MAPPER_DEVICE)"
          else
            echo "LUKS mapping: closed"
          fi

          if is_mounted; then
            echo "Mount:        mounted at $MOUNT_POINT"
          else
            echo "Mount:        not mounted"
          fi
          ;;

        open)
          if [ ! -e "$DEVICE" ]; then
            echo "Vault device not found: $DEVICE" >&2
            echo "This host needs an 8G (or larger) GPT partition with:" >&2
            echo "  label = \"secrets\";" >&2
            echo "  content.type = \"luks\";" >&2
            echo "  content.name = \"secrets\";" >&2
            echo "  content.initrdUnlock = false;" >&2
            echo "and an ext4 filesystem mounted at $MOUNT_POINT with noauto." >&2
            exit 1
          fi

          if ! is_open; then
            sudo ${pkgs.cryptsetup}/bin/cryptsetup open --allow-discards "$DEVICE" "$MAPPER"
          fi

          if ! is_mounted; then
            if ! sudo ${pkgs.util-linux}/bin/mount "$MOUNT_POINT"; then
              sudo ${pkgs.cryptsetup}/bin/cryptsetup close "$MAPPER" || true
              exit 1
            fi
          fi

          sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o egrapa -g users "$DATABASE_DIR"
          echo "Vault opened at $MOUNT_POINT"
          ;;

        keepass)
          if ! is_mounted; then
            echo "Vault is closed. Run: pino vault open" >&2
            exit 1
          fi

          if [ -f "$DATABASE_FILE" ]; then
            ${pkgs.systemd}/bin/systemctl --user start keepassxc-vault.service
            echo "KeePassXC started with $DATABASE_FILE"
          else
            echo "No database exists yet. Create one and save it as:"
            echo "  $DATABASE_FILE"
            ${pkgs.systemd}/bin/systemctl --user start keepassxc-vault.service
          fi
          ;;

        close)
          if ${pkgs.procps}/bin/pgrep -x keepassxc >/dev/null 2>&1; then
            echo "KeePassXC is still running. Save, lock, and close it first." >&2
            exit 1
          fi

          if is_mounted; then
            sudo ${pkgs.util-linux}/bin/umount "$MOUNT_POINT"
          fi

          if is_open; then
            sudo ${pkgs.cryptsetup}/bin/cryptsetup close "$MAPPER"
          fi

          echo "Vault closed"
          ;;

        "")
          echo "Usage: pino vault <status|open|keepass|close>"
          ;;

        *)
          echo "pino vault: unknown command '$1'" >&2
          echo "Run 'pino vault help' for usage." >&2
          exit 1
          ;;
      esac
    '';
    fishCompletions = ''
      set -l vault_cmds status open keepass close
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a status  -d 'Show vault status'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a open    -d 'Unlock and mount the vault'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a keepass -d 'Open KeePassXC'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a close   -d 'Unmount and lock the vault'
    '';
  };
}
