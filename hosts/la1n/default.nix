{ config, ... }:
{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../configurations/desktop
    ../../modules/hardware/intel-laptop.nix
  ];

  networking.hostName = "la1n";

  pino.user = {
    name = "egrapa";
    home = "/home/egrapa";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  pino.profiles = {
    musicLite.localDir = "${config.pino.user.home}/music-lite";
  };

  programs.ssh.extraConfig = ''
    Host github.com
      IdentityAgent none
      IdentityFile ${config.pino.user.home}/.ssh/github
      IdentitiesOnly yes

    Host mosk
      HostName vpn.egrapa.com
      User vincent
      IdentityAgent none
      IdentityFile ${config.pino.user.home}/.ssh/mosk
      IdentitiesOnly yes
  '';

  system.stateVersion = "25.05";
}
