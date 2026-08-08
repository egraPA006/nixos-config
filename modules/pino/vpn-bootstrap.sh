#!/usr/bin/env bash
# Called by `pino bootstrap server vpn ...` with these variables supplied:
# PINO_CONFIG_DIR, PINO_VAULT_ROOT, PINO_OPERATION.
set -euo pipefail

AWG="@awg@"
NIX="@nix@"
FINDMNT="@findmnt@"
FIND="@find@"

host="${1:-}"
[ -n "$host" ] || { echo "A server host name is required." >&2; exit 1; }
shift || true

vault_mount="${PINO_VAULT_ROOT%%/system/hosts*}"
if ! "$FINDMNT" --mountpoint "$vault_mount" >/dev/null 2>&1; then
  echo "The encrypted vault is closed. Run: pino storage vault open" >&2
  exit 1
fi

flake="path:$PINO_CONFIG_DIR"
host_attr="$flake#nixosConfigurations.$host.config"
if ! "$NIX" --extra-experimental-features 'nix-command flakes' \
  eval --raw "$host_attr.networking.hostName" >/dev/null; then
  echo "Cannot evaluate NixOS host '$host'." >&2
  exit 1
fi

state_root="$vault_mount/vpn/$host"
peer_root="$state_root/peers"
generated_root="$state_root/generated"
bootstrap_output="$PINO_VAULT_ROOT/$host/server/awg0.conf"

valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$ ]]
}

read_state() {
  sudo test -f "$state_root/initialized" || {
    echo "VPN state for $host does not exist. Run:" >&2
    echo "  pino bootstrap server vpn init $host <endpoint>" >&2
    exit 1
  }
  endpoint="$(sudo cat "$state_root/endpoint")"
  port="$(sudo cat "$state_root/port")"
  prefix="$(sudo cat "$state_root/prefix")"
  prefix_length="$(sudo cat "$state_root/prefix-length")"
  jc="$(sudo cat "$state_root/jc")"
  jmin="$(sudo cat "$state_root/jmin")"
  jmax="$(sudo cat "$state_root/jmax")"
  s1="$(sudo cat "$state_root/s1")"
  s2="$(sudo cat "$state_root/s2")"
  h1="$(sudo cat "$state_root/h1")"
  h2="$(sudo cat "$state_root/h2")"
  h3="$(sudo cat "$state_root/h3")"
  h4="$(sudo cat "$state_root/h4")"
}

peer_names() {
  sudo "$FIND" "$peer_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
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

render_all() {
  local runtime_dir server_tmp server_private server_public name peer_dir
  local peer_private peer_public psk address client_tmp
  read_state
  runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg.XXXXXX")"
  trap 'rm -rf "$runtime_dir"' RETURN
  server_tmp="$runtime_dir/server.conf"
  server_private="$(sudo cat "$state_root/server.private")"
  server_public="$(sudo cat "$state_root/server.public")"

  {
    echo '[Interface]'
    printf 'Address = %s.1/%s\n' "$prefix" "$prefix_length"
    printf 'ListenPort = %s\n' "$port"
    printf 'PrivateKey = %s\n' "$server_private"
  } > "$server_tmp"
  append_parameters "$server_tmp"

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    peer_dir="$peer_root/$name"
    peer_private="$(sudo cat "$peer_dir/private")"
    peer_public="$(sudo cat "$peer_dir/public")"
    psk="$(sudo cat "$peer_dir/preshared")"
    address="$(sudo cat "$peer_dir/address")"
    {
      echo
      echo '[Peer]'
      printf '# %s\n' "$name"
      printf 'PublicKey = %s\n' "$peer_public"
      printf 'PresharedKey = %s\n' "$psk"
      printf 'AllowedIPs = %s/32\n' "$address"
    } >> "$server_tmp"

    client_tmp="$runtime_dir/$name.conf"
    {
      echo '[Interface]'
      printf 'Address = %s/32\n' "$address"
      printf 'PrivateKey = %s\n' "$peer_private"
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
    sudo install -D -o root -g root -m 0600 "$client_tmp" "$generated_root/$name.conf"
  done < <(peer_names)

  sudo install -D -o root -g root -m 0600 "$server_tmp" "$generated_root/server.conf"
  sudo install -D -o root -g root -m 0600 "$server_tmp" "$bootstrap_output"
  rm -rf "$runtime_dir"
  trap - RETURN
}

next_address() {
  local candidate name used
  for candidate in $(seq 2 254); do
    used=false
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if [ "$(sudo cat "$peer_root/$name/address")" = "$prefix.$candidate" ]; then
        used=true
        break
      fi
    done < <(peer_names)
    [ "$used" = true ] || { printf '%s.%s\n' "$prefix" "$candidate"; return; }
  done
  echo "No free address remains in $prefix.0/$prefix_length." >&2
  return 1
}

add_peer() {
  local name="$1" runtime_dir private public psk address
  valid_name "$name" || { echo "Invalid peer name: $name" >&2; exit 1; }
  sudo test ! -e "$peer_root/$name" || { echo "Peer already exists: $name" >&2; exit 1; }
  read_state
  address="$(next_address)"
  runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-key.XXXXXX")"
  trap 'rm -rf "$runtime_dir"' RETURN
  private="$($AWG genkey)"
  public="$(printf '%s\n' "$private" | "$AWG" pubkey)"
  psk="$($AWG genpsk)"
  printf '%s\n' "$private" > "$runtime_dir/private"
  printf '%s\n' "$public" > "$runtime_dir/public"
  printf '%s\n' "$psk" > "$runtime_dir/preshared"
  printf '%s\n' "$address" > "$runtime_dir/address"
  sudo install -d -o root -g root -m 0700 "$peer_root/$name"
  for file in private public preshared address; do
    sudo install -o root -g root -m 0600 "$runtime_dir/$file" "$peer_root/$name/$file"
  done
  rm -rf "$runtime_dir"
  trap - RETURN
  render_all
  echo "Added peer $name at $address."
}

random_u32() {
  od -An -N4 -tu4 /dev/urandom | tr -d ' '
}

case "$PINO_OPERATION" in
  init)
    endpoint="${1:-}"
    shift || true
    [ -n "$endpoint" ] || { echo "Usage: pino bootstrap server vpn init <host> <endpoint> [peer ...]" >&2; exit 1; }
    [[ "$endpoint" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Use an IPv4 address or DNS name without a port." >&2; exit 1; }
    sudo test ! -e "$state_root" || {
      echo "VPN state already exists for $host; refusing to rotate its keys." >&2
      exit 1
    }
    port="$($NIX --extra-experimental-features 'nix-command flakes' eval --raw "$host_attr.pino.server.vpn.port")"
    subnet="$($NIX --extra-experimental-features 'nix-command flakes' eval --raw "$host_attr.pino.server.vpn.clientSubnet")"
    if [[ "$subnet" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.0/24$ ]]; then
      prefix="${BASH_REMATCH[1]}"
    else
      echo "Automatic generation currently requires an IPv4 /24 ending in .0: $subnet" >&2
      exit 1
    fi
    runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pino-awg-init.XXXXXX")"
    trap 'rm -rf "$runtime_dir"' EXIT INT TERM
    server_private="$($AWG genkey)"
    printf '%s\n' "$server_private" > "$runtime_dir/server.private"
    printf '%s\n' "$server_private" | "$AWG" pubkey > "$runtime_dir/server.public"
    printf '%s\n' "$endpoint" > "$runtime_dir/endpoint"
    printf '%s\n' "$port" > "$runtime_dir/port"
    printf '%s\n' "$prefix" > "$runtime_dir/prefix"
    echo 24 > "$runtime_dir/prefix-length"
    echo 4 > "$runtime_dir/jc"
    echo 64 > "$runtime_dir/jmin"
    echo 128 > "$runtime_dir/jmax"
    echo 32 > "$runtime_dir/s1"
    echo 24 > "$runtime_dir/s2"
    random_u32 > "$runtime_dir/h1"
    random_u32 > "$runtime_dir/h2"
    random_u32 > "$runtime_dir/h3"
    random_u32 > "$runtime_dir/h4"
    : > "$runtime_dir/initialized"
    sudo install -d -o root -g root -m 0700 "$state_root" "$peer_root" "$generated_root"
    for file in server.private server.public endpoint port prefix prefix-length jc jmin jmax s1 s2 h1 h2 h3 h4 initialized; do
      sudo install -o root -g root -m 0600 "$runtime_dir/$file" "$state_root/$file"
    done
    rm -rf "$runtime_dir"
    trap - EXIT INT TERM
    if [ "$#" -eq 0 ]; then set -- re-1 phone; fi
    for name in "$@"; do add_peer "$name"; done
    render_all
    echo "Initialized $host VPN for endpoint $endpoint:$port."
    ;;
  add)
    [ "$#" -eq 1 ] || { echo "Usage: pino bootstrap server vpn peer add <host> <peer>" >&2; exit 1; }
    add_peer "$1"
    ;;
  remove)
    [ "$#" -eq 1 ] || { echo "Usage: pino bootstrap server vpn peer remove <host> <peer>" >&2; exit 1; }
    name="$1"
    valid_name "$name" || { echo "Invalid peer name: $name" >&2; exit 1; }
    sudo test -d "$peer_root/$name" || { echo "Unknown peer: $name" >&2; exit 1; }
    read -r -p "Type '$name' to remove this peer and rotate its access out: " confirmation
    [ "$confirmation" = "$name" ] || { echo "Removal cancelled."; exit 1; }
    sudo rm -rf "$peer_root/$name"
    sudo rm -f "$generated_root/$name.conf"
    render_all
    echo "Removed peer $name. Run the server secret sync to apply the new peer list."
    ;;
  list)
    read_state
    printf 'Server:   %s\nEndpoint: %s:%s\nSubnet:   %s.0/%s\n\n' "$host" "$endpoint" "$port" "$prefix" "$prefix_length"
    printf '%-20s %s\n' PEER ADDRESS
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      printf '%-20s %s\n' "$name" "$(sudo cat "$peer_root/$name/address")"
    done < <(peer_names)
    ;;
  export)
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "Usage: pino bootstrap server vpn export <host> <peer> [path|--install]" >&2; exit 1; }
    name="$1"
    destination="${2:-./awg-$host-$name.conf}"
    valid_name "$name" || { echo "Invalid peer name: $name" >&2; exit 1; }
    source_file="$generated_root/$name.conf"
    sudo test -f "$source_file" || { echo "Unknown peer or missing generated file: $name" >&2; exit 1; }
    if [ "$destination" = --install ]; then
      destination="$PINO_VAULT_ROOT/$name/vpn/$host.conf"
      sudo install -D -o root -g root -m 0600 "$source_file" "$destination"
      echo "Installed the $host connection into the $name host vault tree."
    else
      [ ! -e "$destination" ] || { echo "Destination already exists: $destination" >&2; exit 1; }
      sudo install -D -o "$(id -un)" -g "$(id -gn)" -m 0600 "$source_file" "$destination"
      echo "Exported $name configuration to $destination"
    fi
    ;;
  set-endpoint)
    [ "$#" -eq 1 ] || { echo "Usage: pino bootstrap server vpn set-endpoint <host> <endpoint>" >&2; exit 1; }
    endpoint="$1"
    [[ "$endpoint" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Use an IPv4 address or DNS name without a port." >&2; exit 1; }
    read_state
    printf '%s\n' "$endpoint" | sudo tee "$state_root/endpoint" >/dev/null
    sudo chmod 0600 "$state_root/endpoint"
    render_all
    echo "Updated every $host client configuration to endpoint $endpoint:$port."
    ;;
  *) echo "Unknown VPN bootstrap operation: $PINO_OPERATION" >&2; exit 1 ;;
esac
