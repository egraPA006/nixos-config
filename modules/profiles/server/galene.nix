{ config, lib, pkgs, ... }:

let
  cfg = config.pino.server.galene;
  domain = if cfg.domain == null then "meet.invalid.local" else cfg.domain;
  publicConfig = pkgs.writeText "galene-config.json" (builtins.toJSON {
    proxyURL = "https://${domain}/";
  });
in
{
  pino.provision.secrets = [{
    item = "pino-galene-${config.networking.hostName}-main";
    target = "/etc/pino/galene/main.json";
    units = [ "galene.service" ];
  }];

  assertions = [{
    assertion = cfg.domain != null;
    message = "server-galene requires pino.server.domain or pino.server.galene.domain";
  }];

  services.galene = {
    enable = true;
    insecure = true;
    httpAddress = "127.0.0.1";
    httpPort = 8443;
    turnAddress = ":${toString cfg.turnPort}";
  };

  systemd.services.galene = {
    unitConfig.ConditionPathExists = "/etc/pino/galene/main.json";
    serviceConfig.LoadCredential = "main-group:/etc/pino/galene/main.json";
    preStart = lib.mkAfter ''
      install -m 0600 ${publicConfig} /var/lib/galene/data/config.json
      install -m 0600 "$CREDENTIALS_DIRECTORY/main-group" /var/lib/galene/groups/main.json
    '';
  };

  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      reverse_proxy 127.0.0.1:8443
    '';
  };

  networking.firewall = {
    allowedTCPPorts = [ 80 443 cfg.turnPort ];
    allowedUDPPorts = [ cfg.turnPort ];
    allowedUDPPortRanges = [{ from = 49152; to = 65535; }];
  };

  environment.systemPackages = [ config.services.galene.package ];

  pino.subcommands.server.commands.galene = {
    description = "Operate the Galene video-call server";
    commands = {
      status.description = "Show Galene status";
      logs.description = "Show recent Galene logs";
      hash-password.description = "Generate a bcrypt password object for group JSON";
    };
    helpText = ''
      Store the complete group JSON in the `pino-galene-mosk-main` Bitwarden Secure Note, then run:

        pino provision send pino-galene-mosk-main mosk /etc/pino/galene/main.json galene.service

      The room is available at https://${domain}/group/main/. Galene remains
      stopped until the group file exists.
    '';
    script = ''
      case "''${1:-}" in
        status) systemctl status galene --no-pager ;;
        logs) journalctl -u galene -n 150 --no-pager ;;
        hash-password) ${config.services.galene.package}/bin/galenectl hash-password -type bcrypt -cost 12 ;;
        *) echo "Run 'pino server galene help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
