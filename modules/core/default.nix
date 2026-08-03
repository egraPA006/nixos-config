{ ... }:
{
  imports = [
    ../pino.nix
    ./options.nix
    ./system.nix
    ./nix-settings.nix
    ./locale.nix
    ./packages.nix
    ./user.nix
    ../pino/package.nix
    ../pino/system.nix
    ../pino/bootstrap.nix
  ];
}
