{ config, pkgs, lib, ... }:

{
  imports = [
    ../modules/apps.nix
    ../modules/sway.nix
    ../modules/system.nix
    ../modules/utillities.nix
    ./hardware-configuration.nix
  ];

  # Basic system configuration
  boot.loader.grub = {
    enable = true;
    version = 2;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.11"; # Make sure to set this to your actual NixOS version
}