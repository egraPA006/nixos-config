{ activeProfiles, config, lib, pkgs, ... }:


let
  cfg = config.pino.profiles.hotspot;
  ssid = "${config.networking.hostName}-hotspot";
  vaultEnabled = lib.elem "vault" activeProfiles;
  fallbackConnection = pkgs.writeText "hotspot.nmconnection" ''
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

          Connection: ${if vaultEnabled then "provisioned from the encrypted vault" else "local gitignored hotspot.conf fallback"}.
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

    pino.vault.secrets.hotspot-connection = lib.mkIf vaultEnabled {
      source = "hotspot.nmconnection";
      target = "/etc/NetworkManager/system-connections/hotspot.nmconnection";
      mode = "0600";
      restartUnits = [ "NetworkManager.service" ];
    };

    system.activationScripts.hotspot-nmconnection = lib.mkIf (!vaultEnabled) ''
      source=${lib.escapeShellArg "${config.pino.configDir}/secrets/hotspot.conf"}
      if [ -f "$source" ]; then
        ${pkgs.coreutils}/bin/mkdir -p /etc/NetworkManager/system-connections
        password="$(${pkgs.gnused}/bin/sed -n 's/^password=//p' "$source" | ${pkgs.coreutils}/bin/head -n 1)"
        ${pkgs.gnused}/bin/sed "s|__PSK__|$password|" ${fallbackConnection} \
          > /etc/NetworkManager/system-connections/hotspot.nmconnection
        ${pkgs.coreutils}/bin/chmod 0600 /etc/NetworkManager/system-connections/hotspot.nmconnection
      fi
    '';
  };
}
