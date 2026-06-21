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
  help|*)
    echo "pino vpn — AmneziaWG VPN"
    echo "  pino vpn on       Start VPN + enable autostart on boot"
    echo "  pino vpn off      Stop VPN + disable autostart"
    echo "  pino vpn status   Show service status"
    ;;
esac
