#!/usr/bin/env bash
set -euo pipefail

operation="${1:-}"
host="${2:-}"
initial_target="${3:-}"
identity_file="${4:-}"
disk=/dev/vda

case "$operation" in install|rescue) ;; *) echo "Run 'pino bootstrap help' for usage." >&2; exit 1 ;; esac
case "$host" in mosk|halos) ;; *) echo "Host must be mosk or halos." >&2; exit 1 ;; esac
[[ "$initial_target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9.-]+$ ]] || {
  echo "SSH target must be user@IPv4-or-hostname." >&2
  exit 1
}
[ -f "$identity_file" ] || { echo "Public key file not found: $identity_file" >&2; exit 1; }

public_key="$(tr -d '\r' < "$identity_file")"
[[ "$public_key" != *$'\n'* ]] || { echo "Public key file must contain exactly one key." >&2; exit 1; }
case "$public_key" in
  ssh-ed25519\ *|ssh-rsa\ *|sk-ssh-ed25519@openssh.com\ *) ;;
  *) echo "The identity selector must contain an SSH public key, never a private key." >&2; exit 1 ;;
esac
ssh-keygen -lf "$identity_file" >/dev/null

[ -n "${SSH_AUTH_SOCK:-}" ] || { echo "SSH_AUTH_SOCK is not set; enable Bitwarden SSH Agent." >&2; exit 1; }
ssh-add -L >/dev/null 2>&1 || { echo "Bitwarden SSH Agent is locked or has no keys." >&2; exit 1; }
[ -n "${BW_SESSION:-}" ] || {
  echo 'Unlock Bitwarden CLI first: export BW_SESSION="$(bw unlock --raw)"' >&2
  exit 1
}

address="${initial_target#*@}"
final_user="$(nix eval --raw "path:$BOOTSTRAP_CONFIG_DIR#nixosConfigurations.$host.config.pino.user.name")"
final_target="$final_user@$address"
known_hosts="$(mktemp)"
hardware_tmp=""
cleanup() {
  rm -f "$known_hosts"
  [ -z "$hardware_tmp" ] || rm -f "$hardware_tmp"
}
trap cleanup EXIT INT TERM

ssh_options=(
  -i "$identity_file"
  -o IdentitiesOnly=yes
  -o UserKnownHostsFile="$known_hosts"
  -o StrictHostKeyChecking=ask
  -o ConnectTimeout=10
)
scp_options=(
  -i "$identity_file"
  -o IdentitiesOnly=yes
  -o UserKnownHostsFile="$known_hosts"
  -o StrictHostKeyChecking=ask
  -o ConnectTimeout=10
)

ssh_to() { ssh "${ssh_options[@]}" "$@"; }
scp_to() { scp "${scp_options[@]}" "$@"; }

check_note() {
  local item="$1"
  bw get item "$item" \
    | jq -e 'select(.type == 2 and (.notes | type == "string") and (.notes | length > 0))' \
      >/dev/null || {
        echo "Missing non-empty Bitwarden Secure Note: $item" >&2
        exit 1
      }
}

echo "Checking GitHub state and Bitwarden items before touching $initial_target..."
[ -z "$(git -C "$BOOTSTRAP_CONFIG_DIR" status --porcelain)" ] || {
  echo "Configuration checkout has uncommitted files; commit and push first." >&2
  exit 1
}
git -C "$BOOTSTRAP_CONFIG_DIR" fetch origin main
[ "$(git -C "$BOOTSTRAP_CONFIG_DIR" rev-parse HEAD)" = \
  "$(git -C "$BOOTSTRAP_CONFIG_DIR" rev-parse origin/main)" ] || {
  echo "Local HEAD is not the pushed origin/main." >&2
  exit 1
}
bw sync >/dev/null
check_note "pino-vpn-server-$host"
if [ "$host" = mosk ]; then check_note pino-galene-mosk-main; fi

echo "Connecting to $initial_target. Verify the new VPS host fingerprint when prompted."
remote_uid="$(ssh_to "$initial_target" 'id -u')"
if [ "$remote_uid" = 0 ]; then
  elevate=""
else
  ssh_to "$initial_target" 'sudo -n true'
  elevate=sudo
fi

if [ "$operation" = install ]; then
  echo "Preparing root SSH access for the RAM installer..."
  printf '%s\n' "$public_key" | ssh_to "$initial_target" "
    key=\$(cat)
    $elevate install -d -m 0700 /root/.ssh
    $elevate touch /root/.ssh/authorized_keys
    $elevate chmod 0600 /root/.ssh/authorized_keys
    $elevate grep -qxF \"\$key\" /root/.ssh/authorized_keys \
      || printf '%s\\n' \"\$key\" | $elevate tee -a /root/.ssh/authorized_keys >/dev/null
  "

  echo "Building the pinned NixOS kexec installer locally..."
  kexec_output="$(nix build --no-link --print-out-paths \
    "path:$BOOTSTRAP_CONFIG_DIR#kexec-installer")"
  kexec_image="$kexec_output/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz"
  [ -f "$kexec_image" ] || { echo "The kexec installer archive is missing." >&2; exit 1; }
  scp_to "$kexec_image" "$initial_target:/tmp/pino-kexec.tar.gz"
  remote_kexec_dir="$(ssh_to "$initial_target" "$elevate mktemp -d /root/pino-kexec.XXXXXX")"
  ssh_to "$initial_target" \
    "$elevate tar -xzf /tmp/pino-kexec.tar.gz -C '$remote_kexec_dir'"

  echo "Booting the RAM installer; SSH will disconnect briefly..."
  set +e
  ssh_to "$initial_target" "$elevate '$remote_kexec_dir/kexec/run'"
  kexec_status=$?
  set -e
  case "$kexec_status" in 0|255) ;; *) echo "kexec failed with status $kexec_status." >&2; exit 1 ;; esac
fi

installer_target="root@$address"
echo "Waiting for the NixOS installer at $installer_target..."
installer_ready=false
for _ in $(seq 1 60); do
  if ssh_to -o BatchMode=yes "$installer_target" \
    'test -e /etc/NIXOS && command -v nixos-install >/dev/null' 2>/dev/null; then
    installer_ready=true
    break
  fi
  sleep 5
done
[ "$installer_ready" = true ] || {
  echo "The installer did not become reachable. Use the provider console or rescue system." >&2
  exit 1
}

echo "Refreshing the public hardware configuration before disk changes..."
hardware_tmp="$(mktemp)"
if ! ssh_to "$installer_target" \
  'nixos-generate-config --show-hardware-config --no-filesystems' > "$hardware_tmp"; then
  rm -f "$hardware_tmp"
  echo "Could not generate hardware.nix in the installer." >&2
  exit 1
fi
grep -q 'nixpkgs.hostPlatform' "$hardware_tmp" || {
  rm -f "$hardware_tmp"
  echo "Generated hardware.nix is incomplete." >&2
  exit 1
}
if ! cmp -s "$hardware_tmp" "$BOOTSTRAP_CONFIG_DIR/hosts/$host/hardware.nix"; then
  install -m 0644 "$hardware_tmp" "$BOOTSTRAP_CONFIG_DIR/hosts/$host/hardware.nix"
  git -C "$BOOTSTRAP_CONFIG_DIR" add "hosts/$host/hardware.nix"
  git -C "$BOOTSTRAP_CONFIG_DIR" commit -m "hosts($host): refresh generated hardware configuration"
  git -C "$BOOTSTRAP_CONFIG_DIR" push origin main
  echo "Pushed the generated $host hardware configuration."
fi
rm -f "$hardware_tmp"
hardware_tmp=""

echo "Cloning the pushed configuration in the installer..."
ssh_to "$installer_target" \
  "test ! -e /root/nixos-config && nix-shell -p git --run 'git clone --depth 1 $BOOTSTRAP_REPOSITORY /root/nixos-config'"
printf '%s\n' "$public_key" | ssh_to "$installer_target" \
  'umask 077; cat > /root/pino-bootstrap.pub'

echo "The next prompt is the final destructive confirmation for $disk."
ssh_to -tt "$installer_target" \
  "cd /root/nixos-config && scripts/server-stage.sh '$host' '$disk' /root/pino-bootstrap.pub"

final_host_key="$(ssh_to "$installer_target" \
  'cat /mnt/etc/ssh/ssh_host_ed25519_key.pub')"
case "$final_host_key" in ssh-ed25519\ *) ;; *) echo "Installed SSH host key is missing." >&2; exit 1 ;; esac

echo "Rebooting into the installed system..."
ssh_to "$installer_target" 'reboot' >/dev/null 2>&1 || true
ssh-keygen -R "$address" -f "$known_hosts" >/dev/null 2>&1 || true
printf '%s %s\n' "$address" "$final_host_key" >> "$known_hosts"
server_ready=false
for _ in $(seq 1 60); do
  if ssh_to -o BatchMode=yes "$final_target" true 2>/dev/null; then
    server_ready=true
    break
  fi
  sleep 5
done
[ "$server_ready" = true ] || {
  echo "Installed server did not become reachable as $final_target." >&2
  exit 1
}

echo "Provisioning enabled services from Bitwarden..."
export PINO_SSH_IDENTITY_FILE="$identity_file"
export PINO_SSH_KNOWN_HOSTS_FILE="$known_hosts"
pino provision send "pino-vpn-server-$host" "$final_target" \
  /etc/pino/vpn/awg0.conf amneziawg-server.service pino-vpn-mode.service
if [ "$host" = mosk ]; then
  pino provision send pino-galene-mosk-main "$final_target" \
    /etc/pino/galene/main.json galene.service
fi

ssh_to "$final_target" '/run/current-system/sw/bin/pino server status'
echo "$host installation and provisioning complete at $address."
