{ config, ... }:
{
  imports = [
    ./hardware.nix
    ./disko.nix
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
    vpn.connections.mosk = { };
  };

  pino.portableVaults.trustedClient = true;

  pino.data.datasets.music-lite = config.pino.profiles.musicLite.localDir;

  pino.secrets.entries.ssh = {
    source = "ssh";
    target = "${config.pino.user.home}/.ssh";
    owner = config.pino.user.name;
    group = "users";
    mode = "0600";
    directoryMode = "0700";
    recursive = true;
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
