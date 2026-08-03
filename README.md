# nixos-config

Personal NixOS flake for `re-1` (PC) and `la1n` (laptop).

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
| `pino network vpn on/off/status` | AmneziaWG VPN |
| `pino network hotspot start/stop` | WiFi access point (re-1) |
| `pino storage vault files/populate` | List and provision root-only system secrets from the local vault |
| `pino storage vault disks/backup/check/restore` | Manage any labelled offline vault disk and its snapshots |
| `pino storage data list/disks/backup/restore/merge` | Manage plain non-secret datasets on an external medium |
| `pino desktop music-lite start/stop/status/log` | NAM guitar amp sim in PipeWire (re-1) |
| `pino desktop music-lite set-latency/set-volume` | Adjust PipeWire latency and output level |

> System-secret source files live only under `/data/secrets/system/{shared,hosts/<hostname>}`. `pino storage vault populate` merges the shared and current-host trees into root-only `/var/lib/pino/secrets`; Nix modules declare only filenames, destinations, permissions, and restart units.

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

Profiles can overlap freely when their packages and services are compatible.

Dev environments are handled per-project via `nix develop` / `devShell` in each project's `flake.nix`.

---

## Structure

```
flake.nix                    # inputs: nixpkgs, home-manager, disko
configurations/
  desktop/                   # full NixOS desktop entry point used by re-1 and la1n
  server/                    # future headless NixOS entry point
  nix/                       # future standalone Home Manager entry point for Ubuntu
hosts/
  re-1/
    default.nix              # host-specific imports and settings
    hardware.nix             # generated hardware config (placeholder → replace)
    disko.nix                # declarative disk layout
    active-profiles.nix      # managed by pino profile CLI
  la1n/  (same layout)
modules/
  pino.nix                   # pino CLI framework — defines pino.subcommands option
  pino/
    system.nix               # NixOS generation and system-information commands
    profile.sh               # profile state CLI
    pino-art.sh              # system-info art
    pino-info.sh             # system-info layout
  core/                      # minimal shared NixOS, user, shell, and Pino foundation
    options.nix              # pino.user and pino.configDir machine identity
  boot/                      # selectable boot-loader policy
  desktop/                   # desktop networking and user integration
  server/                    # future server-specific foundation
  hardware/
    nvidia.nix               # RTX 4060, proprietary driver, Wayland vars
    intel-laptop.nix         # Ice Lake iGPU, thermald
  profiles/                  # NixOS profile registry and domain option schemas
    desktop/                 # graphical desktop, gaming, music, and desktop services
    development/             # development tools currently integrated through NixOS
    network/                 # VPN and hotspot capabilities
    security/                # vault and identity capabilities
scripts/                     # installation helpers (run once, not part of the built system)
  hardware.sh                # generate hardware.nix for a new host
  disko.sh                   # partition disks
  install.sh                 # run nixos-install
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
