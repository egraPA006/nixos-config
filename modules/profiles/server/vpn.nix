{ config, lib, pkgs, ... }:

let
  cfg = config.pino.server.vpn;
  awg = "${pkgs.amneziawg-tools}/bin/awg";
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  table = "pino_vpn_egress";
  vpnMode = pkgs.writeShellScript "pino-vpn-mode" ''
    set -euo pipefail

    operation="''${1:-apply}"
    requested="''${2:-}"
    state_dir=/var/lib/pino/vpn
    mode_file="$state_dir/mode"
    external_override=${lib.escapeShellArg (if cfg.externalInterface == null then "" else cfg.externalInterface)}

    stored_mode() {
      if [ -f "$mode_file" ]; then
        ${pkgs.coreutils}/bin/cat "$mode_file"
      else
        echo private
      fi
    }

    external_interface() {
      if [ -n "$external_override" ]; then
        echo "$external_override"
        return
      fi
      ${pkgs.iproute2}/bin/ip -4 route show default \
        | ${pkgs.gawk}/bin/awk '$1 == "default" { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }'
    }

    apply_mode() {
      local mode="$1" external
      case "$mode" in
        private|egress|full)
          external="$(external_interface)"
          if [ "$mode" != private ] && [ -z "$external" ]; then
            echo "Cannot determine the default IPv4 interface; set pino.server.vpn.externalInterface." >&2
            return 1
          fi
          ${pkgs.nftables}/bin/nft delete table inet ${table} 2>/dev/null || true
          ${pkgs.nftables}/bin/nft -f - <<EOF
    table inet ${table} {
      chain input {
        type filter hook input priority -10; policy accept;
        $(if [ "$mode" = egress ]; then printf 'iifname "%s" drop' "${cfg.interface}"; fi)
      }
      chain forward {
        type filter hook forward priority -10; policy accept;
        $(if [ "$mode" != egress ]; then printf 'iifname "%s" oifname "%s" ip saddr %s accept' "${cfg.interface}" "${cfg.interface}" "${cfg.clientSubnet}"; fi)
        $(if [ "$mode" != private ]; then printf 'iifname "%s" oifname "%s" ip saddr %s accept' "${cfg.interface}" "$external" "${cfg.clientSubnet}"; fi)
        $(if [ "$mode" != private ]; then printf 'iifname "%s" oifname "%s" ip daddr %s ct state established,related accept' "$external" "${cfg.interface}" "${cfg.clientSubnet}"; fi)
        iifname "${cfg.interface}" drop
        oifname "${cfg.interface}" drop
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        $(if [ "$mode" != private ]; then printf 'ip saddr %s oifname "%s" masquerade' "${cfg.clientSubnet}" "$external"; fi)
      }
    }
    EOF
          ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1 >/dev/null
          ;;
        *) echo "Invalid VPN mode in $mode_file: $mode" >&2; return 1 ;;
      esac
    }

    cleanup_rules() {
      ${pkgs.nftables}/bin/nft delete table inet ${table} 2>/dev/null || true
      ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=0 >/dev/null
    }

    write_mode() {
      local mode="$1" replacement
      ${pkgs.coreutils}/bin/install -d -m 0700 "$state_dir"
      replacement="$(${pkgs.coreutils}/bin/mktemp "$state_dir/mode.XXXXXX")"
      cleanup() { ${pkgs.coreutils}/bin/rm -f "$replacement"; }
      trap cleanup EXIT INT TERM
      ${pkgs.coreutils}/bin/printf '%s\n' "$mode" > "$replacement"
      ${pkgs.coreutils}/bin/chmod 0600 "$replacement"
      ${pkgs.coreutils}/bin/mv -f "$replacement" "$mode_file"
      trap - EXIT INT TERM
    }

    case "$operation" in
      apply)
        mode="$(stored_mode)"
        apply_mode "$mode"
        echo "VPN mode: $mode"
        ;;
      set)
        case "$requested" in private|egress|full) ;; *) echo "Usage: $0 set <private|egress|full>" >&2; exit 1 ;; esac
        apply_mode "$requested"
        write_mode "$requested"
        echo "VPN mode: $requested"
        ;;
      status)
        mode="$(stored_mode)"
        echo "Stored mode: $mode"
        external="$(external_interface || true)"
        echo "External interface: ''${external:-unavailable}"
        printf 'ip_forward: '
        ${pkgs.procps}/bin/sysctl -n net.ipv4.ip_forward
        ${pkgs.nftables}/bin/nft list table inet ${table} 2>/dev/null || echo "NAT: disabled"
        ;;
      cleanup)
        cleanup_rules
        echo "VPN forwarding disabled"
        ;;
      *) echo "Usage: $0 <apply|set MODE|status|cleanup>" >&2; exit 1 ;;
    esac
  '';
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

  systemd.services.pino-vpn-mode = {
    description = "Apply the persisted Pino VPN forwarding mode";
    after = [ "amneziawg-server.service" "firewall.service" ];
    requires = [ "amneziawg-server.service" ];
    partOf = [ "amneziawg-server.service" "firewall.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${vpnMode} apply";
      ExecStop = "${vpnMode} cleanup";
    };
    unitConfig.ConditionPathExists = cfg.configFile;
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 0;

  pino.subcommands.server.commands.vpn = {
    description = "Operate the AmneziaWG private network";
    commands = {
      start.description = "Start the VPN interface";
      stop.description = "Stop the VPN interface";
      status.description = "Show VPN service and peers";
      peers.description = "Show peer handshakes and traffic";
      logs.description = "Show recent VPN service logs";
      mode = {
        description = "Control client Internet forwarding";
        commands = {
          status.description = "Show forwarding and NAT state";
          set = { description = "Select the persistent forwarding mode"; usage = "<private|egress|full>"; };
        };
      };
    };
    helpText = ''
      private allows the server and VPN peers only. egress exposes only the
      Internet exit and blocks the server and other peers. full enables both
      peer communication and Internet NAT. The mode persists across reboots;
      the initial mode is private.
    '';
    script = ''
      case "''${1:-}" in
        start) sudo systemctl start amneziawg-server pino-vpn-mode ;;
        stop) sudo systemctl stop pino-vpn-mode amneziawg-server ;;
        status)
          sudo test -f ${lib.escapeShellArg cfg.configFile} || {
            echo "VPN config is missing: ${cfg.configFile}" >&2
            exit 1
          }
          sudo ${pkgs.coreutils}/bin/stat \
            --format='Config: %n (%U:%G %a)' ${lib.escapeShellArg cfg.configFile}
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
            status) sudo ${vpnMode} status ;;
            set)
              case "''${3:-}" in
                private|egress|full) sudo ${vpnMode} set "''${3}" ;;
                *) echo "Usage: pino server vpn mode set <private|egress|full>" >&2; exit 1 ;;
              esac
              ;;
            *) echo "Run 'pino server vpn mode help' for usage." >&2; exit 1 ;;
          esac
          ;;
        *) echo "Run 'pino server vpn help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
