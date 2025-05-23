{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Core utilities
    wget
    curl
    git
    neofetch
    # Web browsers
    firefox

    # Media
    vlc
    mpv

    # Office
    onlyoffice-bin

    # Chat
    telegram-desktop

    # Development
    vscode
  ];
}