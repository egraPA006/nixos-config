{ pkgs, ... }:
{
  programs.nix-ld.enable = true;
  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
    libreoffice
    imagemagick
  ];
}
