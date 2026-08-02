{ config, lib, pkgs, ... }:

let
  vaultDevice = "/dev/disk/by-partlabel/secrets";
  vaultMapper = "secrets";
  vaultMountPoint = "/data/secrets";
  databaseDir = "${vaultMountPoint}/keepass";
  databaseFile = "${databaseDir}/identity.kdbx";
  provisionedDir = config.pino.vault.provisionedDir;
  declaredSecrets = builtins.attrNames config.pino.vault.secrets;
  deploySecret = name: secret: lib.optionalString (secret.target != null) ''
    source="$PROVISIONED_DIR/${secret.source}"
    if [ -f "$source" ]; then
      sudo ${pkgs.coreutils}/bin/install -d \
        -o ${lib.escapeShellArg secret.owner} \
        -g ${lib.escapeShellArg secret.group} \
        -m ${lib.escapeShellArg secret.directoryMode} \
        ${lib.escapeShellArg (builtins.dirOf secret.target)}
      sudo ${pkgs.coreutils}/bin/install -D \
        -o ${lib.escapeShellArg secret.owner} \
        -g ${lib.escapeShellArg secret.group} \
        -m ${lib.escapeShellArg secret.mode} \
        "$source" ${lib.escapeShellArg secret.target}
    fi
  '';
  deploySecrets = lib.concatStringsSep "\n" (lib.mapAttrsToList deploySecret config.pino.vault.secrets);
  activateSecret = name: secret: lib.optionalString (secret.target != null) ''
    source=${lib.escapeShellArg "${provisionedDir}/${secret.source}"}
    if [ -f "$source" ]; then
      ${pkgs.coreutils}/bin/install -d \
        -o ${lib.escapeShellArg secret.owner} \
        -g ${lib.escapeShellArg secret.group} \
        -m ${lib.escapeShellArg secret.directoryMode} \
        ${lib.escapeShellArg (builtins.dirOf secret.target)}
      ${pkgs.coreutils}/bin/install -D \
        -o ${lib.escapeShellArg secret.owner} \
        -g ${lib.escapeShellArg secret.group} \
        -m ${lib.escapeShellArg secret.mode} \
        "$source" ${lib.escapeShellArg secret.target}
    fi
  '';
  activateSecrets = lib.concatStringsSep "\n" (lib.mapAttrsToList activateSecret config.pino.vault.secrets);
  restartUnits = lib.unique (lib.concatMap (secret: secret.restartUnits) (lib.attrValues config.pino.vault.secrets));
  keepassxcVault = pkgs.writeShellScript "keepassxc-vault" ''
    if [ -f ${databaseFile} ]; then
      exec ${pkgs.keepassxc}/bin/keepassxc ${databaseFile}
    else
      exec ${pkgs.keepassxc}/bin/keepassxc
    fi
  '';
in
{
  system.activationScripts.pino-vault-secrets = {
    deps = [ "users" "groups" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${lib.escapeShellArg provisionedDir}
      ${activateSecrets}
    '';
  };

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
    description = "Manage the KeePassXC vault and its offline backups";
    commands = {
      status.description = "Show local vault status";
      open.description = "Unlock and mount the local vault";
      keepass.description = "Open the KeePassXC database";
      close.description = "Unmount and lock the local vault";
      files.description = "List declared and provisioned secret files";
      populate.description = "Provision this host from the local vault";
      disks.description = "List connected vault backup disks";
      backup = { description = "Back up the local vault"; usage = "[disk]"; };
      check = { description = "Verify a vault backup"; usage = "[disk]"; };
      snapshots = { description = "List vault backup snapshots"; usage = "[disk]"; };
      restore = { description = "Stage or apply a vault snapshot"; usage = "[disk] [snapshot] [--apply]"; };
    };
    helpText = ''
      pino vault — manage the local KeePassXC identity vault
        pino vault status    Show whether the vault is open and mounted
        pino vault open      Unlock and mount the vault
        pino vault keepass   Open the vault database in KeePassXC
        pino vault close     Unmount and lock the vault
        pino vault disks     List connected pino-vault-* backup disks
        pino vault backup [disk]   Back up to a disk (for example: 1)
        pino vault check [disk]    Check a backup disk without changing it
        pino vault snapshots [disk]  List snapshots for this host
        pino vault restore [disk] [snapshot] [--apply]
                                    Stage or directly apply an exact snapshot
        pino vault files     List declared and provisioned system-secret files
        pino vault populate  Provision this host from the local encrypted vault

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
      BACKUP_LABEL_PREFIX=pino-vault-
      PROVISIONED_DIR=${lib.escapeShellArg provisionedDir}
      HOST_NAME=${lib.escapeShellArg config.networking.hostName}

      is_open() {
        [ -e "$MAPPER_DEVICE" ]
      }

      is_mounted() {
        ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_POINT" >/dev/null 2>&1
      }

      backup_labels() {
        ${pkgs.util-linux}/bin/lsblk -rno LABEL,FSTYPE \
          | ${pkgs.gawk}/bin/awk '$2 == "crypto_LUKS" && $1 ~ /^pino-vault-/ { print $1 }'
      }

      backup_device() {
        local label="$1"
        local -a devices
        mapfile -t devices < <(
          ${pkgs.util-linux}/bin/lsblk -rpn -o NAME,LABEL,FSTYPE \
            | ${pkgs.gawk}/bin/awk -v label="$label" '$2 == label && $3 == "crypto_LUKS" { print $1 }'
        )
        case "''${#devices[@]}" in
          1) printf '%s\n' "''${devices[0]}" ;;
          0)
            echo "No LUKS partition found with label: $label" >&2
            return 1
            ;;
          *)
            echo "Several LUKS partitions have label $label; labels must be unique." >&2
            return 1
            ;;
        esac
      }

      select_backup_label() {
        local requested="''${1:-}"
        local -a labels
        if [ -n "$requested" ]; then
          case "$requested" in
            "$BACKUP_LABEL_PREFIX"*) BACKUP_LABEL="$requested" ;;
            *) BACKUP_LABEL="$BACKUP_LABEL_PREFIX$requested" ;;
          esac
          if ! backup_device "$BACKUP_LABEL" >/dev/null; then
            echo "Backup disk not found: $BACKUP_LABEL" >&2
            exit 1
          fi
          return
        fi

        mapfile -t labels < <(backup_labels)
        case "''${#labels[@]}" in
          0)
            echo "No connected LUKS disk labelled pino-vault-* was found." >&2
            exit 1
            ;;
          1) BACKUP_LABEL="''${labels[0]}" ;;
          *)
            echo "Several vault disks are connected; specify one:" >&2
            printf '  %s\n' "''${labels[@]}" >&2
            exit 1
            ;;
        esac
      }

      with_backup_disk() {
        local mode="$1"
        local operation="$2"
        local requested="''${3:-}"
        local device mapper mount_point operation_status opened=false mounted=false
        local -a active_children
        shift 3
        select_backup_label "$requested"
        device="$(backup_device "$BACKUP_LABEL")"
        mapfile -t active_children < <(${pkgs.util-linux}/bin/lsblk -nrpo NAME "$device" | ${pkgs.coreutils}/bin/tail -n +2)
        if [ "''${#active_children[@]}" -ne 0 ]; then
          echo "$BACKUP_LABEL is already unlocked outside Pino:" >&2
          printf '  %s\n' "''${active_children[@]}" >&2
          echo "Unmount/eject it in the file manager, then retry." >&2
          return 1
        fi
        mapper="pino-vault-$(${pkgs.coreutils}/bin/printf '%s' "$BACKUP_LABEL" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -c1-12)"
        mount_point="/run/$mapper"

        cleanup_backup_disk() {
          if [ "$mounted" = true ]; then
            sudo ${pkgs.util-linux}/bin/umount "$mount_point" || true
          fi
          if [ "$opened" = true ]; then
            sudo ${pkgs.cryptsetup}/bin/cryptsetup close "$mapper" || true
          fi
        }
        if [ -e "/dev/mapper/$mapper" ]; then
          if ${pkgs.util-linux}/bin/findmnt -rn -S "/dev/mapper/$mapper" >/dev/null 2>&1; then
            echo "Backup mapper is already mounted: /dev/mapper/$mapper" >&2
            echo "Unmount it before retrying." >&2
            return 1
          fi
          sudo ${pkgs.cryptsetup}/bin/cryptsetup close "$mapper"
        fi

        if [ "$mode" = ro ]; then
          sudo ${pkgs.cryptsetup}/bin/cryptsetup open --readonly "$device" "$mapper"
        else
          sudo ${pkgs.cryptsetup}/bin/cryptsetup open "$device" "$mapper"
        fi
        opened=true
        trap cleanup_backup_disk EXIT INT TERM
        sudo ${pkgs.coreutils}/bin/mkdir -p "$mount_point"
        if [ "$mode" = ro ]; then
          sudo ${pkgs.util-linux}/bin/mount -o ro,nodev,nosuid,noexec "/dev/mapper/$mapper" "$mount_point"
        else
          sudo ${pkgs.util-linux}/bin/mount -o nodev,nosuid,noexec "/dev/mapper/$mapper" "$mount_point"
        fi
        mounted=true
        if "$operation" "$mount_point" "$@"; then
          operation_status=0
        else
          operation_status=$?
        fi
        cleanup_backup_disk
        trap - EXIT INT TERM
        return "$operation_status"
      }

      backup_vault() {
        local backup_mount="$1"
        local metadata="$backup_mount/.pino"
        local repository="$backup_mount/backups/vault"
        if ! is_mounted; then
          echo "The local vault is closed. Run: pino vault open" >&2
          return 1
        fi
        if sudo ${pkgs.coreutils}/bin/test -d "$MOUNT_POINT/system"; then
          sudo ${pkgs.coreutils}/bin/install -d -m 0700 "$backup_mount/bootstrap"
          sudo ${pkgs.rsync}/bin/rsync -a --delete \
            "$MOUNT_POINT/system/" "$backup_mount/bootstrap/"
          echo "Installation secrets synchronized to $BACKUP_LABEL"
        else
          echo "No system-secret tree exists at $MOUNT_POINT/system; bootstrap sync skipped." >&2
        fi
        sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o egrapa -g users "$metadata" "$repository"
        if [ ! -f "$metadata/restic-password" ]; then
          ${pkgs.openssl}/bin/openssl rand -base64 48 | sudo ${pkgs.coreutils}/bin/tee "$metadata/restic-password" >/dev/null
          sudo ${pkgs.coreutils}/bin/chown egrapa:users "$metadata/restic-password"
          sudo ${pkgs.coreutils}/bin/chmod 0600 "$metadata/restic-password"
        fi
        if [ ! -f "$repository/config" ]; then
          sudo ${pkgs.restic}/bin/restic \
            --repo "$repository" \
            --password-file "$metadata/restic-password" \
            init
        fi
        sudo ${pkgs.restic}/bin/restic \
          --repo "$repository" \
          --password-file "$metadata/restic-password" \
          backup "$MOUNT_POINT" \
          --exclude "$MOUNT_POINT/lost+found" \
          --exclude "$MOUNT_POINT/restores" \
          --host "$(${pkgs.inetutils}/bin/hostname)" \
          --tag pino-vault
        sudo ${pkgs.restic}/bin/restic \
          --repo "$repository" \
          --password-file "$metadata/restic-password" \
          forget --keep-last 2 --keep-monthly 1 --prune
        echo "Vault backed up to $BACKUP_LABEL"
      }

      check_vault_backup() {
        local backup_mount="$1"
        local metadata="$backup_mount/.pino"
        local repository="$backup_mount/backups/vault"
        if [ ! -f "$metadata/restic-password" ] || [ ! -f "$repository/config" ]; then
          echo "$BACKUP_LABEL is encrypted correctly but has no initialized vault backup." >&2
          return 1
        fi
        RESTIC_CACHE_DIR="$(${pkgs.coreutils}/bin/mktemp -d)"
        if ! sudo ${pkgs.restic}/bin/restic \
          --repo "$repository" \
          --password-file "$metadata/restic-password" \
          --cache-dir "$RESTIC_CACHE_DIR" \
          --no-lock \
          check --read-data; then
          sudo ${pkgs.coreutils}/bin/rm -rf "$RESTIC_CACHE_DIR"
          return 1
        fi
        echo
        sudo ${pkgs.restic}/bin/restic \
          --repo "$repository" \
          --password-file "$metadata/restic-password" \
          --cache-dir "$RESTIC_CACHE_DIR" \
          --no-lock \
          snapshots --latest 1
        sudo ${pkgs.coreutils}/bin/rm -rf "$RESTIC_CACHE_DIR"
        echo "Backup disk $BACKUP_LABEL is healthy"
      }

      restore_vault_backup() {
        local backup_mount="$1"
        local snapshot="''${2:-latest}"
        local apply_mode="''${3:-}"
        local metadata="$backup_mount/.pino"
        local repository="$backup_mount/backups/vault"
        local restore_root restored_vault hostname confirmation snapshot_name
        if ! is_mounted; then
          echo "The local vault is closed. Run: pino vault open" >&2
          return 1
        fi
        if [ ! -f "$metadata/restic-password" ] || [ ! -f "$repository/config" ]; then
          echo "$BACKUP_LABEL has no initialized vault backup." >&2
          return 1
        fi
        hostname="$(${pkgs.inetutils}/bin/hostname)"
        snapshot_name="$(${pkgs.coreutils}/bin/printf '%s' "$snapshot" | ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9._-')"
        if [ -z "$snapshot_name" ]; then
          echo "Invalid snapshot ID: $snapshot" >&2
          return 1
        fi
        case "$apply_mode" in
          ""|--apply) ;;
          *)
            echo "Unknown restore option: $apply_mode" >&2
            return 1
            ;;
        esac
        restore_root="$MOUNT_POINT/restores/$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)-$snapshot_name"
        sudo ${pkgs.coreutils}/bin/mkdir -p "$restore_root"
        sudo ${pkgs.restic}/bin/restic \
          --repo "$repository" \
          --password-file "$metadata/restic-password" \
          --no-lock \
          restore "$snapshot" --host "$hostname" --target "$restore_root"
        restored_vault="$restore_root/data/secrets"

        if [ "$apply_mode" != --apply ]; then
          echo "Snapshot $snapshot restored without overwriting live files:"
          echo "  $restored_vault"
          return
        fi
        if ${pkgs.procps}/bin/pgrep -x keepassxc >/dev/null 2>&1; then
          echo "KeePassXC is running. Save and close it before applying a snapshot." >&2
          return 1
        fi
        echo "WARNING: this makes the live vault match snapshot $snapshot."
        echo "Newer live files will be deleted, except restores/ and lost+found/."
        read -r -p "Type '$snapshot' to apply it: " confirmation
        if [ "$confirmation" != "$snapshot" ]; then
          echo "Apply cancelled; the staged restore remains at:"
          echo "  $restored_vault"
          return 1
        fi
        sudo ${pkgs.rsync}/bin/rsync -a --delete \
          --exclude '/restores/' \
          --exclude '/lost+found/' \
          "$restored_vault/" "$MOUNT_POINT/"
        echo "Snapshot $snapshot applied to $MOUNT_POINT"
      }

      list_vault_snapshots() {
        local backup_mount="$1"
        local metadata="$backup_mount/.pino"
        local repository="$backup_mount/backups/vault"
        if [ ! -f "$metadata/restic-password" ] || [ ! -f "$repository/config" ]; then
          echo "$BACKUP_LABEL has no initialized vault backup." >&2
          return 1
        fi
        sudo ${pkgs.restic}/bin/restic \
          --repo "$repository" \
          --password-file "$metadata/restic-password" \
          --no-lock \
          snapshots --host "$(${pkgs.inetutils}/bin/hostname)"
      }

      list_secret_files() {
        echo "Declared by Nix:"
        ${lib.concatMapStringsSep "\n" (name: "echo '  ${name}'") declaredSecrets}
        echo
        echo "Provisioned for $HOST_NAME:"
        if [ -d "$PROVISIONED_DIR" ]; then
          sudo ${pkgs.findutils}/bin/find "$PROVISIONED_DIR" -type f -printf '  %P\n' | ${pkgs.coreutils}/bin/sort
        else
          echo "  none"
        fi
      }

      populate_secret_files() {
        local staging source_dir
        if ! is_mounted; then
          echo "The local vault is closed. Run: pino vault open" >&2
          return 1
        fi
        source_dir="$MOUNT_POINT/system"
        if ! sudo ${pkgs.coreutils}/bin/test -d "$source_dir/shared" \
          && ! sudo ${pkgs.coreutils}/bin/test -d "$source_dir/hosts/$HOST_NAME"; then
          echo "No secrets exist for $HOST_NAME." >&2
          echo "Expected $source_dir/shared or $source_dir/hosts/$HOST_NAME" >&2
          return 1
        fi
        staging="$(sudo ${pkgs.coreutils}/bin/mktemp -d /run/pino-secrets.XXXXXX)"
        cleanup_staging() { sudo ${pkgs.coreutils}/bin/rm -rf "$staging"; }
        trap cleanup_staging EXIT INT TERM
        if sudo ${pkgs.coreutils}/bin/test -d "$source_dir/shared"; then
          sudo ${pkgs.rsync}/bin/rsync -a "$source_dir/shared/" "$staging/"
        fi
        if sudo ${pkgs.coreutils}/bin/test -d "$source_dir/hosts/$HOST_NAME"; then
          sudo ${pkgs.rsync}/bin/rsync -a "$source_dir/hosts/$HOST_NAME/" "$staging/"
        fi
        sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root "$PROVISIONED_DIR"
        sudo ${pkgs.rsync}/bin/rsync -a --delete "$staging/" "$PROVISIONED_DIR/"
        sudo ${pkgs.findutils}/bin/find "$PROVISIONED_DIR" -type d -exec ${pkgs.coreutils}/bin/chown root:root {} +
        sudo ${pkgs.findutils}/bin/find "$PROVISIONED_DIR" -type d -exec ${pkgs.coreutils}/bin/chmod 0700 {} +
        sudo ${pkgs.findutils}/bin/find "$PROVISIONED_DIR" -type f -exec ${pkgs.coreutils}/bin/chown root:root {} +
        sudo ${pkgs.findutils}/bin/find "$PROVISIONED_DIR" -type f -exec ${pkgs.coreutils}/bin/chmod 0600 {} +
        ${deploySecrets}
        ${lib.concatMapStringsSep "\n" (unit: "sudo ${pkgs.systemd}/bin/systemctl try-restart ${lib.escapeShellArg unit}") restartUnits}
        cleanup_staging
        trap - EXIT INT TERM
        echo "Secrets for $HOST_NAME populated from the local vault"
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

          sudo ${pkgs.coreutils}/bin/chown root:root "$MOUNT_POINT"
          sudo ${pkgs.coreutils}/bin/chmod 0711 "$MOUNT_POINT"
          sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o egrapa -g users "$DATABASE_DIR"
          sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root "$MOUNT_POINT/system"
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

        disks)
          disk_labels="$(backup_labels)"
          if [ -z "$disk_labels" ]; then
            echo "No connected LUKS disks labelled pino-vault-* found"
          else
            printf '%s\n' "$disk_labels"
          fi
          ;;

        backup)
          with_backup_disk rw backup_vault "''${2:-}"
          ;;

        check)
          with_backup_disk ro check_vault_backup "''${2:-}"
          ;;

        snapshots)
          with_backup_disk ro list_vault_snapshots "''${2:-}"
          ;;

        restore)
          with_backup_disk ro restore_vault_backup "''${2:-}" "''${3:-latest}" "''${4:-}"
          ;;

        files)
          list_secret_files
          ;;

        populate)
          populate_secret_files
          ;;

        "")
          echo "Usage: pino vault <status|open|keepass|close|files|populate|disks|backup|check|snapshots|restore>"
          ;;

        *)
          echo "pino vault: unknown command '$1'" >&2
          echo "Run 'pino vault help' for usage." >&2
          exit 1
          ;;
      esac
    '';
    fishCompletions = ''
      set -l vault_cmds status open keepass close files populate disks backup check snapshots restore
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a status  -d 'Show vault status'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a open    -d 'Unlock and mount the vault'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a keepass -d 'Open KeePassXC'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a close   -d 'Unmount and lock the vault'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a disks   -d 'List backup disks'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a backup  -d 'Back up the vault'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a check   -d 'Check a vault backup'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a snapshots -d 'List vault snapshots'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a restore -d 'Stage or apply a selected snapshot'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a files -d 'List system-secret files'
      complete -c pino -f -n '__fish_seen_subcommand_from vault; and not __fish_seen_subcommand_from $vault_cmds' -a populate -d 'Provision system-secret files'
    '';
  };
}
