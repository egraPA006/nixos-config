{ config, lib, pkgs, ... }:

let
  cfg = config.pino.server.storageMirror;
  serve = pkgs.writeShellScript "pino-storage-webdav" ''
    set -euo pipefail
    credentials="$CREDENTIALS_DIRECTORY/webdav-env"
    [ -r "$credentials" ] || {
      echo "Missing WebDAV credentials" >&2
      exit 1
    }
    # shellcheck disable=SC1090
    . "$credentials"
    : "''${PINO_WEBDAV_USER:?PINO_WEBDAV_USER is missing}"
    : "''${PINO_WEBDAV_PASSWORD:?PINO_WEBDAV_PASSWORD is missing}"
    exec ${pkgs.rclone}/bin/rclone serve webdav \
      --addr 127.0.0.1:${toString cfg.port} \
      --read-only \
      --user "$PINO_WEBDAV_USER" \
      --pass "$PINO_WEBDAV_PASSWORD" \
      ${lib.escapeShellArg cfg.root}
  '';
  serveShare = pkgs.writeShellScript "pino-share-webdav" ''
    set -euo pipefail
    credentials="$CREDENTIALS_DIRECTORY/webdav-env"
    [ -r "$credentials" ] || {
      echo "Missing WebDAV credentials" >&2
      exit 1
    }
    # shellcheck disable=SC1090
    . "$credentials"
    : "''${PINO_WEBDAV_USER:?PINO_WEBDAV_USER is missing}"
    : "''${PINO_WEBDAV_PASSWORD:?PINO_WEBDAV_PASSWORD is missing}"
    exec ${pkgs.rclone}/bin/rclone serve webdav \
      --addr 127.0.0.1:${toString cfg.sharePort} \
      --user "$PINO_WEBDAV_USER" \
      --pass "$PINO_WEBDAV_PASSWORD" \
      /var/lib/syncthing/share
  '';
in
{
  options.pino.server.storageMirror = {
    enable = lib.mkEnableOption "ciphertext-only Pino storage mirror" // { default = true; };
    root = lib.mkOption {
      type = lib.types.str;
      default = config.pino.server.sync.encryptedRoot;
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "storage.${config.pino.server.domain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8091;
    };
    shareHostName = lib.mkOption {
      type = lib.types.str;
      default = "share.${config.pino.server.domain}";
    };
    sharePort = lib.mkOption {
      type = lib.types.port;
      default = 8092;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.git pkgs.rclone pkgs.rsync ];

    pino.secrets.entries."server/storage-webdav.env" = {
      source = "server/storage-webdav.env";
      restartUnits = [
        "pino-storage-webdav.service"
        "pino-share-webdav.service"
      ];
    };

    systemd.services.pino-storage-webdav = {
      description = "Read-only WebDAV access to Pino ciphertext";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/var/lib/pino/secrets/server/storage-webdav.env";
      serviceConfig = {
        Type = "simple";
        User = "syncthing";
        Group = "syncthing";
        ExecStart = serve;
        LoadCredential = "webdav-env:/var/lib/pino/secrets/server/storage-webdav.env";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    systemd.services.pino-share-webdav = {
      description = "WebDAV access to the Pino temporary encrypted share";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "syncthing.service" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/var/lib/pino/secrets/server/storage-webdav.env";
      serviceConfig = {
        Type = "simple";
        User = "syncthing";
        Group = "syncthing";
        ExecStart = serveShare;
        LoadCredential = "webdav-env:/var/lib/pino/secrets/server/storage-webdav.env";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/syncthing/share" ];
      };
    };

    services.caddy.virtualHosts.${cfg.hostName}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
    services.caddy.virtualHosts.${cfg.shareHostName}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.sharePort}
    '';
  };
}
