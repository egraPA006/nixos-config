# Mutable state ownership. Keep shared resources until their last owner is disabled.
{ config, lib, pkgs, activeProfiles, profiles }:
let
  user = config.pino.user;
  home = user.home;
  cfg = config.pino.profiles;
  hm = config.home-manager.users.${user.name};
  c = hm.xdg.configHome;
  d = hm.xdg.dataHome;
  cache = hm.xdg.cacheHome;
  resource = owners: paths: { inherit owners paths; };
  wineOwners = [ "music-full" "guitar-pro" "gaming-full" ];
  manifest = pkgs.writeText "pino-profile-cleanup.json" (builtins.toJSON {
    inherit profiles;
    user = user.name;
    configHome = c;
    dataHome = d;
    cacheHome = cache;
    protected = [ "/" "/etc" "/var" "/var/lib" "/var/lib/private" "/var/log" "/home" "/root" "/nix" "/nix/store" "/run" "/tmp" "/opt" "/srv" "/mnt" "/media" home c d cache config.pino.configDir ];
    forbiddenTrees = [ "/nix" "/proc" "/sys" "/dev" "/usr" "/bin" "/sbin" "/lib" "/lib64" "/boot" ];
    keep = [
      "${cfg.musicFull.localDir}/installs"
      "${cfg.guitarPro.localDir}/installs"
    ] ++ lib.optional (cfg.guitarPro.replacementExe != null) cfg.guitarPro.replacementExe;
    tools = {
      env = "${pkgs.coreutils}/bin/env";
      runuser = "${pkgs.util-linux}/bin/runuser";
      timeout = "${pkgs.coreutils}/bin/timeout";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      dconf = "${pkgs.dconf}/bin/dconf";
      dbusRunSession = "${pkgs.dbus}/bin/dbus-run-session";
      nmcli = "${pkgs.networkmanager}/bin/nmcli";
      nft = "${pkgs.nftables}/bin/nft";
      sysctl = "${pkgs.procps}/bin/sysctl";
    } // lib.optionalAttrs (lib.any (p: builtins.elem p activeProfiles) wineOwners) {
      wineserver = "${pkgs.wineWow64Packages.stable}/bin/wineserver";
    };
    resources = [
      ((resource [ "guitar-pro" ] [ cfg.guitarPro.localDir cfg.guitarPro.winePrefix ]) // {
        winePrefixes = [ cfg.guitarPro.winePrefix ];
        processes = [ "GuitarPro.exe" ];
      })
      ((resource [ "music-full" ] [
        cfg.musicFull.localDir cfg.musicFull.winePrefix
        "${c}/REAPER" "${c}/yabridgectl" "${c}/carla" "${c}/falkTX"
        "${d}/surge-xt" "${d}/Surge XT" "${c}/surge-xt" "${c}/drumgizmo"
        "${home}/.vst/yabridge" "${home}/.vst3/yabridge" "${home}/.clap/yabridge"
        "${cache}/REAPER"
      ]) // {
        winePrefixes = [ cfg.musicFull.winePrefix ];
        processes = [ "reaper" "yabridge-host" "yabridge-host.exe" "yabridge-host-32.exe" "carla" ];
      })
      ((resource [ "music-lite" ] [ cfg.musicLite.localDir "${c}/lingot" "${home}/.lingot" "${c}/neural-amp-modeler-lv2" "/tmp/pino-music-lite-tuner.pid" ]) // {
        processes = [ "jalv" "lingot" ];
        runtimePaths = [ "pino/music-lite" ];
      })
      ((resource [ "workstation" "music-lite" "music-full" ] [
        "${c}/rncbc.org/qpwgraph.conf" "${c}/qpwgraph" "${c}/pulse" "${home}/.local/state/wireplumber"
      ]) // { processes = [ "qpwgraph" ]; })
      ((resource wineOwners [ "${cache}/wine" "${cache}/winetricks" "${d}/applications/wine" ]) // {
        patterns = [ "${c}/menus/applications-merged/wine-*.menu" "${d}/desktop-directories/wine-*.directory" ];
      })
      ((resource [ "torrent" ] [ cfg.torrent.localDir config.services.transmission.home "${c}/transmission" "${cache}/transmission" ]) // {
        services = [ "transmission.service" ];
      })
      ((resource [ "gaming-lite" "gaming-full" ] [
        "${d}/Steam" "${home}/.steam" "${home}/.steampath" "${home}/.steampid"
        "${c}/MangoHud" "${c}/gamemode.ini" "${cache}/protonfixes" "${home}/Games"
      ]) // { processes = [ "steam" "steamwebhelper" ]; })
      ((resource [ "gaming-full" ] [
        "${c}/lutris" "${d}/lutris" "${cache}/lutris" "${c}/boxflat"
        "${c}/r2modman" "${c}/r2modmanPlus-local" "${cache}/r2modman" "${home}/.wine"
      ]) // { processes = [ "lutris" "boxflat" "r2modman" ]; })
      ((resource [ "workstation" ] [
        "${c}/chromium" "${cache}/chromium" "${d}/TelegramDesktop"
        "${c}/libreoffice" "${cache}/libreoffice" "${c}/Bitwarden" "${cache}/com.bitwarden.desktop"
        "${c}/ImageMagick" "${home}/.magick"
      ]) // { processes = [ "chromium" "chrome" "Telegram" "telegram-desktop" "soffice.bin" "bitwarden" ]; })
      ((resource [ "workstation" "gnome" ] [ "/var/lib/bluetooth" ]) // {
        services = [ "bluetooth.service" ];
      })
      ((resource [ "workstation" ] [ "${c}/blueman" "${cache}/blueman" ]) // {
        dconf = [ "/org/blueman/" ];
      })
      ((resource [ "development" ] [
        "${c}/Code" "${home}/.vscode" "${cache}/Microsoft" "${home}/.codex"
        "${c}/git" "${home}/.gitconfig"
      ]) // { processes = [ "code" "codex" ]; })
      ((resource [ "gnome" ] [
        "${c}/monitor-profiles" "${c}/monitors.xml" "${c}/monitors.xml~" "${c}/tiling-assistant"
        "${c}/gnome-initial-setup-done" "${c}/.gsd-keyboard.settings-ported"
        "${c}/nautilus" "${d}/nautilus" "${d}/gnome-shell" "${d}/gnome-settings-daemon"
        "${c}/evolution" "${d}/evolution" "${cache}/evolution" "${c}/goa-1.0"
        "${d}/org.gnome.TextEditor" "${cache}/gnome-desktop-thumbnailer"
        "${cache}/clipboard-history@alexsaveau.dev" "${cache}/tracker3"
      ]) // {
        processes = [ "gnome-shell" "nautilus" ];
        dconf = [ "/org/gnome/" ];
      })
      ((resource [ "vpn-client" ] [
        "/etc/amneziawg" "/var/lib/amneziawg" "/run/pino-vpn-share"
        "/etc/NetworkManager/system-connections/${cfg.vpn.share.connection}.nmconnection"
        "${c}/AmneziaVPN" "${d}/AmneziaVPN" "${cache}/AmneziaVPN"
      ]) // {
        services = [ "amneziawg-autostart.service" "pino-vpn-client-guard.service" "amneziawg@*.service" ];
        vpnShare = cfg.vpn.share.connection;
      })
      ((resource [ "server-vpn" ] [ config.pino.server.vpn.configFile "/var/lib/pino/vpn" ]) // {
        services = [ "amneziawg-server.service" "pino-vpn-mode.service" ];
      })
      ((resource [ "server-galene" ] [ config.services.galene.stateDir "/etc/pino/galene" ]) // {
        services = [ "galene.service" ];
      })
      ((resource [ "server-web" "server-galene" ] [ config.services.caddy.dataDir "/var/lib/private/caddy" "/var/log/caddy" ]) // {
        services = [ "caddy.service" ];
      })
    ];
  });
in
{
  inherit manifest;
  runner = pkgs.writeShellScript "pino-profile-cleanup" ''
    exec ${pkgs.python3}/bin/python3 ${../../scripts/profile-cleanup.py} ${manifest} "$@"
  '';
}
