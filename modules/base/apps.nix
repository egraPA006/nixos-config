{ pkgs, ... }:
{
  programs.nix-ld.enable = true;
  programs.amnezia-vpn.enable = true;

  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
  ];
}
