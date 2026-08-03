{ config, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../configurations/server
    ../../modules/boot/systemd-boot.nix
  ];

  networking.hostName = "mosk";

  pino.user = {
    name = "vincent";
    home = "/home/vincent";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  # Public domain, service profiles, and client device IDs are selected before
  # staging. scripts/server-stage.sh replaces the disk placeholder and
  # generates hardware.nix on the installation machine.
  system.stateVersion = "25.05";
}
