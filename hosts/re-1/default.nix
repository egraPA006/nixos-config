{ config, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../configurations/desktop
    ../../modules/hardware/nvidia.nix
  ];

  pino.profiles = {
    musicLite.localDir = "/data/fast/music-lite";
    musicFull = {
      localDir = "/data/fast/music-full";
      winePrefix = "/data/fast/music-full/wine-prefix";
    };
    torrent.localDir = "/data/fast/torrent";
    hotspot.wifiInterface = "wlp8s0";
  };

  pino.snapshots.volumes = {
    root = { subvolume = "/"; group = "system"; };
    home = { subvolume = "/home"; group = "system"; };
    fast = { subvolume = "/data/fast"; group = "data"; };
    slow = { subvolume = "/data/slow"; group = "data"; };
  };

  # Host paths for datasets that can be carried between machines on egrapa_hdd.
  pino.data.datasets = {
    music-full = {
      localPath = config.pino.profiles.musicFull.localDir;
      scope = "shared";
    };
    photos = {
      localPath = "/data/slow/photos";
      scope = "shared";
    };
  };

  pino.vault.secrets.github-ssh = {
    source = "ssh/github_ed25519";
    target = "/home/egrapa/.ssh/github_ed25519";
    owner = "egrapa";
    group = "users";
    mode = "0600";
    directoryMode = "0700";
  };

  networking.hostName = "re-1";

  systemd.tmpfiles.rules = [
    "z /data/fast 0755 egrapa users -"
    "z /data/slow 0755 egrapa users -"
  ];

  services.hardware.openrgb.enable = true;

  environment.etc."systemd/sleep.conf.d/nosuspend.conf".text = ''
    [Sleep]
    AllowSuspend=no
    AllowHibernation=no
    AllowSuspendThenHibernate=no
    AllowHybridSleep=no
  '';

  home-manager.users.egrapa = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."github.com" = {
        IdentityFile = "/home/egrapa/.ssh/github_ed25519";
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

  system.stateVersion = "25.05";
}
