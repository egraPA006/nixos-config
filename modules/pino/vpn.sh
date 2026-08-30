#!/usr/bin/env bash
# pino vpn — named AmneziaWG connections and explicit WiFi sharing
set -euo pipefail

config_dir=/etc/amneziawg
marker=/var/lib/amneziawg/autostart
share_table=pino_vpn_share
share_state=/run/pino-vpn-share

valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]]; }

connections() {
  local config
  shopt -s nullglob
  for config in "$config_dir"/*.conf; do
    basename "${config%.conf}"
  done
}

select_name() {
  local requested="${1:-}"
  local -a available
  if [ -n "$requested" ]; then
    valid_name "$requested" || { echo "Invalid VPN connection name: $requested" >&2; return 1; }
    [ -f "$config_dir/$requested.conf" ] || { echo "VPN connection is not installed: $requested" >&2; return 1; }
    printf '%s\n' "$requested"
    return
  fi
  mapfile -t available < <(connections)
  case "${#available[@]}" in
    0) echo "No VPN configurations are installed." >&2; return 1 ;;
    1) printf '%s\n' "${available[0]}" ;;
    *) echo "Several VPN connections exist; specify one: ${available[*]}" >&2; return 1 ;;
  esac
}

stop_active() {
  local unit
  while read -r unit; do
    [ -n "$unit" ] || continue
    sudo systemctl stop "$unit"
  done < <(systemctl list-units --type=service --state=active --plain --no-legend 'amneziawg@*.service' | awk '{print $1}')
}

guard_apply() { sudo "$VPN_GUARD" apply "$1"; }
guard_clear() { sudo "$VPN_GUARD" clear; }
guard_restore() {
  local vpn
  if vpn="$(active_connection 2>/dev/null)"; then
    guard_apply "$vpn"
  else
    guard_clear
  fi
}

active_connection() {
  local unit name
  mapfile -t units < <(systemctl list-units --type=service --state=active --plain --no-legend 'amneziawg@*.service' | awk '{print $1}')
  [ "${#units[@]}" -eq 1 ] || { echo "VPN sharing requires exactly one active connection." >&2; return 1; }
  unit="${units[0]}"
  name="${unit#amneziawg@}"
  printf '%s\n' "${name%.service}"
}

wifi_interface() {
  if [ -n "${VPN_SHARE_WIFI:-}" ]; then
    printf '%s\n' "$VPN_SHARE_WIFI"
  else
    nmcli -t -f DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1; exit }'
  fi
}

share_stop() {
  nmcli connection down "$VPN_SHARE_CONNECTION" >/dev/null 2>&1 || true
  sudo nft delete table inet "$share_table" 2>/dev/null || true
  if sudo test -f "$share_state/ip_forward"; then
    previous="$(sudo cat "$share_state/ip_forward")"
    [[ "$previous" =~ ^[01]$ ]] && sudo sysctl -w "net.ipv4.ip_forward=$previous" >/dev/null
  fi
  sudo rm -f "$share_state/ip_forward"
  sudo rmdir "$share_state" 2>/dev/null || true
  guard_restore
}

share_start() {
  local vpn wifi previous
  vpn="$(active_connection)"
  wifi="$(wifi_interface)"
  [[ "$vpn" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] || { echo "Invalid VPN interface: $vpn" >&2; return 1; }
  [[ "$wifi" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] || { echo "Cannot determine a safe WiFi interface." >&2; return 1; }
  nmcli -g NAME connection show "$VPN_SHARE_CONNECTION" >/dev/null 2>&1 || {
    echo "NetworkManager connection is missing: $VPN_SHARE_CONNECTION" >&2
    echo "Create a dedicated WiFi hotspot with that name, then retry." >&2
    return 1
  }

  share_stop
  guard_clear
  previous="$(sysctl -n net.ipv4.ip_forward)"
  sudo install -d -m 0700 "$share_state"
  printf '%s\n' "$previous" | sudo tee "$share_state/ip_forward" >/dev/null
  sudo nft -f - <<EOF
table inet $share_table {
  chain forward {
    type filter hook forward priority -20; policy accept;
    iifname "$wifi" oifname "$vpn" accept
    iifname "$vpn" oifname "$wifi" ct state established,related accept
    iifname "$wifi" drop
    oifname "$wifi" drop
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    iifname "$wifi" oifname "$vpn" masquerade
  }
}
EOF
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
  if ! nmcli connection up "$VPN_SHARE_CONNECTION" ifname "$wifi"; then
    share_stop
    return 1
  fi
  printf 'Sharing VPN %s over %s using %s\n' "$vpn" "$wifi" "$VPN_SHARE_CONNECTION"
}

case "${1:-}" in
  list)
    selected="$(sudo cat "$marker" 2>/dev/null || true)"
    printf '%-18s %-10s %s\n' CONNECTION ACTIVE AUTOSTART
    while IFS= read -r name; do
      active=no
      autostart=no
      systemctl is-active --quiet "amneziawg@$name.service" && active=yes
      [ "$selected" = "$name" ] && autostart=yes
      printf '%-18s %-10s %s\n' "$name" "$active" "$autostart"
    done < <(connections)
    ;;
  connect)
    name="$(select_name "${2:-}")"
    share_stop
    stop_active
    sudo install -d -m 0700 /var/lib/amneziawg
    printf '%s\n' "$name" | sudo tee "$marker" >/dev/null
    sudo chmod 0600 "$marker"
    sudo systemctl start "amneziawg@$name.service"
    guard_apply "$name"
    echo "VPN connection active: $name"
    ;;
  disconnect)
    name="${2:-all}"
    share_stop
    if [ "$name" = all ]; then
      sudo rm -f "$marker"
      stop_active
    else
      valid_name "$name" || { echo "Invalid VPN connection name: $name" >&2; exit 1; }
      selected="$(sudo cat "$marker" 2>/dev/null || true)"
      [ "$selected" != "$name" ] || sudo rm -f "$marker"
      sudo systemctl stop "amneziawg@$name.service"
    fi
    guard_restore
    ;;
  status)
    name="${2:-}"
    if [ -n "$name" ]; then
      valid_name "$name" || { echo "Invalid VPN connection name: $name" >&2; exit 1; }
      systemctl status "amneziawg@$name.service" --no-pager
    else
      systemctl list-units --all --plain 'amneziawg@*.service'
      echo
      sudo awg show
    fi
    ;;
  share)
    case "${2:-}" in
      start) share_start ;;
      stop) share_stop ;;
      status)
        nmcli connection show --active "$VPN_SHARE_CONNECTION" || true
        echo
        sudo nft list table inet "$share_table" 2>/dev/null || echo "VPN sharing is inactive"
        ;;
      *) echo "Run 'pino vpn share help' for usage." >&2; exit 1 ;;
    esac
    ;;
  *) echo "Run 'pino vpn help' for usage." >&2; exit 1 ;;
esac
