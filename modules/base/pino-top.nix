{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.lm_sensors ];

  pino.subcommands.top = {
    description = "System snapshot — temps, CPU/GPU/RAM load, top processes";
    helpText = ''
      pino top — system snapshot
        CPU/GPU temperature, load averages, memory, top processes.
        For a live view: watch -n2 pino top
        Note: CPU temp requires sensors-detect to have been run once.
    '';
    script = ''
      SENSORS="${pkgs.lm_sensors}/bin/sensors"

      # ── CPU usage (two /proc/stat samples 0.3 s apart) ──────────────────
      cpu1=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8, $5}')
      sleep 0.3
      cpu2=$(grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8, $5}')
      cpu_usage=$(awk -v a="$cpu1" -v b="$cpu2" 'BEGIN {
        split(a, x); split(b, y)
        total = y[1] - x[1]; idle = y[2] - x[2]
        printf "%d", (total > 0) ? 100 * (total - idle) / total : 0
      }')

      # ── CPU temperature ──────────────────────────────────────────────────
      cpu_temp=$($SENSORS 2>/dev/null \
        | grep -E 'Tctl|Tdie|Core 0|Package id 0|CPU Temperature' \
        | head -1 \
        | grep -oP '[+-]?\K[0-9]+\.[0-9]+' | head -1)
      [ -z "$cpu_temp" ] && cpu_temp="n/a"

      # ── Load averages ────────────────────────────────────────────────────
      read -r load1 load5 load15 _ < /proc/loadavg

      # ── Memory ──────────────────────────────────────────────────────────
      mem_line=$(free -m | grep '^Mem:')
      mem_total=$(echo "$mem_line" | awk '{printf "%.1f", $2/1024}')
      mem_used=$(echo  "$mem_line" | awk '{printf "%.1f", $3/1024}')
      mem_pct=$(echo   "$mem_line" | awk '{printf "%d",   100*$3/$2}')

      swap_line=$(free -m | grep '^Swap:')
      swap_total=$(echo "$swap_line" | awk '{printf "%.1f", $2/1024}')
      swap_used=$(echo  "$swap_line" | awk '{printf "%.1f", $3/1024}')

      # ── Print ────────────────────────────────────────────────────────────
      echo ""
      printf "CPU   temp %s°C   load %s / %s / %s   usage %s%%\n" \
        "$cpu_temp" "$load1" "$load5" "$load15" "$cpu_usage"

      if command -v nvidia-smi >/dev/null 2>&1; then
        gpu=$(nvidia-smi \
          --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total \
          --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$gpu" ]; then
          gpu_temp=$(echo "$gpu"  | cut -d, -f1 | tr -d ' ')
          gpu_load=$(echo "$gpu"  | cut -d, -f2 | tr -d ' ')
          gpu_mused=$(echo "$gpu" | cut -d, -f3 | tr -d ' ')
          gpu_mtot=$(echo  "$gpu" | cut -d, -f4 | tr -d ' ')
          gpu_mused_gb=$(awk "BEGIN {printf \"%.1f\", $gpu_mused/1024}")
          gpu_mtot_gb=$(awk  "BEGIN {printf \"%.1f\", $gpu_mtot/1024}")
          printf "GPU   temp %s°C   load %s%%   vram %s / %s GB\n" \
            "$gpu_temp" "$gpu_load" "$gpu_mused_gb" "$gpu_mtot_gb"
        fi
      fi

      printf "RAM   %s / %s GB   %s%%\n" "$mem_used" "$mem_total" "$mem_pct"
      printf "SWAP  %s / %s GB\n" "$swap_used" "$swap_total"

      echo ""
      printf "%-7s  %5s  %5s  %s\n" "PID" "CPU%" "MEM%" "PROCESS"
      ps -eo pid,pcpu,pmem,comm --sort=-pcpu --no-headers \
        | head -10 \
        | awk '{printf "%-7s  %5s  %5s  %s\n", $1, $2, $3, $4}'
      echo ""
    '';
    fishCompletions = "";
  };
}
