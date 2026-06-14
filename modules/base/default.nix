{ ... }:
{
  imports = [
    ./nix-settings.nix
    ./locale.nix
    ./desktop.nix
    ./audio.nix
    ./networking.nix
    ./apps.nix
    ./shell.nix
    ./snapper.nix
    ./vpn.nix
  ];
}
