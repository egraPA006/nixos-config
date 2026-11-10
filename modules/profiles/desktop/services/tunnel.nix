{ config, lib, pkgs, ... }:
let
  supervisor = pkgs.writeShellApplication {
    name = "pino-tunnel";
    runtimeInputs = with pkgs; [ python3 iproute2 systemd amneziawg-tools sing-box xray ];
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
    description = "Pino system tunnel with application routing";
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
  # Application rules apply to this host, never to forwarded hotspot traffic.
  networking.nftables.tables.pino_tunnel_forward_guard = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -25; policy accept;
        oifname "pino-tun" drop
      }
    '';
  };

  pino.subcommands.vpn.commands.split = {
    description = "Shared AWG/Xray application rules; default is all applications through VPN";
    usage = "[list | default vpn/direct | add vpn/direct executable | remove executable]";
  };
  pino.subcommands.xray = {
    description = "Xray users and full-system desktop connections";
    commands = {
      add-client = {
        description = "Save a client and VLESS URI in Bitwarden, then deploy the server";
        usage = "<mosk|halos> <name> [new-export-directory]";
      };
      remove-client = {
        description = "Revoke a server user and trash its client records";
        usage = "<mosk|halos> <name> [--yes]";
      };
      connect = { description = "Select and autostart a full-system Xray connection"; usage = "<name>"; };
      disconnect.description = "Stop the selected system tunnel and disable autostart";
      status.description = "Show the selected system tunnel";
      list.description = "List provisioned Xray connections";
      split = {
        description = "Shared application routing; same policy as pino vpn split";
        usage = "[list | default vpn/direct | add vpn/direct executable | remove executable]";
      };
    };
    script = ''
      case "''${1:-}" in
        add-client|remove-client)
          export PINO_SERVER_SECRETS=${../../../../scripts/server-secrets.py}
          export PINO_PROXY_SETTINGS=${../../../../resources/mosk-proxies.json}
          export PINO_HALOS_PROXY_SETTINGS=${../../../../resources/halos-proxies.json}
          export PATH=${lib.makeBinPath [ pkgs.git pkgs.bitwarden-cli ]}:"$PATH"
          exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../../../scripts/xray-client.py} "$@"
          ;;
        connect)
          [ "$#" -eq 2 ] || { echo "Usage: pino xray connect <name>" >&2; exit 1; }
          [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]] || { echo "Invalid connection name" >&2; exit 1; }
          sudo test -f "/etc/pino/xray-client/$2.json" || { echo "Provision this Xray connection first" >&2; exit 1; }
          pino vpn disconnect all
          exec sudo ${tunnel} connect xray "$2"
          ;;
        disconnect) exec pino vpn disconnect all ;;
        status) exec sudo ${tunnel} status ;;
        list) exec sudo ${tunnel} list xray ;;
        split) shift; exec sudo ${tunnel} split "$@" ;;
        *) echo "Run 'pino xray help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
  # The AWG command retains its existing hotspot and connection selection UI.
  _module.args.pinoTunnel = tunnel;
}
