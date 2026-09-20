{ ... }:
{
  pino.secretVault.enable = true;
  pino.bootstrap.enable = true;

  imports = [
    ../../modules/core
    ../../modules/desktop
    ../../modules/pino/files.nix
    ../../modules/profiles
  ];
}
