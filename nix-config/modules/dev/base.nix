# /etc/nixos/modules/dev/dev-base.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Version Control
    git

    # Utilities
    bat
  ];
}