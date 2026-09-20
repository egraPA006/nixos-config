{ config, pkgs, ... }:
let
  disableOpenrgbLogitechDetector = pkgs.writeShellScript "disable-openrgb-logitech-detector" ''
    set -eu
    settings="$1"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$settings")"
    if [ ! -f "$settings" ]; then
      printf '{}\n' > "$settings"
    fi
    if ${pkgs.jq}/bin/jq -e '.Detectors.detectors["Logitech HID++ 2.0"] == false' "$settings" >/dev/null; then
      exit 0
    fi
    temporary="$(${pkgs.coreutils}/bin/mktemp "''${settings}.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$temporary"' EXIT
    ${pkgs.jq}/bin/jq '.Detectors.detectors["Logitech HID++ 2.0"] = false' "$settings" > "$temporary"
    ${pkgs.coreutils}/bin/mv "$temporary" "$settings"
  '';
in
{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../configurations/desktop
    ../../modules/hardware/nvidia.nix
  ];

  pino.user = {
    name = "egrapa";
    home = "/home/egrapa";
  };
  pino.configDir = "${config.pino.user.home}/nixos-config";

  pino.profiles = {
    vpn.share.wifiInterface = "wlp8s0";
    musicLite.localDir = "/data/fast/music-lite";
    musicFull = {
      localDir = "/data/fast/music-full";
      winePrefix = "/data/fast/music-full/wine-prefix";
    };
    torrent.localDir = "/data/fast/torrent";
  };

  networking.hostName = "re-1";

  systemd.tmpfiles.rules = [
    "z /data/fast 0755 ${config.pino.user.name} users -"
    "z /data/slow 0755 ${config.pino.user.name} users -"
  ];

  services.hardware.openrgb.enable = true;
  systemd.services.openrgb.preStart = ''
    ${disableOpenrgbLogitechDetector} /var/lib/OpenRGB/OpenRGB.json
  '';

  environment.etc."systemd/sleep.conf.d/nosuspend.conf".text = ''
    [Sleep]
    AllowSuspend=no
    AllowHibernation=no
    AllowSuspendThenHibernate=no
    AllowHybridSleep=no
  '';

  programs.ssh.extraConfig = ''
    Host github.com
      IdentityAgent none
      IdentityFile ${config.pino.user.home}/.ssh/github
      IdentitiesOnly yes

    Host mosk
      HostName vpn.egrapa.com
      User vincent
      IdentityAgent none
      IdentityFile ${config.pino.user.home}/.ssh/mosk
      IdentitiesOnly yes
  '';

  home-manager.users.${config.pino.user.name} = { lib, ... }: {
    home.activation.disableOpenrgbLogitechDetector =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${disableOpenrgbLogitechDetector} "$HOME/.config/OpenRGB/OpenRGB.json"
      '';
    systemd.user.services.monitor-default = {
      Unit.Description = "Apply default single-monitor profile";
      Unit.After = [ "graphical-session.target" ];
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "oneshot";
        ExecStart = "/run/current-system/sw/bin/monitor switch single";
        RemainAfterExit = false;
      };
    };
    systemd.user.services.openrgb-init = {
      Unit.Description = "Set OpenRGB default colors";
      Unit.After = [ "graphical-session.target" ];
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.openrgb}/bin/openrgb --color FF70AB";
        RemainAfterExit = false;
      };
    };
  };
  system.stateVersion = "25.05";
}
