{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.lm_sensors ];

  pino.subcommands.top = {
    description = "System snapshot — temps, CPU/GPU/RAM load, top processes";
    helpText = ''
      pino top — system snapshot
        CPU/GPU temperature, load averages, memory, top processes (2 columns).
        For a live view: watch -n2 pino top
        Note: CPU temp requires sensors-detect to have been run once.
    '';
    script = ''
      SENSORS="${pkgs.lm_sensors}/bin/sensors"

      # ── terminal width & helpers ─────────────────────────────────────────
      TW=$(tput cols 2>/dev/null || echo 80)

      hline() { awk -v n="$1" 'BEGIN{for(i=0;i<n;i++) printf "─"; print ""}'; }

      # bar <pct> [width=20]  — coloured block bar
      bar() {
        local pct=$1 w=''${2:-20}
        [ "$pct" -gt 100 ] && pct=100
        [ "$pct" -lt 0   ] && pct=0
        local n=$(( pct * w / 100 )) e i=0
        e=$(( w - n ))
        if   [ "$pct" -lt 60 ]; then printf '\033[32m'
        elif [ "$pct" -lt 85 ]; then printf '\033[33m'
        else                          printf '\033[31m'; fi
        while [ $i -lt $n ]; do printf '█'; i=$(( i+1 )); done
        printf '\033[90m'
        i=0; while [ $i -lt $e ]; do printf '░'; i=$(( i+1 )); done
        printf '\033[0m'
      }

      # ── CPU usage (two /proc/stat samples 0.3 s apart) ──────────────────
      cpu1=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8, $5}')
      sleep 0.3
      cpu2=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8, $5}')
      cpu_pct=$(awk -v a="$cpu1" -v b="$cpu2" 'BEGIN {
        split(a,x); split(b,y)
        total=y[1]-x[1]; idle=y[2]-x[2]
        printf "%d", (total>0) ? 100*(total-idle)/total : 0
      }')

      # ── CPU temperature ──────────────────────────────────────────────────
      cpu_temp=$($SENSORS 2>/dev/null \
        | grep -E 'Tctl|Tdie|Core 0|Package id 0|CPU Temperature' \
        | head -1 | grep -oP '[+-]?\K[0-9]+\.[0-9]+' | head -1)
      [ -z "$cpu_temp" ] && cpu_temp="n/a"

      # ── Load averages ────────────────────────────────────────────────────
      read -r load1 load5 load15 _ < /proc/loadavg

      # ── Memory ───────────────────────────────────────────────────────────
      mem_total=$(free -m | awk '/^Mem:/  {printf "%.1f", $2/1024}')
      mem_used=$( free -m | awk '/^Mem:/  {printf "%.1f", $3/1024}')
      mem_pct=$(  free -m | awk '/^Mem:/  {printf "%d",   100*$3/$2}')
      swap_total=$(free -m | awk '/^Swap:/ {printf "%.1f", $2/1024}')
      swap_used=$( free -m | awk '/^Swap:/ {printf "%.1f", $3/1024}')
      swap_pct=$(  free -m | awk '/^Swap:/ {printf "%d",   ($2>0 ? 100*$3/$2 : 0)}')

      # ── Header ───────────────────────────────────────────────────────────
      printf "\n"
      printf '\033[1m\033[36m  pino top\033[0m  ·  %s  ·  %s\n' \
        "$(hostname)" "$(date '+%H:%M:%S')"
      printf '\033[2m  %s\033[0m\n\n' "$(hline $(( TW - 2 )))"

      # ── CPU / GPU rows ───────────────────────────────────────────────────
      printf '  \033[1mCPU\033[0m  %s°C  ' "$cpu_temp"
      bar "$cpu_pct"
      printf '  %3d%%   \033[2mload %s · %s · %s\033[0m\n' \
        "$cpu_pct" "$load1" "$load5" "$load15"

      if command -v nvidia-smi >/dev/null 2>&1; then
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
          bar "$gpu_load"
          printf '  %3d%%   \033[2mvram %s / %s GB\033[0m\n' \
            "$gpu_load" "$gpu_mused_gb" "$gpu_mtot_gb"
        fi
      fi

      printf '\n'

      # ── Memory rows ──────────────────────────────────────────────────────
      printf '  \033[1mRAM \033[0m  '
      bar "$mem_pct"
      printf '  %3d%%   \033[2m%s / %s GB\033[0m\n' \
        "$mem_pct" "$mem_used" "$mem_total"

      printf '  \033[1mSWAP\033[0m  '
      bar "$swap_pct"
      printf '  %3d%%   \033[2m%s / %s GB\033[0m\n' \
        "$swap_pct" "$swap_used" "$swap_total"

      # ── Process tables (2 columns) ───────────────────────────────────────
      COL=$(( (TW - 5) / 2 ))
      CMD=$(( COL - 16 ))   # 6 pid + 2 + 5 pct + 2 + 1 pad
      CLINE=$(hline $COL)

      mapfile -t cpu_procs < <(
        ps -eo pid,pcpu,comm --sort=-pcpu --no-headers | head -8
      ) || cpu_procs=()
      mapfile -t mem_procs < <(
        ps -eo pid,pmem,comm --sort=-pmem --no-headers | head -8
      ) || mem_procs=()

      printf '\n\033[2m  %s\033[0m\n\n' "$(hline $(( TW - 2 )))"

      printf '  \033[1m%-*s\033[0m  \033[2m│\033[0m  \033[1m%-*s\033[0m\n' \
        $COL "TOP CPU" $COL "TOP MEMORY"
      printf '  \033[2m%s  │  %s\033[0m\n' "$CLINE" "$CLINE"
      printf '  \033[2m%6s  %5s  %-*s  │  %6s  %5s  %-*s\033[0m\n' \
        PID CPU% $CMD Process PID MEM% $CMD Process

      for i in 0 1 2 3 4 5 6 7; do
        cl="''${cpu_procs[$i]:-}"
        ml="''${mem_procs[$i]:-}"
        [ -z "$cl" ] && [ -z "$ml" ] && break

        cpid=$(echo "$cl" | awk '{print $1}')
        cpct=$(echo "$cl" | awk '{print $2}')
        ccmd=$(echo "$cl" | awk '{print $3}')
        ccmd="''${ccmd:0:$CMD}"

        mpid=$(echo "$ml" | awk '{print $1}')
        mpct=$(echo "$ml" | awk '{print $2}')
        mcmd=$(echo "$ml" | awk '{print $3}')
        mcmd="''${mcmd:0:$CMD}"

        printf '  %6s  %5s  %-*s  \033[2m│\033[0m  %6s  %5s  %-*s\n' \
          "$cpid" "$cpct" $CMD "$ccmd" \
          "$mpid" "$mpct" $CMD "$mcmd"
      done

      printf '\n'
    '';
    fishCompletions = "";
  };
}
