{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../configurations/desktop
    ../../modules/hardware/nvidia.nix
    ./music-full-fabfilter.nix
  ];

  pino.user = {
    name = "egrapa";
    home = "/home/egrapa";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  pino.profiles = {
    vpn.share.wifiInterface = "wlp8s0";
    musicLite.localDir = "/data/fast/music-lite";
    guitarPro = {
      localDir = "/data/fast/guitar-pro";
      winePrefix = "/data/fast/guitar-pro/wine-prefix";
      replacementExe = "${config.pino.profiles.guitarPro.localDir}/installs/replacement/GuitarPro.exe";
    };
    musicFull = {
      localDir = "/data/fast/music-full";
      winePrefix = "/data/fast/music-full/wine-prefix-new";
      windowsPlugins.Gojira = {
        installer = "Gojira/Setup Archetype Gojira v1.0.0.exe";
        sha256 = "c80d19911d98523d5bcccace01373d1cb34ec695f825e6c1c929aa91a3d15200";
        method = "innoextract";
        winetricks = [ "vcrun2019" ];
        extractedFiles = {
          "code$GetDir$VST3x64/Archetype Gojira.vst3" = "drive_c/Program Files/Common Files/VST3/Archetype Gojira.vst3";
          "commonappdata/Neural DSP/Archetype Gojira" = "drive_c/ProgramData/Neural DSP/Archetype Gojira";
        };
      };
      windowsPlugins."TDR-Nova" = {
        installer = "TDR-Nova/setup.exe";
        sha256 = "85a17a025bb32a7346dec308cee8cbdc40ba9f777d8915ea7411f1cbc24909c0";
        method = "innoextract";
        extractedFiles."code$GetVST3Dir_64/TDR Nova.vst3" = "drive_c/Program Files/Common Files/VST3/TDR Nova.vst3";
      };
      windowsPlugins.Soldano = {
        installer = "Soldano/Setup Soldano SLO-100 X v1.0.0.exe";
        sha256 = "5955a1f72f28b06e2f300a483825158237082f36ea211eaa6e03f8793237b137";
        args = [ "/VERYSILENT" "/SUPPRESSMSGBOXES" "/NORESTART" "/COMPONENTS=vst3_64,data" ];
        winetricks = [ "vcrun2019" ];
      };
      windowsPlugins."Valhalla-Delay" = {
        installer = "ValhallaDSP - Valhalla Delay v3.0.0/Setup Valhalla Delay v3.0.0.exe";
        sha256 = "12a1e14460351bf3e7a7a2089cea89657764fff6a0c29d3d96ff8dec97a856fc";
        method = "innoextract";
        extractedFiles = {
          "code$GetDir$VST3x64/ValhallaDelay.vst3" = "drive_c/Program Files/Common Files/VST3/ValhallaDelay.vst3";
          "commonappdata/Valhalla DSP, LLC/ValhallaDelay" = "drive_c/ProgramData/Valhalla DSP, LLC/ValhallaDelay";
        };
      };
      windowsPlugins."Valhalla-VintageVerb" = {
        installer = "Valhalla.DSP.Valhalla.VintageVerb.v4.0.5-R2R/Setup Valhalla VintageVerb v4.0.5.exe";
        sha256 = "f73dfac2c047672bf898cb22afc1a36a05917dfc5f9b2f843f487a6a0b621e95";
        method = "innoextract";
        extractedFiles = {
          "code$GetDir$VST3x64/ValhallaVintageVerb.vst3" = "drive_c/Program Files/Common Files/VST3/ValhallaVintageVerb.vst3";
          "commonappdata/Valhalla DSP, LLC/ValhallaVintageVerb" = "drive_c/ProgramData/Valhalla DSP, LLC/ValhallaVintageVerb";
        };
      };
      windowsPlugins."EZX-Death-Metal" = {
        installer = "TT451_Death_Metal_EZX";
        method = "link";
        links = {
          "EZX2_DeathMetal" = "drive_c/Program Files (x86)/Common Files/Toontrack/EZDrummer/EZX2_DeathMetal";
          "Midi/1926@EZX_DEATH_METAL" = "drive_c/Program Files (x86)/Common Files/Toontrack/EZDrummer/Midi/1926@EZX_DEATH_METAL";
        };
      };
      windowsPlugins."EZX-Dark-Matter" = {
        installer = "TT452_Dark_Matter_EZX";
        method = "link";
        links = {
          "EZX2_DarkMatter" = "drive_c/Program Files (x86)/Common Files/Toontrack/EZDrummer/EZX2_DarkMatter";
          "Midi/1925@EZX_DARK_MATTER" = "drive_c/Program Files (x86)/Common Files/Toontrack/EZDrummer/Midi/1925@EZX_DARK_MATTER";
        };
      };
      windowsPlugins."MODO-BASS-2" = {
        installer = "IK.Multimedia.MODO.BASS.2.v2.0.4.Incl.Keygen-R2R/Setup MODO BASS 2 v2.0.4.exe";
        sha256 = "102c73c82a6296d87d37635745de356a7049208a4e666b1c667132f7fd0db713";
        args = [ "/VERYSILENT" "/SUPPRESSMSGBOXES" "/NORESTART" ];
      };
      windowsPlugins.EZdrummer = {
        installer = "Toontrack - EZdrummer 3.1.2/WIN/Toontrack EZdrummer v3.1.2.exe";
        sha256 = "3f68f4120dde39335ddf0f99da8e8abeda33558bab3ae7453b4bf2300834abcf";
        args = [ "/VERYSILENT" "/SUPPRESSMSGBOXES" "/NORESTART" ];
      };
      windowsPlugins."Toontrack-MIDI" = {
        installer = "Toontrack - EZdrummer 3.1.2/WIN/Toontrack Drum MIDI Packs Bundle.exe";
        sha256 = "708158571325384b8ab1e0f49f341ec0babf51479faebaf1be96821917fa1de3";
        args = [ "/VERYSILENT" "/SUPPRESSMSGBOXES" "/NORESTART" ];
      };
      windowsPlugins.Nucleus = {
        installer = "Nucleus";
        method = "link";
        links."Nucleus 1.4.0 [Audio Imperia]" = "drive_c/Libraries/Nucleus";
      };
    };
    torrent.localDir = "/data/fast/torrent";
  };

  networking.hostName = "re-1";

  systemd.tmpfiles.rules = [
    "z /data/fast 0755 ${config.pino.user.name} users -"
    "z /data/slow 0755 ${config.pino.user.name} users -"
  ];

  services.hardware.openrgb.enable = true;

  environment.etc."systemd/sleep.conf.d/nosuspend.conf".text = ''
    [Sleep]
    AllowSuspend=no
    AllowHibernation=no
    AllowSuspendThenHibernate=no
    AllowHybridSleep=no
  '';

  programs.ssh.extraConfig = ''
    Host github.com
      IdentityAgent none
      IdentityFile ${config.pino.user.home}/.ssh/github
      IdentitiesOnly yes

    Host mosk
      HostName vpn.egrapa.com
      User vincent
      IdentityAgent none
      IdentityFile ${config.pino.user.home}/.ssh/mosk
      IdentitiesOnly yes
  '';

  home-manager.users.${config.pino.user.name} = {
    systemd.user.services.monitor-default = lib.mkIf config.services.desktopManager.gnome.enable {
      Unit.Description = "Apply default single-monitor profile";
      Unit.After = [ "graphical-session.target" ];
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "oneshot";
        ExecStart = "/run/current-system/sw/bin/monitor switch single";
        RemainAfterExit = false;
      };
    };
    systemd.user.services.openrgb-init = {
      Unit.Description = "Set OpenRGB default colors";
      Unit.After = [ "graphical-session.target" ];
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "oneshot";
        ExecStart = "${config.services.hardware.openrgb.package}/bin/openrgb --color FF70AB";
        RemainAfterExit = false;
      };
    };
  };
  system.stateVersion = "25.05";
}
