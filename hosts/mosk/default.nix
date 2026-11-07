{ config, ... }:

{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../configurations/server
    ../../modules/boot/grub-bios.nix
  ];

  networking.hostName = "mosk";

  pino.user = {
    name = "vincent";
    home = "/home/vincent";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  system.stateVersion = "25.05";
  pino.server = {
    domain = "egrapa.com";
    acmeEmail = "admin@egrapa.com";
  } // builtins.fromJSON (builtins.readFile ../../resources/mosk-proxies.json);
}
