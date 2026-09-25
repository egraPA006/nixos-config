# Pino NixOS config

One small flake for four machines:

- `re-1`: desktop, ext4 root plus `/data/fast` and `/data/slow`;
- `la1n`: laptop, LUKS2-encrypted ext4 root;
- `mosk`: VPN exit, static website, and data disk;
- `halos`: VPN only.

There is no Disko, Btrfs, mail server, or Git mirror. GitHub stores only the
public configuration. Bitwarden stores passwords, SSH keys, and runtime
configuration. A 10 GiB local LUKS2 container mounted at `~/Secrets` stores
recovery codes and document copies only. An external LUKS2 disk is compared
and merged manually; Pino has no automatic backup or dataset layer.

## Fresh installation

### Remote servers

The normal VPS flow starts from the temporary Ubuntu or Debian image supplied
by the provider. Create Bitwarden SSH Key items named `pino-ssh-server-mosk`
and `pino-ssh-server-halos`. Give the provider only the public half of the
matching item. Before initial bootstrap, save that public key locally as a
selector, for example `~/.ssh/mosk.pub`. On an installed desktop,
`pino provision install` installs both halves locally as `~/.ssh/mosk` and
`~/.ssh/mosk.pub`.

Provision the SSH key, make sure this checkout is clean and pushed to
`origin/main`, then run:

```bash
pino provision install
pino bootstrap install mosk ubuntu@203.0.113.10 ~/.ssh/mosk.pub
```

`pino bootstrap` unlocks and synchronizes Bitwarden itself when needed.

`install` requires an x86_64 Linux VPS with passwordless root or `sudo`, enough
RAM for the pinned NixOS kexec installer, working DHCP, and Secure Boot disabled.
It boots the installer in RAM, so no provider console is needed in the normal
case.

If the provider has already booted a NixOS installer or rescue image, skip
kexec:

```bash
pino bootstrap rescue halos root@203.0.113.11 ~/.ssh/halos.pub
```

Both commands verify the required Bitwarden Secure Notes, generate the public
`hardware.nix`, commit and push it if it changed, clone that exact GitHub state
in the installer, and stop for the final disk-erasure confirmation. They then
install `/dev/vda`, reboot, provision the server runtime files from Bitwarden,
and show service status. The private SSH key and secret contents are never
copied into Git or onto the installer.

The first SSH connection uses the normal interactive host-fingerprint prompt.
Check it against the provider console. If kexec is unsupported or networking
does not return, use the rescue flow instead.

### Installer console

Boot a NixOS installer, clone the repository, inspect the disks, then run the
host-specific partition command:

```bash
nix-shell -p git
git clone https://github.com/egraPA006/nixos-config.git
cd nixos-config
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
```

```bash
# Desktop: EFI + ext4 root, then two ext4 data disks
sudo scripts/partition.sh re-1 /dev/system /dev/fast /dev/slow

# Laptop: EFI + LUKS2 container + ext4 root
sudo scripts/partition.sh la1n /dev/nvme0n1

# Mosk: BIOS boot + 64 GiB ext4 root + ext4 /data
sudo scripts/partition.sh mosk /dev/vda

# Halos: BIOS boot + ext4 root
sudo scripts/partition.sh halos /dev/vda
```

The server configurations currently target the provider's `/dev/vda`. Change
both the host storage file and this safety check before using another device.

Install after the script mounts everything below `/mnt`:

```bash
sudo scripts/install.sh <host>
```

The installer generates `hosts/<host>/hardware.nix` from the mounted target,
installs the bootloader, copies the Git checkout, optionally installs one SSH
public key, and asks for the local user password on desktops. Servers require
the public key and intentionally have no local password.

A desktop or laptop installation performs no secret provisioning. After the
first boot, use the copied checkout (or a normal HTTPS `git clone` on an
already installed host), then run `pino provision install` to log in to
Bitwarden and install the runtime files declared by active profiles.

To reinstall the declared system and bootloader without repartitioning or
regenerating hardware configuration:

```bash
sudo scripts/install.sh repair <host>
```

For a new Mosk or Halos VPS, the short combined command is:

```bash
sudo scripts/server-stage.sh mosk /dev/vda
```

All partition commands are destructive and require typing a host-specific
confirmation. `repair` is not destructive to filesystems.

## Profiles

Enabled profiles are plain lists in `hosts/<host>/active-profiles.nix`.

```bash
pino profile list
pino profile enable server-web
pino profile disable torrent
pino provision install
```

The profile catalog in `modules/profiles/default.nix` exposes user-facing roles;
small implementation modules are composed inside them. `pino profile list`
shows their purpose.

Desktop profiles are:

- `workstation`: desktop applications, audio, and Bluetooth;
- `gnome`: GNOME desktop environment;
- `development`: Git, Codex, and VS Code;
- `vpn-client`: named AmneziaWG connections and explicit WiFi sharing;
- `gaming-lite` / `gaming-full`;
- `music-lite` / `music-full`;
- `torrent`.

The current host assignments are:

- `la1n`: workstation, GNOME, development, VPN client, light gaming, and light music;
- `re-1`: workstation, GNOME, development, VPN client, full gaming, torrent, and light music;
- `mosk`: VPN server, static website, and Galene;
- `halos`: VPN server only.

`music-full` is kept as an on-demand `re-1` profile. Its installers live under
`/data/fast/music-full/installs`; `pino desktop music-full plugins install` prepares
Wine automatically and `pino desktop music-full plugins sync` runs yabridge.

Declared plugins can run a Bash `postInstall` hook, for example to install a
preset for your own plugin (illustrative configuration, not enabled by default):

```nix
pino.profiles.musicFull.windowsPlugins."Example-NAM" = {
  installer = "Example-NAM/setup.exe";
  postInstall = ''
    install -Dm644 "$INSTALLER_DIR/presets/Clean.nam" \
      "$WINEPREFIX/drive_c/users/egrapa/Documents/Example-NAM/Clean.nam"
  '';
};
```

The hook runs as the invoking user with `WINEPREFIX`, `INSTALLER_DIR` (the
installer's directory, or the source directory for `method = "link"`) and
`PLUGIN_NAME`. Hooks are native Bash scripts, not network-isolated Wine
installers. Use explicit store paths for additional tools. A failed hook fails
the installation without writing its success stamp; it does not roll back files.
Changing the hook reruns installation on the next `plugins apply`. An unchanged
installation skips the hook unless `--force` is given. Link hooks run on every
apply, like the links themselves. Hooks must therefore be safe to repeat.
The top-level commands are `reaper`, `connect`, `quantum`, `status` and `plugins`.

For a Scarlett Solo guitar session, select JACK in REAPER's Audio Device preferences
and enable at least two inputs and outputs, then run:

```bash
pino desktop music-full connect --dry-run
pino desktop music-full connect
pino desktop music-full quantum 64
pino desktop music-full quantum 128
pino desktop music-full quantum auto
```

`connect` routes Focusrite `alsa_input.hw_USB_0:capture_AUX1` to REAPER input 2, and REAPER outputs 1/2 to
Focusrite left/right. On the guitar track select mono Input 2 and enable record
monitoring. The command disconnects all other REAPER audio inputs and replaces
conflicting output links, preserving MIDI and other applications' connections.
Rerun it after reopening REAPER or
reconnecting the interface; qpwgraph is installed for visual inspection.
Port patterns are configurable in `pino.profiles.musicFull.connections`.

The music profiles default to 128 samples at 48 kHz, configurable with
`pino.profiles.music.quantum`. The quantum command changes the entire running
PipeWire graph without restarting it; `auto` releases the forced value.
Use 64 for lower latency if the current project runs without xruns, or 128/256
for more processing headroom. `pino desktop music-full quantum` shows current settings.

`pino profile disable <name>` rebuilds the system and then deletes that
profile's declared mutable state. This includes settings, caches and application
data: `music-full` removes its Wine prefixes, installed plugins, installation
stamps, yabridge files and REAPER settings; `torrent` removes downloads and
Transmission state; gaming profiles remove their game libraries and settings.
Desktop and development profiles also remove their application profiles,
extensions and sessions. Server profiles remove their service state and
provisioned service credentials.

Original installation artifacts under the music-full and Guitar Pro `installs`
directories are retained, including the replacement Guitar Pro EXE and saved
libraries used by linked plugins. Shared data is retained while another enabled
profile owns it (for example Steam, audio settings, or Caddy used by Galene).
Ownership and cleanup paths are declared in `modules/profiles/cleanup.nix`.

Close the affected applications first. Log out of GNOME and use a TTY to disable
the GNOME profile. Cleanup only runs after a successful rebuild; if it fails or
is interrupted, rerun the same disable command to finish. A system rollback
does not restore deleted application data. Nix generations/store objects,
shared system logs and files outside the declared application directories are
not erased by this command.

Server profiles are:

- `server-vpn`: AmneziaWG server;
- `server-web`: static Caddy site;
- `server-galene`: lightweight calls, screen sharing, and streams.

Galene is enabled on Mosk at `https://meet.egrapa.com/group/main/`. Store the
complete group definition in a Bitwarden Secure Note named
`pino-galene-mosk-main`, then provision it without exposing its contents:

```bash
pino provision send pino-galene-mosk-main mosk \
  /etc/pino/galene/main.json galene.service
```

Galene stays stopped until that file exists. Generate a bcrypt password object
with `pino server galene hash-password`, then place its output in that JSON
instead of storing a plaintext password:

```json
{
  "users": {
    "admin": {
      "password": {
        "type": "bcrypt",
        "key": "$2a$12$replace-with-generated-hash"
      },
      "permissions": "op"
    }
  }
}
```

## Local secrets, Bitwarden, and SSH

On `re-1` and `la1n`, `~/Secrets` is an ext4 filesystem inside a 10 GiB LUKS2
container file on the normal root filesystem. It is not a partition and is not
mounted at boot. It contains recovery codes, encrypted authenticator exports,
document copies, and other emergency material only. The first unlock creates
the container and asks for a new LUKS passphrase:

```bash
pino secret unlock
pino secret lock
```

The encrypted file is `~/.local/share/pino/secrets.luks`. Synchronization is a
manual folder comparison while both the local container and external disk are
unlocked. Do not keep live VPN or server configuration there, and never add
`~/Secrets`, a LUKS container, or a Bitwarden export to Git.

All working secrets live in Bitwarden. On a new host, run:

```bash
pino provision install
```

Pino prompts for CLI login on the first run and unlocks the vault on later
runs. There is no shell-session setup command to remember.

Store every complete runtime file in a uniquely named Secure Note. Names use
`pino-<type>-<source>-<destination>` where applicable:

- `pino-vpn-client-re-1-mosk` and `pino-vpn-client-re-1-halos`;
- `pino-vpn-client-la1n-mosk` and `pino-vpn-client-la1n-halos`;
- `pino-vpn-server-mosk` and `pino-vpn-server-halos`;
- `pino-hotspot-re-1` and `pino-hotspot-la1n`;
- `pino-galene-mosk-main`.

For desktop SSH access, use a device-specific Bitwarden SSH Key item named
`pino-ssh-<host>-github` (for example, `pino-ssh-re-1-github`), plus
`pino-ssh-server-mosk` and `pino-ssh-server-halos`. Provision installs their
private keys as `~/.ssh/github`, `mosk`, and `halos` with mode `0600`, and their
public keys beside them with the `.pub` suffix. It verifies each key pair
before writing it. The private keys stay on local disk in plaintext, protected
by Unix file permissions and any disk encryption; using them no longer needs
Bitwarden Desktop or its SSH Agent.

Install every file declared by active profiles on the current host:

```bash
pino provision install
```

Each profile declares its Bitwarden item name and destination in its Nix module.
The VPN client profile declares both VPN connections and the dedicated hotspot
connection. The workstation profile declares SSH key pairs. After
installing the hotspot file, run
`sudo nmcli connection reload`. Server VPN and Galene profiles declare their
service restarts. Missing or invalid Bitwarden items are reported at the end;
other items still install, and the command exits with an error after the full
run. Rebuild after changing the active profile list so the command uses the new
declarations.

Install one locally without printing it or creating a plaintext temporary file:

```bash
pino provision install pino-vpn-client-re-1-mosk /etc/amneziawg/mosk.conf
```

Or send it directly from Bitwarden to a server over SSH:

```bash
pino provision send pino-vpn-server-mosk mosk \
  /etc/pino/vpn/awg0.conf \
  amneziawg-server.service pino-vpn-mode.service
```

As an explicit manual alternative, stream a file from any trusted unlocked
folder to the same root-owned destination, then restart the service:

```bash
ssh mosk 'sudo install -D -o root -g root -m 0600 /dev/stdin /etc/pino/vpn/awg0.conf' \
  < /trusted/folder/awg0.conf
ssh mosk sudo systemctl restart amneziawg-server.service pino-vpn-mode.service
```

Pino synchronizes Bitwarden first. The destination is root-owned and mode
`0600`. The server does not need a Bitwarden session when `send` is run from a
trusted desktop.

Desktop systems install Bitwarden Desktop and the Bitwarden Chromium extension.
SSH uses the provisioned local private keys directly. After provisioning, Pino
tests SSH access to the GitHub repository and changes an HTTPS `origin` to SSH
if the check succeeds. If the key is missing or access fails, the remote stays
on HTTPS; rerun `pino provision install` after fixing the SSH key.

Bitwarden keeps vault lock settings per account and app. In Bitwarden Desktop,
open File → Settings → Account security, set Vault timeout to 1 minute and
Timeout action to Lock, then enable Unlock with PIN and choose a PIN in the app.
Keep "Lock with master password on restart" enabled if you want a master
password prompt after fully quitting and reopening Bitwarden. Configure the
Chromium extension's timeout and PIN separately in its Account security
settings. Bitwarden stores these settings locally; Nix does not provision them.

## VPN modes

Mosk and Halos start in `private` mode. The selected mode survives reboots:

```bash
pino server vpn mode status
pino server vpn mode set private  # server and VPN peers, no Internet exit
pino server vpn mode set egress   # Internet exit only
pino server vpn mode set full     # Internet exit, server, and VPN peers
```

The AmneziaWG configuration lives at `/etc/pino/vpn/awg0.conf` and is normally
provisioned from a uniquely named Bitwarden Secure Note.

## Manual files and encrypted external disk

Initialize a whole external disk once. This erases it and creates one LUKS2
partition containing ext4:

```bash
sudo scripts/encrypted-disk-init.sh /dev/sdX
```

Reconnect the disk, unlock it with the desktop disk prompt, enter either local
folder, and open a two-way comparison:

```bash
cd ~/Pictures
pino files merge /run/media/$USER/pino-external/Pictures
```

Meld shows additions, changes, and deletions in both directions and applies
only the operations selected in its UI. The same command can compare an
unlocked `~/Secrets` with its folder on the encrypted disk. There are no
snapshots, automatic synchronization, retention rules, or Pino metadata.

## Development environments and packages

Create a normal project-local development flake:

```bash
pino env init cpp ./my-project
cd ./my-project
nix develop
```

For a persistent package-only environment, create and enter a named profile:

```bash
pino env create lab python
pino env list
pino env enter lab
pino env add ripgrep
exit
```

Packages added inside `lab` remain there, but files, processes, and networking
are not isolated. Delete the package profile without touching project files,
or export it as a reusable dev-shell configuration:

```bash
pino env export lab ./lab-template
pino env delete lab
```

Available presets are `empty`, `cpp`, `python`, and `verilog`. One-off global
user packages still do not require a system rebuild:

```bash
pino os package search ripgrep
pino os package install ripgrep
pino os package list
pino os package remove ripgrep
```

## Git and system updates

Use Git in `~/nixos-config` for status, pull, and push. Update flake inputs with:

```bash
pino os update
```

Only declarative configuration and public host hardware data belong in this
repository. `.gitignore` rejects common local secret containers, dotenv files,
`Secrets` folders, and Bitwarden exports; inspect `git status` and the staged
diff before every push.

Rebuild the current host with:

```bash
pino os rebuild
```
