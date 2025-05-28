{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Web browsers
    # firefox
    librewolf

    # Media
    vlc
    mpv

    # Office
    onlyoffice-bin

    # Chat
    telegram-desktop
  ];
}