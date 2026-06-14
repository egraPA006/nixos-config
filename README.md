# nixos-config

Personal NixOS flake for `re-1` (PC) and `la1n` (laptop).

---

## Fresh install

### 1. Boot the NixOS installer

Download from [nixos.org](https://nixos.org/download). Use the minimal ISO.

### 2. Clone this repo

```bash
nix-shell -p git
git clone https://github.com/egrapa/nixos-config /mnt/etc/nixos  # or any path
cd /mnt/etc/nixos
```

### 3. Partition disks with disko

> **re-1** — wipes nvme0n1 (system), nvme1n1 (/data/fast), sda (/data/slow). Double-check device names with `lsblk` first.

```bash
sudo nix run github:nix-community/disko -- --mode disko hosts/re-1/disko.nix
```

### 4. Generate and merge hardware config

```bash
nixos-generate-config --show-hardware-config
```

Copy the output into `hosts/<hostname>/hardware.nix`, replacing the placeholder.
Key things to keep from generated output: `boot.initrd.availableKernelModules`, detected filesystems, `nixpkgs.hostPlatform`.

### 5. Install

```bash
sudo nixos-install --flake .#re-1   # or la1n
```

Then reboot. Set password for egrapa with `passwd` on first login.

---

## Day-to-day

### Rebuild after config changes

```bash
sudo nixos-rebuild switch --flake /home/egrapa/prog/nixos-config#re-1
```

### Roll back

```bash
sudo nixos-rebuild switch --rollback
# or pick a generation at boot (systemd-boot shows them)
```

### Update inputs

```bash
nix flake update
sudo nixos-rebuild switch --flake .#re-1
```

### Garbage collect

Runs automatically weekly. To do it manually:

```bash
sudo nix-collect-garbage -d       # system
nix-collect-garbage -d            # user
sudo nixos-rebuild boot --flake .#re-1  # clean up boot entries too
```

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
| `dev-cpp` | GCC, Clang, CMake, GDB, Valgrind |
| `dev-rust` | rustup + cargo tools |
| `dev-python-ml` | Python + numpy/pandas/sklearn/jupyter + uv |
| `dev-osdev` | QEMU + nasm + cross-compile toolchain stubs |
| `dev-fpga` | Distrobox + Podman (for Quartus etc.) |

Profiles can overlap freely — e.g. `virt-general` + `gaming-full` at the same time is fine.

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
