{ pkgs, config, ... }:
let
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
in
{
  system.activationScripts.amneziawg-config = ''
    mkdir -p /etc/amneziawg
    src="/home/egrapa/nixos-config/secrets/awg0.conf"
    if [ -f "$src" ]; then
      cp "$src" /etc/amneziawg/awg0.conf
      chmod 600 /etc/amneziawg/awg0.conf
    fi
  '';

  boot.extraModulePackages = [ config.boot.kernelPackages.amneziawg ];
  boot.kernelModules = [ "amneziawg" ];

  environment.systemPackages = with pkgs; [
    amneziawg-tools
  ];

  systemd.services.amneziawg = {
    description = "AmneziaWG VPN";
    after = [ "network.target" ];
    wantedBy = [];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${awgQuick} up /etc/amneziawg/awg0.conf";
      ExecStop = "${awgQuick} down /etc/amneziawg/awg0.conf";
    };
  };

  # Restores VPN state on boot if the user had it enabled
  systemd.services.amneziawg-autostart = {
    description = "AmneziaWG VPN autostart";
    after = [ "network.target" "amneziawg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ -f /var/lib/amneziawg/autostart ]; then systemctl start amneziawg; fi'";
    };
  };

  programs.fish.shellAliases = {
    vpn-on     = "sudo mkdir -p /var/lib/amneziawg && sudo touch /var/lib/amneziawg/autostart && sudo systemctl start amneziawg";
    vpn-off    = "sudo rm -f /var/lib/amneziawg/autostart && sudo systemctl stop amneziawg";
    vpn-status = "sudo systemctl status amneziawg";
  };
}
