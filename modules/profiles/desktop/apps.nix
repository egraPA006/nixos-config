{ config, pkgs, ... }:
{
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
