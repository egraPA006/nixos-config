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
    ../pino/backup.nix
    ../pino/bitwarden-backup.nix
    ../pino/artifacts.nix
    ../pino/datasets.nix
    ../pino/populate.nix
    ../pino/bootstrap.nix
    ../pino/env.nix
    ../pino/top.nix
  ];
}
