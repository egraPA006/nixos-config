{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base
    ../../modules/hardware/nvidia.nix
    ../../modules/profiles
  ];

  _module.args.activeProfiles = import ./active-profiles.nix;

  networking.hostName = "re-1";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap.enable = true;

  services.hardware.openrgb.enable = true;

  users.users.egrapa = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    shell = pkgs.bash;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.egrapa = import ../../home;
  };

  system.stateVersion = "25.05";
}
