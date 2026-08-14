{ config, lib, pkgs, ... }:

let
  cfg = config.pino.portableVaults;
  user = config.pino.user.name;
  home = config.pino.user.home;
  primary = cfg.remotes.${cfg.primary};
  effectiveScopes = lib.unique (
    cfg.scopes
    ++ [ "shared_sec" ]
    ++ (if cfg.trustedClient
        then map (host: "hosts/${host}") config.pino.secrets.knownHosts
        else [ "hosts/${config.networking.hostName}" ])
  );
  cryptomatorScopes = [ "shared" ] ++ effectiveScopes;
  scopeId = scope: "pino-${builtins.substring 0 12 (builtins.hashString "sha256" scope)}";
  syncFolderId = scope: "pino-secret-${lib.replaceStrings [ "/" ] [ "-" ] scope}";
  cryptomatorEntry = scope: {
    id = scopeId scope;
    path = "${cfg.cipherRoot}/${scope}";
    displayName = lib.last (lib.splitString "/" scope);
    unlockAfterStartup = scope == "shared";
    revealAfterMount = false;
    usesReadOnlyMode = false;
    mountFlags = "";
    maxCleartextFilenameLength = -1;
    actionAfterUnlock = "ASK";
    autoLockWhenIdle = scope != "shared";
    autoLockIdleSeconds = 1800;
    mountPoint = "${cfg.mountRoot}/${scope}";
    port = 42427;
  };
  declaredCryptomatorEntries = map cryptomatorEntry cryptomatorScopes;
  collectCryptomatorEntries = lib.concatMapStringsSep "\n" (entry: ''
    if [ -f ${lib.escapeShellArg "${entry.path}/vault.cryptomator"} ]; then
      declared="$(${pkgs.jq}/bin/jq -c \
        --argjson entry ${lib.escapeShellArg (builtins.toJSON entry)} \
        '. + [$entry]' <<< "$declared")"
    fi
  '') declaredCryptomatorEntries;
  cryptomatorSettings = "${home}/.config/Cryptomator/settings.json";
  reconcileCryptomator = pkgs.writeShellScript "pino-cryptomator-reconcile" ''
    set -euo pipefail
    settings=${lib.escapeShellArg cryptomatorSettings}
    settings_dir="$(${pkgs.coreutils}/bin/dirname "$settings")"
    ${pkgs.coreutils}/bin/mkdir -p "$settings_dir"
    ${pkgs.coreutils}/bin/chmod 0700 "$settings_dir"

    if [ -s "$settings" ]; then
      ${pkgs.jq}/bin/jq empty "$settings" || {
        echo "Refusing to replace invalid Cryptomator settings: $settings" >&2
        exit 1
      }
      source="$settings"
    else
      source="$(${pkgs.coreutils}/bin/mktemp "$settings_dir/settings.empty.XXXXXX")"
      printf '{}\n' > "$source"
    fi

    temporary="$(${pkgs.coreutils}/bin/mktemp "$settings_dir/settings.new.XXXXXX")"
    cleanup_reconcile() {
      [ "$source" = "$settings" ] || ${pkgs.coreutils}/bin/rm -f "$source"
      ${pkgs.coreutils}/bin/rm -f "$temporary"
    }
    trap cleanup_reconcile EXIT INT TERM
    declared='[]'
    ${collectCryptomatorEntries}
    ${pkgs.jq}/bin/jq \
      --argjson declared "$declared" \
      --arg keychainProvider org.cryptomator.linux.keychain.GnomeKeyringKeychainAccess \
      '
        .directories = (
          ((.directories // [])
            | map(. as $existing
              | select($declared
                | any(.id == $existing.id or .path == $existing.path)
                | not)))
          + $declared
        )
        | .startHidden = true
        | .useKeychain = true
        | .keychainProvider = $keychainProvider
      ' "$source" > "$temporary"
    ${pkgs.coreutils}/bin/chmod 0600 "$temporary"
    ${pkgs.coreutils}/bin/mv -f "$temporary" "$settings"
    trap - EXIT INT TERM
    [ "$source" = "$settings" ] || ${pkgs.coreutils}/bin/rm -f "$source"
  '';
  clientSyncDevices =
    lib.optional (config.pino.vault.sync.serverId != null) config.pino.vault.sync.serverName
    ++ builtins.attrNames config.pino.vault.sync.mirrors;
  secretSyncFolders = lib.listToAttrs (map (scope: {
    name = syncFolderId scope;
    value = {
      label = "Pino encrypted ${scope}";
      path = "${cfg.cipherRoot}/${scope}";
      devices = clientSyncDevices;
      versioning = {
        type = "simple";
        params.keep = "2";
      };
    };
  }) effectiveScopes);
  scopeWords = lib.concatStringsSep " " (map lib.escapeShellArg effectiveScopes);
  cryptomatorScopeWords = lib.concatStringsSep " " (map lib.escapeShellArg cryptomatorScopes);
in
{
  options.pino.portableVaults = {
    enable = lib.mkEnableOption "portable client-encrypted Pino vaults" // { default = true; };
    cipherRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/share/pino/encrypted";
      description = "Local Cryptomator ciphertext root";
    };
    mountRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Secrets";
      description = "Parent directory for unlocked Cryptomator vaults";
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
          shareUrl = "https://share.egrapa.com";
        };
      };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          sshHost = lib.mkOption { type = lib.types.str; };
          path = lib.mkOption { type = lib.types.str; default = "/var/lib/pino/storage"; };
          webdavUrl = lib.mkOption { type = lib.types.str; };
          shareUrl = lib.mkOption { type = lib.types.str; };
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
    ];

    environment.systemPackages = [
      pkgs.cryptomator
      pkgs.fuse3
      pkgs.jq
      pkgs.openssh
      pkgs.rsync
    ];

    environment.etc."cryptomator/config.properties".text = ''
      cryptomator.mountPointsDir=${cfg.mountRoot}
    '';

    systemd.tmpfiles.rules = [
      "d ${home}/.local/share/pino 0700 ${user} users -"
      "d ${home}/.local/state/pino 0700 ${user} users -"
      "d ${cfg.cipherRoot} 0700 ${user} users -"
      "d ${cfg.mountRoot} 0700 ${user} users -"
      "d ${home}/.local/state/pino/secrets 0700 ${user} users -"
      "L+ /run/pino-secrets - - - - ${cfg.mountRoot}"
    ] ++ lib.concatMap (scope: [
      "d ${cfg.cipherRoot}/${scope} 0700 ${user} users -"
      "d ${cfg.mountRoot}/${scope} 0700 ${user} users -"
    ]) cryptomatorScopes;

    services.syncthing.settings.folders = lib.mkIf
      ((config.pino.vault.sync.serverId != null) || (config.pino.vault.sync.mirrors != { })) ({
        share = {
          label = "Pino temporary encrypted share";
          path = "${cfg.cipherRoot}/shared";
          devices =
            lib.optional (config.pino.vault.sync.serverId != null) config.pino.vault.sync.serverName
            ++ builtins.attrNames config.pino.vault.sync.mirrors;
        };
      } // secretSyncFolders);

    home-manager.users.${user}.systemd.user.services.cryptomator = {
      Unit = {
        Description = "Cryptomator declarative vaults";
        After = [ "keepassxc-identity.service" ];
        Wants = [ "keepassxc-identity.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = reconcileCryptomator;
        ExecStart = "${pkgs.cryptomator}/bin/cryptomator";
        Restart = "no";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    pino.subcommands.vault.commands.share = {
      description = "Open the temporary client-encrypted file exchange";
      commands = {
        init.description = "Prepare the local encrypted share and open Cryptomator";
        open.description = "Open the encrypted share in Cryptomator";
        status.description = "Show local transport and Android WebDAV information";
      };
      helpText = ''
        Share is a disposable Cryptomator vault transported as ciphertext by
        Syncthing. It has no versioned or external backup policy. Enable
        password storage in the desktop keyring after its first unlock.
      '';
      script = ''
        CIPHER_ROOT=${lib.escapeShellArg cfg.cipherRoot}
        MOUNT_ROOT=${lib.escapeShellArg cfg.mountRoot}
        case "''${1:-}" in
          init)
            ${pkgs.coreutils}/bin/mkdir -p "$CIPHER_ROOT/shared" "$MOUNT_ROOT/shared"
            echo "Create a Cryptomator vault in $CIPHER_ROOT/shared."
            echo "Use the declared mount point $MOUNT_ROOT/shared."
            echo "After unlocking it, store its password through KeePassXC Secret Service."
            ${pkgs.systemd}/bin/systemctl --user start cryptomator.service
            ;;
          open)
            [ -f "$CIPHER_ROOT/shared/vault.cryptomator" ] || {
              echo "The shared vault has not been created yet." >&2
              echo "Run: pino vault share init" >&2
              exit 1
            }
            echo "Unlock shared in Cryptomator; it mounts at $MOUNT_ROOT/shared"
            ${pkgs.systemd}/bin/systemctl --user start cryptomator.service
            ;;
          status)
            if [ -f "$CIPHER_ROOT/shared/vault.cryptomator" ]; then cipher=ready; else cipher=missing; fi
            if ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_ROOT/shared" >/dev/null 2>&1; then mount=unlocked; else mount=locked; fi
            echo "Share: $cipher, $mount"
            echo "Ciphertext: $CIPHER_ROOT/shared"
            echo "Android shared_sec: ${primary.webdavUrl}/shared_sec (read-only)"
            echo "Android live share: ${primary.shareUrl}"
            systemctl status syncthing.service --no-pager
            ;;
          *) echo "Run 'pino vault share help' for usage." >&2; exit 1 ;;
        esac
      '';
    };

    pino.subcommands.vault.commands.backup = {
      description = "Back up encrypted identity, secrets, and configuration offline";
      commands = {
        create = { description = "Write current and previous portable copies to a pino-data disk"; usage = "[disk-id]"; };
        list = { description = "List portable generations on a pino-data disk"; usage = "[disk-id]"; };
        restore = { description = "Replace local encrypted state from an offline generation"; usage = "[disk-id] <current|previous>"; };
        resume.description = "Resume Syncthing after inspecting a restored generation";
      };
      helpText = ''
        The backup contains only ciphertext, the encrypted KeePass database,
        and a public Git bundle. The disposable `shared` vault is excluded.
        The target keeps exactly current and previous generations.

        Restore deliberately leaves Syncthing stopped. Inspect the restored
        databases and vaults, then run `pino vault backup resume` to synchronize.
      '';
      script = ''
        CIPHER_ROOT=${lib.escapeShellArg cfg.cipherRoot}
        IDENTITY_ROOT=${lib.escapeShellArg "${home}/.local/share/pino/identity"}
        MOUNT_ROOT=${lib.escapeShellArg cfg.mountRoot}
        PINO_USER=${lib.escapeShellArg user}
        MOUNTED=false
        MOUNT_POINT=
        DATA_DEVICE=
        RESTART_SYNC=false

        cleanup_backup() {
          if [ "$MOUNTED" = true ]; then
            sudo ${pkgs.util-linux}/bin/umount "$MOUNT_POINT" || true
            sudo ${pkgs.coreutils}/bin/rmdir "$MOUNT_POINT" || true
            MOUNTED=false
          fi
          if [ "$RESTART_SYNC" = true ]; then
            sudo ${pkgs.systemd}/bin/systemctl start syncthing.service || true
            RESTART_SYNC=false
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
              echo "$scope is unlocked; lock it in Cryptomator first." >&2
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

        stop_sync() {
          if ${pkgs.systemd}/bin/systemctl is-active --quiet syncthing.service; then
            sudo ${pkgs.systemd}/bin/systemctl stop syncthing.service
            RESTART_SYNC=true
          fi
        }

        backup_run() {
          local root incoming bundle_tmp
          require_closed
          select_disk "''${1:-}"
          mount_disk rw
          stop_sync
          root="$MOUNT_POINT/pino/portable-backup"
          incoming="$root/incoming"
          sudo ${pkgs.coreutils}/bin/rm -rf "$incoming"
          sudo ${pkgs.coreutils}/bin/mkdir -p "$incoming/identity" "$incoming/encrypted"
          if [ -d "$IDENTITY_ROOT" ]; then
            sudo ${pkgs.rsync}/bin/rsync -rt --delete --exclude='.stversions/' \
              "$IDENTITY_ROOT/" "$incoming/identity/"
          fi
          sudo ${pkgs.rsync}/bin/rsync -rt --delete \
            --exclude='/shared/' --exclude='.stversions/' \
            "$CIPHER_ROOT/" "$incoming/encrypted/"
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
              "$(${pkgs.findutils}/bin/find "$root/$generation/encrypted" -mindepth 1 -maxdepth 2 -name vault.cryptomator 2>/dev/null | ${pkgs.coreutils}/bin/wc -l) vaults"
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
          echo "Syncthing will remain stopped until 'pino vault backup resume'."
          read -r -p "Type 'restore $generation' to continue: " confirmation
          [ "$confirmation" = "restore $generation" ] || {
            echo "Restore cancelled."
            return 1
          }
          stop_sync
          sudo ${pkgs.coreutils}/bin/install -d -m 0700 -o "$PINO_USER" -g users \
            "$IDENTITY_ROOT" "$CIPHER_ROOT"
          sudo ${pkgs.rsync}/bin/rsync -rt --delete --chown="$PINO_USER:users" \
            --chmod=D0700,F0600 \
            "$source/identity/" "$IDENTITY_ROOT/"
          sudo ${pkgs.rsync}/bin/rsync -rt --delete --chown="$PINO_USER:users" \
            --chmod=D0700,F0600 \
            "$source/encrypted/" "$CIPHER_ROOT/"
          RESTART_SYNC=false
          echo "Restored $generation. Inspect locally before running: pino vault backup resume"
          if [ -f "$source/nixos-config.bundle" ]; then
            echo "Configuration bundle retained on the disk; the working checkout was not overwritten."
          fi
        }

        case "''${1:-}" in
          create) backup_run "''${2:-}" ;;
          list) backup_list "''${2:-}" ;;
          restore) backup_restore "$@" ;;
          resume) sudo ${pkgs.systemd}/bin/systemctl start syncthing.service ;;
          *) echo "Run 'pino vault backup help' for usage." >&2; exit 1 ;;
        esac
      '';
    };

    pino.subcommands.vault.commands.secrets = {
      description = "Open and stage client-encrypted secret vaults";
      commands = {
        status.description = "Show declared vault and Syncthing state";
        init = { description = "Prepare a scope and open Cryptomator to create it"; usage = "<scope>"; };
        open = { description = "Open Cryptomator for the configured secret vaults"; usage = "[scope]"; };
        reconcile.description = "Reconcile existing vaults into Cryptomator settings";
        populate.description = "Stage only this host's unlocked runtime secrets";
        storage-init = { description = "Generate WebDAV credentials inside a host vault"; usage = "<server-host>"; };
      };
      helpText = ''
        Secret scopes are Cryptomator vaults. Syncthing transports ciphertext
        only; the server never receives a vault password. Do not edit the same
        secret scope concurrently on two clients.

        `shared_sec` is for documents and recovery material. Runtime system
        configuration is accepted only from `hosts/<hostname>`.
      '';
      script = ''
        CIPHER_ROOT=${lib.escapeShellArg cfg.cipherRoot}
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
            echo "The disposable shared vault is managed by 'pino vault share'." >&2
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

        case "''${1:-}" in
          status)
            printf '%-24s %-12s %-12s\n' SCOPE CIPHERTEXT MOUNT
            for scope in "''${CONFIGURED_SCOPES[@]}"; do
              if [ -f "$CIPHER_ROOT/$scope/vault.cryptomator" ]; then cipher=ready; else cipher=missing; fi
              if ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_ROOT/$scope" >/dev/null 2>&1; then mount=unlocked; else mount=locked; fi
              printf '%-24s %-12s %-12s\n' "$scope" "$cipher" "$mount"
            done
            ;;
          init)
            scope="''${2:-}"
            selected_scopes "$scope" >/dev/null
            ${pkgs.coreutils}/bin/mkdir -p "$CIPHER_ROOT/$scope" "$MOUNT_ROOT/$scope"
            echo "Create the Cryptomator vault at: $CIPHER_ROOT/$scope"
            echo "Its declared mount point is: $MOUNT_ROOT/$scope"
            ${pkgs.systemd}/bin/systemctl --user start cryptomator.service
            ;;
          open)
            if [ -n "''${2:-}" ]; then
              selected_scopes "$2" >/dev/null
              [ -f "$CIPHER_ROOT/$2/vault.cryptomator" ] || {
                echo "The $2 vault has not been created yet." >&2
                echo "Run: pino vault secrets init $2" >&2
                exit 1
              }
              echo "Unlock $2 in Cryptomator; it mounts at $MOUNT_ROOT/$2"
            fi
            ${pkgs.systemd}/bin/systemctl --user start cryptomator.service
            ;;
          reconcile)
            if ${pkgs.systemd}/bin/systemctl --user is-active --quiet cryptomator.service; then
              for scope in ${cryptomatorScopeWords}; do
                if ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_ROOT/$scope" >/dev/null 2>&1; then
                  echo "$scope is unlocked; lock it before reconciling settings." >&2
                  exit 1
                fi
              done
              ${pkgs.systemd}/bin/systemctl --user stop cryptomator.service
            fi
            ${reconcileCryptomator}
            ${pkgs.systemd}/bin/systemctl --user start cryptomator.service
            echo "Cryptomator settings reconciled and reloaded."
            ;;
          populate)
            host_scope="hosts/${config.networking.hostName}"
            source="$MOUNT_ROOT/$host_scope"
            target=${lib.escapeShellArg config.pino.secrets.provisionedDir}
            ${pkgs.util-linux}/bin/findmnt --mountpoint "$source" >/dev/null 2>&1 || {
              echo "Unlock $host_scope in Cryptomator at $source first." >&2
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
              echo "Unlock hosts/$server_host in Cryptomator at $host_root first." >&2
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
