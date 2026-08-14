{ activeProfiles, config, lib, pkgs, ... }:

let
  cfg = config.pino.server;
  domain = if cfg.web.domain == null then "invalid.local" else cfg.web.domain;
  proxyUsers = lib.mapAttrsToList (name: user: {
    inherit name;
    uuid._secret = user.uuidFile;
    flow = "xtls-rprx-vision";
  }) cfg.proxy.users;
  settings = {
    log = {
      level = "warn";
      timestamp = true;
    };
    inbounds = [{
      type = "vless";
      tag = "vless-reality";
      listen = "::";
      listen_port = cfg.proxy.port;
      users = proxyUsers;
      tls = {
        enabled = true;
        server_name = domain;
        reality = {
          enabled = true;
          handshake = {
            server = "127.0.0.1";
            server_port = cfg.web.internalHttpsPort;
          };
          private_key._secret = "${cfg.proxy.secretDir}/reality-private-key";
          short_id = [{ _secret = "${cfg.proxy.secretDir}/reality-short-id"; }];
        };
      };
    }];
    outbounds = [
      {
        type = "selector";
        tag = "internet";
        outbounds = [ "direct" "blocked" ];
        default = "direct";
        interrupt_exist_connections = true;
      }
      { type = "direct"; tag = "direct"; }
      { type = "block"; tag = "blocked"; }
    ];
    route.final = "internet";
    experimental.clash_api = {
      external_controller = "127.0.0.1:9090";
    };
  };
in
{
  assertions = [
    {
      assertion = builtins.elem "server-web" activeProfiles;
      message = "server-proxy requires server-web for the local REALITY handshake target";
    }
    {
      assertion = cfg.web.domain != null;
      message = "server-proxy requires pino.server.web.domain or pino.server.domain";
    }
    {
      assertion = proxyUsers != [ ];
      message = "server-proxy requires at least one pino.server.proxy.users entry";
    }
  ];

  services.sing-box = {
    enable = true;
    inherit settings;
  };

  pino.secrets.entries = {
    "server/sing-box/reality-private-key".restartUnits = [ "sing-box.service" ];
    "server/sing-box/reality-short-id".restartUnits = [ "sing-box.service" ];
  } // lib.mapAttrs' (name: user: lib.nameValuePair
    "server/sing-box/users/${name}.uuid" {
      target = user.uuidFile;
      restartUnits = [ "sing-box.service" ];
    }) cfg.proxy.users;

  systemd.services.sing-box.unitConfig = {
    ConditionPathExists = [
      "${cfg.proxy.secretDir}/reality-private-key"
      "${cfg.proxy.secretDir}/reality-short-id"
    ] ++ map (user: user.uuidFile) (lib.attrValues cfg.proxy.users);
  };

  networking.firewall.allowedTCPPorts = [ cfg.proxy.port ];

  pino.subcommands.server.commands.proxy = {
    description = "Operate the sing-box TCP proxy";
    commands = {
      status.description = "Show service and selected egress mode";
      connections.description = "List current proxy connections";
      logs.description = "Show recent sing-box logs";
      mode = {
        description = "Select proxy Internet access";
        commands = {
          status.description = "Show the selected proxy mode";
          set = { description = "Select the proxy mode"; usage = "<direct|blocked>"; };
        };
      };
    };
    helpText = ''
      Secrets:
        ${cfg.proxy.secretDir}/users/<name>.uuid
        ${cfg.proxy.secretDir}/reality-private-key
        ${cfg.proxy.secretDir}/reality-short-id

      NixOS injects these individual values into /run at service start; their
      contents never enter the Nix store.
    '';
    script = ''
      api=http://127.0.0.1:9090
      case "''${1:-}" in
        status)
          systemctl status sing-box --no-pager
          ${pkgs.curl}/bin/curl -fsS "$api/proxies/internet" | jq -r '"mode: \(.now)"'
          ;;
        connections)
          ${pkgs.curl}/bin/curl -fsS "$api/connections" \
            | jq -r '.connections[]? | [.metadata.sourceIP, .metadata.destinationIP, .metadata.destinationPort, .rule, .chains[-1]] | @tsv'
          ;;
        logs) journalctl -u sing-box -n 100 --no-pager ;;
        mode)
          if [ "''${2:-}" = status ]; then
            ${pkgs.curl}/bin/curl -fsS "$api/proxies/internet" | jq -r '"mode: \(.now)"'
            exit
          fi
          [ "''${2:-}" = set ] || { echo "Run 'pino server proxy mode help' for usage." >&2; exit 1; }
          mode="''${3:-}"
          case "$mode" in direct|blocked) ;; *) echo "Usage: pino server proxy mode set <direct|blocked>" >&2; exit 1 ;; esac
          ${pkgs.curl}/bin/curl -fsS -X PUT -H 'Content-Type: application/json' \
            -d "{\"name\":\"$mode\"}" "$api/proxies/internet" >/dev/null
          echo "Proxy mode: $mode"
          ;;
        *) echo "Run 'pino server proxy help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
