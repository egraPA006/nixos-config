# nixos-config

Personal NixOS flake for `re-1` (PC), `la1n` (laptop), and the staged `mosk`
server.

---

## Fresh install

### 1. Boot the NixOS installer

Download from [nixos.org](https://nixos.org/download). Use the minimal ISO.

### 2. Clone this repo

```bash
nix-shell -p git
git clone https://github.com/egrapa/nixos-config /tmp/nixos-config
cd /tmp/nixos-config
```

### 3. Generate hardware config

Do this before disko so `/mnt` is still empty and btrfs probing can't interfere:

```bash
bash scripts/hardware.sh <hostname>
```

### 4. Partition disks

> Double-check device names with `lsblk` before proceeding — this wipes disks.

```bash
bash scripts/disko.sh <hostname>
```

### 5. Install

```bash
bash scripts/install.sh <hostname>
```

Then reboot. If the selected vault contains
`bootstrap/{shared,hosts/<hostname>}/user-password-hash`, the installer applies
it automatically; otherwise set the password with `passwd` on first login.

---

## Day-to-day

Everything is under one CLI: **`pino`**.

```
pino help                        show all commands
pino <command> help              help for any command level
pino <command> <subcommand> help help for a leaf command
```

| Command | What it does |
|---|---|
| `pino os info/top` | System information and live monitoring |
| `pino os list` | List NixOS system generations |
| `pino os rebuild/update` | Interactively rebuild or update the flake |
| `pino os rollback [N]` | Select and activate a system generation |
| `pino os gc` | Keep current + previous generation and collect the rest |
| `pino profile list/status/enable/disable` | Manage NixOS profiles |
| `pino os package search/locate/install/remove` | Search files/packages and manage temporary user packages |
| `pino desktop monitor list/status/switch/save/rm` | Manage display profiles |
| `pino storage snap <label>` | Snapshot this host's configured system volumes |
| `pino storage snap ls/rb/rm` | List / roll back / delete system snapshots |
| `pino storage snap data <label>` | Snapshot configured data volumes when present |
| `pino storage snap data help` | Show host-specific data snapshot operations |
| `pino network vpn list/on/off/status` | Select and operate named AmneziaWG connections |
| `pino bootstrap server vpn help` | Generate server VPN state and manage/export peers |
| `pino network hotspot start/stop` | WiFi access point (re-1) |
| `pino storage vault files/populate` | List and provision root-only system secrets from the local vault |
| `pino storage vault disks/backup/check/restore` | Manage any labelled offline vault disk and its snapshots |
| `pino storage data list/disks/backup/restore/merge` | Manage plain non-secret datasets on an external medium |
| `pino desktop music-lite start/stop/status/log` | NAM guitar amp sim in PipeWire (re-1) |
| `pino desktop music-lite set-latency/set-volume` | Adjust PipeWire latency and output level |
| `pino server status/connections/disk/logs` | Inspect the server without a dashboard |
| `pino server web/proxy/vpn/passwords/mail help` | Operate an enabled server capability |

> System-secret source files live only under `/data/secrets/system/{shared,hosts/<hostname>}`. `pino storage vault populate` merges the shared and current-host trees into root-only `/var/lib/pino/secrets`; Nix modules declare only filenames, destinations, permissions, and restart units.

> When the `vault` profile is enabled, `pino os rebuild` and `pino os update`
> ask whether to populate before evaluating the new system. Answering yes
> requires the local vault to be open and refreshes the provisioned cache;
> answering no rebuilds using its existing root-only copies. Rebuilds never
> unlock the vault automatically.

> Offline vault disks use unique LUKS labels matching `pino-vault-*`. If exactly one is connected it is selected automatically; otherwise pass any full label or suffix. A backup includes the complete `/data/secrets` vault and synchronizes its system-secret tree into the disk's root-only installation bootstrap.

Create a complete removable backup disk with matching data and vault IDs:

```bash
sudo scripts/backup-disk-init.sh /dev/sdX 16GiB 1
```

This erases the selected whole disk, creates `pino-data-1` as exFAT using all
space except the final 16 GiB, and creates `pino-vault-1` there as LUKS2 with
ext4. Change the size and numeric ID for other media.

> Use `pino storage vault snapshots 1` to select a snapshot. `pino storage vault restore 1 <snapshot>` stages it under `/data/secrets/restores/`; adding `--apply` makes the live vault exactly match it after explicit confirmation.

> Hosts map logical datasets to local paths with `pino.data.datasets`. Shared
> datasets live under `pino-data-*/pino/datasets/shared/`; host-specific datasets
> live under `datasets/hosts/<hostname>/`, all as ordinary exFAT files accessible
> from Windows. `backup` makes the medium exactly match local, `restore` makes
> local exactly match the medium, and `merge` interactively incorporates medium
> changes locally without changing the medium. Installation can restore selected
> datasets using `PINO_RESTORE_DATA=all` or a comma-separated list.
> `pino storage data backup all` backs up every configured dataset while retaining
> the normal preview and per-dataset confirmation.

> Snapshot volumes are declared per host with `pino.snapshots.volumes`. `re-1`
> groups `root` and `home` as system volumes and `fast` and `slow` as data
> volumes; `la1n` currently declares only `root`. Pino generates only the
> snapshot branches supported by that host. For multi-volume groups, Pino
> records the actual per-volume Snapper numbers as one logical snapshot set;
> rollback and deletion therefore remain correct when counters differ.

### Vault-backed system secrets

When the optional `vault` profile is enabled, the internal vault separates the user-writable KeePass database from root-only
system material:

```text
/data/secrets/keepass/                    egrapa-only
/data/secrets/system/shared/              root-only, every host
/data/secrets/system/hosts/<hostname>/     root-only, one host
/data/secrets/system/devices/<device>/     root-only, manually exported devices
```

Shared files are merged first and host files override them. Provision with
`pino storage vault populate`; deployed copies live under root-only
`/var/lib/pino/secrets`, so normal rebuilds do not require the vault.

A module declares a secret without reading it into the Nix store:

```nix
pino.vault.secrets.proxy-config = {
  source = "proxy.conf";
  target = "/etc/example-proxy/config.conf";
  mode = "0600";
  restartUnits = [ "example-proxy.service" ];
};
```

For `re-1`, `system/hosts/re-1/ssh/github_ed25519` is installed as the
user-owned `~/.ssh/github_ed25519`; Home Manager selects it for `github.com`.

`pino storage vault backup [disk]` also updates the selected disk's `bootstrap/` tree.
During installation, `scripts/install.sh` selects the only connected
`pino-vault-*` disk, or the label supplied through `PINO_VAULT_LABEL` when
several are connected. With no vault disk it installs normally and falls back
to setting the user password manually. Without the vault profile, VPN and
hotspot retain their local gitignored configuration-file fallbacks.

> Monitor profiles are stored as JSON in `~/.config/monitor-profiles/`. Two defaults are seeded on first activation for re-1: `single` (DP-3 only) and `dual` (DP-3 + TV). Set a layout in GNOME Settings → Displays, then `pino desktop monitor save <name>` to capture it.

### Roll back NixOS generation

Run `pino os rollback` to list and select a generation interactively, or pass
its number directly with `pino os rollback <N>`. The systemd-boot menu remains
available when the system cannot boot normally.

---

## Profile system

Profiles are optional modules (gaming, music, dev tools, etc.) toggled via a CLI tool.
Disabling removes their declarative packages and services while preserving user data.

```bash
pino profile list                   # show available profiles
pino profile status                 # show what's active on this machine
pino profile enable  gaming-full    # enable + rebuild
pino profile disable gaming-full    # disable + rebuild
```

Active profiles are stored per-host in `hosts/<hostname>/active-profiles.nix`.
The file is safe to commit — it tracks the intended state of each machine separately.

### Available profiles

| Profile | Purpose |
|---|---|
| `desktop-apps` | Shared daily desktop applications such as Chromium and Telegram |
| `desktop-audio` | PipeWire desktop audio, PulseAudio/JACK compatibility, and qpwgraph |
| `desktop-bluetooth` | Bluetooth support and Blueman |
| `gaming-lite` | Steam + gamemode (laptop) |
| `gaming-full` | Steam + Lutris + Wine + Proton GE (PC) |
| `music-lite` | NAM guitar amp sim + low-latency PipeWire |
| `music-full` | Reaper + yabridge + Wine VST support |
| `dev-cpp` | GCC, Clang, CMake, Meson, Ninja, GDB + VSCode clangd/meson extensions |
| `torrent` | On-demand Transmission daemon and storage |
| `vault` | KeePassXC, root-only system secrets, and offline backups |
| `gnome` | GNOME session, extensions, portals, and display tooling |
| `vscode` | VS Code, Nix language support, and shared editor settings |
| `codex` | Codex CLI and user configuration |
| `git` | Git identity and defaults |
| `vpn` | AmneziaWG client and Pino controls |
| `hotspot` | NetworkManager access point routed through the VPN |
| `datasets` | Portable non-secret dataset backup and restore commands |
| `snapshots` | Host-configured Snapper volumes and Pino snapshot commands |
| `system-monitor` | Live temperatures, CPU, GPU, RAM, and process monitoring |
| `server-web` | Caddy, ACME, and a small static website |
| `server-proxy` | VLESS Reality over TCP 443 with switchable Internet egress |
| `server-vpn` | AmneziaWG private access with optional Internet egress |
| `server-password-sync` | KeePass-only Syncthing over the private VPN |
| `server-mail` | Postfix, Dovecot, Rspamd, DKIM, and ACME mail certificates |

Profiles can overlap freely when their packages and services are compatible.

Dev environments are handled per-project via `nix develop` / `devShell` in each project's `flake.nix`.

### Mosk server scaffold

The canonical Ergo Proxy city spelling is **Mosk**. Its host is `hosts/mosk`,
with local user `vincent`. It is a valid flake output, but its committed disk
path is an intentionally unusable placeholder. The staging script replaces it
only after interactive whole-disk confirmation and generates `hardware.nix`.

A minimal service selection looks like:

```nix
# hosts/mosk/active-profiles.nix
[
  "server-web"
  "server-proxy"
  "server-vpn"
  "server-password-sync"
  "server-mail"
]

# hosts/mosk/default.nix
pino.server = {
  domain = "example.com";
  acmeEmail = "admin@example.com";
  proxy.users.vincent = { };
  vpn.externalInterface = "ens3";
  passwordSync.devices.re-1.id = "SYNCTHING-DEVICE-ID";
  mail.accounts."vincent@example.com".aliases = [ "postmaster@example.com" ];
};
```

Keep the referenced secret files outside Git. The local vault source exactly
mirrors their server-relative paths:

```text
/data/secrets/system/hosts/mosk/
└── server/
    ├── awg0.conf
    ├── sing-box/
    │   ├── reality-private-key
    │   ├── reality-short-id
    │   └── users/vincent.uuid
    └── mail/accounts/vincent@example.com.hash
```

The deployable files are also the authoritative VPN state. NixOS clients live
under `hosts`; phones and other unmanaged clients live under `devices`. Only a
host's own tree is ever populated or uploaded:

```text
/data/secrets/system/
├── hosts/
│   ├── mosk/server/awg0.conf
│   └── re-1/vpn/mosk.conf
└── devices/
    └── phone/vpn/mosk.conf
```

After receiving the VPS public IP, initialize it locally. With no peer names,
the defaults are `re-1` and `phone`:

```bash
pino storage vault open
pino bootstrap server vpn init mosk 203.0.113.10
pino bootstrap server vpn list mosk
```

The generator creates independent keys and preshared keys, assigns Mosk
`10.77.0.1` and peers from `.2`, and generates common AmneziaWG masking
parameters. It writes each peer directly to its canonical host/device path and
refuses to overwrite initialized state. Existing vaults using the former
`/data/secrets/vpn/<host>` generator layout migrate once with:

```bash
pino bootstrap server vpn migrate mosk
```

Migration verifies and installs every client before offering to remove the
redundant legacy state.

Peer lifecycle does not rotate unaffected clients:

```bash
pino bootstrap server vpn peer add mosk laptop
pino bootstrap server vpn peer remove mosk phone
pino bootstrap server vpn set-endpoint mosk vpn.example.com
```

After a peer change, run `pino bootstrap server sync mosk <address>` to deploy
the updated server peer list. Export never prints key material. It copies an
existing canonical configuration to a user-owned `0600` file suitable for
Android import:

```bash
pino bootstrap server vpn export mosk phone ~/Downloads/mosk-phone.conf
```

Adding the `re-1` peer writes `system/hosts/re-1/vpn/mosk.conf` immediately.
re-1 declares `mosk` as a named connection alongside the legacy `awg0`
connection. More servers use the same model through
`pino.profiles.vpn.connections.<name>` and can then be selected without
replacing configurations:

```bash
pino network vpn list
pino network vpn on mosk
pino network vpn off mosk
pino network vpn status
```

Pino intentionally stops another active named connection before starting a
full-route VPN, avoiding conflicting default routes. Configurations remain
saved and independently selectable.

Each server profile contributes its required files to
`pino.bootstrap.secrets`; there is no second shell-script manifest to maintain.
Check the vault before installing:

```bash
pino storage vault open
pino bootstrap server check mosk
```

#### Install and bootstrap Mosk

This is the complete first-deployment order. Mosk currently enables only
`server-vpn`, so a domain is not required.

1. On re-1, validate the exact revision that the live ISO will clone:

   ```bash
   cd ~/nixos-config
   git status
   git diff --check
   nix flake check --no-build
   ```

   Review the diff, commit all intended tracked and new files, then `git push`.
   Never add anything below `/data/secrets` or an exported client config.

2. Create a dedicated administrator key. Keep its passphrase; only its `.pub`
   file is pasted into the installer:

   ```bash
   ssh-keygen -t ed25519 -a 100 -f ~/.ssh/mosk_ed25519 -C "vincent@mosk"
   ssh-add ~/.ssh/mosk_ed25519
   cat ~/.ssh/mosk_ed25519.pub
   ```

   Back up the private key in the encrypted vault before relying on it as the
   only remote access method.

3. Once the provider has assigned the public IP, prepare all initial VPN
   artifacts on re-1. `init` is one-time; use `list` instead if state exists:

   ```bash
   pino os rebuild
   pino storage vault open
   # Existing vaults only: migrate the former /data/secrets/vpn/mosk state.
   pino bootstrap server vpn migrate mosk
   # New vaults instead: initialize the VPN once.
   # pino bootstrap server vpn init mosk 203.0.113.10
   pino bootstrap server vpn list mosk
   pino storage vault populate
   pino bootstrap server check mosk
   ```

   The final check must show `server/awg0.conf` as `OK`.

4. On the NixOS live ISO, verify networking and identify the whole installation
   disk. The selected disk will be erased:

   ```bash
   ip -br address
   ip route
   ping -c 3 cache.nixos.org
   lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL
   ```

5. Clone the pushed configuration and confirm the VPN-only profile:

   ```bash
   nix-shell -p git
   git clone https://github.com/egrapa/nixos-config
   cd nixos-config
   cat hosts/mosk/active-profiles.nix
   ```

6. Stage the server, replacing `/dev/vda` with the verified whole disk:

   ```bash
   sudo scripts/server-stage.sh mosk /dev/vda
   ```

   Paste the contents of `~/.ssh/mosk_ed25519.pub` when asked. The script shows
   all disks, requires the exact selected path as confirmation, generates
   hardware configuration, partitions and installs the server, and prints its
   SSH fingerprint plus a one-time bootstrap code. No private key or vault
   secret is entered on the server console.

7. Save the `SHA256:...` SSH fingerprint and bootstrap code, then reboot and
   detach the ISO. The code expires one hour after staging:

   ```bash
   reboot
   ```

   If needed, reproduce the fingerprint through the trusted provider console:

   ```bash
   ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
   ```

8. From re-1, provision the manifest-listed server file. Type the console
   fingerprint and one-time code when prompted:

   ```bash
   ssh-add ~/.ssh/mosk_ed25519
   pino bootstrap server apply mosk 203.0.113.10
   ```

9. Verify the installed server and private VPN:

   ```bash
   ssh -i ~/.ssh/mosk_ed25519 vincent@203.0.113.10
   pino server status
   pino server disk
   pino server vpn status
   ```

   Then, back on re-1:

   ```bash
   pino network vpn list
   pino network vpn on mosk
   ping -c 3 10.77.0.1
   pino network vpn status mosk
   ```

10. Export the Android peer, transfer it locally, import it into AmneziaWG, and
    remove the temporary exported copy afterward:

    ```bash
    pino bootstrap server vpn export mosk phone ~/Downloads/mosk-phone.conf
    ```

11. The staging checkout now contains generated, non-secret Mosk hardware and
    disk files. Copy them back to re-1, review, commit, and push them so future
    rebuilds reproduce the installed machine:

    ```bash
    cd ~/nixos-config
    scp -i ~/.ssh/mosk_ed25519 \
      vincent@203.0.113.10:~/nixos-config/hosts/mosk/hardware.nix \
      vincent@203.0.113.10:~/nixos-config/hosts/mosk/disko.nix \
      hosts/mosk/
    git diff -- hosts/mosk
    ```

The receiver accepts only regular files declared by the evaluated manifest and
only destinations below `/var/lib/pino/secrets`. It rejects extra files,
symlinks, missing files, wrong bootstrap codes, expired codes, and a mismatched
hostname. It never performs a root rebuild from the user-owned checkout.
Successful initial provisioning consumes the code and restarts only declared
units. Later secret changes use the same constrained receiver without reopening
initial bootstrap access:

```bash
pino bootstrap server check mosk
pino bootstrap server sync mosk 203.0.113.10
```

Both remote operations scan the ED25519 host key and require typing the
fingerprint visible through the trusted server console. Secret contents are
transferred directly over SSH and are never printed or placed in the Nix store.

The public DNS prerequisites are an `A`/`AAAA` record for the website and
`mail` host, an `MX` record, SPF, DKIM, and DMARC. Ask the VPS provider for
matching reverse DNS and verify that SMTP port 25 is permitted. Public ports
are HTTP 80, proxy HTTPS 443/TCP, AmneziaWG 585/UDP, and the standard mail
ports opened by the mail profile. Syncthing and its GUI are not public:
synchronization is reachable only through the trusted VPN interface and the
GUI binds to localhost.

The default mail quota is 5 GiB per account, journals are capped at 256 MiB,
and only five KeePass sync versions are retained. Those defaults are intended
to fit a 10–20 GiB server, but mail usage still needs monitoring with
`pino server disk`.

#### Pair re-1 with Mosk for KeePass

The desktop client belongs to the existing `vault` profile rather than a
separate profile: it can synchronize only the KeePass directory inside the
mounted encrypted vault. Discovery, relays, NAT traversal, incoming listening,
and the public GUI are disabled; re-1 connects directly to Mosk at
`10.77.0.1:22000` over AmneziaWG.

Pair both ends once:

1. On re-1, open the vault and run `pino storage vault sync id`. Put that ID in
   Mosk as `pino.server.passwordSync.devices.re-1.id`.
2. On Mosk, run `pino server passwords id`. Put that ID on re-1 as
   `pino.vault.sync.serverId`.
3. Rebuild both machines, connect re-1 to the VPN, then run
   `pino storage vault open`. Opening starts the client; closing the vault stops
   it before unmounting.

Override `pino.vault.sync.serverAddress` only if Mosk uses a different VPN
address. Syncthing remains unconfigured until `serverId` is set, so no fake or
placeholder device identity is necessary.

---

## Structure

```
flake.nix                    # inputs: nixpkgs, home-manager, disko
configurations/
  desktop/                   # full NixOS desktop entry point used by re-1 and la1n
  server/                    # headless NixOS entry point
  nix/                       # future standalone Home Manager entry point for Ubuntu
hosts/
  re-1/
    default.nix              # host-specific imports and settings
    hardware.nix             # generated hardware config (placeholder → replace)
    disko.nix                # declarative disk layout
    active-profiles.nix      # managed by pino profile CLI
  la1n/  (same layout)
  mosk/                      # server identity; staging replaces hardware/disk placeholders
modules/
  pino.nix                   # pino CLI framework — defines pino.subcommands option
  pino/
    bootstrap.nix            # local-vault to constrained remote-server provisioning
    system.nix               # NixOS generation and system-information commands
    profile.sh               # profile state CLI
    pino-art.sh              # system-info art
    pino-info.sh             # system-info layout
  core/                      # minimal shared NixOS, user, shell, and Pino foundation
    options.nix              # pino.user and pino.configDir machine identity
  boot/                      # selectable boot-loader policy
  desktop/                   # desktop networking and user integration
  server/                    # SSH, bounded logs, constrained bootstrap receiver, Pino operations
  hardware/
    nvidia.nix               # RTX 4060, proprietary driver, Wayland vars
    intel-laptop.nix         # Ice Lake iGPU, thermald
  profiles/                  # NixOS profile registry and domain option schemas
    desktop/                 # graphical desktop, gaming, music, and desktop services
    development/             # development tools currently integrated through NixOS
    network/                 # VPN and hotspot capabilities
    security/                # vault and identity capabilities
    server/                  # web, proxy, VPN, KeePass sync, and mail capabilities
scripts/                     # installation helpers (run once, not part of the built system)
  hardware.sh                # generate hardware.nix for a new host
  disko.sh                   # partition disks
  install.sh                 # run nixos-install
  server-stage.sh            # confirm disk, install server, and issue one-time bootstrap code
  backup-disk-init.sh        # create matching pino-data/pino-vault partitions
  monitor.py                 # built into monitor binary
```

---

## Home Manager

Home Manager is embedded in the NixOS configuration, so there is no separate
`home-manager switch`. User-facing configuration lives beside the capability
that owns it—for example, the Codex and GNOME profiles configure their own Home
Manager options. Only the basic user and shell setup is always enabled.

Each real host declares `pino.user.name`, `pino.user.home`, and
`pino.configDir`. Shared modules and the installer consume those values instead
of embedding a username or checkout path.

The profile groups separate desktop-specific modules from capabilities that can
later be reused by server hosts. A future standalone Home Manager entry point
for Ubuntu should import portable user modules directly rather than importing
the NixOS profile registry.

---

## NixOS quick reference

```bash
# Search packages
nix search nixpkgs <name>

# Try a package without installing
nix shell nixpkgs#<name>

# Check what a config change would do (no apply)
sudo nixos-rebuild dry-activate --flake .#re-1

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Open a dev shell (if you add devShells to flake.nix)
nix develop
```
