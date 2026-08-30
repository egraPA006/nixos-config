#!/usr/bin/env bash
set -euo pipefail

validate_target() {
  [[ "$1" =~ ^/[A-Za-z0-9_./-]+$ ]] && [[ "/$1/" != *"/../"* ]] || {
    echo "Target must be a safe absolute path." >&2
    return 1
  }
}

validate_units() {
  local unit
  for unit in "$@"; do
    [[ "$unit" =~ ^[A-Za-z0-9_.@-]+$ ]] || {
      echo "Invalid systemd unit: $unit" >&2
      return 1
    }
  done
}

stream_note() {
  local item="$1"
  bw get item "$item" \
    | jq -er 'select(.type == 2 and (.notes | type == "string")) | .notes'
}

operation="${1:-}"
item="${2:-}"
[ -n "$item" ] || { echo "A unique Bitwarden item name is required." >&2; exit 1; }
[[ "$item" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid Bitwarden item name." >&2; exit 1; }
[ -n "${BW_SESSION:-}" ] || {
  echo 'Unlock Bitwarden first: export BW_SESSION="$(bw unlock --raw)"' >&2
  exit 1
}

if [ "$operation" = send ]; then
  host="${3:-}"
  target="${4:-}"
  shift_count=4
  [[ "$host" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid SSH host: $host" >&2; exit 1; }
elif [ "$operation" = install ]; then
  target="${3:-}"
  shift_count=3
else
  echo "Run 'pino provision help' for usage." >&2
  exit 1
fi

validate_target "$target"
shift "$shift_count"
validate_units "$@"
bw sync >/dev/null
if ! payload="$(stream_note "$item")"; then
  echo "Could not read '$item' as a Bitwarden Secure Note." >&2
  exit 1
fi
[ -n "$payload" ] || { echo "Bitwarden Secure Note '$item' is empty." >&2; exit 1; }

if [ "$operation" = send ]; then
  printf -v remote_install 'sudo install -D -o root -g root -m 0600 /dev/stdin %q' "$target"
  remote_restart=""
  if [ "$#" -gt 0 ]; then
    remote_restart=' && sudo systemctl restart'
    for unit in "$@"; do printf -v remote_restart '%s %q' "$remote_restart" "$unit"; done
  fi
  ssh_args=()
  if [ -n "${PINO_SSH_IDENTITY_FILE:-}" ]; then
    [ -f "$PINO_SSH_IDENTITY_FILE" ] || { echo "SSH identity selector not found." >&2; exit 1; }
    ssh_args+=(-i "$PINO_SSH_IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi
  if [ -n "${PINO_SSH_KNOWN_HOSTS_FILE:-}" ]; then
    [ -f "$PINO_SSH_KNOWN_HOSTS_FILE" ] || { echo "SSH known_hosts file not found." >&2; exit 1; }
    ssh_args+=(-o "UserKnownHostsFile=$PINO_SSH_KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=yes)
  fi
  printf '%s\n' "$payload" | ssh "${ssh_args[@]}" "$host" "$remote_install$remote_restart"
else
  printf '%s\n' "$payload" | sudo install -D -o root -g root -m 0600 /dev/stdin "$target"
  if [ "$#" -gt 0 ]; then sudo systemctl restart "$@"; fi
fi

echo "Provisioned '$item' at $target."
