{ lib, ... }:
{
  options = {
    pino.profiles.musicLite.localDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/egrapa/music-lite";
    };
    pino.profiles.musicFull.localDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/egrapa/music-full";
    };
    pino.profiles.musicFull.winePrefix = lib.mkOption {
      type = lib.types.str;
      default = "/home/egrapa/music-full/wine-prefix";
    };
    pino.profiles.torrent.localDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/egrapa/torrent";
    };
    pino.profiles.hotspot.wifiInterface = lib.mkOption {
      type = lib.types.str;
      default = "wlp8s0";
      description = "WiFi interface used by the hotspot profile";
    };
    pino.profiles.hotspot.vpnInterface = lib.mkOption {
      type = lib.types.str;
      default = "awg0";
      description = "VPN interface used for hotspot NAT";
    };

    pino.vault.provisionedDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pino/secrets";
    };
    pino.vault.secrets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          source = lib.mkOption { type = lib.types.str; default = name; };
          target = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          owner = lib.mkOption { type = lib.types.str; default = "root"; };
          group = lib.mkOption { type = lib.types.str; default = "root"; };
          mode = lib.mkOption { type = lib.types.str; default = "0600"; };
          directoryMode = lib.mkOption { type = lib.types.str; default = "0700"; };
          restartUnits = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      }));
    };
  };
}
