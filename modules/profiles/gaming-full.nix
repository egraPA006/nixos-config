{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };

  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
    lutris
    wineWowPackages.stable
    winetricks
    # boxflat — wheel/controller config; not in nixpkgs yet, install manually
    # or add via: nix run nixpkgs#boxflat
  ];
}
