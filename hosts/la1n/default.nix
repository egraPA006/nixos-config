{ ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../configurations/desktop
    ../../modules/hardware/intel-laptop.nix
  ];

  networking.hostName = "la1n";

  pino.snapshots.volumes.root = {
    subvolume = "/";
    group = "system";
  };

  system.stateVersion = "25.05";
}
