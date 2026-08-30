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
      IdentityFile ${config.pino.user.home}/.ssh/github_ed25519
      IdentitiesOnly yes

    Host mosk
      HostName vpn.egrapa.com
      User vincent
      IdentityFile ${config.pino.user.home}/.ssh/mosk_ed25519
      IdentitiesOnly yes
  '';

  system.stateVersion = "25.05";
}
