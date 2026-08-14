{ activeProfiles, config, lib, nixos-mailserver, ... }:

let
  cfg = config.pino.server;
  fqdn = if cfg.mail.fqdn == null then "mail.invalid.local" else cfg.mail.fqdn;
  domain = if cfg.domain == null then "invalid.local" else cfg.domain;
  accountConfig = lib.mapAttrs (address: account: {
    hashedPasswordFile = "/var/lib/pino/secrets/server/mail/accounts/${address}.hash";
    inherit (account) aliases quota;
  }) cfg.mail.accounts;
in
{
  imports = [ nixos-mailserver.nixosModules.default ];

  assertions = [
    {
      assertion = builtins.elem "server-web" activeProfiles;
      message = "server-mail requires server-web to serve ACME HTTP challenges";
    }
    {
      assertion = cfg.domain != null && cfg.mail.fqdn != null;
      message = "server-mail requires pino.server.domain and pino.server.mail.fqdn";
    }
    {
      assertion = cfg.acmeEmail != null;
      message = "server-mail requires pino.server.acmeEmail";
    }
    {
      assertion = accountConfig != { };
      message = "server-mail requires at least one pino.server.mail.accounts entry";
    }
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = if cfg.acmeEmail == null then "unset@example.invalid" else cfg.acmeEmail;
    certs.${fqdn}.webroot = "/var/lib/acme/acme-challenge";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/acme/acme-challenge 0755 acme acme -"
  ];

  mailserver = {
    enable = true;
    stateVersion = 5;
    inherit fqdn;
    domains = [ domain ];
    accounts = accountConfig;
    openFirewall = true;
    x509.useACMEHost = fqdn;
  };

  pino.secrets.entries = lib.mapAttrs' (address: _: lib.nameValuePair
    "server/mail/accounts/${address}.hash" {
      restartUnits = [ "postfix.service" "dovecot2.service" ];
    }) cfg.mail.accounts;

  pino.subcommands.server.commands.mail = {
    description = "Inspect the mail server";
    commands = {
      status.description = "Show Postfix, Dovecot, and Rspamd status";
      queue.description = "Show the Postfix delivery queue";
      logs.description = "Show recent mail logs";
      dkim.description = "Show generated DKIM DNS records";
    };
    script = ''
      case "''${1:-}" in
        status)
          systemctl --no-pager status postfix dovecot2 rspamd
          ;;
        queue) sudo postqueue -p ;;
        logs) journalctl -u postfix -u dovecot2 -u rspamd -n 150 --no-pager ;;
        dkim)
          sudo find /var/dkim -maxdepth 2 -type f -name '*.txt' -print -exec cat {} \;
          ;;
        *) echo "Run 'pino server mail help' for usage." >&2; exit 1 ;;
      esac
    '';
  };
}
