# Guitar amp sim via NAM (Neural Amp Modeler).
# Requires PipeWire (already in base).
{ pkgs, ... }:
let
  configDir  = "/home/egrapa/nixos-config";
  ampsDir    = "${configDir}/data/music-lite/amps";
  pluginUri  = "http://github.com/mikeoliphant/neural-amp-modeler-lv2";
  modelParam = "${pluginUri}#model";
in
{
  environment.systemPackages = with pkgs; [
    neural-amp-modeler-lv2
    jalv
  ];

  pino.subcommands.music = {
    description = "Neural Amp Modeler — load a .nam model into PipeWire";
    helpText = ''
      pino music — run NAM guitar amp models in PipeWire
        pino music list              List available .nam models
        pino music start <name>      Load a model as a PipeWire node
        pino music stop              Stop the running node
        pino music status            Show whether a node is running

        Models: drop .nam files into ${ampsDir}
        Once started, connect guitar in → NAM → output in qpwgraph.
        Get models: https://tonehunt.org
    '';
    script = ''
      AMPS_DIR="${ampsDir}"
      PID_FILE="/tmp/pino-music.pid"
      STATE_DIR="/tmp/pino-music-state"

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
@prefix state: <http://lv2plug.in/ns/ext/state#> .

[]
    state:state [
        <${modelParam}>
            "$model"^^atom:Path
    ] .
EOF

          jalv.gtk3 -l "$STATE_DIR" "${pluginUri}" &
          echo $! > "$PID_FILE"
          echo "Started NAM: $name (PID $!)"
          echo "Connect in qpwgraph — look for 'Neural Amp Modeler' ports"
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

        *)
          echo "Usage: pino music list|start <model>|stop|status"
          exit 1
          ;;
      esac
    '';
    fishCompletions = ''
      complete -c pino -f -n '__fish_seen_subcommand_from music' -a list   -d 'List available models'
      complete -c pino -f -n '__fish_seen_subcommand_from music' -a start  -d 'Load a model into PipeWire'
      complete -c pino -f -n '__fish_seen_subcommand_from music' -a stop   -d 'Stop the running node'
      complete -c pino -f -n '__fish_seen_subcommand_from music' -a status -d 'Show running status'
      complete -c pino -f -n '__fish_seen_subcommand_from music; and __fish_seen_subcommand_from start' \
        -a "(ls ${ampsDir}/*.nam 2>/dev/null | string replace -r '.*/(.*)\.nam$' '$1')" \
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
}
