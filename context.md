# NixOS Config — Planning Context

## Goal
Reproducible, low-maintenance NixOS setup to replace Arch.
Clean base system + optional profiles that persist across reboots when enabled, fully removed when disabled.

## Hosts
- `la1n` — laptop
- `re-1` — PC
- Same user across both. Host-specific differences TBD.

## Structure
- **Flakes** — yes
- **Home-manager** — yes, for user config (shell, vscode, git, etc.)
- **Bootloader** — systemd-boot
- **Filesystem** — btrfs (leverage snapshots + NixOS generations for rollback)
- **Per-host configs** in `hosts/la1n` and `hosts/re-1`, shared modules in `modules/`

## Profile System
Profiles are optional modules toggled via CLI:
```
nix run .#enable-gaming-full
nix run .#disable-gaming-full
```
State stored in a file (e.g. `/etc/nixos/active-profiles.nix`), CLI script writes it and triggers `nixos-rebuild switch`.
Enabled profiles persist across reboots. Disabling removes all related packages/config.

---

## Base System (all hosts)

### Desktop
- GNOME on Wayland
- Extensions: Clipboard History, Tiling Assistant (or equivalent)

### Audio
- PipeWire
- qpwgraph for audio routing

### Connectivity
- Bluetooth support
- WiFi support

### Apps
- Telegram
- AmneziaVPN
- Chromium

### Shell & Editor
- Bash with completion and syntax highlighting (via home-manager)
- VSCode (via home-manager)
- Vim — system-level, no plugins, for quick edits

---

## Optional Profiles

### `gaming-lite`
**Use case:** light gaming on laptop
- Steam

### `gaming-full`
**Use case:** full gaming on PC
- Steam
- Boxflat (wheel/controller config)
- Lutris + Wine — placeholder, not configured yet
- Optimizations: TODO (start clean, improve later)

### `virt-general`
**Use case:** experiments, assignments in isolated VMs
- QEMU + virt-manager
- Default VM: Ubuntu
- SSH pre-configured on new VMs (cloud-init or similar)

### `virt-osdev`
**Use case:** OS development
- QEMU with cross-arch support (not just host x86_64)
- May share base with `virt-general`

### `music-lite`
**Use case:** play guitar through laptop
- NUM (native Linux guitar amp sim) via PipeWire
- No Wine needed

### `music-full`
**Use case:** full music production
- Reaper (DAW)
- Guitar Pro via Wine
- yabridge (bridge Windows VST plugins)
- Drum plugins (TBD)
- **Declarative Wine plugins:** user provides a file with plugin exe URLs (e.g. from cloud storage link), activation downloads and installs them via yabridge — TODO, design later

### `dev-cpp`
**Use case:** general C/C++ development
- TBD toolchain (gcc, clang, cmake, etc.)

### `dev-rust`
**Use case:** Rust projects
- rustup or nix rust toolchain

### `dev-python-ml`
**Use case:** data analytics + model training
- Python env with ML stack (TBD: numpy, pytorch, etc.)

### `dev-osdev`
**Use case:** OS / bare-metal development
- Cross-compile toolchains
- QEMU (overlaps with `virt-osdev`)

### `dev-fpga`
**Use case:** FPGA / JTAG reversing projects
- Distrobox container (avoid FHS pain with Quartus)
- Not needed immediately, placeholder for later

---

## Notes & TODOs
- Home-manager handles: bash config, vscode, git, user-level dotfiles
- Wine plugin declarative install flow: design in a future session
- Gaming optimizations (gamemode, mangohud, CPU governor): add in a future iteration
- Host differences (`la1n` vs `re-1`): TBD as setup progresses
- FPGA profile: skip for now, revisit when starting JTAG work
