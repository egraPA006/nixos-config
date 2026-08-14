{ config, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../configurations/desktop
    ../../modules/hardware/nvidia.nix
  ];

  pino.user = {
    name = "egrapa";
    home = "/home/egrapa";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  pino.profiles = {
    vpn.connections = {
      awg0.source = "vpn/awg0.conf";
      mosk = { };
    };
    musicLite.localDir = "/data/fast/music-lite";
    musicFull = {
      localDir = "/data/fast/music-full";
      winePrefix = "/data/fast/music-full/wine-prefix";
    };
    torrent.localDir = "/data/fast/torrent";
    hotspot.wifiInterface = "wlp8s0";
  };

  # Host paths for datasets that can be carried between machines on egrapa_hdd.
  pino.data.datasets = {
    music-full = {
      localPath = config.pino.profiles.musicFull.localDir;
      scope = "shared";
    };
    photos = {
      localPath = "/data/fast/photos";
      scope = "shared";
    };
    file_archive = {
      localPath = "/data/fast/file_archive";
      scope = "host";
    };
    nixos-config = {
      localPath = "/home/egrapa/nixos-config";
      scope = "shared";
    };
  };

  pino.secrets.entries.ssh = {
    source = "ssh";
    target = "${config.pino.user.home}/.ssh";
    owner = config.pino.user.name;
    group = "users";
    mode = "0600";
    directoryMode = "0700";
    recursive = true;
  };

  networking.hostName = "re-1";

  pino.portableVaults.trustedClient = true;

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

  home-manager.users.${config.pino.user.name} = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."github.com" = {
        IdentityFile = "${config.pino.user.home}/.ssh/github_ed25519";
        IdentitiesOnly = true;
      };
    };

    systemd.user.services.monitor-default = {
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
        ExecStart = "${pkgs.openrgb}/bin/openrgb --color FF70AB";
        RemainAfterExit = false;
      };
    };
  };
  pino.vault.sync.serverId = "DSIVLOL-YANNKJ6-7PMBSYF-X4HHLDU-O4NEKQR-EWQ4KVE-JMSM4AI-X2D5LQ7";
  system.stateVersion = "25.05";
}
