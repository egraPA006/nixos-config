{ activeProfiles, pkgs, config, lib, ... }:

let
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  vaultEnabled = lib.elem "vault" activeProfiles;
  connections = config.pino.profiles.vpn.connections;
  connectionNames = builtins.attrNames connections;
  fallbackConfigs = lib.concatMapStringsSep "\n" (name:
    let connection = connections.${name};
    in ''
      source=${lib.escapeShellArg "${config.pino.configDir}/secrets/${connection.source}"}
      if [ -f "$source" ]; then
        ${pkgs.coreutils}/bin/install -D -m 0600 "$source" ${lib.escapeShellArg "/etc/amneziawg/${name}.conf"}
      fi
    '') connectionNames;
in
{
  programs.amnezia-vpn.enable = true;

  assertions = map (name: {
    assertion = builtins.match "[A-Za-z0-9][A-Za-z0-9_-]{0,14}" name != null;
    message = "AmneziaWG connection name '${name}' must be 1-15 safe interface characters";
  }) connectionNames;

  pino.vault.secrets = lib.mkIf vaultEnabled (lib.mapAttrs' (name: connection:
    lib.nameValuePair "vpn-${name}-config" {
      source = connection.source;
      target = "/etc/amneziawg/${name}.conf";
      restartUnits = [ "amneziawg@${name}.service" ];
    }) connections);

  system.activationScripts.amneziawg-config = lib.mkIf (!vaultEnabled) ''
    ${pkgs.coreutils}/bin/mkdir -p /etc/amneziawg
    ${fallbackConfigs}
  '';

  boot.extraModulePackages = [ config.boot.kernelPackages.amneziawg ];
  boot.kernelModules = [ "amneziawg" ];

  environment.systemPackages = with pkgs; [
    amneziawg-tools
  ];

  systemd.services."amneziawg@" = {
    description = "AmneziaWG VPN connection %i";
    after = [ "network.target" ];
    wantedBy = [];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${awgQuick} up /etc/amneziawg/%i.conf";
      ExecStop = "${awgQuick} down /etc/amneziawg/%i.conf";
    };
  };

  systemd.services.amneziawg-autostart = {
    description = "AmneziaWG VPN autostart";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "amneziawg-autostart" ''
        marker=/var/lib/amneziawg/autostart
        [ -f "$marker" ] || exit 0
        name="$(${pkgs.coreutils}/bin/cat "$marker")"
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]] || exit 1
        [ -f "/etc/amneziawg/$name.conf" ] || exit 1
        ${pkgs.systemd}/bin/systemctl start "amneziawg@$name.service"
      '';
    };
  };

  pino.subcommands.network.commands.vpn = {
    description = "AmneziaWG VPN";
    commands = {
      list.description = "List installed named VPN connections";
      on = { description = "Select, start, and autostart a connection"; usage = "[name]"; };
      off = { description = "Stop one or all connections and disable autostart"; usage = "[name|all]"; };
      status = { description = "Show active VPN connections and peers"; usage = "[name]"; };
    };
    helpText = ''
      pino network vpn — AmneziaWG VPN
        pino network vpn list          List saved connections
        pino network vpn on [name]     Select one connection and enable autostart
        pino network vpn off [name]    Stop one connection (all when omitted)
        pino network vpn status [name] Show service and peer status

        Configs: ${if vaultEnabled then "provisioned from the encrypted vault" else "local gitignored secrets/ fallback"}.
        Pino selects one full-route connection at a time to avoid route conflicts.
    '';
    script = builtins.readFile ../../pino/vpn.sh;
  };
}
