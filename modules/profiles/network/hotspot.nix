{ config, pkgs, ... }:


let
  cfg = config.pino.profiles.hotspot;
  ssid = "${config.networking.hostName}-hotspot";
in
{
  config = {
    pino.subcommands.network.commands.hotspot = {
      description = "WiFi access point";
      commands = {
        start.description = "Bring up the access point";
        stop.description = "Tear down the access point";
      };
      helpText = ''
        pino network hotspot — WiFi access point  (SSID: ${ssid})
          pino network hotspot start   Bring up AP, traffic routed via VPN
          pino network hotspot stop    Tear down AP

          Connection: provisioned from this host's encrypted secret projection.
      '';
      script = ''
        case "''${1:-}" in
          start|stop) hotspot "''${1:-}" ;;
          *) echo "Usage: pino network hotspot start|stop" >&2; exit 1 ;;
        esac
      '';
    };

    networking.firewall.trustedInterfaces = [ cfg.wifiInterface ];

    networking.nat = {
      enable = true;
      externalInterface = cfg.vpnInterface;
      internalInterfaces = [ cfg.wifiInterface ];
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "hotspot" ''
        case "$1" in
          start) nmcli con up hotspot ifname ${cfg.wifiInterface} ;;
          stop)  nmcli con down hotspot ;;
          *) echo "Usage: hotspot start|stop" ;;
        esac
      '')
    ];

    pino.secrets.entries.hotspot-connection = {
      source = "hotspot.nmconnection";
      target = "/etc/NetworkManager/system-connections/hotspot.nmconnection";
      mode = "0600";
      restartUnits = [ "NetworkManager.service" ];
    };

  };
}
