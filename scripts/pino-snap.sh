#!/usr/bin/env bash
# pino snap — btrfs snapshot management
# Called with snap subargs already in $1..$n
sub="${1:-}"
shift || true

case "$sub" in
  ls)
    echo "=== root ===" && sudo snapper -c root list
    echo "=== home ===" && sudo snapper -c home list
    ;;
  rb)
    N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino snap rb <N>"; exit 1; }
    sudo snapper -c root undochange "$N..0"
    sudo snapper -c home undochange "$N..0"
    ;;
  rm)
    N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino snap rm <N>"; exit 1; }
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
        N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino snap data rb-fast <N>"; exit 1; }
        sudo snapper -c fast undochange "$N..0"
        ;;
      rb-slow)
        N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino snap data rb-slow <N>"; exit 1; }
        sudo snapper -c slow undochange "$N..0"
        ;;
      rm)
        N="${1:-}"; [ -z "$N" ] && { echo "Usage: pino snap data rm <N>"; exit 1; }
        sudo snapper -c fast delete "$N"
        sudo snapper -c slow delete "$N"
        ;;
      help|"")
        echo "pino snap data — /data/fast + /data/slow snapshots"
        echo "  pino snap data <label>         Create snapshot"
        echo "  pino snap data ls              List snapshots"
        echo "  pino snap data rb-fast <N>     Roll back /data/fast to snapshot N"
        echo "  pino snap data rb-slow <N>     Roll back /data/slow to snapshot N"
        echo "  pino snap data rm <N>          Delete snapshot N"
        ;;
      *)
        sudo snapper -c fast create -d "$dsub"
        sudo snapper -c slow create -d "$dsub"
        echo "Created data snapshot: $dsub"
        ;;
    esac
    ;;
  help|"")
    echo "pino snap — btrfs snapshots (root + home)"
    echo "  pino snap <label>          Create snapshot of root + home"
    echo "  pino snap ls               List snapshots"
    echo "  pino snap rb <N>           Roll back root + home to snapshot N"
    echo "  pino snap rm <N>           Delete snapshot N"
    echo "  pino snap data <...>       Data disk snapshots  (pino snap data help)"
    ;;
  *)
    sudo snapper -c root create -d "$sub"
    sudo snapper -c home create -d "$sub"
    echo "Created snapshot: $sub"
    ;;
esac
