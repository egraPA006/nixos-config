{ lib, ... }:
{
  options.pino.profiles.vpn.share = {
    wifiInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "WiFi interface used for VPN sharing; null detects it with NetworkManager";
    };
    connection = lib.mkOption {
      type = lib.types.str;
      default = "pino-vpn-share";
      description = "Dedicated NetworkManager hotspot connection used only by Pino VPN sharing";
    };
  };
}
