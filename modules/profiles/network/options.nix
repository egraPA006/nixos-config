{ lib, ... }:
{
  options.pino.profiles.vpn.connections = lib.mkOption {
    description = "Named AmneziaWG client configurations available on this host";
    default = {
      awg0.source = "awg0.conf";
    };
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options.source = lib.mkOption {
        type = lib.types.str;
        default = "vpn/${name}.conf";
        description = "Path relative to this host's merged vault secret tree";
      };
    }));
  };

  options.pino.profiles.hotspot = {
    wifiInterface = lib.mkOption {
      type = lib.types.str;
      default = "wlp8s0";
      description = "WiFi interface used by the hotspot profile";
    };
    vpnInterface = lib.mkOption {
      type = lib.types.str;
      default = "awg0";
      description = "VPN interface used for hotspot NAT";
    };
  };
}
