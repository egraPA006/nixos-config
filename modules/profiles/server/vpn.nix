{ config, pkgs, ... }:

let
  cfg = config.pino.server.vpn;
  awg = "${pkgs.amneziawg-tools}/bin/awg";
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  table = "pino_vpn_egress";
in
{
  boot.extraModulePackages = [ config.boot.kernelPackages.amneziawg ];
  boot.kernelModules = [ "amneziawg" ];
  networking.nftables.enable = true;
  networking.firewall.allowedUDPPorts = [ cfg.port ];
  networking.firewall.trustedInterfaces = [ cfg.interface ];
  environment.systemPackages = [ pkgs.amneziawg-tools ];

  systemd.services.amneziawg-server = {
    description = "AmneziaWG private server network";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${awgQuick} up ${cfg.configFile}";
      ExecStop = "${awgQuick} down ${cfg.configFile}";
    };
    unitConfig.ConditionPathExists = cfg.configFile;
  };

  pino.bootstrap.secrets."server/awg0.conf" = {
    target = cfg.configFile;
    restartUnits = [ "amneziawg-server.service" ];
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 0;

  pino.subcommands.server.commands.vpn = {
    description = "Operate the AmneziaWG private network";
    commands = {
      on.description = "Start the VPN interface";
      off.description = "Stop the VPN interface";
      status.description = "Show VPN service and peers";
      peers.description = "Show peer handshakes and traffic";
      logs.description = "Show recent VPN service logs";
      mode = {
        description = "Control client Internet forwarding";
        usage = "<private|egress|status>";
      };
    };
    helpText = ''
      pino server vpn status       Show config metadata, service, and interface
      pino server vpn peers        Show safe peer handshake and traffic details
      pino server vpn logs         Show recent service logs
      pino server vpn mode status  Show forwarding and NAT state

      private keeps server/VPN access but disables forwarded Internet traffic.
      egress enables IPv4 forwarding and NAT through the configured external
      interface. The default after boot is private.
    '';
    script = ''
      case "''${1:-}" in
        on) sudo systemctl start amneziawg-server ;;
        off) sudo systemctl stop amneziawg-server ;;
        status)
          sudo test -f ${cfg.configFile} || {
            echo "VPN config is missing: ${cfg.configFile}" >&2
            exit 1
          }
          sudo ${pkgs.coreutils}/bin/stat \
            --format='Config: %n (%U:%G %a)' ${cfg.configFile}
          echo "Interface: ${cfg.interface}"
          echo "UDP port:  ${toString cfg.port}"
          echo
          result=0
          systemctl status amneziawg-server --no-pager || result=1
          sudo ${awg} show ${cfg.interface} || result=1
          exit "$result"
          ;;
        peers) sudo ${awg} show ${cfg.interface} ;;
        logs) journalctl -u amneziawg-server -n 100 --no-pager ;;
        mode)
          case "''${2:-}" in
            private)
              sudo ${pkgs.nftables}/bin/nft delete table inet ${table} 2>/dev/null || true
              sudo ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=0 >/dev/null
              echo "VPN mode: private"
              ;;
            egress)
              external=${if cfg.externalInterface == null then "" else cfg.externalInterface}
              if [ -z "$external" ]; then
                echo "Set pino.server.vpn.externalInterface before enabling egress." >&2
                exit 1
              fi
              sudo ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1 >/dev/null
              sudo ${pkgs.nftables}/bin/nft delete table inet ${table} 2>/dev/null || true
              sudo ${pkgs.nftables}/bin/nft -f - <<EOF
      table inet ${table} {
        chain forward {
          type filter hook forward priority 10; policy accept;
          iifname "${cfg.interface}" oifname "$external" ip saddr ${cfg.clientSubnet} accept
          iifname "$external" oifname "${cfg.interface}" ip daddr ${cfg.clientSubnet} ct state established,related accept
          iifname "${cfg.interface}" oifname "$external" drop
          iifname "$external" oifname "${cfg.interface}" drop
        }
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${cfg.clientSubnet} oifname "$external" masquerade
        }
      }
      EOF
              echo "VPN mode: egress through $external"
              ;;
            status)
              printf 'ip_forward: '
              ${pkgs.procps}/bin/sysctl -n net.ipv4.ip_forward
              sudo ${pkgs.nftables}/bin/nft list table inet ${table} 2>/dev/null || echo "NAT: disabled"
              ;;
            *) echo "Usage: pino server vpn mode <private|egress|status>" >&2; exit 1 ;;
          esac
          ;;
        *) echo "Run 'pino server vpn help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
