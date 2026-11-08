# Shared service hardening and CLI for runtime-only proxy credentials.
{ config, lib, pkgs, name, settings, package, arguments }:
let
  credential = "/etc/pino/${name}/users.json";
  runtimeConfig = "/run/pino-${name}/config.${if name == "xray" then "json" else "toml"}";
  manifest = pkgs.writeText "${name}-public.json" (builtins.toJSON settings);
  render = pkgs.writeShellScript "${name}-render" ''
    set -euo pipefail
    umask 077
    ${pkgs.python3}/bin/python3 ${../../../scripts/proxy-config.py} \
      ${name} ${manifest} "$CREDENTIALS_DIRECTORY/users.json" ${runtimeConfig}
    ${lib.optionalString (name == "xray") ''
      if ! ${package}/bin/xray run -test -config ${runtimeConfig} >/dev/null 2>&1; then
        echo "Xray rejected its runtime configuration; inspect the Bitwarden declaration." >&2
        exit 1
      fi
    ''}
  '';
in {
  pino.provision.secrets = [{
    item = "pino-${name}-${config.networking.hostName}";
    target = credential;
    units = [ "${name}.service" ];
  }];
  systemd.services.${name} = {
    description = "Pino ${name} proxy";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = credential;
    serviceConfig = {
      ExecStartPre = render;
      ExecStart = "${package}/bin/${name} ${arguments} ${runtimeConfig}";
      DynamicUser = true;
      LoadCredential = "users.json:${credential}";
      RuntimeDirectory = "pino-${name}";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "pino-${name}";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/pino-${name}";
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
      LimitNOFILE = 65536;
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      CapabilityBoundingSet = "";
      # Upstream errors may include parsed credentials. Expose status via systemd,
      # never save proxy-generated connection URLs or config fragments to journal.
      StandardOutput = "null";
      StandardError = "null";
    };
  };
  pino.subcommands.server.commands.${name} = {
    description = "Inspect ${name}; service lifecycle is declared by its profile";
    commands = {
      status.description = "Show service state";
      logs.description = "Show systemd lifecycle events (proxy payload logging is disabled)";
    };
    script = ''
      case "''${1:-}" in
        status) systemctl status ${name} --no-pager ;;
        logs) journalctl -u ${name} -n 100 --no-pager ;;
        *) echo "Run 'pino server ${name} help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
