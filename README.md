# Pino NixOS config

One small flake for four machines:

- `re-1`: desktop, ext4 root plus `/data/fast` and `/data/slow`;
- `la1n`: laptop, LUKS2-encrypted ext4 root;
- `mosk`: VPN exit, static website, and data disk;
- `halos`: VPN only.

There is no Disko, Btrfs, mail server, or Git mirror. GitHub stores only the
public configuration. Bitwarden stores passwords, SSH keys, and runtime
configuration. A local LUKS2 container mounted at `~/secrets` stores recovery
material only. Offline disks store folder snapshots.

## Fresh installation

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
public key, and asks for the local user password.

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
- `re-1`: workstation, GNOME, development, VPN client, full gaming, and torrent;
- `mosk`: VPN server, static website, and Galene;
- `halos`: VPN server only.

`music-full` is kept as an on-demand `re-1` profile. Its installers live under
`/data/fast/music-full/installers`; `pino desktop music-full install` prepares
Wine automatically and `pino desktop music-full sync` runs yabridge.

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

On `re-1` and `la1n`, `~/secrets` is an ext4 filesystem inside a LUKS2
container file on the normal root filesystem. It is not a partition and is not
mounted at boot. It contains recovery codes, encrypted authenticator exports,
and other emergency material only. The first unlock creates the container and
asks for a new LUKS passphrase:

```bash
pino secret unlock
pino secret lock
```

The encrypted file is `~/.local/share/pino/secrets.luks`. Back up that file as
a whole; external-disk synchronization will be added to `pino backup` later.
For safety, `pino backup` refuses a source or restore target containing an
unlocked `~/secrets`; lock it first.
Do not keep live VPN or server configuration there, and do not add
`~/secrets` or the container to Git.

All working secrets live in Bitwarden. Log in once, then unlock its CLI in each
trusted shell where provisioning is needed:

```bash
bw login
export BW_SESSION="$(bw unlock --raw)"
```

Store every complete runtime file in a uniquely named Secure Note. Names use
`pino-<type>-<source>-<destination>` where applicable:

- `pino-vpn-client-re-1-mosk` and `pino-vpn-client-re-1-halos`;
- `pino-vpn-client-la1n-mosk` and `pino-vpn-client-la1n-halos`;
- `pino-vpn-server-mosk` and `pino-vpn-server-halos`;
- `pino-hotspot-re-1` and `pino-hotspot-la1n`;
- `pino-galene-mosk-main`.

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

Pino synchronizes Bitwarden first. The destination is root-owned and mode
`0600`. The server does not need a Bitwarden session when `send` is run from a
trusted desktop.

Desktop systems install Bitwarden Desktop and point `SSH_AUTH_SOCK` at its
native Linux agent socket. Enable the SSH agent once in Bitwarden settings and
test it with `ssh-add -L`. The repository remote then uses the key from
Bitwarden. See the [Bitwarden SSH agent guide](https://bitwarden.com/help/ssh-agent/).

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

## Offline backups

Initialize a whole backup disk once. This erases it and creates one ext4
partition labelled `pino-backup`:

```bash
sudo scripts/backup-disk-init.sh /dev/sdX
```

Reconnect or mount it, then use its mount path or mounted block device:

```bash
pino backup /run/media/$USER/pino-backup ~/Pictures photos
pino backup push /run/media/$USER/pino-backup ~/Projects projects
pino backup status /run/media/$USER/pino-backup
pino backup pull /run/media/$USER/pino-backup ~/Pictures photos
```

Each push creates an immutable, hard-linked snapshot. Pull requires typing an
explicit confirmation because it makes the target folder exactly match the
snapshot. Push stops with a conflict if the disk changed since this machine's
last push or pull.

## Development environments and packages

Create a normal project-local development flake:

```bash
pino env init cpp ./my-project
pino env enter ./my-project
```

Without a path, the environment is personal and lives below
`~/.config/pino/envs`:

```bash
pino env init python
pino env list
pino env enter python
```

Available presets are `cpp`, `python`, and `verilog`. One-off user packages do
not require a system rebuild:

```bash
pino os package search ripgrep
pino os package install ripgrep
pino os package list
pino os package remove ripgrep
```

## Git and system updates

GitHub is the only remote:

```bash
pino repo status
pino repo pull
pino repo push
pino repo inputs update
```

Rebuild the current host with:

```bash
pino os rebuild
```
