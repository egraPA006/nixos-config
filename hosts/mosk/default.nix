{ config, ... }:

{
  imports = [ ../../configurations/server ];

  networking.hostName = "mosk";

  pino.user = {
    name = "vincent";
    home = "/home/vincent";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  # Hardware, disk layout, public domain, and service profiles are selected
  # when the physical or virtual server is provisioned.
  system.stateVersion = "25.05";
}
