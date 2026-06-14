{ ... }:
{
  imports = [
    ./bash.nix
    ./vscode.nix
    ./git.nix
  ];

  home.username = "egrapa";
  home.homeDirectory = "/home/egrapa";
  home.stateVersion = "25.05";

  nixpkgs.config.allowUnfree = true;

  programs.home-manager.enable = true;
}
