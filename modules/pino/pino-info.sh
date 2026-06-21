
# --- system info ---
_u=$(id -un)
_h=$(hostname)
_os=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || printf 'NixOS')
_kernel=$(uname -r)
_uptime=$(awk '{s=$1;h=int(s/3600);m=int((s%3600)/60);printf "%dh %dm",h,m}' /proc/uptime)
_shell=$(basename "${SHELL:-sh}")
_cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]*//')
_gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 \
     || grep -hm1 'DRIVER' /sys/class/drm/card*/device/uevent 2>/dev/null | cut -d= -f2 \
     || echo 'unknown')
_mem_total=$(awk '/MemTotal/{printf "%.0f",$2/1024}' /proc/meminfo)
_mem_used=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%.0f",(t-a)/1024}' /proc/meminfo)
_nixos_ver=$(nixos-version 2>/dev/null || cat /etc/nixos-version 2>/dev/null || echo 'unknown')
_generation=$(readlink /nix/var/nix/profiles/system 2>/dev/null | grep -o '[0-9]*' || echo '?')
_disk=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s / %s", $3, $2}' || echo '?')

# --- separator (matches user@host length) ---
_sep=''
for (( _j=0; _j < ${#_u} + ${#_h} + 1; _j++ )); do _sep+='─'; done

# --- colors ---
_G='\e[1;32m'
_B='\e[1m'
_R='\e[0m'

_info=(
  "${_G}${_u}${_R}@${_G}${_h}${_R}"
  "${_sep}"
  "${_B}Kernel${_R}   ${_kernel}"
  "${_B}Uptime${_R}   ${_uptime}"
  "${_B}Shell${_R}    ${_shell}"
  ""
  "${_B}CPU${_R}      ${_cpu}"
  "${_B}GPU${_R}      ${_gpu}"
  "${_B}Memory${_R}   ${_mem_used}MiB / ${_mem_total}MiB"
  "${_B}Disk${_R}     ${_disk}"
  ""
  "${_B}Gen${_R}      ${_generation}"
  "${_B}Version${_R}  ${_nixos_ver}"
)

# --- auto-detect visible art width (strips ANSI) ---
_art_w=0
for _line in "${_art[@]}"; do
  _w=$(printf '%s' "$_line" | sed 's/\x1b\[[0-9;]*[mGKHF]//g' | wc -m)
  if (( _w > _art_w )); then _art_w=$(( _w - 1 )); fi
done
_info_col=$(( _art_w + 4 ))

# --- vertical centering: offset info to center within art height ---
_n_art=${#_art[@]}
_n_info=${#_info[@]}
_max=$(( _n_art > _n_info ? _n_art : _n_info ))
_v_off=$(( (_n_art - _n_info) / 2 ))
if (( _v_off < 0 )); then _v_off=0; fi

# --- print side by side ---
for (( _i=0; _i<_max; _i++ )); do
  printf '%s' "${_art[_i]:-}"
  _ii=$(( _i - _v_off ))
  if (( _ii >= 0 && _ii < _n_info )); then
    printf '\e[%dG' "$_info_col"
    printf '%b' "${_info[_ii]}"
  fi
  printf '\n'
done
printf '\e[0m\n'
