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

  pino.data.datasets.music-lite = {
    localPath = config.pino.profiles.musicLite.localDir;
    scope = "shared";
  };

  pino.secrets.entries.ssh = {
    source = "ssh";
    target = "${config.pino.user.home}/.ssh";
    owner = config.pino.user.name;
    group = "users";
    mode = "0600";
    directoryMode = "0700";
    recursive = true;
  };

  # Mosk's public Syncthing identity. Pair la1n on Mosk after la1n's first boot.
  pino.vault.sync.serverId =
    "DSIVLOL-YANNKJ6-7PMBSYF-X4HHLDU-O4NEKQR-EWQ4KVE-JMSM4AI-X2D5LQ7";

  home-manager.users.${config.pino.user.name}.programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "github.com" = {
        IdentityFile = "${config.pino.user.home}/.ssh/github_ed25519";
        IdentitiesOnly = true;
      };
      mosk = {
        HostName = "vpn.egrapa.com";
        User = "vincent";
        IdentityFile = "${config.pino.user.home}/.ssh/mosk_ed25519";
        IdentitiesOnly = true;
      };
    };
  };

  system.stateVersion = "25.05";
}
