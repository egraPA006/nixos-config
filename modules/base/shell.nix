{ pkgs, ... }:
{
  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    rsync
    file
    unzip
  ];
}
