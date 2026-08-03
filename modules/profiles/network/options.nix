{ lib, ... }:
{
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
