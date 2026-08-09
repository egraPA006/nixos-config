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
      internalHttpsPort = lib.mkOption {
        type = lib.types.port;
        default = 8443;
      };
    };
    proxy = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
      };
      secretDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/pino/secrets/server/sing-box";
      };
      users = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options.uuidFile = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.proxy.secretDir}/users/${name}.uuid";
          };
        }));
        default = { };
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
        default = "/var/lib/pino/secrets/server/awg0.conf";
      };
    };
    passwordSync = {
      folder = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/syncthing/keepass";
      };
      devices = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.str; };
            addresses = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "dynamic" ];
            };
          };
        });
        default = { };
      };
    };
    mail = {
      fqdn = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if cfg.domain == null then null else "mail.${cfg.domain}";
      };
      accounts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            quota = lib.mkOption {
              type = lib.types.str;
              default = "5G";
            };
          };
        });
        default = { };
      };
    };
  };
}
