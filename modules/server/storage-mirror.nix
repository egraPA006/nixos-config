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
    PINO_WEBDAV_USER="$(${pkgs.gnused}/bin/sed -n 's/^PINO_WEBDAV_USER=//p' "$credentials" \
      | ${pkgs.coreutils}/bin/head -n 1)"
    PINO_WEBDAV_PASSWORD="$(${pkgs.gnused}/bin/sed -n 's/^PINO_WEBDAV_PASSWORD=//p' "$credentials" \
      | ${pkgs.coreutils}/bin/head -n 1)"
    : "''${PINO_WEBDAV_USER:?PINO_WEBDAV_USER is missing}"
    : "''${PINO_WEBDAV_PASSWORD:?PINO_WEBDAV_PASSWORD is missing}"
    htpasswd="$RUNTIME_DIRECTORY/htpasswd"
    printf '%s\n' "$PINO_WEBDAV_PASSWORD" \
      | ${pkgs.apacheHttpd}/bin/htpasswd -i -B -c "$htpasswd" "$PINO_WEBDAV_USER"
    unset PINO_WEBDAV_USER PINO_WEBDAV_PASSWORD
    exec ${pkgs.rclone}/bin/rclone serve webdav \
      --config /dev/null \
      --addr 127.0.0.1:${toString cfg.port} \
      --htpasswd "$htpasswd" \
      ${lib.escapeShellArg cfg.root}
  '';
in
{
  options.pino.server.storageMirror = {
    enable = lib.mkEnableOption "ciphertext-only Pino storage mirror" // { default = true; };
    root = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pino/vault-store";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "storage.${config.pino.server.domain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8091;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.git pkgs.rclone pkgs.rsync ];

    users.groups.pino-storage = { };
    users.users.pino-storage = {
      isSystemUser = true;
      group = "pino-storage";
      home = cfg.root;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.root} 0700 pino-storage pino-storage -"
    ];

    pino.secrets.entries."server/storage-webdav.env" = {
      source = "server/storage-webdav.env";
      restartUnits = [ "pino-storage-webdav.service" ];
      startUnits = [ "pino-storage-webdav.service" ];
    };

    systemd.services.pino-storage-webdav = {
      description = "Writable WebDAV access to client-encrypted Pino data";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/var/lib/pino/secrets/server/storage-webdav.env";
      serviceConfig = {
        Type = "simple";
        User = "pino-storage";
        Group = "pino-storage";
        ExecStart = serve;
        LoadCredential = "webdav-env:/var/lib/pino/secrets/server/storage-webdav.env";
        RuntimeDirectory = "pino-storage-webdav";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.root ];
      };
    };

    services.caddy.virtualHosts.${cfg.hostName}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
  };
}
