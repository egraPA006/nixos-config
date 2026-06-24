{ config, pkgs, ... }:
let
  cfg          = config.torrent;
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
        chown -R egrapa:users "${cfg.localDir}"
      else
        echo "torrent-dirs: $parent not available, skipping" >&2
      fi
    '';

    services.transmission = {
      enable        = true;
      user          = "egrapa";
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

    environment.systemPackages = [ config.services.transmission.package ];

    pino.subcommands.torrent = {
      description = "Transmission torrent client";
      helpText = ''
        pino torrent — Transmission torrent client
          pino torrent list           List all torrents (grouped by status)
          pino torrent share          Show seeding/completed torrents (what you can share)
          pino torrent add <url>      Add a torrent by URL or magnet link
          pino torrent status         Show daemon status
          pino torrent start          Start the Transmission daemon
          pino torrent stop           Stop the Transmission daemon

          Downloads: ${downloadsDir}
          Web UI:    http://localhost:9091
      '';
      script = ''
        TR="${tr}"

        _tr_check() {
          if ! $TR -l >/dev/null 2>&1; then
            echo "Transmission is not running. Use: pino torrent start"
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
            [ -z "$url" ] && { echo "Usage: pino torrent add <url|magnet>"; exit 1; }
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
            echo "Usage: pino torrent list|share|add <url>|status|start|stop"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        set -l tr_no_sub 'not __fish_seen_subcommand_from list share add status start stop'
        complete -c pino -f -n "__fish_seen_subcommand_from torrent; and $tr_no_sub" -a list   -d 'List all torrents'
        complete -c pino -f -n "__fish_seen_subcommand_from torrent; and $tr_no_sub" -a share  -d 'Show seeding/shareable torrents'
        complete -c pino -f -n "__fish_seen_subcommand_from torrent; and $tr_no_sub" -a add    -d 'Add a torrent by URL or magnet'
        complete -c pino -f -n "__fish_seen_subcommand_from torrent; and $tr_no_sub" -a status -d 'Show daemon status'
        complete -c pino -f -n "__fish_seen_subcommand_from torrent; and $tr_no_sub" -a start  -d 'Start Transmission daemon'
        complete -c pino -f -n "__fish_seen_subcommand_from torrent; and $tr_no_sub" -a stop   -d 'Stop Transmission daemon'
      '';
    };
  };
}
