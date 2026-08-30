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
    ../pino/repository.nix
    ../pino/bitwarden.nix
    ../pino/bootstrap.nix
    ../pino/secrets.nix
    ../pino/env.nix
    ../pino/backup.nix
    ../pino/top.nix
  ];
}
