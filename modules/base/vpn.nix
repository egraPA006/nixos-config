{ pkgs, lib, ... }:
let
  configFile = "/etc/amneziawg/awg0.conf";

  vpn-up = pkgs.writeShellScript "vpn-up" ''
    if [ ! -f ${configFile} ]; then
      echo "VPN config not found at ${configFile}"
      exit 1
    fi
    ${pkgs.amneziawg-go}/bin/amneziawg-go awg0
    ${pkgs.amneziawg-tools}/bin/awg setconf awg0 ${configFile}
    ${pkgs.iproute2}/bin/ip address add $(${pkgs.gnugrep}/bin/grep Address ${configFile} | ${pkgs.gawk}/bin/awk '{print $3}') dev awg0
    ${pkgs.iproute2}/bin/ip link set awg0 up
    ${pkgs.iproute2}/bin/ip route add 0.0.0.0/0 dev awg0
  '';

  vpn-down = pkgs.writeShellScript "vpn-down" ''
    ${pkgs.iproute2}/bin/ip link del awg0
  '';
in
{
  environment.etc."amneziawg/awg0.conf".source = /home/egrapa/nixos-config/secrets/awg0.conf;

  environment.systemPackages = with pkgs; [
    amneziawg-tools
    amneziawg-go
  ];

  systemd.services.amneziawg = {
    description = "AmneziaWG VPN";
    after = [ "network.target" ];
    wantedBy = lib.mkDefault [];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = vpn-up;
      ExecStop = vpn-down;
    };
  };

  programs.fish.shellAliases = {
    vpn-on     = "sudo systemctl start amneziawg";
    vpn-off    = "sudo systemctl stop amneziawg";
    vpn-status = "sudo systemctl status amneziawg";
  };
}
