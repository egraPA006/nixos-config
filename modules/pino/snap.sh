#!/usr/bin/env bash
# pino storage snap — btrfs snapshot management
# Called with snap subargs already in $1..$n
sub="${1:-}"
shift || true

case "$sub" in
  ls)
    echo "=== root ===" && sudo snapper -c root list
    echo "=== home ===" && sudo snapper -c home list
    ;;
  rb)
    N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino storage snap rb <N>"; exit 1; }
    sudo snapper -c root undochange "$N..0"
    sudo snapper -c home undochange "$N..0"
    ;;
  rm)
    N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino storage snap rm <N>"; exit 1; }
    sudo snapper -c root delete "$N"
    sudo snapper -c home delete "$N"
    ;;
  data)
    dsub="${1:-}"
    shift || true
    case "$dsub" in
      ls)
        echo "=== fast ===" && sudo snapper -c fast list
        echo "=== slow ===" && sudo snapper -c slow list
        ;;
      rb-fast)
        N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino storage snap data rb-fast <N>"; exit 1; }
        sudo snapper -c fast undochange "$N..0"
        ;;
      rb-slow)
        N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino storage snap data rb-slow <N>"; exit 1; }
        sudo snapper -c slow undochange "$N..0"
        ;;
      rm)
        N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino storage snap data rm <N>"; exit 1; }
        sudo snapper -c fast delete "$N"
        sudo snapper -c slow delete "$N"
        ;;
      help|"")
        echo "pino storage snap data — /data/fast + /data/slow snapshots"
        echo "  pino storage snap data <label>         Create snapshot"
        echo "  pino storage snap data ls              List snapshots"
        echo "  pino storage snap data rb-fast <N>     Roll back /data/fast to snapshot N"
        echo "  pino storage snap data rb-slow <N>     Roll back /data/slow to snapshot N"
        echo "  pino storage snap data rm <N>          Delete snapshot N"
        exit 0
        ;;
      *)
        sudo snapper -c fast create -d "$dsub"
        sudo snapper -c slow create -d "$dsub"
        echo "Created data snapshot: $dsub"
        ;;
    esac
    ;;
  "")
    echo "Usage: pino storage snap <label|ls|rb N|rm N|data ...>"
    echo "Run 'pino storage snap help' for details."
    ;;
  *)
    sudo snapper -c root create -d "$sub"
    sudo snapper -c home create -d "$sub"
    echo "Created snapshot: $sub"
    ;;
esac
