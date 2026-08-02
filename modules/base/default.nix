{ ... }:
{
  imports = [
    ../pino.nix
    ./system.nix
    ./nix-settings.nix
    ./locale.nix
    ./networking.nix
    ./packages.nix
    ./user.nix
    ./snapper.nix
    ../pino/top.nix
    ../pino/package.nix
    ../pino/system.nix
    ../pino/data.nix
  ];
}
