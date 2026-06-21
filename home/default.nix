{ ... }:
{
  imports = [
    ./bash.nix
    ./vscode.nix
    ./git.nix
    ./gnome.nix
  ];

  home.username = "egrapa";
  home.homeDirectory = "/home/egrapa";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
