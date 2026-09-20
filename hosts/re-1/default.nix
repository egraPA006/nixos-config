{ config, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../configurations/desktop
    ../../modules/hardware/nvidia.nix
  ];

  pino.user = {
    name = "egrapa";
    home = "/home/egrapa";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  pino.profiles = {
    vpn.share.wifiInterface = "wlp8s0";
    musicLite.localDir = "/data/fast/music-lite";
    musicFull = {
      localDir = "/data/fast/music-full";
      winePrefix = "/data/fast/music-full/wine-prefix";
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
