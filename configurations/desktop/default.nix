{ ... }:
{
  pino.secretVault.enable = true;

  imports = [
    ../../modules/core
    ../../modules/desktop
    ../../modules/profiles
  ];
}
