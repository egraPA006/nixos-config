{ pkgs, ... }:

{
  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    htop
    rsync
    file
    unzip
  ];
}
