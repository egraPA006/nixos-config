{ config, lib, ... }:
{
  options.pino.profiles = {
    musicLite.localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.pino.user.home}/music-lite";
    };
    guitarPro = {
      replacementExe = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional local executable copied over GuitarPro.exe during installation.";
      };
      localDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.pino.user.home}/guitar-pro";
      };
      winePrefix = lib.mkOption {
        type = lib.types.str;
        default = "${config.pino.user.home}/guitar-pro/wine-prefix";
      };
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
              description = "Installer path relative to the music-full installers directory.";
            };
            method = lib.mkOption {
              type = lib.types.enum [ "wine" "innoextract" "link" ];
              default = "wine";
              description = "Install with Wine, extract selected files from Inno Setup, or link saved content into the Wine prefix.";
            };
            extractedFiles = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "For innoextract: source paths mapped to destinations relative to the Wine prefix.";
            };
            links = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "For link: paths relative to the saved directory mapped to destinations relative to the Wine prefix.";
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Arguments passed to the Windows installer.";
            };
            winetricks = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Winetricks dependencies installed with network access before the offline installer.";
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
