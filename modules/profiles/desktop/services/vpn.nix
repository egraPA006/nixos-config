{
  pkgs,
  config,
  lib,
  pinoTunnel,
  pinoProvisionSend,
  ...
}:

let
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  share = config.pino.profiles.vpn.share;
  vpnGuard = pkgs.writeShellScript "pino-vpn-guard" ''
    set -euo pipefail
    table=pino_vpn_guard

    clear() {
      ${pkgs.nftables}/bin/nft delete table inet "$table" 2>/dev/null || true
    }

    apply() {
      local interface="$1"
      [[ "$interface" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] || {
        echo "Invalid VPN interface: $interface" >&2
        return 1
      }
      clear
      ${pkgs.nftables}/bin/nft -f - <<EOF
table inet $table {
  chain forward {
    type filter hook forward priority -15; policy accept;
    oifname "$interface" drop
  }
}
EOF
    }

    case "''${1:-}" in
      apply) apply "''${2:-}" ;;
      apply-marker)
        marker=/var/lib/amneziawg/autostart
        if [ -s "$marker" ]; then
          interface="$(${pkgs.coreutils}/bin/cat "$marker")"
          if ${pkgs.systemd}/bin/systemctl is-active --quiet "amneziawg@$interface.service"; then
            apply "$interface"
          else
            clear
          fi
        else
          clear
        fi
        ;;
      clear) clear ;;
      *) echo "Usage: $0 <apply INTERFACE|apply-marker|clear>" >&2; exit 1 ;;
    esac
  '';
in
{
  imports = [ ./tunnel.nix ];
  pino.provision.secrets = [
    { item = "pino-vpn-client-${config.networking.hostName}-mosk"; target = "/etc/amneziawg/mosk.conf"; }
    { item = "pino-vpn-client-${config.networking.hostName}-halos"; target = "/etc/amneziawg/halos.conf"; }
    { item = "pino-hotspot-${config.networking.hostName}"; target = "/etc/NetworkManager/system-connections/${share.connection}.nmconnection"; }
  ];

  programs.amnezia-vpn.enable = true;

  systemd.tmpfiles.rules = [
    "d /etc/amneziawg 0755 root root -"
  ];

  boot.extraModulePackages = [ config.boot.kernelPackages.amneziawg ];
  boot.kernelModules = [ "amneziawg" ];
  networking.nftables.enable = true;

  environment.systemPackages = with pkgs; [
    amneziawg-tools
    nftables
    procps
  ];

  systemd.services."amneziawg@" = {
    description = "AmneziaWG VPN connection %i";
    after = [ "network.target" ];
    wantedBy = [ ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${awgQuick} up /etc/amneziawg/%i.conf";
      ExecStop = "${awgQuick} down /etc/amneziawg/%i.conf";
    };
    unitConfig.ConditionPathExists = "/etc/amneziawg/%i.conf";
  };

  systemd.services.amneziawg-autostart = {
    description = "AmneziaWG VPN autostart";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "amneziawg-autostart" ''
        marker=/var/lib/amneziawg/autostart
        selected=/var/lib/pino/tunnel/selected.json
        if [ -f "$selected" ]; then
          name="$(${pkgs.python3}/bin/python3 -c 'import json,sys; x=json.load(open(sys.argv[1])); print(x.get("name", "") if x.get("kind") == "awg" else "")' "$selected")"
          if [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]] && [ -f "/etc/amneziawg/$name.conf" ]; then
            if [ ! -f "$marker" ]; then
              ${pkgs.coreutils}/bin/install -d -m 0700 /var/lib/amneziawg
              ${pkgs.coreutils}/bin/printf '%s\n' "$name" > "$marker"
              ${pkgs.coreutils}/bin/chmod 0600 "$marker"
            fi
            ${pkgs.coreutils}/bin/rm -f "$selected"
          fi
        fi
        [ -f "$marker" ] || exit 0
        name="$(${pkgs.coreutils}/bin/cat "$marker")"
        if [ -z "$name" ] && [ -f /etc/amneziawg/awg0.conf ]; then
          name=awg0
          ${pkgs.coreutils}/bin/printf '%s\n' "$name" > "$marker"
          ${pkgs.coreutils}/bin/chmod 0600 "$marker"
        fi
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]] || exit 1
        [ -f "/etc/amneziawg/$name.conf" ] || exit 1
        ${pkgs.systemd}/bin/systemctl start "amneziawg@$name.service"
      '';
    };
  };

  systemd.services.pino-vpn-client-guard = {
    description = "Keep ordinary hotspot traffic out of the active VPN";
    after = [ "amneziawg-autostart.service" "firewall.service" ];
    partOf = [ "firewall.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${vpnGuard} apply-marker";
      ExecStop = "${vpnGuard} clear";
    };
  };

  pino.subcommands.vpn = {
    description = "AWG and Xray VPN connections";
    commands = {
      users = {
        description = "Manage AWG and Xray users in Bitwarden and on servers";
        commands = {
          add = { description = "Create and deploy a user"; usage = "<awg|xray> <mosk|halos> <name> [export-directory]"; };
          remove = { description = "Revoke a user"; usage = "<awg|xray> <mosk|halos> <name> [--yes]"; };
          list = { description = "Compare users in Bitwarden and on the server"; usage = "<awg|xray> <mosk|halos>"; };
        };
      };
      list.description = "List installed named VPN connections";
      server = {
        description = "Control server forwarding over SSH";
        commands.mode = {
          description = "Show or select the server VPN mode";
          usage = "<mosk|halos> [private|egress|full]";
        };
      };
      connect = {
        description = "Select, start, and autostart a connection";
        usage = "[awg|xray] [name]";
      };
      disconnect = {
        description = "Stop one or all connections and disable autostart";
        usage = "[name|all]";
      };
      status = {
        description = "Show active VPN connections and peers";
        usage = "[name]";
      };
      share = {
        description = "Explicitly share the active VPN over a dedicated WiFi hotspot";
        commands = {
          start.description = "Start the VPN-only hotspot";
          stop.description = "Stop the VPN-only hotspot";
          status.description = "Show VPN sharing state";
        };
      };
    };
    helpText = ''
      Store complete configs as uniquely named Bitwarden Secure Notes, then run
      `pino os provision` to install the files declared by this profile.
      Pino selects one connection at a time. Xray provides a local SOCKS proxy;
      AWG uses the routes in its profile.
      `share` only affects the dedicated `${share.connection}` connection. A hotspot
      created normally in GNOME keeps NetworkManager's normal routing behaviour.
      After provisioning the `${share.connection}.nmconnection` Secure Note,
      run `sudo nmcli connection reload`.
    '';
    script = ''
      if [ "''${1:-}" = users ]; then
        [ "$#" -ge 3 ] || { echo 'Usage: pino vpn users <list|add|remove> <awg|xray> <host> ...' >&2; exit 1; }
        operation="''${2:-}"
        kind="''${3:-}"
        shift 3
        export PINO_SERVER_SECRETS=${../../../../scripts/server-secrets.py}
        export PINO_PROVISION_SEND=${pinoProvisionSend}
        export PINO_PROXY_SETTINGS=${../../../../resources/mosk-proxies.json}
        export PINO_HALOS_PROXY_SETTINGS=${../../../../resources/halos-proxies.json}
        export PATH=${lib.makeBinPath [ pkgs.amneziawg-tools pkgs.git pkgs.bitwarden-cli ]}:"$PATH"
        if [ "$operation" = add ] && [ "$kind" = awg ] && [ "$#" -eq 2 ] && [ -t 0 ]; then
          read -r -p 'New export directory: ' export_dir
          [ -n "$export_dir" ] || { echo 'An export directory is required.' >&2; exit 1; }
          set -- "$@" "$export_dir"
        fi
        case "$operation:$kind" in
          list:awg|list:xray) exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../../../scripts/vpn-client.py} --list "$kind" "$@" ;;
          add:awg) exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../../../scripts/vpn-client.py} "$@" ;;
          remove:awg) exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../../../scripts/vpn-client.py} --remove "$@" ;;
          add:xray|remove:xray) exec ${pkgs.python3.withPackages (p: [ p.bcrypt ])}/bin/python3 ${../../../../scripts/xray-client.py} "$operation" "$@" ;;
          *) echo 'Usage: pino vpn users <list|add|remove> <awg|xray> <host> ...' >&2; exit 1 ;;
        esac
      fi
      VPN_SHARE_WIFI=${lib.escapeShellArg (if share.wifiInterface == null then "" else share.wifiInterface)}
      VPN_SHARE_CONNECTION=${lib.escapeShellArg share.connection}
      VPN_GUARD=${vpnGuard}
      PINO_TUNNEL=${pinoTunnel}
      GSETTINGS=${pkgs.glib}/bin/gsettings
      ${builtins.readFile ../../../pino/vpn.sh}
    '';
  };
}
