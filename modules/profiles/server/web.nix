{ config, pkgs, ... }:

let
  cfg = config.pino.server;
  domain = cfg.web.domain;
  safeDomain = if domain == null then "invalid.local" else domain;
  safeEmail = if cfg.acmeEmail == null then "unset@example.invalid" else cfg.acmeEmail;
  site = pkgs.runCommand "mosk-static-site" { } ''
    mkdir -p "$out"
    cp ${./site/index.html} "$out/index.html"
  '';
in
{
  assertions = [
    {
      assertion = domain != null;
      message = "server-web requires pino.server.web.domain or pino.server.domain";
    }
    {
      assertion = cfg.acmeEmail != null;
      message = "server-web requires pino.server.acmeEmail";
    }
  ];

  services.caddy = {
    enable = true;
    # Declarative changes restart Caddy instead of requiring its admin API.
    enableReload = false;
    globalConfig = ''
      email ${safeEmail}
      admin off
    '';
    virtualHosts.${safeDomain}.extraConfig = ''
      root * ${site}
      encode zstd gzip
      file_server
      header {
        X-Content-Type-Options nosniff
        Referrer-Policy no-referrer
        X-Frame-Options DENY
      }
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  pino.subcommands.server.commands.web = {
    description = "Inspect the Caddy website and certificates";
    commands = {
      status.description = "Show Caddy status";
      logs.description = "Show recent Caddy logs";
      certificate.description = "Show the live website certificate";
    };
    script = ''
      case "''${1:-}" in
        status) systemctl status caddy --no-pager ;;
        logs) journalctl -u caddy -n 100 --no-pager ;;
        certificate)
          echo | ${pkgs.openssl}/bin/openssl s_client \
            -connect ${safeDomain}:443 \
            -servername ${safeDomain} 2>/dev/null \
            | ${pkgs.openssl}/bin/openssl x509 -noout -subject -issuer -dates
          ;;
        *) echo "Run 'pino server web help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
