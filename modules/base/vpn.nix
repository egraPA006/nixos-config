{ activeProfiles, pkgs, config, lib, ... }:
let
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  vaultEnabled = lib.elem "vault" activeProfiles;
in
{
  pino.vault.secrets.awg0-config = lib.mkIf vaultEnabled {
    source = "awg0.conf";
    target = "/etc/amneziawg/awg0.conf";
    restartUnits = [ "amneziawg.service" ];
  };

  system.activationScripts.amneziawg-config = lib.mkIf (!vaultEnabled) ''
    ${pkgs.coreutils}/bin/mkdir -p /etc/amneziawg
    source=/home/egrapa/nixos-config/secrets/awg0.conf
    if [ -f "$source" ]; then
      ${pkgs.coreutils}/bin/install -m 0600 "$source" /etc/amneziawg/awg0.conf
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

        Config: ${if vaultEnabled then "provisioned from the encrypted vault" else "local gitignored secrets/awg0.conf fallback"}.
    '';
    script = builtins.readFile ../pino/vpn.sh;
    fishCompletions = ''
      complete -c pino -f -n '__fish_seen_subcommand_from vpn' -a on     -d 'Start VPN + enable autostart'
      complete -c pino -f -n '__fish_seen_subcommand_from vpn' -a off    -d 'Stop VPN + disable autostart'
      complete -c pino -f -n '__fish_seen_subcommand_from vpn' -a status -d 'Show service status'
    '';
  };
}
