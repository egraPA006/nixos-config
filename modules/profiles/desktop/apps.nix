{ config, lib, pkgs, ... }:
let
  chromiumLauncher = pkgs.writeShellScriptBin "chromium" ''
    if [ -f "''${XDG_CONFIG_HOME:-$HOME/.config}/pino/chromium-proxy" ]; then
      exec ${pkgs.chromium}/bin/chromium --proxy-server=socks5://127.0.0.1:10808 "$@"
    fi
    exec ${pkgs.chromium}/bin/chromium "$@"
  '';
in
{
  programs.chromium = {
    enable = true;
    extensions = [ "nngceckbapebfimnlniiiahkandclblb" ];
  };

  pino.provision.sshKeys = [
    { item = "pino-ssh-${config.networking.hostName}-github"; target = "${config.pino.user.home}/.ssh/github"; }
    { item = "pino-ssh-server-mosk"; target = "${config.pino.user.home}/.ssh/mosk"; }
    { item = "pino-ssh-server-halos"; target = "${config.pino.user.home}/.ssh/halos"; }
  ];

  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
    (lib.hiPrio chromiumLauncher)
    libreoffice
    imagemagick
    bitwarden-desktop
  ];

}
