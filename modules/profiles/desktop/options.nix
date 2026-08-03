{ config, lib, ... }:
{
  options.pino.profiles = {
    musicLite.localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.pino.user.home}/music-lite";
    };
    musicFull = {
      localDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.pino.user.home}/music-full";
      };
      winePrefix = lib.mkOption {
        type = lib.types.str;
        default = "${config.pino.user.home}/music-full/wine-prefix";
      };
    };
    torrent.localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.pino.user.home}/torrent";
    };
  };
}
