# Guitar amp sim via NAM (Neural Amp Modeler).

# PipeWire and low-latency settings come from the shared music base.
{ config, pkgs, ... }:
let
  cfg        = config.pino.profiles.musicLite;
  ampsDir    = "${cfg.localDir}/amps";
  pluginUri  = "http://github.com/mikeoliphant/neural-amp-modeler-lv2";
  modelParam = "${pluginUri}#model";
in
{
  imports = [ ./music-base.nix ];

  config = {
    environment.systemPackages = with pkgs; [
      neural-amp-modeler-lv2
      jalv
      lingot
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.localDir} 0755 ${config.pino.user.name} users -"
      "d ${ampsDir} 0755 ${config.pino.user.name} users -"
    ];

    pino.subcommands.desktop.commands."music-lite" = {
      description = "Neural Amp Modeler — load a .nam model into PipeWire";
      commands = {
        list.description = "List available NAM models";
        start = { description = "Load a NAM model into PipeWire"; usage = "<model>"; };
        stop.description = "Stop the running NAM node";
        status.description = "Show whether NAM is running";
        log.description = "Show the latest NAM output";
        set-latency = { description = "Set the PipeWire quantum"; usage = "<samples>"; };
        set-volume = { description = "Set NAM output volume"; usage = "<percent>"; };
        tuner = {
          description = "Start or stop the chromatic tuner";
          usage = "[stop]";
        };
      };
      helpText = ''
        Models: ${ampsDir}
        Once started, connect guitar in → NAM → output in qpwgraph.
        Get models: https://tonehunt.org
      '';
      script = ''
        AMPS_DIR="${ampsDir}"
        RUNTIME_ROOT="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pino/music-lite"
        mkdir -p "$RUNTIME_ROOT"
        chmod 0700 "$RUNTIME_ROOT"
        PID_FILE="$RUNTIME_ROOT/jalv.pid"
        HOLDER_PID_FILE="$RUNTIME_ROOT/holder.pid"
        CTRL_PIPE="$RUNTIME_ROOT/control"
        STATE_DIR="$RUNTIME_ROOT/state"
        LOG_FILE="$RUNTIME_ROOT/jalv.log"

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
            [ -z "$name" ] && { echo "Usage: pino desktop music-lite start <model>"; echo "Run 'pino desktop music-lite list'"; exit 1; }
            [[ "$name" =~ ^[A-Za-z0-9._\ -]+$ ]] || { echo "Invalid model name: $name" >&2; exit 1; }
            model="$AMPS_DIR/''${name}.nam"
            [ -f "$model" ] || { echo "Not found: $model"; echo "Run 'pino desktop music-lite list'"; exit 1; }

            if [ -f "$PID_FILE" ] && kill -0 "''$(cat "$PID_FILE")" 2>/dev/null; then
              echo "Already running (PID ''$(cat "$PID_FILE")). Run 'pino desktop music-lite stop' first."
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
              echo "NAM failed to start — check log: pino desktop music-lite log"
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
              echo "No log yet — run 'pino desktop music-lite start <model>' first"
            fi
            ;;

          set-latency)
            quantum="''${2:-}"
            [ -z "$quantum" ] && { echo "Usage: pino desktop music-lite set-latency <samples>"; echo "Common: 32 64 128 256"; exit 1; }
            case "$quantum" in 32|64|128|256|512|1024) ;; *) echo "Latency must be one of: 32 64 128 256 512 1024" >&2; exit 1 ;; esac
            pw-metadata -n settings 0 clock.force-quantum "$quantum"
            echo "Quantum set to $quantum samples"
            ;;

          set-volume)
            volume="''${2:-}"
            [ -z "$volume" ] && { echo "Usage: pino desktop music-lite set-volume <percent>"; echo "100 = default (0 dB), 200 = +6 dB, 50 = -6 dB"; exit 1; }
            [[ "$volume" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "Volume must be a number" >&2; exit 1; }
            awk -v volume="$volume" 'BEGIN { exit !(volume > 0 && volume <= 400) }' || { echo "Volume must be greater than 0 and at most 400" >&2; exit 1; }
            [ ! -p "$CTRL_PIPE" ] && { echo "NAM not running"; exit 1; }
            db=$(awk -v volume="$volume" 'BEGIN { printf "%.2f", 20 * log(volume / 100) / log(10) }')
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
            echo "Usage: pino desktop music-lite list|start <model>|stop|status|log|set-latency <samples>|set-volume <percent>|tuner [stop]"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        complete -c pino -f -n '__fish_pino_at_path desktop music-lite tuner' \
          -a stop -d 'Stop the tuner'
        complete -c pino -f -n '__fish_pino_at_path desktop music-lite start' \
          -a "(ls ${ampsDir}/*.nam 2>/dev/null | string replace -r '.*/' ''' | string replace '.nam' ''')" \
          -d 'NAM model'
        complete -c pino -f -n '__fish_pino_at_path desktop music-lite set-latency' \
          -a '32 64 128 256' -d 'samples'
        complete -c pino -f -n '__fish_pino_at_path desktop music-lite set-volume' \
          -a '50 75 100 125 150 200' -d '%'
      '';
    };

  };
}
