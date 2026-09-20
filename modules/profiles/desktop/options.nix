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
      windowsPlugins = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            installer = lib.mkOption {
              type = lib.types.str;
              description = "Installer filename in the music-full installers directory.";
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Arguments passed to the Windows installer.";
            };
            sha256 = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional SHA-256 checksum of the installer file.";
            };
          };
        });
        default = { };
        description = "Windows plugins installed into the music-full Wine prefix.";
      };
    };
    torrent.localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.pino.user.home}/torrent";
    };
  };
}
