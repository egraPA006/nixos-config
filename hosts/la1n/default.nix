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
      IdentityAgent ${config.pino.user.home}/.bitwarden-ssh-agent.sock
      IdentityFile ${config.pino.user.home}/.ssh/github.pub
      IdentitiesOnly yes

    Host mosk
      HostName vpn.egrapa.com
      User vincent
      IdentityAgent ${config.pino.user.home}/.bitwarden-ssh-agent.sock
      IdentityFile ${config.pino.user.home}/.ssh/mosk.pub
      IdentitiesOnly yes
  '';

  system.stateVersion = "25.05";
}
