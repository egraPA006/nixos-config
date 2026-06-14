{ pkgs, config, ... }:
{
  programs.fish.enable = true;
  programs.fish.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/egrapa/nixos-config#${config.networking.hostName}";
  };

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
