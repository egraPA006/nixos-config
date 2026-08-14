{
  pkgs,
  config,
  lib,
  ...
}:

let
  awgQuick = "${pkgs.amneziawg-tools}/bin/awg-quick";
  connections = config.pino.profiles.vpn.connections;
  connectionNames = builtins.attrNames connections;
in
{
  programs.amnezia-vpn.enable = true;

  assertions = map (name: {
    assertion = builtins.match "[A-Za-z0-9][A-Za-z0-9_-]{0,14}" name != null;
    message = "AmneziaWG connection name '${name}' must be 1-15 safe interface characters";
  }) connectionNames;

  pino.secrets.entries =
    lib.mapAttrs' (
      name: connection:
      lib.nameValuePair "vpn-${name}-config" {
        source = connection.source;
        target = "/etc/amneziawg/${name}.conf";
        directoryMode = "0755";
        restartUnits = [ "amneziawg@${name}.service" ];
      }
    ) connections
  ;

  systemd.tmpfiles.rules = [
    "d /etc/amneziawg 0755 root root -"
  ];

  boot.extraModulePackages = [ config.boot.kernelPackages.amneziawg ];
  boot.kernelModules = [ "amneziawg" ];

  environment.systemPackages = with pkgs; [
    amneziawg-tools
  ];

  systemd.services."amneziawg@" = {
    description = "AmneziaWG VPN connection %i";
    after = [ "network.target" ];
    wantedBy = [ ];

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
        if [ -z "$name" ] && [ -f /etc/amneziawg/awg0.conf ]; then
          name=awg0
          ${pkgs.coreutils}/bin/printf '%s\n' "$name" > "$marker"
          ${pkgs.coreutils}/bin/chmod 0600 "$marker"
        fi
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]] || exit 1
        [ -f "/etc/amneziawg/$name.conf" ] || exit 1
        ${pkgs.systemd}/bin/systemctl start "amneziawg@$name.service"
      '';
    };
  };

  pino.subcommands.desktop.commands.services.commands.vpn = {
    description = "AmneziaWG VPN";
    commands = {
      list.description = "List installed named VPN connections";
      connect = {
        description = "Select, start, and autostart a connection";
        usage = "[name]";
      };
      disconnect = {
        description = "Stop one or all connections and disable autostart";
        usage = "[name|all]";
      };
      status = {
        description = "Show active VPN connections and peers";
        usage = "[name]";
      };
    };
    helpText = ''
      Configs are provisioned from this host's encrypted secret projection.
      Pino selects one full-route connection at a time to avoid route conflicts.
    '';
    script = builtins.readFile ../../../pino/vpn.sh;
  };
}
