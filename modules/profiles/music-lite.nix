# Guitar amp sim via NAM (Neural Amp Modeler).
# Requires PipeWire (already in base).
{ config, pkgs, ... }:
let
  cfg        = config.musicLite;
  configDir  = "/home/egrapa/nixos-config";
  srcDir     = "${configDir}/data/music-lite";
  ampsDir    = "${cfg.localDir}/amps";
  pluginUri  = "http://github.com/mikeoliphant/neural-amp-modeler-lv2";
  modelParam = "${pluginUri}#model";
in
{
  config = {
    environment.systemPackages = with pkgs; [
      neural-amp-modeler-lv2
      jalv
      lingot
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

    pino.subcommands."music-lite" = {
      description = "Neural Amp Modeler — load a .nam model into PipeWire";
      helpText = ''
        pino music-lite — run NAM guitar amp models in PipeWire
          pino music-lite list                  List available .nam models
          pino music-lite start <name>          Load a model as a PipeWire node
          pino music-lite stop                  Stop the running node
          pino music-lite status                Show whether a node is running
          pino music-lite log                   Show last jalv output
          pino music-lite set-latency <samples> Set PipeWire quantum (32/64/128/256)
          pino music-lite set-volume <percent>  Set output level (100=default, 200=+6dB)
          pino music-lite tuner                 Start chromatic tuner (lingot)
          pino music-lite tuner stop            Stop the tuner

          Models: ${ampsDir}  (synced from ${srcDir} on rebuild)
          Once started, connect guitar in → NAM → output in qpwgraph.
          Get models: https://tonehunt.org
      '';
      script = ''
        AMPS_DIR="${ampsDir}"
        PID_FILE="/tmp/pino-music-lite.pid"
        HOLDER_PID_FILE="/tmp/pino-music-lite-holder.pid"
        CTRL_PIPE="/tmp/pino-music-lite-ctrl"
        STATE_DIR="/tmp/pino-music-lite-state"
        LOG_FILE="/tmp/pino-music-lite.log"

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
            [ -z "$name" ] && { echo "Usage: pino music-lite start <model>"; echo "Run 'pino music-lite list'"; exit 1; }
            model="$AMPS_DIR/''${name}.nam"
            [ -f "$model" ] || { echo "Not found: $model"; echo "Run 'pino music-lite list'"; exit 1; }

            if [ -f "$PID_FILE" ] && kill -0 "''$(cat "$PID_FILE")" 2>/dev/null; then
              echo "Already running (PID ''$(cat "$PID_FILE")). Run 'pino music-lite stop' first."
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

            rm -f "$CTRL_PIPE"
            mkfifo "$CTRL_PIPE"
            sleep infinity > "$CTRL_PIPE" &
            echo $! > "$HOLDER_PID_FILE"

            jalv -l "$STATE_DIR" "${pluginUri}" < "$CTRL_PIPE" > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"

            sleep 1
            if kill -0 "''$(cat "$PID_FILE")" 2>/dev/null; then
              echo "Started NAM: $name (PID ''$(cat "$PID_FILE"))"
              echo "Connect in qpwgraph — look for 'Neural Amp Modeler' ports"
              grep -i "error\|warn\|unable" "$LOG_FILE" >&2 || true
            else
              echo "NAM failed to start — check log: pino music-lite log"
              cat "$LOG_FILE" >&2
              kill "''$(cat "$HOLDER_PID_FILE")" 2>/dev/null || true
              rm -f "$PID_FILE" "$HOLDER_PID_FILE" "$CTRL_PIPE"
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
            [ -f "$HOLDER_PID_FILE" ] && kill "''$(cat "$HOLDER_PID_FILE")" 2>/dev/null || true
            rm -f "$HOLDER_PID_FILE" "$CTRL_PIPE"
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
              echo "No log yet — run 'pino music-lite start <model>' first"
            fi
            ;;

          set-latency)
            quantum="''${2:-}"
            [ -z "$quantum" ] && { echo "Usage: pino music-lite set-latency <samples>"; echo "Common: 32 64 128 256"; exit 1; }
            pw-metadata -n settings 0 clock.force-quantum "$quantum"
            echo "Quantum set to $quantum samples"
            ;;

          set-volume)
            volume="''${2:-}"
            [ -z "$volume" ] && { echo "Usage: pino music-lite set-volume <percent>"; echo "100 = default (0 dB), 200 = +6 dB, 50 = -6 dB"; exit 1; }
            [ ! -p "$CTRL_PIPE" ] && { echo "NAM not running"; exit 1; }
            db=$(awk "BEGIN { printf \"%.2f\", 20 * log($volume / 100) / log(10) }")
            echo "output_level = $db" > "$CTRL_PIPE"
            echo "Volume: $volume% → output_level $db dB"
            ;;

          tuner)
            TUNER_PID_FILE="/tmp/pino-music-lite-tuner.pid"
            case "''${2:-}" in
              stop)
                if [ -f "$TUNER_PID_FILE" ]; then
                  pid="''$(cat "$TUNER_PID_FILE")"
                  kill "$pid" 2>/dev/null && echo "Tuner stopped (PID $pid)" || echo "Already stopped"
                  rm -f "$TUNER_PID_FILE"
                else
                  echo "Tuner not running"
                fi
                ;;
              *)
                if [ -f "$TUNER_PID_FILE" ] && kill -0 "''$(cat "$TUNER_PID_FILE")" 2>/dev/null; then
                  echo "Tuner already running (PID ''$(cat "$TUNER_PID_FILE"))"
                  exit 0
                fi
                lingot &
                echo $! > "$TUNER_PID_FILE"
                echo "Tuner started (PID ''$(cat "$TUNER_PID_FILE"))"
                ;;
            esac
            ;;

          *)
            echo "Usage: pino music-lite list|start <model>|stop|status|log|set-latency <samples>|set-volume <percent>|tuner [stop]"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        set -l ml_no_sub 'not __fish_seen_subcommand_from list start stop status log set-latency set-volume tuner'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a list        -d 'List available models'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a start       -d 'Load a model into PipeWire'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a stop        -d 'Stop the running node'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a status      -d 'Show running status'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a log         -d 'Show last jalv output'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a set-latency -d 'Set PipeWire quantum'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a set-volume  -d 'Set output level (100=default)'
        complete -c pino -f -n "__fish_seen_subcommand_from music-lite; and $ml_no_sub" -a tuner       -d 'Start chromatic tuner (lingot)'
        complete -c pino -f -n '__fish_seen_subcommand_from music-lite; and __fish_seen_subcommand_from tuner' \
          -a stop -d 'Stop the tuner'
        complete -c pino -f -n '__fish_seen_subcommand_from music-lite; and __fish_seen_subcommand_from start' \
          -a "(ls ${ampsDir}/*.nam 2>/dev/null | string replace -r '.*/' ''' | string replace '.nam' ''')" \
          -d 'NAM model'
        complete -c pino -f -n '__fish_seen_subcommand_from music-lite; and __fish_seen_subcommand_from set-latency' \
          -a '32 64 128 256' -d 'samples'
        complete -c pino -f -n '__fish_seen_subcommand_from music-lite; and __fish_seen_subcommand_from set-volume' \
          -a '50 75 100 125 150 200' -d '%'
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
