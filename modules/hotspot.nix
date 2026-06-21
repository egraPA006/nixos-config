{ config, lib, pkgs, ... }:

let
  cfg = config.hotspot;
  ssid = "${config.networking.hostName}-hotspot";

  nmConnection = pkgs.writeText "hotspot.nmconnection" ''
    [connection]
    id=hotspot
    type=wifi
    interface-name=${cfg.wifiInterface}

    [wifi]
    mode=ap
    band=bg
    channel=6
    ssid=${ssid}

    [wifi-security]
    key-mgmt=wpa-psk
    pmf=1
    proto=rsn
    pairwise=ccmp
    group=ccmp
    psk=__PSK__

    [ipv4]
    method=shared

    [ipv6]
    method=disabled
  '';
in
{
  options.hotspot = {
    enable = lib.mkEnableOption "hotspot AP via NetworkManager";

    wifiInterface = lib.mkOption {
      type = lib.types.str;
      description = "WiFi interface to use as AP (e.g. wlp8s0)";
    };

    vpnInterface = lib.mkOption {
      type = lib.types.str;
      default = "awg0";
      description = "VPN interface to NAT hotspot traffic through";
    };
  };

  config = lib.mkIf cfg.enable {
    pino.subcommands.hotspot = {
      description = "WiFi access point";
      script = ''
        case "''${1:-}" in
          start|stop) hotspot "''${1:-}" ;;
          help|*)
            echo "pino hotspot — WiFi AP  (SSID: ${ssid})"
            echo "  pino hotspot start   Bring up AP, traffic routed via VPN"
            echo "  pino hotspot stop    Tear down AP"
            ;;
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

    # Reads secrets/hotspot.conf (password=<psk>) and installs the NM keyfile.
    # Same pattern as the awg0.conf activation script in modules/base/vpn.nix.
    system.activationScripts.hotspot-nmconnection = ''
      mkdir -p /etc/NetworkManager/system-connections
      src="/home/egrapa/nixos-config/secrets/hotspot.conf"
      if [ -f "$src" ]; then
        PSK=$(grep '^password=' "$src" | cut -d= -f2-)
        ${pkgs.gnused}/bin/sed "s|__PSK__|$PSK|" ${nmConnection} \
          > /etc/NetworkManager/system-connections/hotspot.nmconnection
        chmod 600 /etc/NetworkManager/system-connections/hotspot.nmconnection
      fi
    '';
  };
}
