{ config, pkgs, ... }:
{
  zramSwap.enable = true;

  users.users.egrapa = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs.hostname = config.networking.hostName;
  };
}
