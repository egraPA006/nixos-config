{ ... }:
{
  pino.bootstrap.enable = true;

  imports = [
    ../../modules/core
    ../../modules/desktop
    ../../modules/pino/host.nix
    ../../modules/profiles
  ];
}
