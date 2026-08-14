#!/usr/bin/env bash
# pino desktop services vpn — named AmneziaWG connections
set -euo pipefail

config_dir=/etc/amneziawg
marker=/var/lib/amneziawg/autostart

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
  on)
    name="$(select_name "${2:-}")"
    stop_active
    sudo install -d -m 0700 /var/lib/amneziawg
    printf '%s\n' "$name" | sudo tee "$marker" >/dev/null
    sudo chmod 0600 "$marker"
    sudo systemctl start "amneziawg@$name.service"
    echo "VPN connection active: $name"
    ;;
  off)
    name="${2:-all}"
    if [ "$name" = all ]; then
      sudo rm -f "$marker"
      stop_active
    else
      valid_name "$name" || { echo "Invalid VPN connection name: $name" >&2; exit 1; }
      selected="$(sudo cat "$marker" 2>/dev/null || true)"
      [ "$selected" != "$name" ] || sudo rm -f "$marker"
      sudo systemctl stop "amneziawg@$name.service"
    fi
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
  *) echo "Run 'pino desktop services vpn help' for usage." >&2; exit 1 ;;
esac
