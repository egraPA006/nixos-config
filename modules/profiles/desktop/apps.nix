{ config, lib, pkgs, ... }:
let
  clashmi = pkgs.callPackage ../../../pkgs/clashmi.nix { };
  clashmiTmpfiles = pkgs.writeText "clashmi-tmpfiles.conf" ''
    d /var/lib/pino-clashmi 0755 root root -
    C /var/lib/pino-clashmi/${builtins.baseNameOf clashmi} 0755 root root - ${clashmi}/opt/clashmi
  '';
  chromiumLauncher = pkgs.writeShellScriptBin "chromium" ''
    if [ -f "''${XDG_CONFIG_HOME:-$HOME/.config}/pino/chromium-proxy" ]; then
      exec ${pkgs.chromium}/bin/chromium --proxy-server=socks5://127.0.0.1:10808 "$@"
    fi
    exec ${pkgs.chromium}/bin/chromium "$@"
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/pino-clashmi 0755 root root -"
    "C /var/lib/pino-clashmi/${builtins.baseNameOf clashmi} 0755 root root - ${clashmi}/opt/clashmi"
  ];
  system.activationScripts.clashmi = lib.stringAfter [ "etc" ] ''
    ${pkgs.systemd}/bin/systemd-tmpfiles --create ${clashmiTmpfiles}
  '';
  programs.chromium = {
    enable = true;
    extensions = [ "nngceckbapebfimnlniiiahkandclblb" ];
  };

  pino.provision.sshKeys = [
    { item = "pino-ssh-${config.networking.hostName}-github"; target = "${config.pino.user.home}/.ssh/github"; }
    { item = "pino-ssh-server-mosk"; target = "${config.pino.user.home}/.ssh/mosk"; }
    { item = "pino-ssh-server-halos"; target = "${config.pino.user.home}/.ssh/halos"; }
  ];

  pino.provision.userSecrets = [{
    item = "pino-clashmi-subscription";
    target = "${config.pino.user.home}/.config/pino/clashmi-subscription";
  }];

  environment.systemPackages = with pkgs; [
    telegram-desktop
    chromium
    (lib.hiPrio chromiumLauncher)
    libreoffice
    imagemagick
    bitwarden-desktop
    clashmi
  ];

}
