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

  systemd.services.amneziawg-autostart = {
    description = "AmneziaWG VPN autostart";
    after = [ "network.target" "amneziawg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ -f /var/lib/amneziawg/autostart ]; then systemctl start amneziawg; fi'";
    };
  };

  pino.subcommands.vpn = {
    description = "AmneziaWG VPN";
    helpText = ''
      pino vpn — AmneziaWG VPN
        pino vpn on       Start VPN + enable autostart on boot
        pino vpn off      Stop VPN + disable autostart
        pino vpn status   Show service status

        Config: secrets/awg0.conf (gitignored).
    '';
    script = builtins.readFile ../../scripts/pino-vpn.sh;
  };
}
