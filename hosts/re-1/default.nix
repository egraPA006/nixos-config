{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base
    ../../modules/hardware/nvidia.nix
    ../../modules/profiles
    ../../modules/hotspot.nix
  ];

  musicLite.localDir   = "/data/fast/music-lite";
  musicFull.localDir   = "/data/fast/music-full";
  musicFull.winePrefix = "/data/fast/music-full/wine-prefix";
  torrent.localDir     = "/data/fast/torrent";

  networking.hostName = "re-1";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap.enable = true;

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

  users.users.egrapa = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
    ];
    shell = pkgs.fish;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      hostname = "re-1";
    };
    users.egrapa = {
      imports = [ ../../home ];
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
  };

  system.stateVersion = "25.05";
}
