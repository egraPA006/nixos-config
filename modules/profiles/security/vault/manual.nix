{ config, lib, pkgs, ... }:

let
  cfg = config.pino.portableVaults;
  user = config.pino.user.name;
  home = config.pino.user.home;
  identityRoot = "${home}/.local/share/pino/identity";
  effectiveScopes = lib.unique (
    cfg.scopes
    ++ [ "shared_sec" ]
    ++ (if cfg.trustedClient
        then map (host: "hosts/${host}") config.pino.secrets.knownHosts
        else [ "hosts/${config.networking.hostName}" ])
  );
  transferScopes = [ "identity" "shared" ] ++ effectiveScopes;
  transferScopeWords = lib.concatStringsSep " " (map lib.escapeShellArg transferScopes);
  manualTransferScript = ''
    set -euo pipefail
    CREDENTIAL_FILE=${lib.escapeShellArg cfg.manual.credentialFile}
    STATE_ROOT=${lib.escapeShellArg cfg.manual.stateRoot}
    IDENTITY_ROOT=${lib.escapeShellArg identityRoot}
    SHARE_ROOT=${lib.escapeShellArg cfg.shareRoot}
    CIPHER_ROOT=${lib.escapeShellArg cfg.cipherRoot}
    LEGACY_ROOT=${lib.escapeShellArg cfg.legacyCipherRoot}
    MOUNT_ROOT=${lib.escapeShellArg cfg.mountRoot}
    TARGET_MODE="''${TARGET_MODE:-current}"
    CONFIGURED_SCOPES=( ${transferScopeWords} )
    RCLONE_CONFIG_FILE=
    STAGING=

    cleanup_transfer() {
      [ -z "$RCLONE_CONFIG_FILE" ] || ${pkgs.coreutils}/bin/rm -f "$RCLONE_CONFIG_FILE"
      [ -z "$STAGING" ] || ${pkgs.coreutils}/bin/rm -rf "$STAGING"
    }
    trap cleanup_transfer EXIT INT TERM

    [ -r "$CREDENTIAL_FILE" ] || {
      echo "Manual vault credentials are not provisioned." >&2
      echo "Run: pino vault remote configure" >&2
      exit 1
    }
    # shellcheck disable=SC1090
    . "$CREDENTIAL_FILE"
    : "''${PINO_VAULT_USER:?PINO_VAULT_USER is missing}"
    : "''${PINO_VAULT_PASSWORD:?PINO_VAULT_PASSWORD is missing}"
    : "''${PINO_VAULT_CRYPT_PASSWORD:?PINO_VAULT_CRYPT_PASSWORD is missing}"
    : "''${PINO_VAULT_CRYPT_SALT:?PINO_VAULT_CRYPT_SALT is missing}"

    webdav_password="$(${pkgs.coreutils}/bin/printf '%s\n' "$PINO_VAULT_PASSWORD" \
      | ${pkgs.rclone}/bin/rclone obscure -)"
    crypt_password="$(${pkgs.coreutils}/bin/printf '%s\n' "$PINO_VAULT_CRYPT_PASSWORD" \
      | ${pkgs.rclone}/bin/rclone obscure -)"
    crypt_salt="$(${pkgs.coreutils}/bin/printf '%s\n' "$PINO_VAULT_CRYPT_SALT" \
      | ${pkgs.rclone}/bin/rclone obscure -)"
    RCLONE_CONFIG_FILE="$(${pkgs.coreutils}/bin/mktemp "''${XDG_RUNTIME_DIR:-/run/user/$UID}/pino-rclone.XXXXXX")"
    ${pkgs.coreutils}/bin/chmod 0600 "$RCLONE_CONFIG_FILE"
    {
      printf '%s\n' '[transport]' 'type = webdav'
      printf 'url = %s\n' ${lib.escapeShellArg cfg.manual.url}
      printf '%s\n' 'vendor = other'
      printf 'user = %s\n' "$PINO_VAULT_USER"
      printf 'pass = %s\n' "$webdav_password"
      printf '%s\n' '[vault]' 'type = crypt' 'remote = transport:'
      printf 'password = %s\n' "$crypt_password"
      printf 'password2 = %s\n' "$crypt_salt"
      printf '%s\n' 'filename_encryption = standard' 'directory_name_encryption = true'
    } > "$RCLONE_CONFIG_FILE"
    unset PINO_VAULT_PASSWORD PINO_VAULT_CRYPT_PASSWORD PINO_VAULT_CRYPT_SALT
    unset webdav_password crypt_password crypt_salt

    rclone_run() {
      ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG_FILE" "$@"
    }

    selected_scopes() {
      local scope
      if [ "$REQUESTED" = all ]; then
        printf '%s\n' "''${CONFIGURED_SCOPES[@]}"
        return
      fi
      for scope in "''${CONFIGURED_SCOPES[@]}"; do
        if [ "$scope" = "$REQUESTED" ]; then
          printf '%s\n' "$scope"
          return
        fi
      done
      echo "This client has no configured transfer scope: $REQUESTED" >&2
      return 1
    }

    local_path() {
      if [ "$TARGET_MODE" = legacy ]; then
        case "$1" in
          identity|shared)
            echo "Legacy pulls apply only to protected secret scopes." >&2
            return 1
            ;;
          *) printf '%s/%s\n' "$LEGACY_ROOT" "$1" ;;
        esac
        return
      fi
      case "$1" in
        identity) printf '%s\n' "$IDENTITY_ROOT" ;;
        shared) printf '%s\n' "$SHARE_ROOT" ;;
        *) printf '%s/%s\n' "$CIPHER_ROOT" "$1" ;;
      esac
    }

    require_closed() {
      local scope="$1"
      if [ "$scope" = identity ] && ${pkgs.procps}/bin/pgrep -x keepassxc >/dev/null 2>&1; then
        echo "Close KeePassXC before transferring identity." >&2
        return 1
      fi
      case "$scope" in
        identity|shared) ;;
        *)
          if ${pkgs.util-linux}/bin/findmnt --mountpoint "$MOUNT_ROOT/$scope" >/dev/null 2>&1; then
            echo "Close the $scope vault before transferring its ciphertext." >&2
            return 1
          fi
          ;;
      esac
    }

    scope_key() {
      printf '%s' "$1" | ${pkgs.gnused}/bin/sed 's|/|__|g'
    }

    remote_fingerprint() {
      local scope="$1" listing
      if ! rclone_run lsf "vault:" >/dev/null; then
        echo "Cannot access the encrypted remote; check its endpoint and provisioned credentials." >&2
        return 1
      fi
      listing="$(${pkgs.coreutils}/bin/mktemp "''${XDG_RUNTIME_DIR:-/run/user/$UID}/pino-list.XXXXXX")"
      if rclone_run lsf --recursive --format pst "vault:current/$scope" > "$listing" 2>/dev/null; then
        LC_ALL=C ${pkgs.coreutils}/bin/sort "$listing" \
          | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1
      else
        printf '%s\n' missing
      fi
      ${pkgs.coreutils}/bin/rm -f "$listing"
    }

    pull_scope() {
      local scope="$1" target fingerprint key state
      require_closed "$scope"
      target="$(local_path "$scope")"
      fingerprint="$(remote_fingerprint "$scope")"
      [ "$fingerprint" != missing ] || {
        echo "$scope has no remote generation; seed it with 'pino vault push $scope'." >&2
        return 1
      }
      STAGING="$(${pkgs.coreutils}/bin/mktemp -d "$STATE_ROOT/pull.XXXXXX")"
      rclone_run sync "vault:current/$scope" "$STAGING"
      ${pkgs.coreutils}/bin/install -d -m 0700 "$target"
      ${pkgs.rsync}/bin/rsync -a --delete "$STAGING/" "$target/"
      ${pkgs.coreutils}/bin/rm -rf "$STAGING"
      STAGING=
      key="$(scope_key "$scope")"
      state="$STATE_ROOT/fingerprints/$key"
      ${pkgs.coreutils}/bin/printf '%s\n' "$fingerprint" > "$state"
      ${pkgs.coreutils}/bin/chmod 0600 "$state"
      if [ "$TARGET_MODE" = legacy ]; then
        echo "Pulled legacy $scope ciphertext. Unlock and migrate it before pushing."
      else
        echo "Pulled $scope. Edit locally, then run: pino vault push $scope"
      fi
    }

    push_scope() {
      local scope="$1" source fingerprint key state baseline new_fingerprint
      require_closed "$scope"
      source="$(local_path "$scope")"
      [ -d "$source" ] || { echo "Local scope is missing: $source" >&2; return 1; }
      fingerprint="$(remote_fingerprint "$scope")"
      key="$(scope_key "$scope")"
      state="$STATE_ROOT/fingerprints/$key"
      if [ "$fingerprint" != missing ]; then
        [ -r "$state" ] || {
          echo "Pull $scope before pushing; no local remote fingerprint exists." >&2
          return 1
        }
        baseline="$(${pkgs.coreutils}/bin/cat "$state")"
        [ "$baseline" = "$fingerprint" ] || {
          echo "Remote $scope changed after the last pull; refusing to overwrite it." >&2
          return 1
        }
        rclone_run sync "vault:current/$scope" "vault:previous/$scope"
      fi
      rclone_run sync "$source" "vault:current/$scope"
      new_fingerprint="$(remote_fingerprint "$scope")"
      [ "$new_fingerprint" != missing ] || {
        echo "Remote verification failed after pushing $scope." >&2
        return 1
      }
      ${pkgs.coreutils}/bin/rm -f "$state"
      echo "Pushed and verified $scope. Pull again before its next push."
    }

    mapfile -t scopes < <(selected_scopes)
    printf '%s %s? [y/N] ' "$ACTION" "''${scopes[*]}"
    read -r confirmation
    [ "$confirmation" = y ] || [ "$confirmation" = Y ] || {
      echo "Cancelled."
      exit 0
    }
    for scope in "''${scopes[@]}"; do
      case "$ACTION" in
        pull) pull_scope "$scope" ;;
        push) push_scope "$scope" ;;
      esac
    done
  '';
in
{
  options.pino.portableVaults.manual = {
    enable = lib.mkEnableOption "manual encrypted pull/push transport" // { default = true; };
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://storage.egrapa.com";
      description = "Writable WebDAV endpoint containing only rclone ciphertext";
    };
    credentialFile = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/state/pino/vault-remote.env";
      description = "Provisioned WebDAV and rclone-crypt credentials";
    };
    stateRoot = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/state/pino/vault-remote";
      description = "Local successful-pull fingerprints";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.manual.enable) {
    assertions = [
      {
        assertion = lib.hasPrefix "${home}/" cfg.manual.credentialFile;
        message = "pino.portableVaults.manual.credentialFile must be inside the Pino user's home";
      }
      {
        assertion = lib.hasPrefix "${home}/" cfg.manual.stateRoot;
        message = "pino.portableVaults.manual.stateRoot must be inside the Pino user's home";
      }
    ];

    environment.systemPackages = [ pkgs.rclone ];

    systemd.tmpfiles.rules = [
      "d ${cfg.manual.stateRoot} 0700 ${user} users -"
      "d ${cfg.manual.stateRoot}/fingerprints 0700 ${user} users -"
    ];

    pino.secrets.entries."vault/remote.env" = {
      target = cfg.manual.credentialFile;
      owner = user;
      group = "users";
      mode = "0600";
      directoryMode = "0700";
    };

    pino.subcommands.vault.commands = {
      remote = {
        description = "Configure and inspect the manual encrypted remote";
        commands = {
          configure.description = "Store remote credentials in this host's protected vault";
          export = {
            description = "Export a sensitive S3Drive-compatible rclone INI";
            usage = "[output.ini]";
          };
          status.description = "Check credentials and encrypted remote access";
        };
        helpText = ''
          Credentials are stored as plaintext only inside the current host's
          protected host vault and its mode-0600 provisioned cache. The WebDAV
          credential is copied from the primary server's mounted host vault;
          it is never retyped. Keep the crypt password and salt in identity.kdbx
          so Android can recreate the same rclone-compatible crypt remote.
        '';
        script = ''
          MOUNT_ROOT=${lib.escapeShellArg cfg.mountRoot}
          CREDENTIAL_FILE=${lib.escapeShellArg cfg.manual.credentialFile}
          HOST_SCOPE=${lib.escapeShellArg "hosts/${config.networking.hostName}"}
          PRIMARY_SCOPE=${lib.escapeShellArg "hosts/${cfg.primary}"}
          case "''${1:-}" in
            configure)
              host_root="$MOUNT_ROOT/$HOST_SCOPE"
              ${pkgs.util-linux}/bin/findmnt --mountpoint "$host_root" >/dev/null 2>&1 || {
                echo "Open $HOST_SCOPE first." >&2
                exit 1
              }
              primary_root="$MOUNT_ROOT/$PRIMARY_SCOPE"
              ${pkgs.util-linux}/bin/findmnt --mountpoint "$primary_root" >/dev/null 2>&1 || {
                echo "Open $PRIMARY_SCOPE first." >&2
                exit 1
              }
              server_credential="$primary_root/server/storage-webdav.env"
              [ -r "$server_credential" ] || {
                echo "Missing primary-server credential: $server_credential" >&2
                exit 1
              }
              remote_user="$(${pkgs.gnused}/bin/sed -n 's/^PINO_WEBDAV_USER=//p' "$server_credential" \
                | ${pkgs.coreutils}/bin/head -n 1)"
              remote_password="$(${pkgs.gnused}/bin/sed -n 's/^PINO_WEBDAV_PASSWORD=//p' "$server_credential" \
                | ${pkgs.coreutils}/bin/head -n 1)"
              [ -n "$remote_user" ] && [ -n "$remote_password" ] || {
                echo "The primary-server WebDAV credential is incomplete." >&2
                exit 1
              }
              destination="$host_root/vault/remote.env"
              if [ -e "$destination" ]; then
                printf 'Remote credentials already exist. Replace them? [y/N] '
                read -r confirmation
                [ "$confirmation" = y ] || [ "$confirmation" = Y ] || {
                  echo "Cancelled."
                  exit 0
                }
              fi
              IFS= read -r -s -p "Vault crypt password from identity.kdbx: " crypt_password
              echo
              IFS= read -r -s -p "Vault crypt salt from identity.kdbx: " crypt_salt
              echo
              [ -n "$remote_password" ] && [ -n "$crypt_password" ] && [ -n "$crypt_salt" ] || {
                echo "Every password field is required." >&2
                exit 1
              }
              [ "''${#crypt_password}" -ge 20 ] || {
                echo "Use a crypt password of at least 20 characters." >&2
                exit 1
              }
              ${pkgs.coreutils}/bin/install -d -m 0700 "$(${pkgs.coreutils}/bin/dirname "$destination")"
              umask 077
              {
                printf 'PINO_VAULT_USER=%q\n' "$remote_user"
                printf 'PINO_VAULT_PASSWORD=%q\n' "$remote_password"
                printf 'PINO_VAULT_CRYPT_PASSWORD=%q\n' "$crypt_password"
                printf 'PINO_VAULT_CRYPT_SALT=%q\n' "$crypt_salt"
              } > "$destination"
              unset remote_user remote_password crypt_password crypt_salt
              /run/current-system/sw/bin/pino vault secrets populate
              echo "Manual encrypted remote configured. Seed it with: pino vault push all"
              ;;
            export)
              [ -r "$CREDENTIAL_FILE" ] || {
                echo "Manual vault credentials are not provisioned." >&2
                echo "Run: pino vault remote configure" >&2
                exit 1
              }
              output="''${2:-${home}/Downloads/pino-vault.ini}"
              output="$(${pkgs.coreutils}/bin/realpath -m -- "$output")"
              case "$output" in
                ${lib.escapeShellArg "${home}/"}*) ;;
                *) echo "The export path must be inside ${home}." >&2; exit 1 ;;
              esac
              [ -d "$(${pkgs.coreutils}/bin/dirname "$output")" ] || {
                echo "Export directory does not exist: $(${pkgs.coreutils}/bin/dirname "$output")" >&2
                exit 1
              }
              [ ! -e "$output" ] || {
                echo "Refusing to replace existing file: $output" >&2
                exit 1
              }
              # shellcheck disable=SC1090
              . "$CREDENTIAL_FILE"
              : "''${PINO_VAULT_USER:?PINO_VAULT_USER is missing}"
              : "''${PINO_VAULT_PASSWORD:?PINO_VAULT_PASSWORD is missing}"
              : "''${PINO_VAULT_CRYPT_PASSWORD:?PINO_VAULT_CRYPT_PASSWORD is missing}"
              : "''${PINO_VAULT_CRYPT_SALT:?PINO_VAULT_CRYPT_SALT is missing}"
              webdav_password="$(${pkgs.coreutils}/bin/printf '%s\n' "$PINO_VAULT_PASSWORD" \
                | ${pkgs.rclone}/bin/rclone obscure -)"
              crypt_password="$(${pkgs.coreutils}/bin/printf '%s\n' "$PINO_VAULT_CRYPT_PASSWORD" \
                | ${pkgs.rclone}/bin/rclone obscure -)"
              crypt_salt="$(${pkgs.coreutils}/bin/printf '%s\n' "$PINO_VAULT_CRYPT_SALT" \
                | ${pkgs.rclone}/bin/rclone obscure -)"
              umask 077
              {
                printf '%s\n' '[transport]' 'type = webdav'
                printf 'url = %s\n' ${lib.escapeShellArg cfg.manual.url}
                printf '%s\n' 'vendor = other'
                printf 'user = %s\n' "$PINO_VAULT_USER"
                printf 'pass = %s\n' "$webdav_password"
                printf '%s\n' '[vault]' 'type = crypt' 'remote = transport:'
                printf 'password = %s\n' "$crypt_password"
                printf 'password2 = %s\n' "$crypt_salt"
                printf '%s\n' 'filename_encryption = standard' 'directory_name_encryption = true'
              } > "$output"
              ${pkgs.coreutils}/bin/chmod 0600 "$output"
              unset PINO_VAULT_PASSWORD PINO_VAULT_CRYPT_PASSWORD PINO_VAULT_CRYPT_SALT
              unset webdav_password crypt_password crypt_salt
              echo "Exported S3Drive-compatible configuration: $output"
              echo "This file grants remote access. Delete it from both devices after importing."
              ;;
            status)
              if [ -f "$CREDENTIAL_FILE" ]; then
                echo "Credentials: provisioned"
                echo "Endpoint: ${cfg.manual.url}"
              else
                echo "Credentials: missing"
                echo "Run: pino vault remote configure"
                exit 1
              fi
              ;;
            *) echo "Run 'pino vault remote help' for usage." >&2; exit 1 ;;
          esac
        '';
      };

      pull = {
        description = "Replace local vault data from the encrypted remote";
        usage = "[--legacy] [all|identity|shared|shared_sec|hosts/<host>]";
        script = ''
          ACTION=pull
          if [ "''${1:-}" = --legacy ]; then
            TARGET_MODE=legacy
            REQUESTED="''${2:-}"
            [ -n "$REQUESTED" ] || {
              echo "Usage: pino vault pull --legacy <protected-scope>" >&2
              exit 1
            }
          else
            TARGET_MODE=current
            REQUESTED="''${1:-all}"
          fi
          ${manualTransferScript}
        '';
      };

      push = {
        description = "Replace remote vault data after a successful pull";
        usage = "[all|identity|shared|shared_sec|hosts/<host>]";
        script = ''
          ACTION=push
          TARGET_MODE=current
          REQUESTED="''${1:-all}"
          ${manualTransferScript}
        '';
      };
    };
  };
}
