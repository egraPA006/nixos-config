#!/usr/bin/env bash
# Called by `pino bootstrap host vpn ...` with these variables supplied:
# PINO_CONFIG_DIR, PINO_SECRET_ROOT, PINO_OPERATION.
set -euo pipefail

AWG="@awg@"
NIX="@nix@"
FINDMNT="@findmnt@"
FIND="@find@"

host="${1:-}"
[ -n "$host" ] || { echo "A server host name is required." >&2; exit 1; }
shift || true

host_vault="$PINO_SECRET_ROOT/$host"
server_config="$PINO_SECRET_ROOT/$host/server/awg0.conf"
flake="path:$PINO_CONFIG_DIR"
host_attr="$flake#nixosConfigurations.$host.config"

if ! "$FINDMNT" --mountpoint "$host_vault" >/dev/null 2>&1; then
  echo "The host vault is closed. Run: pino vault secrets open hosts/$host" >&2
  exit 1
fi

if ! "$NIX" --extra-experimental-features 'nix-command flakes' \
  eval --raw "$host_attr.networking.hostName" >/dev/null; then
  echo "Cannot evaluate NixOS host '$host'." >&2
  exit 1
fi

valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$ ]]
}

is_nixos_host() {
  "$NIX" --extra-experimental-features 'nix-command flakes' \
    eval --raw "$flake#nixosConfigurations.$1.config.networking.hostName" \
    >/dev/null 2>&1
}

target_config_path() {
  local name="$1"
  "$FINDMNT" --mountpoint "$PINO_SECRET_ROOT/$name" >/dev/null 2>&1 || {
    echo "Unlock hosts/$name in Cryptomator before changing its VPN configuration." >&2
    return 1
  }
  printf '%s/%s/vpn/%s.conf\n' "$PINO_SECRET_ROOT" "$name" "$host"
}

existing_config_path() {
  local name="$1"
  local host_path="$PINO_SECRET_ROOT/$name/vpn/$host.conf"
  if test -f "$host_path"; then
    printf '%s\n' "$host_path"
  else
    return 1
  fi
}

config_value() {
  local file="$1"
  local key="$2"
  "@awk@" -v key="$key" '
    index($0, key " = ") == 1 {
      sub(/^[^=]*=[[:space:]]*/, "")
      print
      exit
    }
  ' "$file"
}

read_server() {
  test -f "$server_config" || {
    echo "VPN configuration for $host does not exist. Run:" >&2
    echo "  pino bootstrap host vpn init $host <endpoint>" >&2
    exit 1
  }

  endpoint="$(config_value "$server_config" '# PinoEndpoint')"
  port="$(config_value "$server_config" 'ListenPort')"
  server_address="$(config_value "$server_config" 'Address')"
  server_private="$(config_value "$server_config" 'PrivateKey')"
  jc="$(config_value "$server_config" 'Jc')"
  jmin="$(config_value "$server_config" 'Jmin')"
  jmax="$(config_value "$server_config" 'Jmax')"
  s1="$(config_value "$server_config" 'S1')"
  s2="$(config_value "$server_config" 'S2')"
  h1="$(config_value "$server_config" 'H1')"
  h2="$(config_value "$server_config" 'H2')"
  h3="$(config_value "$server_config" 'H3')"
  h4="$(config_value "$server_config" 'H4')"

  [ -n "$endpoint" ] && [ -n "$port" ] && [ -n "$server_private" ] || {
    echo "$server_config is not a Pino-managed server configuration." >&2
    exit 1
  }
  if [[ "$server_address" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.1/([0-9]{1,2})$ ]]; then
    prefix="${BASH_REMATCH[1]}"
    prefix_length="${BASH_REMATCH[2]}"
  else
    echo "Unsupported server address in $server_config: $server_address" >&2
    exit 1
  fi
  server_public="$(printf '%s\n' "$server_private" | "$AWG" pubkey)"
}

append_parameters() {
  local output="$1"
  {
    printf 'Jc = %s\n' "$jc"
    printf 'Jmin = %s\n' "$jmin"
    printf 'Jmax = %s\n' "$jmax"
    printf 'S1 = %s\n' "$s1"
    printf 'S2 = %s\n' "$s2"
    printf 'H1 = %s\n' "$h1"
    printf 'H2 = %s\n' "$h2"
    printf 'H3 = %s\n' "$h3"
    printf 'H4 = %s\n' "$h4"
  } >> "$output"
}

peer_exists() {
  local name="$1"
  "@awk@" -v marker="# $name" '$0 == marker { found=1 } END { exit !found }' "$server_config"
}

peer_rows() {
  "@awk@" '
    /^\[Peer\]$/ { name=""; address=""; next }
    /^# / { name=substr($0, 3); next }
    /^AllowedIPs = / {
      address=$0
      sub(/^AllowedIPs = /, "", address)
      sub(/\/32$/, "", address)
      if (name != "") print name "\t" address
    }
  ' "$server_config"
}

next_address() {
  local candidate used_address
  for candidate in $(seq 2 254); do
    used_address="$prefix.$candidate"
    if ! peer_rows | while IFS=$'\t' read -r _ address; do
      [ "$address" != "$used_address" ] || exit 1
    done; then
      continue
    fi
    printf '%s\n' "$used_address"
    return
  done
  echo "No free address remains in $prefix.0/$prefix_length." >&2
  return 1
}

print_host_enable_steps() {
  local name="$1"
  printf '\nTo enable it on %s, add this to that host configuration:\n\n' "$name"
  printf '  pino.profiles.vpn.connections.%s = { };\n\n' "$host"
  printf 'Then run on %s:\n\n  pino os rebuild\n\n' "$name"
  echo "Answer yes when Pino asks to populate system secrets from the vault."
}

add_peer() {
  local name="$1"
  local runtime_dir private public psk address client_tmp server_tmp destination
  valid_name "$name" || { echo "Invalid peer name: $name" >&2; exit 1; }
  read_server
  peer_exists "$name" && { echo "Peer already exists: $name" >&2; exit 1; }
  destination="$(target_config_path "$name")"
  test ! -e "$destination" || { echo "Client configuration already exists: $destination" >&2; exit 1; }

  address="$(next_address)"
  runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-key.XXXXXX")"
  trap 'rm -rf "$runtime_dir"' RETURN
  private="$($AWG genkey)"
  public="$(printf '%s\n' "$private" | "$AWG" pubkey)"
  psk="$($AWG genpsk)"
  client_tmp="$runtime_dir/client.conf"
  server_tmp="$runtime_dir/server.conf"

  {
    echo '[Interface]'
    printf 'Address = %s/32\n' "$address"
    printf 'PrivateKey = %s\n' "$private"
  } > "$client_tmp"
  append_parameters "$client_tmp"
  {
    echo
    echo '[Peer]'
    printf 'PublicKey = %s\n' "$server_public"
    printf 'PresharedKey = %s\n' "$psk"
    printf 'Endpoint = %s:%s\n' "$endpoint" "$port"
    echo 'AllowedIPs = 0.0.0.0/0'
    echo 'PersistentKeepalive = 25'
  } >> "$client_tmp"

  cat "$server_config" | tee "$server_tmp" >/dev/null
  {
    echo
    echo '[Peer]'
    printf '# %s\n' "$name"
    printf 'PublicKey = %s\n' "$public"
    printf 'PresharedKey = %s\n' "$psk"
    printf 'AllowedIPs = %s/32\n' "$address"
  } >> "$server_tmp"

  install -D -m 0600 "$client_tmp" "$destination"
  if ! install -D -m 0600 "$server_tmp" "$server_config"; then
    rm -f "$destination"
    echo "Could not update the server configuration; removed the new client configuration." >&2
    exit 1
  fi
  rm -rf "$runtime_dir"
  trap - RETURN
  echo "Added peer $name at $address."
  echo "Stored its canonical client configuration at $destination."
  if is_nixos_host "$name"; then
    print_host_enable_steps "$name"
  else
    echo "Export it for the device with: pino bootstrap host vpn peer export $host $name [path]"
  fi
}

remove_peer_block() {
  local name="$1"
  local output="$2"
  cat "$server_config" | "@awk@" -v marker="# $name" '
    BEGIN { RS="\n\\[Peer\\]\n"; ORS="" }
    NR == 1 { printf "%s", $0; next }
    {
      found=0
      count=split($0, lines, "\n")
      for (i=1; i<=count; i++) if (lines[i] == marker) found=1
      if (!found) printf "\n[Peer]\n%s", $0
    }
    END { printf "\n" }
  ' > "$output"
}

update_endpoint_file() {
  local file="$1"
  local value="$2"
  local runtime_dir output
  runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-endpoint.XXXXXX")"
  output="$runtime_dir/config"
  cat "$file" | "@awk@" -v value="$value" '
    /^Endpoint = / { print "Endpoint = " value; next }
    { print }
  ' > "$output"
  install -m 0600 "$output" "$file"
  rm -rf "$runtime_dir"
}

random_u32() {
  od -An -N4 -tu4 /dev/urandom | tr -d ' '
}

case "$PINO_OPERATION" in
  init)
    endpoint="${1:-}"
    shift || true
    [ -n "$endpoint" ] || { echo "Usage: pino bootstrap host vpn init <host> <endpoint> [peer ...]" >&2; exit 1; }
    [[ "$endpoint" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Use an IPv4 address or DNS name without a port." >&2; exit 1; }
    test ! -e "$server_config" || { echo "VPN configuration already exists for $host; refusing to rotate its keys." >&2; exit 1; }
    port="$($NIX --extra-experimental-features 'nix-command flakes' eval --json "$host_attr.pino.server.vpn.port")"
    subnet="$($NIX --extra-experimental-features 'nix-command flakes' eval --raw "$host_attr.pino.server.vpn.clientSubnet")"
    if [[ "$subnet" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.0/24$ ]]; then
      prefix="${BASH_REMATCH[1]}"
    else
      echo "Automatic generation currently requires an IPv4 /24 ending in .0: $subnet" >&2
      exit 1
    fi
    prefix_length=24
    server_private="$($AWG genkey)"
    jc=4
    jmin=64
    jmax=128
    s1=32
    s2=24
    h1="$(random_u32)"
    h2="$(random_u32)"
    h3="$(random_u32)"
    h4="$(random_u32)"
    runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-init.XXXXXX")"
    trap 'rm -rf "$runtime_dir"' EXIT INT TERM
    server_tmp="$runtime_dir/server.conf"
    {
      printf '# PinoEndpoint = %s\n' "$endpoint"
      echo '[Interface]'
      printf 'Address = %s.1/%s\n' "$prefix" "$prefix_length"
      printf 'ListenPort = %s\n' "$port"
      printf 'PrivateKey = %s\n' "$server_private"
    } > "$server_tmp"
    append_parameters "$server_tmp"
    install -D -m 0600 "$server_tmp" "$server_config"
    rm -rf "$runtime_dir"
    trap - EXIT INT TERM
    if [ "$#" -eq 0 ]; then set -- re-1 phone; fi
    for name in "$@"; do add_peer "$name"; done
    echo "Initialized $host VPN for endpoint $endpoint:$port."
    ;;
  add)
    [ "$#" -eq 1 ] || { echo "Usage: pino bootstrap host vpn peer add <host> <peer>" >&2; exit 1; }
    add_peer "$1"
    ;;
  remove)
    [ "$#" -eq 1 ] || { echo "Usage: pino bootstrap host vpn peer remove <host> <peer>" >&2; exit 1; }
    name="$1"
    valid_name "$name" || { echo "Invalid peer name: $name" >&2; exit 1; }
    read_server
    peer_exists "$name" || { echo "Unknown peer: $name" >&2; exit 1; }
    destination="$(existing_config_path "$name")" || {
      echo "Missing canonical client configuration for peer: $name" >&2
      exit 1
    }
    read -r -p "Type '$name' to remove this peer and its client configuration: " confirmation
    [ "$confirmation" = "$name" ] || { echo "Removal cancelled."; exit 1; }
    runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-remove.XXXXXX")"
    trap 'rm -rf "$runtime_dir"' EXIT INT TERM
    server_tmp="$runtime_dir/server.conf"
    remove_peer_block "$name" "$server_tmp"
    install -m 0600 "$server_tmp" "$server_config"
    rm -f "$destination"
    rm -rf "$runtime_dir"
    trap - EXIT INT TERM
    echo "Removed peer $name. Run the server secret sync to apply the new peer list."
    ;;
  list)
    [ "$#" -eq 0 ] || { echo "Usage: pino bootstrap host vpn peer list <host>" >&2; exit 1; }
    read_server
    printf 'Server:   %s\nEndpoint: %s:%s\nSubnet:   %s.0/%s\n\n' "$host" "$endpoint" "$port" "$prefix" "$prefix_length"
    printf '%-20s %-15s %s\n' PEER ADDRESS CONFIGURATION
    while IFS=$'\t' read -r name address; do
      [ -n "$name" ] || continue
      destination="$(existing_config_path "$name" 2>/dev/null || true)"
      printf '%-20s %-15s %s\n' "$name" "$address" "${destination:-MISSING}"
    done < <(peer_rows)
    ;;
  export)
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "Usage: pino bootstrap host vpn peer export <host> <peer> [path]" >&2; exit 1; }
    name="$1"
    destination="${2:-./awg-$host-$name.conf}"
    valid_name "$name" || { echo "Invalid peer name: $name" >&2; exit 1; }
    [ "$destination" != --install ] || {
      echo "Client configurations are installed when peers are added; --install is no longer needed." >&2
      exit 1
    }
    source_file="$(existing_config_path "$name")" || { echo "Unknown peer or missing client configuration: $name" >&2; exit 1; }
    [ ! -e "$destination" ] || { echo "Destination already exists: $destination" >&2; exit 1; }
    install -D -m 0600 "$source_file" "$destination"
    echo "Exported $name configuration to $destination"
    ;;
  set-endpoint)
    [ "$#" -eq 1 ] || { echo "Usage: pino bootstrap host vpn endpoint set <host> <endpoint>" >&2; exit 1; }
    new_endpoint="$1"
    [[ "$new_endpoint" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Use an IPv4 address or DNS name without a port." >&2; exit 1; }
    read_server
    runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-endpoint.XXXXXX")"
    trap 'rm -rf "$runtime_dir"' EXIT INT TERM
    server_tmp="$runtime_dir/server.conf"
    cat "$server_config" | "@awk@" -v value="$new_endpoint" '
      /^# PinoEndpoint = / { print "# PinoEndpoint = " value; next }
      { print }
    ' > "$server_tmp"
    install -m 0600 "$server_tmp" "$server_config"
    while IFS= read -r source_file; do
      [ -n "$source_file" ] || continue
      update_endpoint_file "$source_file" "$new_endpoint:$port"
    done < <("$FIND" "$PINO_SECRET_ROOT" -path "*/vpn/$host.conf" -type f 2>/dev/null)
    rm -rf "$runtime_dir"
    trap - EXIT INT TERM
    echo "Updated every $host client configuration to endpoint $new_endpoint:$port."
    ;;
  *) echo "Unknown VPN bootstrap operation: $PINO_OPERATION" >&2; exit 1 ;;
esac
