{ config, lib, pkgs, ... }:
let
  supervisor = pkgs.writeShellApplication {
    name = "pino-tunnel";
    runtimeInputs = with pkgs; [ python3 iproute2 systemd amneziawg-tools xray ];
    text = ''exec python3 ${../../../../scripts/tunnel.py} "$@"'';
  };
  tunnel = "${supervisor}/bin/pino-tunnel";
in {
  pino.provision.secrets = map (host: {
    item = "pino-xray-client-${config.networking.hostName}-${host}";
    target = "/etc/pino/xray-client/${host}.json";
  }) [ "mosk" "halos" ];

  systemd.tmpfiles.rules = [ "d /etc/pino/xray-client 0700 root root -" ];
  systemd.services.pino-tunnel = {
    description = "Pino Xray local SOCKS proxy";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "amneziawg-autostart.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/var/lib/pino/tunnel/selected.json";
    path = with pkgs; [ iproute2 ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = "${tunnel} serve";
      ExecStopPost = "${tunnel} cleanup";
      RuntimeDirectory = "pino-tunnel";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "pino/tunnel";
      StateDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = 45;
      TimeoutStopSec = 30;
      KillMode = "mixed";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  pino.subcommands.vpn.commands.split = {
    description = "Set GNOME or Chromium proxy mode for Xray";
    usage = "<on|off|chromium>";
  };
  # The AWG command retains its existing hotspot and connection selection UI.
  _module.args.pinoTunnel = tunnel;
}
