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
    ./vpn.nix
  ];
}
