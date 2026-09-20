{ config, pkgs, ... }:
{
  programs.chromium = {
    enable = true;
    extensions = [ "nngceckbapebfimnlniiiahkandclblb" ];
  };

  pino.provision.sshKeys = [
    { item = "pino-ssh-${config.networking.hostName}-github"; target = "${config.pino.user.home}/.ssh/github"; }
    { item = "pino-ssh-server-mosk"; target = "${config.pino.user.home}/.ssh/mosk"; }
    { item = "pino-ssh-server-halos"; target = "${config.pino.user.home}/.ssh/halos"; }
  ];

  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
    libreoffice
    imagemagick
    bitwarden-desktop
  ];

}
