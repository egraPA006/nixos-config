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

install_note() {
  local item="$1" target="$2" payload
  shift 2
  [[ "$item" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid Bitwarden item name." >&2; return 1; }
  validate_target "$target" || return 1
  validate_units "$@" || return 1
  if ! payload="$(stream_note "$item")"; then
    echo "Could not read '$item' as a Bitwarden Secure Note." >&2
    return 1
  fi
  [ -n "$payload" ] || { echo "Bitwarden Secure Note '$item' is empty." >&2; return 1; }
  printf '%s\n' "$payload" | sudo install -D -o root -g root -m 0600 /dev/stdin "$target" || return 1
  if [ "$#" -gt 0 ]; then sudo systemctl restart "$@" || return 1; fi
  echo "Provisioned '$item' at $target."
}

install_ssh_key() {
  local item="$1" target="$2" item_json private_key public_key derived_key
  local public_type public_data derived_type derived_data
  [[ "$item" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid Bitwarden item name." >&2; return 1; }
  validate_target "$target" || return 1
  [[ "$target" == "$HOME/.ssh/"* ]] || {
    echo "SSH key target must be below ~/.ssh." >&2
    return 1
  }
  if ! item_json="$(bw get item "$item")" ||
     ! private_key="$(jq -er 'select(.type == 5) | .sshKey.privateKey | select(type == "string" and length > 0)' <<< "$item_json")" ||
     ! public_key="$(jq -er 'select(.type == 5) | .sshKey.publicKey | select(type == "string")' <<< "$item_json")"; then
    echo "Could not read '$item' as a Bitwarden SSH Key." >&2
    return 1
  fi
  [[ "$public_key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[A-Za-z0-9-]+)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
    echo "Invalid SSH public key in '$item'." >&2
    return 1
  }
  if ! derived_key="$(printf '%s\n' "$private_key" | ssh-keygen -y -P '' -f /dev/stdin 2>/dev/null)"; then
    echo "Invalid or passphrase-protected SSH private key in '$item'." >&2
    return 1
  fi
  read -r public_type public_data _ <<< "$public_key"
  read -r derived_type derived_data _ <<< "$derived_key"
  [ "$public_type" = "$derived_type" ] && [ "$public_data" = "$derived_data" ] || {
    echo "SSH public and private keys do not match in '$item'." >&2
    return 1
  }
  install -d -m 0700 "$HOME/.ssh" || return 1
  printf '%s\n' "$private_key" | install -m 0600 /dev/stdin "$target" || return 1
  printf '%s\n' "$public_key" | install -m 0644 /dev/stdin "$target.pub" || return 1
}

provision_step() {
  local item="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'OK   %s\n' "$item"
  else
    failed_items+=("$item")
    printf 'FAIL %s\n' "$item" >&2
  fi
}

switch_github_remote() {
  local config_dir="$1" current_remote ssh_remote
  current_remote="$(git -C "$config_dir" config --local --get remote.origin.url 2>/dev/null)" || return 0
  if [[ ! "$current_remote" =~ ^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(\.git)?$ ]]; then
    return 0
  fi
  ssh_remote="git@github.com:${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  if git -C "$config_dir" -c 'core.sshCommand=ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes' \
    ls-remote "$ssh_remote" HEAD >/dev/null 2>&1; then
    if git -C "$config_dir" remote set-url origin "$ssh_remote" >/dev/null 2>&1; then
      echo "OK   git origin (HTTPS -> SSH): $ssh_remote"
      return 0
    fi
  fi
  echo "FAIL git origin (HTTPS -> SSH)" >&2
  return 1
}

operation="${1:-}"
if [ "$operation" = install ] && [ "$#" -eq 1 ]; then
  mode=declared
elif [ "$operation" = install ] && [ "$#" -ge 3 ]; then
  mode=single
elif [ "$operation" = send ] && [ "$#" -ge 4 ]; then
  mode=send
else
  echo "Run 'pino provision help' for usage." >&2
  exit 1
fi

if [ "$mode" = declared ] && [ "@declaredCount@" -eq 0 ]; then
  echo "No secrets are declared for active profiles."
  exit 0
fi

if [ -z "${BW_SESSION:-}" ]; then
  vault_status="$(bw status | jq -er '.status')" || {
    echo "Could not read Bitwarden CLI status." >&2
    exit 1
  }
  case "$vault_status" in
    unauthenticated)
      echo "Logging in to Bitwarden..." >&2
      BW_SESSION="$(bw login --raw)" || exit 1
      ;;
    locked|unlocked)
      echo "Unlocking Bitwarden..." >&2
      BW_SESSION="$(bw unlock --raw)" || exit 1
      ;;
    *) echo "Unknown Bitwarden CLI status: $vault_status" >&2; exit 1 ;;
  esac
  [ -n "$BW_SESSION" ] || { echo "Bitwarden did not return a session." >&2; exit 1; }
  export BW_SESSION
fi
bw sync >/dev/null

if [ "$mode" = declared ]; then
  failed_items=()
  @declaredSecrets@
  @afterDeclared@
  if [ "${#failed_items[@]}" -gt 0 ]; then
    printf 'Failed (%d): %s' "${#failed_items[@]}" "${failed_items[0]}" >&2
    for item in "${failed_items[@]:1}"; do printf ', %s' "$item" >&2; done
    printf '\n' >&2
    exit 1
  fi
  echo 'Failed: none.'
  exit 0
fi

item="$2"
[[ "$item" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid Bitwarden item name." >&2; exit 1; }
if [ "$mode" = single ]; then
  install_note "$item" "${3:-}" "${@:4}"
  exit 0
fi

host="$3"
target="$4"
[[ "$host" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid SSH host: $host" >&2; exit 1; }
validate_target "$target"
shift 4
validate_units "$@"
if ! payload="$(stream_note "$item")"; then
  echo "Could not read '$item' as a Bitwarden Secure Note." >&2
  exit 1
fi
[ -n "$payload" ] || { echo "Bitwarden Secure Note '$item' is empty." >&2; exit 1; }

if [ "$mode" = send ]; then
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
fi

echo "Provisioned '$item' at $target."
