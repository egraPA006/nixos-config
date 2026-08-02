{ ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base
    ../../modules/hardware/intel-laptop.nix
    ../../modules/profiles
  ];

  networking.hostName = "la1n";

  system.stateVersion = "25.05";
}
