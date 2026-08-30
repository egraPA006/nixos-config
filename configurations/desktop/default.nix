{ ... }:
{
  pino.secretVault.enable = true;
  pino.bootstrap.enable = true;

  imports = [
    ../../modules/core
    ../../modules/desktop
    ../../modules/profiles
  ];
}
