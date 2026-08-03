{ activeProfiles, pkgs, config, lib, ... }:

let
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  vaultEnabled = lib.elem "vault" activeProfiles;
in
{
  programs.amnezia-vpn.enable = true;

  pino.vault.secrets.awg0-config = lib.mkIf vaultEnabled {
    source = "awg0.conf";
    target = "/etc/amneziawg/awg0.conf";
    restartUnits = [ "amneziawg.service" ];
  };

  system.activationScripts.amneziawg-config = lib.mkIf (!vaultEnabled) ''
    ${pkgs.coreutils}/bin/mkdir -p /etc/amneziawg
    source=${lib.escapeShellArg "${config.pino.configDir}/secrets/awg0.conf"}
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

  pino.subcommands.network.commands.vpn = {
    description = "AmneziaWG VPN";
    commands = {
      on.description = "Start VPN and enable boot autostart";
      off.description = "Stop VPN and disable boot autostart";
      status.description = "Show VPN service status";
    };
    helpText = ''
      pino network vpn — AmneziaWG VPN
        pino network vpn on       Start VPN + enable autostart on boot
        pino network vpn off      Stop VPN + disable autostart
        pino network vpn status   Show service status

        Config: ${if vaultEnabled then "provisioned from the encrypted vault" else "local gitignored secrets/awg0.conf fallback"}.
    '';
    script = builtins.readFile ../../pino/vpn.sh;
  };
}
