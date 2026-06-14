{ pkgs, ... }:
{
  programs.amnezia-vpn.enable = true;

  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
  ];
}
