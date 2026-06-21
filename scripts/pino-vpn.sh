#!/usr/bin/env bash
# pino vpn — AmneziaWG VPN
case "${1:-}" in
  on)
    sudo mkdir -p /var/lib/amneziawg
    sudo touch /var/lib/amneziawg/autostart
    sudo systemctl start amneziawg
    ;;
  off)
    sudo rm -f /var/lib/amneziawg/autostart
    sudo systemctl stop amneziawg
    ;;
  status)
    sudo systemctl status amneziawg
    ;;
  *)
    echo "Usage: pino vpn on|off|status" >&2
    exit 1
    ;;
esac
