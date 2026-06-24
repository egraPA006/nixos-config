{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.lm_sensors ];

  pino.subcommands.top = {
    description = "Live system monitor — temps, per-core CPU, GPU, RAM, top processes";
    helpText = ''
      pino top — live system monitor (Ctrl+C to exit)
        Per-core CPU bars, GPU, RAM/SWAP, top-CPU and top-memory process tables.
        Updates every 2 seconds. CPU% is measured over the interval.
        Note: CPU temp requires sensors-detect to have been run once.
    '';
    script = ''
      SENSORS="${pkgs.lm_sensors}/bin/sensors"
      INTERVAL=2

      # ── helpers ────────────────────────────────────────────────────────────
      TW=$(tput cols 2>/dev/null || echo 80)
      hline() { awk -v n="$1" 'BEGIN{for(i=0;i<n;i++) printf "─"; print ""}'; }

      bar() {  # bar <pct> [width]
        local pct w n e i
        pct=$1; w=''${2:-20}
        [ "$pct" -gt 100 ] && pct=100
        [ "$pct" -lt 0   ] && pct=0
        n=$(( pct * w / 100 ))
        e=$(( w - n ))
        if   [ "$pct" -lt 60 ]; then printf '\033[32m'
        elif [ "$pct" -lt 85 ]; then printf '\033[33m'
        else                          printf '\033[31m'; fi
        i=0; while [ "$i" -lt "$n" ]; do printf '█'; i=$(( i + 1 )); done
        printf '\033[90m'
        i=0; while [ "$i" -lt "$e" ]; do printf '░'; i=$(( i + 1 )); done
        printf '\033[0m'
      }

      # ── setup ──────────────────────────────────────────────────────────────
      STAT1=$(mktemp)
      STAT2=$(mktemp)
      OUTBUF=$(mktemp)
      trap 'rm -f "$STAT1" "$STAT2" "$OUTBUF"; tput cnorm; printf "\n"' EXIT INT TERM
      tput civis   # hide cursor

      grep '^cpu' /proc/stat > "$STAT1"
      sleep 0.5    # short initial sample so first render isn't all 0%
      printf '\033[2J'

      # ── render ─────────────────────────────────────────────────────────────
      render() {
        grep '^cpu' /proc/stat > "$STAT2"

        # per-cpu usage from delta between STAT1 and STAT2
        local cpu_data core_lines
        cpu_data=$(awk '
          NR==FNR { t[$1]=$2+$3+$4+$5+$6+$7+$8; d[$1]=$5; next }
          { total=$2+$3+$4+$5+$6+$7+$8; idle=$5
            dt=total-t[$1]; di=idle-d[$1]
            print $1, (dt>0) ? int(100*(dt-di)/dt) : 0 }
        ' "$STAT1" "$STAT2")

        cp "$STAT2" "$STAT1"   # advance window

        local cpu_pct
        cpu_pct=$(echo "$cpu_data" | awk '$1=="cpu"{print $2}')

        mapfile -t core_lines < <(echo "$cpu_data" | grep '^cpu[0-9]') \
          || core_lines=()

        # load
        local load1 load5 load15 _rest
        read -r load1 load5 load15 _rest < /proc/loadavg

        # CPU temp
        local cpu_temp
        cpu_temp=$($SENSORS 2>/dev/null \
          | grep -E 'Tctl|Tdie|Core 0|Package id 0|CPU Temperature' \
          | head -1 | grep -oP '[+-]?\K[0-9]+\.[0-9]+' | head -1)
        [ -z "$cpu_temp" ] && cpu_temp="n/a"

        # memory
        local mem_total mem_used mem_pct swap_total swap_used swap_pct
        mem_total=$(free -m | awk '/^Mem:/  {printf "%.1f", $2/1024}')
        mem_used=$( free -m | awk '/^Mem:/  {printf "%.1f", $3/1024}')
        mem_pct=$(  free -m | awk '/^Mem:/  {printf "%d",   100*$3/$2}')
        swap_total=$(free -m | awk '/^Swap:/ {printf "%.1f", $2/1024}')
        swap_used=$( free -m | awk '/^Swap:/ {printf "%.1f", $3/1024}')
        swap_pct=$(  free -m | awk '/^Swap:/ {printf "%d",   ($2>0 ? 100*$3/$2 : 0)}')

        # ── render to buffer, then cat atomically (no flicker) ────────────
        {
        printf '\033[H'   # cursor home — overwrite in place, no clear flash
        printf '\n'
        printf '\033[1m\033[36m  pino top\033[0m  ·  %s  ·  %s  \033[2m(Ctrl+C to exit)\033[0m\n' \
          "$(hostname)" "$(date '+%H:%M:%S')"
        printf '\033[2m  %s\033[0m\n\n' "$(hline $(( TW - 2 )))"

        # ── CPU overall ────────────────────────────────────────────────────
        printf '  \033[1mCPU\033[0m  %s°C  ' "$cpu_temp"
        bar "$cpu_pct" 20
        printf '  %3d%%   \033[2mload %s · %s · %s\033[0m\n' \
          "$cpu_pct" "$load1" "$load5" "$load15"

        # ── per-core grid (2 columns, 10-char bars) ────────────────────────
        local ncores i left right lname lpct rname rpct
        ncores=''${#core_lines[@]}
        i=0
        while [ "$i" -lt "$ncores" ]; do
          left=''${core_lines[$i]}
          lname=$(echo "$left" | awk '{print $1}')
          lpct=$( echo "$left" | awk '{print $2}')

          printf '  \033[2m%-5s\033[0m ' "$lname"
          bar "$lpct" 10
          printf ' %3d%%' "$lpct"

          right=''${core_lines[$((i + 1))]:-}
          if [ -n "$right" ]; then
            rname=$(echo "$right" | awk '{print $1}')
            rpct=$( echo "$right" | awk '{print $2}')
            printf '    \033[2m%-5s\033[0m ' "$rname"
            bar "$rpct" 10
            printf ' %3d%%' "$rpct"
          fi
          printf '\n'
          i=$(( i + 2 ))
        done
        printf '\n'

        # ── GPU ───────────────────────────────────────────────────────────
        if command -v nvidia-smi >/dev/null 2>&1; then
          local gpu gpu_temp gpu_load gpu_mused gpu_mtot gpu_mused_gb gpu_mtot_gb
          gpu=$(nvidia-smi \
            --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | head -1)
          if [ -n "$gpu" ]; then
            gpu_temp=$(echo "$gpu"  | cut -d, -f1 | tr -d ' ')
            gpu_load=$(echo "$gpu"  | cut -d, -f2 | tr -d ' ')
            gpu_mused=$(echo "$gpu" | cut -d, -f3 | tr -d ' ')
            gpu_mtot=$(echo  "$gpu" | cut -d, -f4 | tr -d ' ')
            gpu_mused_gb=$(awk "BEGIN{printf \"%.1f\",$gpu_mused/1024}")
            gpu_mtot_gb=$(awk  "BEGIN{printf \"%.1f\",$gpu_mtot/1024}")
            printf '  \033[1mGPU\033[0m  %s°C  ' "$gpu_temp"
            bar "$gpu_load" 20
            printf '  %3d%%   \033[2mvram %s / %s GB\033[0m\n\n' \
              "$gpu_load" "$gpu_mused_gb" "$gpu_mtot_gb"
          fi
        fi

        # ── memory bars ───────────────────────────────────────────────────
        printf '  \033[1mRAM \033[0m  '
        bar "$mem_pct" 20
        printf '  %3d%%   \033[2m%s / %s GB\033[0m\n' \
          "$mem_pct" "$mem_used" "$mem_total"
        printf '  \033[1mSWAP\033[0m  '
        bar "$swap_pct" 20
        printf '  %3d%%   \033[2m%s / %s GB\033[0m\n' \
          "$swap_pct" "$swap_used" "$swap_total"

        # ── process tables (2 columns) ────────────────────────────────────
        local COL CMD CLINE
        COL=$(( (TW - 5) / 2 ))
        CMD=$(( COL - 16 ))
        CLINE=$(hline "$COL")

        local cpu_procs mem_procs
        mapfile -t cpu_procs < <(
          ps -eo pid,pcpu,comm --sort=-pcpu --no-headers | head -8
        ) || cpu_procs=()
        mapfile -t mem_procs < <(
          ps -eo pid,pmem,comm --sort=-pmem --no-headers | head -8
        ) || mem_procs=()

        printf '\n\033[2m  %s\033[0m\n\n' "$(hline $(( TW - 2 )))"
        printf '  \033[1m%-*s\033[0m  \033[2m│\033[0m  \033[1m%-*s\033[0m\n' \
          "$COL" "TOP CPU" "$COL" "TOP MEMORY"
        printf '  \033[2m%s  │  %s\033[0m\n' "$CLINE" "$CLINE"
        printf '  \033[2m%6s  %5s  %-*s  │  %6s  %5s  %-*s\033[0m\n' \
          PID CPU% "$CMD" Process PID MEM% "$CMD" Process

        local j cl ml cpid cpct ccmd mpid mpct mcmd
        j=0
        while [ "$j" -lt 8 ]; do
          cl=''${cpu_procs[$j]:-}
          ml=''${mem_procs[$j]:-}
          [ -z "$cl" ] && [ -z "$ml" ] && break

          cpid=$(echo "$cl" | awk '{print $1}')
          cpct=$(echo "$cl" | awk '{print $2}')
          ccmd=$(echo "$cl" | awk '{print $3}')
          ccmd=''${ccmd:0:$CMD}
          mpid=$(echo "$ml" | awk '{print $1}')
          mpct=$(echo "$ml" | awk '{print $2}')
          mcmd=$(echo "$ml" | awk '{print $3}')
          mcmd=''${mcmd:0:$CMD}

          printf '  %6s  %5s  %-*s  \033[2m│\033[0m  %6s  %5s  %-*s\n' \
            "$cpid" "$cpct" "$CMD" "$ccmd" \
            "$mpid" "$mpct" "$CMD" "$mcmd"
          j=$(( j + 1 ))
        done
        printf '\n'
        printf '\033[J'   # erase any leftover lines below (e.g. if terminal shrank)
        } > "$OUTBUF"
        cat "$OUTBUF"
      }

      # ── live loop ──────────────────────────────────────────────────────────
      while true; do
        render
        sleep "$INTERVAL"
      done
    '';
    fishCompletions = "";
  };
}
