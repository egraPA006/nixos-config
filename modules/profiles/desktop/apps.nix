{ config, pkgs, ... }:
{
  programs.chromium = {
    enable = true;
    extensions = [ "nngceckbapebfimnlniiiahkandclblb" ];
  };

  pino.provision.publicKeys = [
    { item = "pino-ssh-${config.networking.hostName}-github"; target = "${config.pino.user.home}/.ssh/github.pub"; }
    { item = "pino-ssh-server-mosk"; target = "${config.pino.user.home}/.ssh/mosk.pub"; }
    { item = "pino-ssh-server-halos"; target = "${config.pino.user.home}/.ssh/halos.pub"; }
  ];

  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
    libreoffice
    imagemagick
    bitwarden-desktop
  ];

  home-manager.users.${config.pino.user.name}.home.sessionVariables.SSH_AUTH_SOCK =
    "${config.pino.user.home}/.bitwarden-ssh-agent.sock";
}
