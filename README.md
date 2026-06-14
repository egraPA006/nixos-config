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

### Aliases

**System (root + home):**

| Command | What it does |
|---|---|
| `rebuild` | Apply config changes (`nixos-rebuild switch`) |
| `rollback` | Roll back to previous NixOS generation |
| `gc` | Garbage collect all old generations (system + user) and clean boot entries |
| `update` | Delete previous auto snapshot, create a fresh one, pull latest packages, rebuild |
| `snap "label"` | Manual labeled snapshot of root + home, kept until removed |
| `snapls` | List all snapshots |
| `snaprb N` | Roll back root + home filesystem to snapshot N |
| `snaprm N` | Delete snapshot N from root + home |

**Data disks (games, music, projects — independent from system):**

| Command | What it does |
|---|---|
| `dsnap "label"` | Manual snapshot of `/data/fast` + `/data/slow` |
| `dsnapls` | List data snapshots |
| `dsnaprb-fast N` | Roll back `/data/fast` only to snapshot N |
| `dsnaprb-slow N` | Roll back `/data/slow` only to snapshot N |
| `dsnaprm N` | Delete snapshot N from both data disks |

**VPN (AmneziaWG):**

| Command | What it does |
|---|---|
| `vpn-on` | Start VPN |
| `vpn-off` | Stop VPN |
| `vpn-status` | Show VPN service status |

> Config is not in the repo. Place your `awg0.conf` at `secrets/awg0.conf` (gitignored) before rebuilding — the activation script copies it to `/etc/amneziawg/awg0.conf` automatically.

### Roll back NixOS generation

Use `rollback` alias, or pick a previous generation at boot from the systemd-boot menu.

---

## Profile system

Profiles are optional modules (gaming, music, dev tools, etc.) toggled via a CLI tool.
They are fully removed when disabled — no leftover packages.

```bash
nixos-profile list                  # show available profiles
nixos-profile status                # show what's active on this machine
nixos-profile enable  gaming-full   # enable + rebuild
nixos-profile disable gaming-full   # disable + rebuild
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
    active-profiles.nix      # managed by nixos-profile CLI
  la1n/  (same layout)
modules/
  base/                      # always-on: GNOME, PipeWire, networking, apps
  hardware/
    nvidia.nix               # RTX 4060, proprietary driver, Wayland vars
    intel-laptop.nix         # Ice Lake iGPU, thermald
  profiles/                  # one file per profile + loader (default.nix)
scripts/
  nixos-profile.sh           # CLI source (built into nixos-profile binary)
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
