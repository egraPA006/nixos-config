{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base
    ../../modules/hardware/intel-laptop.nix
    ../../modules/profiles
  ];

  networking.hostName = "la1n";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap.enable = true;

  # Laptop power management
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;

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
