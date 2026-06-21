# Guitar amp sim via NAM (Neural Amp Modeler).
# Requires PipeWire (already in base).
{ config, lib, pkgs, ... }:
let
  cfg        = config.musicLite;
  configDir  = "/home/egrapa/nixos-config";
  srcDir     = "${configDir}/data/music-lite";
  ampsDir    = "${cfg.localDir}/amps";
  pluginUri  = "http://github.com/mikeoliphant/neural-amp-modeler-lv2";
  modelParam = "${pluginUri}#model";
in
{
  options.musicLite.localDir = lib.mkOption {
    type        = lib.types.str;
    description = "Host-local path for music-lite data (synced from repo on activation). Must be set per-host — no default.";
  };

  config = {
    environment.systemPackages = with pkgs; [
      neural-amp-modeler-lv2
      jalv
    ];

    system.activationScripts.music-lite-sync.text = ''
      parent="$(dirname "${cfg.localDir}")"
      if [ -d "$parent" ]; then
        mkdir -p "${ampsDir}"
        ${pkgs.rsync}/bin/rsync -a --delete "${srcDir}/" "${cfg.localDir}/"
      else
        echo "music-lite-sync: $parent not available, skipping" >&2
      fi
    '';

    pino.subcommands.music = {
      description = "Neural Amp Modeler — load a .nam model into PipeWire";
      helpText = ''
        pino music — run NAM guitar amp models in PipeWire
          pino music list              List available .nam models
          pino music start <name>      Load a model as a PipeWire node
          pino music stop              Stop the running node
          pino music status            Show whether a node is running
          pino music log               Show last jalv output

          Models: ${ampsDir}  (synced from ${srcDir} on rebuild)
          Once started, connect guitar in → NAM → output in qpwgraph.
          Get models: https://tonehunt.org
      '';
      script = ''
        AMPS_DIR="${ampsDir}"
        PID_FILE="/tmp/pino-music.pid"
        STATE_DIR="/tmp/pino-music-state"
        LOG_FILE="/tmp/pino-music.log"

        case "''${1:-}" in
          list)
            echo "Models in $AMPS_DIR:"
            found=0
            for f in "$AMPS_DIR"/*.nam; do
              [ -f "$f" ] && echo "  ''$(basename "''${f%.nam}")" && found=1
            done
            [ "$found" = 0 ] && echo "  (none — drop .nam files into $AMPS_DIR)"
            ;;

          start)
            name="''${2:-}"
            [ -z "$name" ] && { echo "Usage: pino music start <model>"; echo "Run 'pino music list'"; exit 1; }
            model="$AMPS_DIR/''${name}.nam"
            [ -f "$model" ] || { echo "Not found: $model"; echo "Run 'pino music list'"; exit 1; }

            if [ -f "$PID_FILE" ] && kill -0 "''$(cat "$PID_FILE")" 2>/dev/null; then
              echo "Already running (PID ''$(cat "$PID_FILE")). Run 'pino music stop' first."
              exit 1
            fi

            mkdir -p "$STATE_DIR"
            cat > "$STATE_DIR/state.ttl" << EOF
@prefix atom:  <http://lv2plug.in/ns/ext/atom#> .
@prefix lv2:   <http://lv2plug.in/ns/lv2core#> .
@prefix pset:  <http://lv2plug.in/ns/ext/presets#> .
@prefix state: <http://lv2plug.in/ns/ext/state#> .

<>
    a pset:Preset ;
    lv2:appliesTo <${pluginUri}> ;
    state:state [
        <${modelParam}>
            "$model"^^atom:Path
    ] .
EOF

            jalv -i -l "$STATE_DIR" "${pluginUri}" > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"

            sleep 1
            if kill -0 "''$(cat "$PID_FILE")" 2>/dev/null; then
              echo "Started NAM: $name (PID ''$(cat "$PID_FILE"))"
              echo "Connect in qpwgraph — look for 'Neural Amp Modeler' ports"
              grep -i "error\|warn\|unable" "$LOG_FILE" >&2 || true
            else
              echo "NAM failed to start — check log: pino music log"
              cat "$LOG_FILE" >&2
              exit 1
            fi
            ;;

          stop)
            if [ -f "$PID_FILE" ]; then
              pid="''$(cat "$PID_FILE")"
              kill "$pid" 2>/dev/null && echo "Stopped (PID $pid)" || echo "Already stopped"
              rm -f "$PID_FILE"
            else
              echo "Not running"
            fi
            ;;

          status)
            if [ -f "$PID_FILE" ] && kill -0 "''$(cat "$PID_FILE")" 2>/dev/null; then
              echo "Running (PID ''$(cat "$PID_FILE"))"
            else
              rm -f "$PID_FILE" 2>/dev/null
              echo "Not running"
            fi
            ;;

          log)
            if [ -f "$LOG_FILE" ]; then
              cat "$LOG_FILE"
            else
              echo "No log yet — run 'pino music start <model>' first"
            fi
            ;;

          *)
            echo "Usage: pino music list|start <model>|stop|status|log"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        complete -c pino -f -n '__fish_seen_subcommand_from music' -a list   -d 'List available models'
        complete -c pino -f -n '__fish_seen_subcommand_from music' -a start  -d 'Load a model into PipeWire'
        complete -c pino -f -n '__fish_seen_subcommand_from music' -a stop   -d 'Stop the running node'
        complete -c pino -f -n '__fish_seen_subcommand_from music' -a status -d 'Show running status'
        complete -c pino -f -n '__fish_seen_subcommand_from music' -a log    -d 'Show last jalv output'
        complete -c pino -f -n '__fish_seen_subcommand_from music; and __fish_seen_subcommand_from start' \
          -a "(ls ${ampsDir}/*.nam 2>/dev/null | string replace -r '.*/' ''' | string replace '.nam' ''')" \
          -d 'NAM model'

      '';
    };

    # Low-latency PipeWire config for real-time audio
    services.pipewire.extraConfig.pipewire."10-realtime" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 64;
        "default.clock.min-quantum" = 32;
      };
    };

    security.pam.loginLimits = [
      { domain = "@audio"; item = "rtprio";   type = "-"; value = "99"; }
      { domain = "@audio"; item = "memlock";  type = "-"; value = "unlimited"; }
    ];

    users.users.egrapa.extraGroups = [ "audio" ];
  };
}
