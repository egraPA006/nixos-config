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

Then reboot. Set password for egrapa with `passwd` on first login.

---

## Day-to-day

Everything is under one CLI: **`pino`**.

```
pino help                        show all commands
pino <command> help              detailed help for that command
```

| Command | What it does |
|---|---|
| `pino info` | Neofetch-style system info |
| `pino rebuild` | Apply config changes (`nixos-rebuild switch`) |
| `pino rollback` | Roll back to previous NixOS generation |
| `pino gc` | Garbage-collect old generations and clean boot entries |
| `pino update` | Snapshot, update flake inputs, rebuild |
| `pino profile list/status/enable/disable` | Manage NixOS profiles |
| `pino monitor list/status/switch/save/rm` | Manage display profiles |
| `pino snap <label>` | Snapshot root + home |
| `pino snap ls/rb/rm` | List / roll back / delete snapshots |
| `pino snap data <label>` | Snapshot `/data/fast` + `/data/slow` |
| `pino snap data ls/rb-fast/rb-slow/rm` | Data snapshot operations |
| `pino vpn on/off/status` | AmneziaWG VPN |
| `pino hotspot start/stop` | WiFi access point (re-1) |
| `pino music-lite start/stop/status/log` | NAM guitar amp sim in PipeWire (re-1) |
| `pino music-lite set-latency <samples>` | Adjust PipeWire quantum at runtime |
| `pino music-lite set-volume <percent>` | Output level (100=default, >100 boosts) |

> VPN config: place `awg0.conf` at `secrets/awg0.conf` (gitignored) — activation script copies it to `/etc/amneziawg/awg0.conf`.

> Hotspot PSK: copy `secrets/hotspot.conf.example` → `secrets/hotspot.conf` (gitignored) and set your password.

> Monitor profiles are stored as JSON in `~/.config/monitor-profiles/`. Two defaults are seeded on first activation for re-1: `single` (DP-3 only) and `dual` (DP-3 + TV). Set a layout in GNOME Settings → Displays, then `pino monitor save <name>` to capture it.

### Roll back NixOS generation

Use `rollback` alias, or pick a previous generation at boot from the systemd-boot menu.

---

## Profile system

Profiles are optional modules (gaming, music, dev tools, etc.) toggled via a CLI tool.
They are fully removed when disabled — no leftover packages.

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
| `gaming-lite` | Steam + gamemode (laptop) |
| `gaming-full` | Steam + Lutris + Wine + Proton GE (PC) |
| `virt-general` | QEMU/KVM + virt-manager |
| `virt-osdev` | QEMU with cross-arch support (extends virt-general) |
| `music-lite` | NAM guitar amp sim + low-latency PipeWire |
| `music-full` | Reaper + yabridge + Wine VST support (extends music-lite) |
| `dev-cpp` | GCC, Clang, CMake, Meson, Ninja, GDB + VSCode clangd/meson extensions |

Profiles can overlap freely — e.g. `virt-general` + `gaming-full` at the same time is fine.

Dev environments are handled per-project via `nix develop` / `devShell` in each project's `flake.nix`.

---

## Structure

```
flake.nix                    # inputs: nixpkgs, home-manager, disko
hosts/
  re-1/
    default.nix              # host config (boot, user, imports)
    hardware.nix             # generated hardware config (placeholder → replace)
    disko.nix                # declarative disk layout
    active-profiles.nix      # managed by pino profile CLI
  la1n/  (same layout)
modules/
  pino.nix                   # pino CLI framework — defines pino.subcommands option
  pino/
    pino-art.sh              # ← paste new chafa art here, then pino rebuild
    pino-info.sh             # info layout (auto-adapts to art dimensions)
  base/                      # always-on: GNOME, PipeWire, networking, apps
  hardware/
    nvidia.nix               # RTX 4060, proprietary driver, Wayland vars
    intel-laptop.nix         # Ice Lake iGPU, thermald
  profiles/                  # one file per profile + loader (default.nix)
scripts/                     # installation helpers (run once, not part of the built system)
  hardware.sh                # generate hardware.nix for a new host
  disko.sh                   # partition disks
  install.sh                 # run nixos-install
  monitor.py                 # built into monitor binary
home/                        # home-manager: bash (blesh), vscode, git
```

---

## Home-manager

User config (shell, editor, git) is managed by home-manager as a NixOS module — no separate `home-manager switch` needed. It rebuilds together with the system.

Config lives in `home/`. To add dotfiles, create a new `home/foo.nix` and import it from `home/default.nix`.

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
