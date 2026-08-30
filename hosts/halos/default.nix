{ config, ... }:
{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../configurations/server
    ../../modules/boot/grub-bios.nix
  ];

  networking.hostName = "halos";

  pino.user = {
    name = "vincent";
    home = "/home/vincent";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  system.stateVersion = "25.05";
}
