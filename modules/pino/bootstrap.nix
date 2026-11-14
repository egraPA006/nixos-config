{ config, lib, pkgs, ... }:

let
  cfg = config.pino.bootstrap;
in
{
  options.pino.bootstrap.enable = lib.mkEnableOption "remote Pino server installation";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ git openssh ];


  };
}
