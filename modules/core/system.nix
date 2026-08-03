{ config, pkgs, ... }:
let
  user = config.pino.user.name;
in
{
  zramSwap.enable = true;

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      hostname = config.networking.hostName;
      pinoConfigDir = config.pino.configDir;
      pinoUser = config.pino.user;
    };
  };
}
