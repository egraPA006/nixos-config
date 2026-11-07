{ config, lib, ... }:

let
  cfg = config.pino.server;
in
{
  options.pino.server = {
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public base domain served by Mosk";
    };
    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Contact address used for ACME certificate issuance";
    };
    web = {
      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = cfg.domain;
      };
    };
    galene = {
      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if cfg.domain == null then null else "meet.${cfg.domain}";
        description = "Public Galene domain";
      };
      turnPort = lib.mkOption {
        type = lib.types.port;
        default = 1194;
        description = "Built-in Galene TURN TCP/UDP port";
      };
    };
    xray = {
      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = cfg.domain;
      };
      path = lib.mkOption {
        type = lib.types.strMatching "/[a-zA-Z0-9/_-]+";
        default = "/pino-xhttp";
      };
      port = lib.mkOption { type = lib.types.port; default = 10080; };
    };
    telemt = {
      publicHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if cfg.domain == null then null else "vpn.${cfg.domain}";
        description = "Public endpoint used by Telegram clients.";
      };
      port = lib.mkOption { type = lib.types.port; default = 2443; };
      tlsDomain = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9.-]+";
        default = "www.microsoft.com";
        description = "Real HTTPS masking target; changing it invalidates client links.";
      };
    };
    vpn = {
      interface = lib.mkOption {
        type = lib.types.str;
        default = "awg0";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 585;
      };
      externalInterface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Outbound VPN interface override; null detects the default IPv4 route";
      };
      clientSubnet = lib.mkOption {
        type = lib.types.str;
        default = "10.77.0.0/24";
      };
      configFile = lib.mkOption {
        type = lib.types.str;
        default = "/etc/pino/vpn/awg0.conf";
      };
    };
  };
}
