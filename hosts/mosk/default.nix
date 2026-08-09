{ config, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../configurations/server
    ../../modules/boot/grub-bios.nix
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
  pino.server = {
    domain = "egrapa.com";
    acmeEmail = "admin@egrapa.com";

    passwordSync.devices.re-1.id = "LVLTAKU-35ENIVC-BSHN3KB-5FMLBUQ-YBXHKAA-IAB6QTT-2NVKQFB-BZHXCQU";
    passwordSync.devices.la1n.id = "RLH5AIW-CXNIN2A-Q43HCST-CROXC7J-PVJ7BNW-MTDGTLE-PIGGVJQ-SRPQSQ7";
  };
}
