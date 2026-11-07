{ ... }:
{
  pino.secretVault.enable = true;
  pino.bootstrap.enable = true;

  imports = [
    ../../modules/core
    ../../modules/desktop
    ../../modules/pino/files.nix
    ../../modules/pino/artifacts.nix
    ../../modules/pino/host.nix
    ../../modules/profiles
  ];
}
