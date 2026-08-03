{ config, lib, pkgs, ... }:

let
  cfg          = config.pino.profiles.torrent;
  tr           = "${config.services.transmission.package}/bin/transmission-remote";
  downloadsDir = "${cfg.localDir}/downloads";
  incompleteDir = "${cfg.localDir}/incomplete";
in
{
  config = {
    system.activationScripts.torrent-dirs.text = ''
      parent="$(dirname "${cfg.localDir}")"
      if [ -d "$parent" ]; then
        mkdir -p "${downloadsDir}"
        mkdir -p "${incompleteDir}"
        chown -R ${lib.escapeShellArg config.pino.user.name}:users "${cfg.localDir}"
      else
        echo "torrent-dirs: $parent not available, skipping" >&2
      fi
    '';

    services.transmission = {
      enable        = true;
      package       = pkgs.transmission_4;
      user          = config.pino.user.name;
      group         = "users";
      openFirewall  = true;
      settings = {
        download-dir               = downloadsDir;
        incomplete-dir             = incompleteDir;
        incomplete-dir-enabled     = true;
        rpc-bind-address           = "127.0.0.1";
        rpc-port                   = 9091;
        rpc-authentication-required = false;
      };
    };

    systemd.services.transmission.wantedBy = pkgs.lib.mkForce [];

    environment.systemPackages = [ config.services.transmission.package ];

    pino.subcommands.desktop.commands.torrent = {
      description = "Transmission torrent client";
      commands = {
        list.description = "List torrents grouped by status";
        share.description = "Show completed and seeding torrents";
        add = { description = "Add a torrent or magnet link"; usage = "<url|magnet>"; };
        status.description = "Show daemon status";
        start.description = "Start the Transmission daemon";
        stop.description = "Stop the Transmission daemon";
      };
      helpText = ''
        pino desktop torrent — Transmission torrent client
          pino desktop torrent list           List all torrents (grouped by status)
          pino desktop torrent share          Show seeding/completed torrents (what you can share)
          pino desktop torrent add <url>      Add a torrent by URL or magnet link
          pino desktop torrent status         Show daemon status
          pino desktop torrent start          Start the Transmission daemon
          pino desktop torrent stop           Stop the Transmission daemon

          Downloads: ${downloadsDir}
          Web UI:    http://localhost:9091
      '';
      script = ''
        TR="${tr}"

        _tr_check() {
          if ! $TR -l >/dev/null 2>&1; then
            echo "Transmission is not running. Use: pino desktop torrent start"
            exit 1
          fi
        }

        case "''${1:-}" in
          list)
            _tr_check
            raw=$($TR -l)
            header=$(echo "$raw" | head -1)

            downloading=$(echo "$raw" | grep -E 'Downloading|Queued' || true)
            seeding=$(echo "$raw"     | grep -E 'Seeding|Idle'        || true)
            stopped=$(echo "$raw"     | grep -E 'Stopped'             || true)

            echo "=== Downloading ==="
            if [ -n "$downloading" ]; then
              echo "$header"
              echo "$downloading"
            else
              echo "  (none)"
            fi

            echo ""
            echo "=== Seeding / can share ==="
            if [ -n "$seeding" ]; then
              echo "$header"
              echo "$seeding"
            else
              echo "  (none)"
            fi

            echo ""
            echo "=== Stopped ==="
            if [ -n "$stopped" ]; then
              echo "$header"
              echo "$stopped"
            else
              echo "  (none)"
            fi
            ;;

          share)
            _tr_check
            raw=$($TR -l)
            header=$(echo "$raw" | head -1)
            seeding=$(echo "$raw" | grep -E 'Seeding|Idle' || true)
            echo "Seeding / completed (shareable):"
            if [ -n "$seeding" ]; then
              echo "$header"
              echo "$seeding"
            else
              echo "  (none)"
            fi
            ;;

          add)
            url="''${2:-}"
            [ -z "$url" ] && { echo "Usage: pino desktop torrent add <url|magnet>"; exit 1; }
            _tr_check
            $TR -a "$url"
            ;;

          status)
            systemctl status transmission
            ;;

          start)
            sudo systemctl start transmission
            echo "Transmission started"
            ;;

          stop)
            sudo systemctl stop transmission
            echo "Transmission stopped"
            ;;

          *)
            echo "Usage: pino desktop torrent list|share|add <url>|status|start|stop"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        complete -c pino -F -n '__fish_pino_at_path desktop torrent add'
      '';
    };
  };
}
