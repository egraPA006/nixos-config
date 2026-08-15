{ config, lib, pkgs, ... }:

let
  cfg = config.pino.portableVaults;
  user = config.pino.user.name;
  home = config.pino.user.home;
  effectiveScopes = lib.unique (
    cfg.scopes
    ++ [ "shared_sec" ]
    ++ (if cfg.trustedClient
        then map (host: "hosts/${host}") config.pino.secrets.knownHosts
        else [ "hosts/${config.networking.hostName}" ])
  );
  scopeWords = lib.concatStringsSep " " (map lib.escapeShellArg effectiveScopes);
in
{
  options.pino.portableVaults = {
    enable = lib.mkEnableOption "portable client-encrypted Pino vaults" // { default = true; };
    cipherRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/share/pino/vaults";
      description = "Local gocryptfs ciphertext root";
    };
    legacyCipherRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/share/pino/encrypted";
      description = "Temporary read-only source for Cryptomator-to-gocryptfs migration";
    };
    mountRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Secrets";
      description = "Parent directory for unlocked gocryptfs vaults";
    };
    shareRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Shared";
      description = "Plaintext disposable share on this trusted client";
    };
    scopes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional encrypted secret scopes available to this client";
    };
    trustedClient = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this client receives every known host-secret scope";
    };
    primary = lib.mkOption {
      type = lib.types.str;
      default = "mosk";
      description = "Authoritative remote used for pull-before-push checks";
    };
    remotes = lib.mkOption {
      default = {
        mosk = {
          sshHost = "mosk";
          path = "/var/lib/pino/storage";
          webdavUrl = "https://storage.egrapa.com";
        };
      };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          sshHost = lib.mkOption { type = lib.types.str; };
          path = lib.mkOption { type = lib.types.str; default = "/var/lib/pino/storage"; };
          webdavUrl = lib.mkOption { type = lib.types.str; };
        };
      });
      description = "Ciphertext-only storage mirrors";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.primary cfg.remotes;
        message = "pino.portableVaults.primary must name a configured remote";
      }
      {
        assertion = lib.all (scope:
          builtins.match "[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*" scope != null
          && !(lib.hasInfix ".." scope)) effectiveScopes;
        message = "pino.portableVaults.scopes must contain safe relative paths";
      }
      {
        assertion = lib.hasPrefix "${home}/" cfg.shareRoot;
        message = "pino.portableVaults.shareRoot must be inside the Pino user's home";
      }
      {
        assertion = lib.hasPrefix "${home}/" cfg.cipherRoot
          && lib.hasPrefix "${home}/" cfg.legacyCipherRoot
          && lib.hasPrefix "${home}/" cfg.mountRoot;
        message = "Pino vault roots must be inside the Pino user's home";
      }
      {
        assertion = cfg.cipherRoot != cfg.legacyCipherRoot;
        message = "The gocryptfs and legacy Cryptomator roots must differ during migration";
      }
    ];

    environment.systemPackages = [
      pkgs.gocryptfs
      pkgs.cryptomator
      pkgs.fuse3
      pkgs.openssh
      pkgs.rsync
    ];

    systemd.tmpfiles.rules = [
      "d ${home}/.local/share/pino 0700 ${user} users -"
      "d ${home}/.local/state/pino 0700 ${user} users -"
      "d ${cfg.cipherRoot} 0700 ${user} users -"
      "d ${cfg.mountRoot} 0700 ${user} users -"
      "d ${cfg.shareRoot} 0700 ${user} users -"
      "d ${home}/.local/state/pino/secrets 0700 ${user} users -"
      "L+ /run/pino-secrets - - - - ${cfg.mountRoot}"
    ] ++ lib.concatMap (scope: [
      "d ${cfg.cipherRoot}/${scope} 0700 ${user} users -"
      "d ${cfg.mountRoot}/${scope} 0700 ${user} users -"
    ]) effectiveScopes;

    # Temporary one-shot access to existing Cryptomator vaults during migration.
    # It is deliberately not started with the graphical session.
    home-manager.users.${user}.systemd.user.services.cryptomator-legacy = {
      Unit.Description = "Legacy Cryptomator vault migration";
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.cryptomator}/bin/cryptomator";
        Restart = "no";
      };
    };

    pino.subcommands.vault.commands.backup = {
      description = "Back up encrypted identity, secrets, and configuration offline";
      commands = {
        create = { description = "Write current and previous portable copies to a pino-data disk"; usage = "[disk-id]"; };
        list = { description = "List portable generations on a pino-data disk"; usage = "[disk-id]"; };
        restore = { description = "Replace local encrypted state from an offline generation"; usage = "[disk-id] <current|previous>"; };
      };
      helpText = ''
        The backup contains only ciphertext, the encrypted KeePass database,
        and a public Git bundle. The disposable plaintext share is excluded.
        The target keeps exactly current and previous generations.

        Restored data remains local until an explicit `pino vault push`.
      '';
      script = ''
        CIPHER_ROOT=${lib.escapeShellArg cfg.cipherRoot}
        IDENTITY_ROOT=${lib.escapeShellArg "${home}/.local/share/pino/identity"}
        MOUNT_ROOT=${lib.escapeShellArg cfg.mountRoot}
        PINO_USER=${lib.escapeShellArg user}
        MOUNTED=false
        MOUNT_POINT=
        DATA_DEVICE=
        BACKUP_SCOPES=( ${scopeWords} )

        cleanup_backup() {
          if [ "$MOUNTED" = true ]; then
            sudo ${pkgs.util-linux}/bin/umount "$MOUNT_POINT" || true
            sudo ${pkgs.coreutils}/bin/rmdir "$MOUNT_POINT" || true
            MOUNTED=false
          fi
        }
        trap cleanup_backup EXIT INT TERM

        require_closed() {
          local scope
          if ${pkgs.procps}/bin/pgrep -x keepassxc >/dev/null 2>&1; then
            echo "Save and close KeePassXC before copying its database." >&2
            return 1
          fi
          for scope in ${scopeWords}; do
            if ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_ROOT/$scope" >/dev/null 2>&1; then
              echo "$scope is unlocked; close it before copying ciphertext." >&2
              return 1
            fi
          done
        }

        select_disk() {
          local selector="''${1:-}" label device
          local -a devices=()
          if [ -n "$selector" ]; then
            case "$selector" in
              pino-data-*) label="$selector" ;;
              *) label="pino-data-$selector" ;;
            esac
            mapfile -t devices < <(
              ${pkgs.util-linux}/bin/lsblk -rpn -o NAME,LABEL,FSTYPE \
                | ${pkgs.gawk}/bin/awk -v label="$label" '$2 == label && $3 == "exfat" { print $1 }'
            )
          else
            mapfile -t devices < <(
              ${pkgs.util-linux}/bin/lsblk -rpn -o NAME,LABEL,FSTYPE \
                | ${pkgs.gawk}/bin/awk '$2 ~ /^pino-data-/ && $3 == "exfat" { print $1 }'
            )
          fi
          case "''${#devices[@]}" in
            1) DATA_DEVICE="''${devices[0]}" ;;
            0) echo "No connected ''${label:-pino-data-*} exFAT disk was found." >&2; return 1 ;;
            *)
              echo "Several pino-data disks are connected; specify a label or suffix:" >&2
              for device in "''${devices[@]}"; do
                ${pkgs.util-linux}/bin/lsblk -dno PATH,LABEL "$device" >&2
              done
              return 1
              ;;
          esac
        }

        mount_disk() {
          local mode="$1" existing uid gid options
          existing="$(${pkgs.util-linux}/bin/findmnt -rn -S "$DATA_DEVICE" -o TARGET | ${pkgs.coreutils}/bin/head -n 1 || true)"
          if [ -n "$existing" ]; then
            MOUNT_POINT="$existing"
            if [ "$mode" = rw ] && ! ${pkgs.util-linux}/bin/findmnt -rn -S "$DATA_DEVICE" -o OPTIONS | ${pkgs.gnugrep}/bin/grep -qw rw; then
              echo "$DATA_DEVICE is mounted read-only at $MOUNT_POINT." >&2
              return 1
            fi
            return
          fi
          MOUNT_POINT="$(sudo ${pkgs.coreutils}/bin/mktemp -d /run/pino-portable-backup.XXXXXX)"
          uid="$(${pkgs.coreutils}/bin/id -u)"
          gid="$(${pkgs.coreutils}/bin/id -g)"
          options="$mode,nodev,nosuid,noexec,uid=$uid,gid=$gid,umask=0077"
          sudo ${pkgs.util-linux}/bin/mount -o "$options" "$DATA_DEVICE" "$MOUNT_POINT"
          MOUNTED=true
        }

        backup_run() {
          local root incoming bundle_tmp scope
          require_closed
          select_disk "''${1:-}"
          mount_disk rw
          root="$MOUNT_POINT/pino/portable-backup"
          incoming="$root/incoming"
          sudo ${pkgs.coreutils}/bin/rm -rf "$incoming"
          sudo ${pkgs.coreutils}/bin/mkdir -p "$incoming/identity" "$incoming/encrypted"
          if [ -d "$IDENTITY_ROOT" ]; then
            sudo ${pkgs.rsync}/bin/rsync -rt --delete --exclude='.stversions/' \
              "$IDENTITY_ROOT/" "$incoming/identity/"
          fi
          for scope in "''${BACKUP_SCOPES[@]}"; do
            [ -d "$CIPHER_ROOT/$scope" ] || continue
            sudo ${pkgs.coreutils}/bin/mkdir -p "$incoming/encrypted/$scope"
            sudo ${pkgs.rsync}/bin/rsync -rt --delete --exclude='.stversions/' \
              "$CIPHER_ROOT/$scope/" "$incoming/encrypted/$scope/"
          done
          bundle_tmp="$(${pkgs.coreutils}/bin/mktemp /tmp/pino-config-bundle.XXXXXX)"
          if ${pkgs.git}/bin/git -C ${lib.escapeShellArg config.pino.configDir} \
            bundle create "$bundle_tmp" --all; then
            sudo ${pkgs.coreutils}/bin/mv "$bundle_tmp" "$incoming/nixos-config.bundle"
          else
            ${pkgs.coreutils}/bin/rm -f "$bundle_tmp"
            return 1
          fi
          sudo ${pkgs.coreutils}/bin/rm -rf "$root/previous"
          if [ -d "$root/current" ]; then
            sudo ${pkgs.coreutils}/bin/mv "$root/current" "$root/previous"
          fi
          sudo ${pkgs.coreutils}/bin/mv "$incoming" "$root/current"
          sudo ${pkgs.coreutils}/bin/sync -f "$root"
          echo "Portable backup completed on $DATA_DEVICE (current + previous)."
        }

        backup_list() {
          local root generation
          select_disk "''${1:-}"
          mount_disk ro
          root="$MOUNT_POINT/pino/portable-backup"
          printf '%-10s %-20s %s\n' GENERATION IDENTITY ENCRYPTED
          for generation in current previous; do
            [ -d "$root/$generation" ] || continue
            printf '%-10s %-20s %s\n' "$generation" \
              "$(${pkgs.findutils}/bin/find "$root/$generation/identity" -maxdepth 1 -type f -name '*.kdbx' 2>/dev/null | ${pkgs.coreutils}/bin/wc -l) KDBX" \
              "$(${pkgs.findutils}/bin/find "$root/$generation/encrypted" -mindepth 1 -name gocryptfs.conf 2>/dev/null | ${pkgs.coreutils}/bin/wc -l) vaults"
          done
        }

        backup_restore() {
          local selector generation source confirmation
          if [ -n "''${3:-}" ]; then
            selector="$2"
            generation="$3"
          else
            selector=""
            generation="''${2:-}"
          fi
          case "$generation" in current|previous) ;; *) echo "Usage: pino vault backup restore [disk] <current|previous>" >&2; return 1 ;; esac
          require_closed
          select_disk "$selector"
          mount_disk ro
          source="$MOUNT_POINT/pino/portable-backup/$generation"
          [ -d "$source" ] || {
            echo "No $generation portable generation exists on $DATA_DEVICE." >&2
            return 1
          }
          echo "This replaces local encrypted identity and secret-vault ciphertext."
          echo "A later push is required before this restored state reaches Mosk."
          read -r -p "Type 'restore $generation' to continue: " confirmation
          [ "$confirmation" = "restore $generation" ] || {
            echo "Restore cancelled."
            return 1
          }
          sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o "$PINO_USER" -g users \
            "$IDENTITY_ROOT" "$CIPHER_ROOT"
          sudo ${pkgs.rsync}/bin/rsync -rt --delete --chown="$PINO_USER:users" \
            --chmod=D0700,F0600 \
            "$source/identity/" "$IDENTITY_ROOT/"
          sudo ${pkgs.rsync}/bin/rsync -rt --delete --chown="$PINO_USER:users" \
            --chmod=D0700,F0600 \
            "$source/encrypted/" "$CIPHER_ROOT/"
          echo "Restored $generation. Inspect locally, then pull before any later push."
          if [ -f "$source/nixos-config.bundle" ]; then
            echo "Configuration bundle retained on the disk; the working checkout was not overwritten."
          fi
        }

        case "''${1:-}" in
          create) backup_run "''${2:-}" ;;
          list) backup_list "''${2:-}" ;;
          restore) backup_restore "$@" ;;
          *) echo "Run 'pino vault backup help' for usage." >&2; exit 1 ;;
        esac
      '';
    };

    pino.subcommands.vault.commands.secrets = {
      description = "Open and stage client-encrypted secret vaults";
      commands = {
        status.description = "Show gocryptfs, legacy, and mount state";
        init = { description = "Initialize a new gocryptfs scope"; usage = "<scope>"; };
        open = { description = "Unlock and mount one gocryptfs scope"; usage = "<scope>"; };
        close = { description = "Unmount one or every gocryptfs scope"; usage = "<scope|all>"; };
        legacy-open = { description = "Temporarily open Cryptomator for migration"; usage = "[scope]"; };
        migrate = { description = "Verified copy from an unlocked legacy vault"; usage = "<scope>"; };
        populate.description = "Stage only this host's unlocked runtime secrets";
        storage-init = { description = "Generate WebDAV credentials inside a host vault"; usage = "<server-host>"; };
      };
      helpText = ''
        Secret scopes are gocryptfs vaults mounted by Pino without a GUI. Keep a
        separate password per scope in infra.kdbx. DroidFS opens the same format
        on Android. `migrate` copies and verifies plaintext from an unlocked
        Cryptomator vault but never removes its legacy ciphertext.

        `shared_sec` is for documents and recovery material. Runtime system
        configuration is accepted only from `hosts/<hostname>`.
      '';
      script = ''
        set -euo pipefail
        CIPHER_ROOT=${lib.escapeShellArg cfg.cipherRoot}
        LEGACY_ROOT=${lib.escapeShellArg cfg.legacyCipherRoot}
        MOUNT_ROOT=${lib.escapeShellArg cfg.mountRoot}
        CONFIGURED_SCOPES=( ${scopeWords} )

        valid_scope() {
          case "$1" in
            ""|/*|*..*|*[!A-Za-z0-9_./-]*) return 1 ;;
            *) return 0 ;;
          esac
        }

        selected_scopes() {
          local requested="''${1:-all}"
          local configured
          if [ "$requested" = shared ]; then
            echo "shared is a plaintext transport folder, not a protected secret scope." >&2
            return 1
          fi
          if [ "$requested" = all ]; then
            printf '%s\n' "''${CONFIGURED_SCOPES[@]}"
            return
          fi
          valid_scope "$requested" || {
            echo "Invalid secret scope: $requested" >&2
            return 1
          }
          for configured in "''${CONFIGURED_SCOPES[@]}"; do
            if [ "$configured" = "$requested" ]; then
              printf '%s\n' "$requested"
              return
            fi
          done
          echo "This client has no configured access to $requested" >&2
          return 1
        }

        is_mounted() {
          ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_ROOT/$1" >/dev/null 2>&1
        }

        close_scope() {
          local scope="$1"
          if ! is_mounted "$scope"; then
            echo "$scope is already closed."
            return
          fi
          ${pkgs.fuse3}/bin/fusermount3 -u "$MOUNT_ROOT/$scope"
          echo "Closed $scope."
        }

        case "''${1:-}" in
          status)
            printf '%-24s %-12s %-12s %-12s\n' SCOPE FORMAT LEGACY MOUNT
            for scope in "''${CONFIGURED_SCOPES[@]}"; do
              if [ -f "$CIPHER_ROOT/$scope/gocryptfs.conf" ]; then format=gocryptfs; else format=missing; fi
              if [ -f "$LEGACY_ROOT/$scope/vault.cryptomator" ]; then legacy=cryptomator; else legacy=none; fi
              if is_mounted "$scope"; then mount=unlocked; else mount=locked; fi
              printf '%-24s %-12s %-12s %-12s\n' "$scope" "$format" "$legacy" "$mount"
            done
            ;;
          init)
            scope="''${2:-}"
            selected_scopes "$scope" >/dev/null
            cipher="$CIPHER_ROOT/$scope"
            [ ! -f "$cipher/gocryptfs.conf" ] || {
              echo "$scope is already initialized." >&2
              exit 1
            }
            if ${pkgs.findutils}/bin/find "$cipher" -mindepth 1 -print -quit | ${pkgs.gnugrep}/bin/grep -q .; then
              echo "Refusing to initialize non-empty ciphertext directory: $cipher" >&2
              exit 1
            fi
            echo "Create the gocryptfs password for $scope. Keep it in infra.kdbx."
            ${pkgs.gocryptfs}/bin/gocryptfs -init -- "$cipher"
            echo "Initialized $scope. Open it with: pino vault secrets open $scope"
            ;;
          open)
            scope="''${2:-}"
            selected_scopes "$scope" >/dev/null
            [ -f "$CIPHER_ROOT/$scope/gocryptfs.conf" ] || {
              echo "$scope is not a gocryptfs vault yet." >&2
              if [ -f "$LEGACY_ROOT/$scope/vault.cryptomator" ]; then
                echo "Migrate it first; run 'pino vault secrets help' for the sequence." >&2
              else
                echo "Run: pino vault secrets init $scope" >&2
              fi
              exit 1
            }
            if is_mounted "$scope"; then
              echo "$scope is already open at $MOUNT_ROOT/$scope"
              exit 0
            fi
            if ${pkgs.findutils}/bin/find "$MOUNT_ROOT/$scope" -mindepth 1 -print -quit | ${pkgs.gnugrep}/bin/grep -q .; then
              echo "Refusing to mount over non-empty directory: $MOUNT_ROOT/$scope" >&2
              exit 1
            fi
            ${pkgs.gocryptfs}/bin/gocryptfs -q -idle 30m -- \
              "$CIPHER_ROOT/$scope" "$MOUNT_ROOT/$scope"
            is_mounted "$scope" || { echo "gocryptfs did not mount $scope." >&2; exit 1; }
            echo "Opened $scope at $MOUNT_ROOT/$scope; idle timeout is 30 minutes."
            ;;
          close)
            mapfile -t scopes < <(selected_scopes "''${2:-}")
            for scope in "''${scopes[@]}"; do close_scope "$scope"; done
            ;;
          legacy-open)
            scope="''${2:-}"
            if [ -n "$scope" ]; then
              selected_scopes "$scope" >/dev/null
              [ -f "$LEGACY_ROOT/$scope/vault.cryptomator" ] || {
                echo "No legacy Cryptomator vault exists for $scope." >&2
                exit 1
              }
              echo "Unlock $scope in Cryptomator at $MOUNT_ROOT/$scope."
            fi
            if ${pkgs.systemd}/bin/systemctl --user is-active --quiet cryptomator-legacy.service \
              || ${pkgs.systemd}/bin/systemctl --user is-active --quiet cryptomator.service; then
              echo "Cryptomator is already running."
            else
              ${pkgs.systemd}/bin/systemctl --user start cryptomator-legacy.service
            fi
            ;;
          migrate)
            scope="''${2:-}"
            selected_scopes "$scope" >/dev/null
            legacy="$LEGACY_ROOT/$scope"
            source="$MOUNT_ROOT/$scope"
            cipher="$CIPHER_ROOT/$scope"
            [ -f "$legacy/vault.cryptomator" ] || {
              echo "No legacy Cryptomator ciphertext exists for $scope." >&2
              exit 1
            }
            is_mounted "$scope" || {
              echo "Unlock the legacy $scope vault at $source first." >&2
              echo "Run: pino vault secrets legacy-open $scope" >&2
              exit 1
            }
            mount_type="$(${pkgs.util-linux}/bin/findmnt -rn -T "$source" -o FSTYPE)"
            case "$mount_type" in
              *gocryptfs*) echo "$scope is already mounted as gocryptfs, not legacy Cryptomator." >&2; exit 1 ;;
            esac
            echo "This copies the unlocked legacy $scope contents into gocryptfs."
            echo "The old Cryptomator ciphertext remains untouched at $legacy."
            read -r -p "Type 'migrate $scope' to continue: " confirmation
            [ "$confirmation" = "migrate $scope" ] || { echo "Migration cancelled."; exit 0; }
            if [ ! -f "$cipher/gocryptfs.conf" ]; then
              if ${pkgs.findutils}/bin/find "$cipher" -mindepth 1 -print -quit | ${pkgs.gnugrep}/bin/grep -q .; then
                echo "New ciphertext directory is non-empty but uninitialized: $cipher" >&2
                exit 1
              fi
              echo "Create the replacement gocryptfs password for $scope."
              ${pkgs.gocryptfs}/bin/gocryptfs -init -- "$cipher"
            fi
            migration_mount="$(${pkgs.coreutils}/bin/mktemp -d \
              "''${XDG_RUNTIME_DIR:-/run/user/$UID}/pino-gocryptfs-migrate.XXXXXX")"
            verification="$(${pkgs.coreutils}/bin/mktemp \
              "''${XDG_RUNTIME_DIR:-/run/user/$UID}/pino-gocryptfs-verify.XXXXXX")"
            cleanup_migration() {
              if ${pkgs.util-linux}/bin/findmnt --mountpoint "$migration_mount" >/dev/null 2>&1; then
                ${pkgs.fuse3}/bin/fusermount3 -u "$migration_mount" || true
              fi
              ${pkgs.coreutils}/bin/rm -rf "$migration_mount"
              ${pkgs.coreutils}/bin/rm -f "$verification"
            }
            trap cleanup_migration EXIT INT TERM
            echo "Unlock the replacement gocryptfs vault."
            ${pkgs.gocryptfs}/bin/gocryptfs -q -- "$cipher" "$migration_mount"
            ${pkgs.rsync}/bin/rsync -a --delete "$source/" "$migration_mount/"
            ${pkgs.rsync}/bin/rsync -rcl --delete --dry-run --itemize-changes \
              "$source/" "$migration_mount/" > "$verification"
            [ ! -s "$verification" ] || {
              echo "Migration verification failed; legacy ciphertext was not modified." >&2
              exit 1
            }
            file_count="$(${pkgs.findutils}/bin/find "$source" -type f | ${pkgs.coreutils}/bin/wc -l)"
            cleanup_migration
            trap - EXIT INT TERM
            echo "Migrated and verified $file_count files for $scope."
            echo "Lock the legacy vault, then run: pino vault push $scope"
            ;;
          populate)
            host_scope="hosts/${config.networking.hostName}"
            source="$MOUNT_ROOT/$host_scope"
            target=${lib.escapeShellArg config.pino.secrets.provisionedDir}
            ${pkgs.util-linux}/bin/findmnt --mountpoint "$source" >/dev/null 2>&1 || {
              echo "Open $host_scope at $source first." >&2
              exit 1
            }
            staging="$(${pkgs.coreutils}/bin/mktemp -d "''${XDG_RUNTIME_DIR:-/run/user/$UID}/pino-populate.XXXXXX")"
            cleanup_populate() {
              ${pkgs.coreutils}/bin/rm -rf "$staging"
            }
            trap cleanup_populate EXIT INT TERM
            ${pkgs.rsync}/bin/rsync -a --delete "$source/" "$staging/"
            sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root "$target"
            sudo ${pkgs.rsync}/bin/rsync -a --delete "$staging/" "$target/"
            sudo ${pkgs.findutils}/bin/find "$target" -type d -exec ${pkgs.coreutils}/bin/chmod 0700 {} +
            sudo ${pkgs.findutils}/bin/find "$target" -type f -exec ${pkgs.coreutils}/bin/chmod 0600 {} +
            cleanup_populate
            trap - EXIT INT TERM
            sudo /run/current-system/sw/bin/pino-secrets-deploy --restart
            echo "Runtime secrets populated and deployed from $host_scope."
            ;;
          storage-init)
            server_host="''${2:-}"
            valid_scope "$server_host" || {
              echo "Usage: pino vault secrets storage-init <server-host>" >&2
              exit 1
            }
            host_root="$MOUNT_ROOT/hosts/$server_host"
            ${pkgs.util-linux}/bin/findmnt --mountpoint "$host_root" >/dev/null 2>&1 || {
              echo "Open hosts/$server_host at $host_root first." >&2
              exit 1
            }
            credential="$host_root/server/storage-webdav.env"
            if [ -e "$credential" ]; then
              echo "Credentials already exist for $server_host; refusing to replace them." >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/install -d -m 0700 "$host_root/server"
            umask 077
            {
              printf '%s\n' 'PINO_WEBDAV_USER=pino'
              printf 'PINO_WEBDAV_PASSWORD=%s\n' "$(${pkgs.openssl}/bin/openssl rand -base64 36 | ${pkgs.coreutils}/bin/tr -d '\n')"
            } > "$credential"
            echo "Generated $credential without displaying its contents."
            ;;
          *) echo "Run 'pino vault secrets help' for usage." >&2; exit 1 ;;
        esac
      '';
    };
  };
}
