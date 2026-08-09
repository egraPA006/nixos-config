{ config, lib, pkgs, ... }:
{
  imports = [ ./bootstrap-receiver.nix ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AuthorizedKeysFile = ".ssh/authorized_keys /etc/ssh/authorized_keys.d/%u";
    };
  };

  # Server administration is authenticated by the user's SSH key. The server
  # user intentionally has no local password, so wheel must not prompt for one.
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = [ pkgs.git ];

  systemd.tmpfiles.rules = [
    "d /etc/ssh/authorized_keys.d 0755 root root -"
  ];

  services.journald.extraConfig = ''
    SystemMaxUse=256M
    RuntimeMaxUse=64M
    MaxRetentionSec=14day
  '';

  pino.subcommands.server = {
    description = lib.mkDefault "Server services and connections";
    commands = {
      status.description = "Show failed and active server services";
      connections.description = "Show current listening and established connections";
      disk.description = "Show filesystem and largest state directories";
      logs = {
        description = "Show recent logs for a service";
        usage = "<unit>";
      };
    };
    helpText = ''
      pino server — lightweight server operations
        pino server status
        pino server connections
        pino server disk
        pino server logs <unit>
        pino server bootstrap help

      No monitoring dashboard or management port is exposed.
    '';
    script = ''
      case "''${1:-}" in
        status)
          systemctl --failed --no-pager
          echo
          systemctl list-units --type=service --state=running --no-pager \
            | grep -E 'caddy|sing-box|amneziawg|syncthing|postfix|dovecot|rspamd' || true
          ;;
        connections)
          ${pkgs.iproute2}/bin/ss -H -tupn state established
          ;;
        disk)
          ${pkgs.coreutils}/bin/df -h /
          echo
          sudo ${pkgs.coreutils}/bin/du -xhd1 /nix /var/lib 2>/dev/null \
            | ${pkgs.coreutils}/bin/sort -h
          ;;
        logs)
          unit="''${2:-}"
          [ -n "$unit" ] || { echo "Usage: pino server logs <unit>" >&2; exit 1; }
          journalctl -u "$unit" -n 100 --no-pager
          ;;
        *) echo "Run 'pino server help' for usage." >&2; exit 1 ;;
      esac
    '';
  };

  assertions = [{
    assertion = !config.services.openssh.enable
      || builtins.hasAttr config.pino.user.name config.users.users;
    message = "The Pino server user must exist before enabling SSH";
  }];

  # Server networking, filesystems, and boot policy remain host-selected.
}
