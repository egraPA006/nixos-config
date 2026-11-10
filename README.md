# Pino NixOS config

One small flake for four machines:

- `re-1`: desktop, ext4 root plus `/data/fast` and `/data/slow`;
- `la1n`: laptop, LUKS2-encrypted ext4 root;
- `mosk`: private VPN/optional exit, website, Galene, Xray/XHTTP and telemt/FakeTLS;
- `halos`: AmneziaWG, Xray/XHTTP and telemt at `halos.egrapa.com`, without Galene.

There is no Disko, Btrfs, mail server, or Git mirror. GitHub stores only the
public configuration. Bitwarden stores passwords, SSH keys, and runtime
configuration. An unlocked external LUKS2 disk holds one current copy of declared artifacts,
personal datasets and a portable encrypted Bitwarden export. Pino previews
changes and asks before applying them; backups have no version history.

## CLI layout

- `pino os`: rebuild/update, generations, packages, profiles, populate and diagnostics.
  On desktops it also provides remote `install` / `rescue`; `os provision` manages
  delivery and preparation of Bitwarden credentials.
- `pino backup` / `pino restore`: explicit transfers to/from an unlocked disk.
- `pino host <host> ...`: execute Pino on a remote server.
- `pino desktop` / `pino server`: profile-specific application/service commands.
- `pino vpn`: client connections, WiFi sharing and client creation.
- `pino env`: development environments.

Use `help`, `--help` or `-h` at a command node. Unknown commands and extra arguments
on no-argument commands are rejected. Old root `populate`, `profile`, `provision`
and `bootstrap` entry points redirect with a migration message, but are absent
from help and completion. `files`, `secret`/`recovery` and the old `artifacts`
branch are removed. No personal files are deleted by this CLI reorganization.

Profile enable only rebuilds; `pino os populate` handles application setup using
the same declared prerequisites on first installation and later profile changes.
Profile disable retains data; only explicit, confirmed `profile purge` cleans it.

Server services are enabled declaratively by the host's active profiles and
NixOS modules. Pino exposes inspection commands, not duplicate service
start/stop/restart wrappers. Change the configuration and rebuild for persistent
changes; provisioning restarts affected services after credential updates.
Use ordinary `sudo systemctl restart <unit>` for one-off troubleshooting.
The VPN mode command remains an intentional runtime control for switching
private/egress/full without distributing new client configurations.

## Fresh installation

### Remote servers

Prepare server credentials before bootstrapping:

To generate and save missing records directly in Bitwarden, without temporary
export files, log in to the CLI once with `bw login`, then run from this checkout:

```bash
nix run path:.#server-secrets -- mosk --bitwarden
# After rebuilding the desktop: pino os provision prepare mosk --bitwarden
```

This unlocks the vault when necessary, generates a 32-character Galene password
using `bw generate`, saves the `admin` Login as `pino-galene-mosk-admin`, and
creates Secure Notes `pino-galene-mosk-main`, `pino-vpn-server-mosk`,
`pino-xray-mosk` and `pino-telemt-mosk`. The proxy notes contain a `users` JSON
object and a hidden `owner connection URI` field for importing into clients.
Public endpoints are shared with Nix in `resources/mosk-proxies.json`. Existing
records are never overwritten. Duplicate names, mismatched Login/room passwords,
or an existing room without its Login require manual resolution. Interrupted
runs can be retried: an already-created Login is reused. SSH records are untouched.
Secret payloads are passed through stdin, never command arguments or terminal
output. Bitwarden CLI still maintains its normal encrypted local vault cache.

Rotate existing secrets explicitly (each operation asks for confirmation):

```bash
nix run path:.#server-secrets -- mosk --bitwarden --rotate galene
nix run path:.#server-secrets -- mosk --bitwarden --rotate vpn
```

Before editing, rotation saves the original records in a uniquely named Secure
Note `pino-rotation-backup-<host>-<scope>-…`. Galene rotation preserves room
settings and other users, updating the admin Login and password hash. These two
Bitwarden writes are not atomic: if interrupted, repair the room hash from the
saved Login without generating another password:

```bash
nix run path:.#server-secrets -- mosk --bitwarden --repair-galene
```

VPN rotation changes only the server private key; peers, addresses and AWG
parameters are preserved. Update the server public key on all clients when
deploying. Rotating records does not alter the running server. Deploy from the
desktop using its configured SSH alias (or `vincent@IP`):

```bash
pino os provision send pino-galene-mosk-main mosk /etc/pino/galene/main.json galene.service
pino os provision send pino-vpn-server-mosk mosk /etc/pino/vpn/awg0.conf amneziawg-server.service pino-vpn-mode.service
```

Keep the recovery snapshot until the server and clients have been verified.
Restoring it means restoring each original record's fields from the snapshot
and provisioning the old configuration again. Retire obsolete snapshots manually
once they are no longer needed. Do not run preparation/rotation concurrently:
the CLI checks for changes before writing, but Bitwarden provides no multi-item
transaction here. After a timeout, inspect saved records before retrying rotation;
for Galene, prefer `--repair-galene` to avoid generating another password.

Alternatively, prepare local files for manual import:

```bash
pino os provision prepare mosk
# AmneziaWG, Xray and telemt, without Galene:
pino os provision prepare halos
```

`prepare` prompts twice for the Galene `admin` password on Mosk and stores only
its bcrypt hash. Files go to a unique `pino-<host>-…` directory in the system
temporary directory (normally `/tmp`, directory 0700, files 0600); an optional
final argument selects another new directory. After saving and checking the
Bitwarden notes, delete the generated directory; temporary storage may also be
cleared by the system.
Existing directories and paths inside Git checkouts are rejected. Import the
contents of `pino-vpn-server-<host>.conf` and, for Mosk,
`pino-galene-mosk-main.json` into the Notes fields of Secure Notes with the
matching names (without the file extension). Nothing is uploaded automatically,
and existing SSH keys are not changed. Proxy preparation also writes matching
`pino-xray-<host>.json` / `pino-telemt-<host>.json` note payloads and private
`-client.txt` files with connection URIs; save those as hidden fields in the
corresponding Bitwarden notes, without printing them in terminal logs.

The generated VPN listens on UDP 585 at `10.77.0.1/24`, matching the current
server defaults. It has no peers: add each client's public key and a unique
`AllowedIPs = 10.77.0.x/32`. Clients need the generated server public key from
`server.pub` and matching `S1`, `S2`, `H1`–`H4`. Internet egress is a separate
VPN mode; the default is `private`. Set DNS `meet.egrapa.com` to Mosk for Galene.

Without rebuilding the local system, run the same generator from this checkout:

```bash
nix run path:.#server-secrets -- mosk
```

The normal VPS flow starts from the temporary Ubuntu or Debian image supplied
by the provider. Create Bitwarden SSH Key items named `pino-ssh-server-mosk`
and `pino-ssh-server-halos`. Give the provider only the public half of the
matching item. Before initial bootstrap, save that public key locally as a
selector, for example `~/.ssh/mosk.pub`. On an installed desktop,
`pino os provision install` installs both halves locally as `~/.ssh/mosk` and
`~/.ssh/mosk.pub`.

Provision the SSH key, make sure this checkout is clean and pushed to
`origin/main`, then run:

```bash
pino os provision install
pino os install mosk ubuntu@203.0.113.10 ~/.ssh/mosk.pub
```

`pino os install` / `pino os rescue` unlock and synchronizes Bitwarden itself when needed.

`install` requires an x86_64 Linux VPS with passwordless root or `sudo`, enough
RAM for the pinned NixOS kexec installer, working DHCP, and Secure Boot disabled.
It boots the installer in RAM, so no provider console is needed in the normal
case.

If the provider has already booted a NixOS installer or rescue image, skip
kexec:

```bash
pino os rescue halos root@203.0.113.11 ~/.ssh/halos.pub
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

Boot a NixOS installer, obtain Git if it is not already available, and clone:

```bash
# Only if git is missing; this works without legacy Nix channels:
nix --extra-experimental-features 'nix-command flakes' shell github:NixOS/nixpkgs/20b1ddd1aa5ace70c9468305030aa4f9ef79671b#git
git clone https://github.com/egraPA006/nixos-config.git
cd nixos-config
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
```

Select actual device paths, then run **one** installer command:

```bash
# Fresh desktop: formats ALL THREE selected disks after confirmation.
sudo scripts/install.sh re-1 --disk /dev/system --disk /dev/fast --disk /dev/slow

# Reinstall desktop: format only system; preserve existing labelled ext4 data disks.
sudo scripts/install.sh re-1 --disk /dev/system --disk /dev/fast --disk /dev/slow --keep-data

# Laptop: EFI + LUKS2-encrypted ext4 root.
sudo scripts/install.sh la1n --disk /dev/nvme0n1

# Already in the server installer console (BIOS, /dev/vda).
sudo scripts/install.sh mosk --disk /dev/vda --ssh-key-file /path/to/admin.pub
```

`/dev/system`, `/dev/fast` and `/dev/slow` are placeholders, not device names to
copy blindly. `--keep-data` requires the existing `pino-fast` and `pino-slow`
partition and filesystem labels; it refuses incompatible layouts before erasing
anything. It still erases the selected system disk. For manual/custom mounts,
prepare `/mnt` yourself and omit all `--disk` options. `repair` never partitions.
The existing `partition.sh` and remote `server-stage.sh` entry points still work.

The installer generates hardware configuration, installs NixOS including Pino,
copies the checkout, installs an optional public SSH key and asks for the desktop
user password. Servers require a public key. No Bitwarden login or application
setup happens in the live installer. Reboot, log in as the configured user, unlock
the external disk and run `pino os populate /path/to/disk` without sudo. For hosts
without local artifacts, `pino os populate` is sufficient.

### Reinstalling re-1 and preparing another desktop

There are three inputs to a fresh desktop: Git supplies the system and application
declarations, Bitwarden supplies declared runtime credentials, and an unlocked
external disk supplies saved installers and libraries. Installing NixOS does not
install those local Windows applications or restore personal documents.

After booting the new `re-1`, log in as `egrapa`, unlock the existing external
disk in GNOME, then run:

```bash
pino os populate /run/media/$USER/pino-external
```

This logs in to/unlocks Bitwarden, installs declared credentials, compares and
imports `pino/artifacts/` from the disk, and runs available application setup.
Run it again after following any `action required` instructions. A pending or
failed profile does not block unrelated profiles. Existing commands check their
state; identical secrets do not restart healthy services. Exit codes are 0 for
complete, 2 for pending prerequisites and 1 for failures. `--skip-secrets` skips
the vault explicitly; without a disk, setup uses existing local installers.
Personal datasets are never implicitly restored by populate.

These commands become available after installing this revision or rebuilding the
existing host. **Do not run encrypted-disk-init.sh again on an existing disk.**
Before reinstalling, create/update the artifact copy with:

```bash
pino backup artifacts /run/media/$USER/pino-external
```

| External folder below `pino/artifacts/` | Local destination on re-1 | Contents |
| --- | --- | --- |
| `music-full/` | `/data/fast/music-full/installs/` | Entire installer tree, FabFilter installers, linked EZX/Nucleus libraries and hook assets |
| `guitar-pro/` | `/data/fast/guitar-pro/installs/` | Complete GP8 EXE and configured `replacement/GuitarPro.exe` |
| `assetto-corsa/` | `/data/fast/assetto-corsa/installs/` | Declared local ZIPs; cached public downloads may also be retained |

The transfer shows file sizes, modification timestamps and SHA-256 hashes for
conflicts, asks which version to keep, then asks to apply the final plan. It does
not print file contents or merge them. Missing artifact folders are reported;
available folders are still processed. A required unmounted filesystem is an
error. Do not modify or unmount either side during a transfer. Copies are atomic
per file, not a transaction for the whole tree; after an interrupted transfer,
rerun the command to compare what remains. Application setup still verifies its
own configured checksums.

Use `pino restore artifacts /path/to/disk --dry-run` to inspect destinations
without setting up applications. All artifact commands now take the disk root
and use `pino/artifacts/` below it. The old artifact import/list interface has
been removed. If an existing disk uses `artifacts/` at its root, move that folder
to `pino/artifacts/` once; Pino does not move or delete it automatically.

Keep the imported library directories locally: plugins using `method = "link"`
link into them. They must work after unplugging the external disk. Do not copy
only the EXEs, rename the saved directories, or import old installation stamps
instead of running the installation commands. Licensing/login is separate and
may require manual activation. `pino os provision install` does not retrieve music,
Guitar Pro or Content Manager license keys automatically.

For Assetto Corsa, log into Steam, install the game and required DLC, select
Proton-GE, start the original game once, then close the game and Steam:

```bash
pino os populate
```

The dedicated `pino desktop assetto-corsa setup` command also remains available.
CM and the declared public shader archive can download over HTTPS; the local ZIPs
must already be imported. Configure CM's game directory and AppID starter as
described below. Activate CM manually with your own key stored in Bitwarden.
Populate invokes the declared setup once prerequisites are ready; manual
licensing and the initial Steam login/game launch remain your actions.

For `re-1`, `pino os provision install` currently retrieves these records:

| Bitwarden item | Destination |
| --- | --- |
| SSH Key `pino-ssh-re-1-github` | `~/.ssh/github` and `.pub` |
| SSH Key `pino-ssh-server-mosk` | `~/.ssh/mosk` and `.pub` |
| SSH Key `pino-ssh-server-halos` | `~/.ssh/halos` and `.pub` |
| SSH Key `pino-ssh-re-1-winlaptop` | `~/.ssh/winlaptop` and `.pub` |
| Secure Note `pino-vpn-client-re-1-mosk` | `/etc/amneziawg/mosk.conf` |
| Secure Note `pino-vpn-client-re-1-halos` | `/etc/amneziawg/halos.conf` |
| Secure Note `pino-hotspot-re-1` | `/etc/NetworkManager/system-connections/pino-vpn-share.nmconnection` |

These must already exist; provisioning does not generate a new client identity
or register SSH public keys with GitHub. Browser, Steam, Bitwarden Desktop, Codex
and other application sessions are not restored by this command. Local user and
LUKS passwords are entered during installation/unlock, not fetched from the vault.
Server VPN/Galene notes are provisioned on the servers, not onto this desktop.

For a *second concurrently used computer*, create `hosts/<new-name>/` and a
matching `mkHost` entry in `flake.nix`. Reuse the profile list and application
declarations, but supply its own `networking.hostName`, hardware, storage, GPU
module and WiFi interface. The current re-1 application overrides are in
`hosts/re-1/default.nix`, `music-full-fabfilter.nix`, and `assetto-corsa.nix`:
copy/adapt those declarations too if the same plugins and mods are wanted.
Copying only `active-profiles.nix` does not copy the host's plugin/mod selections.
Keep the needed package overlays from the re-1 flake entry as well.

Do not import the complete re-1 host into the new host: it fixes its hostname,
three-disk storage layout, NVIDIA and device-specific settings. The partition
script supports only the four existing layouts; prepare/mount a new host's
filesystems under `/mnt` yourself before `sudo scripts/install.sh <new-name>`.
The installer regenerates hardware.nix, but does not design storage.nix or add
a flake entry for you. A one-disk machine needs different storage declarations.
Reusing `re-1` unchanged is appropriate only for replacing the original machine.

Create `pino-ssh-<new-name>-github`, `pino-vpn-client-<new-name>-mosk`,
`pino-vpn-client-<new-name>-halos`, and `pino-hotspot-<new-name>` in Bitwarden.
Authorize the new GitHub public key; give each VPN client its own private key
and address and add the matching peer on each server before deploying. Adapt
the hotspot interface in its Secure Note too. Server SSH items are currently
shared between desktops by design. Then use exactly the same provision/import/
application-install sequence. `pino restore artifacts /path/to/disk --dry-run`
shows that computer's local destinations; the external folder names remain unchanged. If local paths use a
separate filesystem, declare `pino.artifacts.<name>.requiredMount` for it.
Custom archive paths outside the declared `installs` directory require separate
handling; keep local archives inside that directory for the common import flow.

Personal projects, photos, REAPER projects, saves, activation state and recovery
documents are separate from installers. Restore those selectively with Meld.
For recovery documents, unlock a new local `~/Secrets` container and merge from
the unlocked encrypted external copy. A fresh empty container is not a restore.
Back up Steam's `compatdata/244210` and its Documents symlink target separately
if CM state/saves are needed. The re-1 partition command erases **all three**
selected disks; an existing `/data/fast` is not preserved by that command.

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
pino os profile list
pino os profile enable server-web
pino os profile disable torrent
pino os provision install
```

The profile catalog in `modules/profiles/default.nix` exposes user-facing roles;
small implementation modules are composed inside them. `pino os profile list`
shows their purpose.

Desktop profiles are:

- `workstation`: desktop applications, audio, and Bluetooth;
- `gnome`: GNOME desktop environment;
- `development`: Git, Codex, and VS Code;
- `latex`: full TeX Live with BibTeX/Biber and LaTeX Workshop when VS Code is enabled;
- `vpn-client`: named AmneziaWG connections and explicit WiFi sharing;
- `gaming-lite` / `gaming-full`;
- `music-lite` / `music-full`;
- `torrent`.

`assetto-corsa` (requires `gaming-full`) includes declarative Content Manager and ZIP mods for the
Steam-installed Assetto Corsa. It discovers the game in native Steam libraries,
including secondary SSD/HDD libraries. Steam still owns and installs the game.

```bash
pino os profile enable assetto-corsa
```

Enabling the profile rebuilds the system. Run `pino os populate` afterwards to
check prerequisites and set up the game. Repeat populate after completing any
requested manual actions; ordinary rebuilds preserve manual in-game changes.
Disabling this profile preserves Steam's game, mods and saves.
For diagnostics or partial restoration, the following commands remain available:

```bash
pino desktop assetto-corsa status
pino desktop assetto-corsa deps
pino desktop assetto-corsa apply
pino desktop assetto-corsa graphics
pino desktop assetto-corsa launch-options
```

Select Proton-GE in Steam and launch the original game once before setup. Close
Steam, the game and Content Manager before applying changes. `apply` restores
the declared launch options for app 244210 in each local Steam account, then verifies all ZIPs
and their SHA-256 digests before installing CM as the Steam launcher, then CSP
and additional mods in declaration order. Identical files are skipped; changed
files are backed up. `graphics` merges video, weather and `settings` INI files,
preserving resolution and undeclared settings. The re-1 training presets enable
automatic clutch, paddle shifting, moderate Neck FX, grass, smoke, ambient
occlusion and half-resolution local reflections. Existing wheel axes and paddle
buttons are preserved. It is a starting
preset, not a measured FPS guarantee. Run `apply` again if Steam Verify restores
the original launcher. Removing a mod declaration does not uninstall its files.

The re-1 bundle includes Moscow Raceway SMP 1.0.5, ACS NOLA Skidpad 1.5,
and Hakone Ohiradai v3 with its emissive shaders. Original downloads and provenance
remain in `installs/`; normalized ZIPs preserve game files. The rejected drift BMWs
and Project Touge are no longer declared, but their existing files are not deleted.

In CM's Quick Drive preset menu, open **Pino**. The folders cover car control on
NOLA (dry and light rain), Moscow Raceway, Magione/Imola, Highlands and Trento.
The roster uses installed Kunos cars with factory paddle/automatic transmissions:
Giulietta QV Launch Edition TCT, Z4 DCT, 4C TCT, Macan PDK and M235i Racing.
Macan is a heavier AWD comparison; M235i is a race car. They are not substitutes
for a low-power road hatchback. Factory ABS/TC are the default; the two Z4
car-control presets explicitly disable TC. Steering axes and paddle bindings
are preserved. `roadTyreCompounds` installs a small CSP app that selects road tyres
for Z4 and 4C once in the offline pre-drive menu, preserving other setup values
and subsequent manual changes. `Pino Drift` remains an alias
for the dry Z4/NOLA exercise.

`quickDrivePresets` declares named presets (including folders). Undeclared presets
are preserved. Launcher edits affect runtime files; reapplying the profile restores
declared settings and presets. Save personal variants under a different name.
`extendedPhysicsCars` enables CSP extended physics per car. Pure Static follows
preset weather; Rain FX is enabled without automatically replacing road tyres with
rain tyres. Base grip is fixed at 98% for repeatability; wet physics is applied by
CSP separately. Snow/ice simulation is not part of this configuration.

Setup also sets CM's **Disable windows transparency** preference for Wine,
the declared weather controller, and the selected cars' extended-physics flags.
Only those records are changed in `Values.data`; other records are preserved,
and this private file is never logged or backed up by the installer.
Set `disableWindowsTransparency = false` to leave that preference untouched.
The launch environment selects Wine's old PDB reader with
`WINE_DBGHELP_OLD_PDB=1`: the newer reader in GE-Proton11-6 omits symbols
required by CSP. Keep CSP's original `NAMES_WINE` mappings intact.

On `re-1`, archive declarations live in `hosts/re-1/assetto-corsa.nix`.
Back up `/data/fast/assetto-corsa`: `installs/` holds source archives (including
downloaded public archives), and `backups/` holds replaced files with a
`changes.jsonl` log. This directory is retained when disabling gaming-full.
`apply` and `deps` check `pino.profiles.assettoCorsa.winetricks` against the
game's `winetricks.log`, installing only missing components. The default fixes
are `dotnet48`, `d3dcompiler_47`, `d3dx11_43`, then `win10`. These match the
manual fix recorded on `re-1` and the bundled GE-Proton game fix. After a
runtime installation, Windows 10 mode is restored even if it was set before.
`status` reports any missing runtime fixes.
`deps` also copies Microsoft core fonts supplied by Nix and Segoe UI supplied
by the Steam game's `content/fonts/` into the Proton prefix,
including the Windows filenames for Verdana styles that CSP opens directly,
links Steam's account-discovery file without copying its contents, and sets
the native `dwrite` override for CSP. The first Proton-GE launch must create
the prefix; runtime fixes are then verified explicitly rather than assumed.
For saves, CM activation and settings, also back up the game's Steam
`steamapps/compatdata/244210` directory while the game is closed; Documents may
be a symlink into your home directory, so include its target in that backup.

Declare paid archives as **string paths**, never Nix path literals, to keep
their contents out of Git and the Nix store. For example:

```nix
pino.profiles.assettoCorsa.mods = [ {
  source = "/data/fast/assetto-corsa/installs/my-track.zip";
  sha256 = "<64-character hex digest from sha256sum>";
  stripPrefix = "release"; # optional enclosing directory inside the ZIP
  destination = "content/tracks"; # omit for archives laid out like the game root
} ];
```

Download CSP preview from x4fab and Pure from Peter Boese using your own
subscriptions. Check each release's compatibility and archive layout before
declaring it. No Patreon credentials or CM activation keys belong in Nix;
activate CM once in its interface using your key from Bitwarden.

`pino.profiles.assettoCorsa.launchOptions` defaults to
`PROTON_ENABLE_WAYLAND=0 WINE_DBGHELP_OLD_PDB=1 WINEDLLOVERRIDES="dwrite=n,b" %command%`.
This keeps CM's keyboard input working through XWayland. `apply` sets it
automatically; `launch-options` restores just this setting without reinstalling
mods. Log in to Steam once after reinstalling, then close Steam before running
either command. Other games and unrelated Steam settings are preserved; whole
Steam configuration files are never copied into the archive backup directory.
In CM select the game directory, set **Settings → Content Manager → Drive →
Game starter** to **AppID**, and disable window transparency if tooltips are
black. The `re-1` declaration selects Pure LCS and the `pureLinear` filter.
For changing weather in Quick Drive, select Pure and configure Pure Planner.

The `latex` profile is optional and independent of `development`. After rebuilding
once to register the new profile, enable it with:

```bash
pino os profile enable latex
```

It installs the full TeX Live distribution (several GB), including `latexmk`,
pdfLaTeX, XeLaTeX, LuaLaTeX, BibTeX and Biber. With `development` enabled,
VS Code also gets LaTeX Workshop, builds on save, and displays PDFs in a tab.
Use **LaTeX Workshop: Build with recipe** to select XeLaTeX or another engine;
the initial recipe uses pdfLaTeX, and subsequent builds reuse the last selected recipe.

Keep the thesis sources, bibliography, fonts and university template settings
in a separate project. For a XeLaTeX project, create a `.latexmkrc` containing
`$pdf_mode = 5;` and build from the project directory with `latexmk main.tex`.
In VS Code, select the **latexmk (latexmkrc)** recipe to use that same configuration.
`latexmk` runs BibTeX or Biber as required by the document; use the bibliography
style required by the university template.

The current host assignments are:

- `la1n`: workstation, GNOME, development, VPN client, light gaming, and light music;
- `re-1`: workstation, GNOME, development, VPN client, full gaming, Assetto Corsa, torrent, full music, Guitar Pro, and LaTeX;
- `mosk`: VPN server, static website, Galene, Xray/XHTTP and telemt/FakeTLS;
- `halos`: AmneziaWG, Xray/XHTTP, telemt and a static HTTPS landing page; no Galene.

`music-full` is enabled on `re-1`. Its installers live under
`/data/fast/music-full/installs`; `pino desktop music-full plugins apply` installs
the declared set and prepares Wine/yabridge. `plugins install <name|path>` runs
one installer; `plugins sync` runs yabridge separately.

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

`pino os profile disable <name>` rebuilds while preserving all application data.
Use `pino os profile purge <name>` to review and confirm deletion. Purge disables
the profile, rebuilds the system and then deletes that
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
is interrupted, rerun the same purge command to finish. A system rollback
does not restore deleted application data. Nix generations/store objects,
shared system logs and files outside the declared application directories are
not erased by this command.

Server profiles are:

- `server-vpn`: AmneziaWG server;
- `server-web`: static Caddy site;
- `server-galene`: lightweight calls, screen sharing, and streams;
- `server-xray`: VLESS over XHTTP, with public TLS terminated by Caddy;
- `server-telemt`: Telegram MTProxy in FakeTLS-only mode.

### Mosk on a small VPS

The current Mosk layout targets an x86_64 BIOS VPS with `/dev/vda`, 4 GB RAM and
20 GB storage. Partitioning creates a small BIOS boot partition and one ext4 root
covering the rest of the disk; there is no separate `/data` partition. This is a
fresh-install layout, not an in-place conversion of an older Mosk disk. The
installation erases the entire selected disk. The tested system closure is about
2 GiB; updates, build inputs, old generations and state need additional space.
Weekly GC removes generations older than 14 days, and journals are capped at
256 MiB. Avoid server-side call recording and large archives on this disk.

| Service | Public endpoint | Runtime secret |
| --- | --- | --- |
| SSH | TCP 22, `vincent@vpn.egrapa.com` | Public half of `pino-ssh-server-mosk` installed as authorized key |
| Website | `https://egrapa.com`, TCP 80/443 | Caddy obtains certificates automatically |
| Galene | `https://meet.egrapa.com/group/main/` | `pino-galene-mosk-main` → `/etc/pino/galene/main.json` |
| AmneziaWG 3.1 | UDP 585, normally `10.77.0.1/24` | `pino-vpn-server-mosk` → `/etc/pino/vpn/awg0.conf` |
| Xray/XHTTP | `https://egrapa.com/pino-xhttp`, TCP 443 | `pino-xray-mosk` → `/etc/pino/xray/users.json` |
| telemt/FakeTLS | `vpn.egrapa.com:2443`, TCP | `pino-telemt-mosk` → `/etc/pino/telemt/users.json` |

Halos uses `halos.egrapa.com` for SSH, HTTPS/Xray, AmneziaWG and telemt, with
the same ports as Mosk. Its profiles exclude Galene and its media/TURN ports.
Create a DNS-only A record pointing this name at the Halos public IPv4 address;
allow TCP 22, 80, 443, 2443 and UDP 585 in the provider firewall.
Only publish an AAAA record if the server has working IPv6.
Create the Bitwarden SSH Key `pino-ssh-server-halos` and install its public half
through the provider or bootstrap. Both desktops already provision that key to
`~/.ssh/halos`, and the `halos` SSH alias uses `vincent@halos.egrapa.com`.

```bash
# Create missing VPN/Xray/telemt credentials without changing existing records:
pino os provision prepare halos --bitwarden
# After installing NixOS and configuring SSH access:
pino os provision host halos
pino host halos server vpn mode set full
pino vpn add-client halos phone ~/halos-phone
```

The Halos secret records are `pino-vpn-server-halos`, `pino-xray-halos` and
`pino-telemt-halos`; proxy connection links are hidden fields in their notes.
The bootstrap selects `kexec-installer-small` for Halos: an ext4/VFAT installer
with XZ-compressed storage and a reduced module set for its QEMU/KVM hardware.
It fits the kernel's half-RAM kexec limit and boots with networking and SSH in a
1 GiB VM. The universal `kexec-installer` remains available for other hosts.
For Halos, Ubuntu also gets a temporary 1 GiB swap file and the bootstrap uses
legacy kexec to avoid exhausting RAM during loading. The swap file lives on the
old system disk and disappears during installation; a failed pre-install attempt
can leave it active until reboot or manual cleanup.
The VPN starts in `private` mode until explicitly changed. Both VPNs currently
use `10.77.0.0/24`; select one full-route desktop connection at a time.

Galene additionally needs TCP/UDP 1194 for TURN and UDP 49152–65535 for media.
Allow these ports both in NixOS and in any provider firewall. Point `egrapa.com`,
`meet.egrapa.com` and `vpn.egrapa.com` at the VPS public IPv4 address. Remove stale
AAAA records if the new VPS has no working IPv6. Use direct DNS for VPN/telemt;
an ordinary HTTP CDN proxy cannot carry their protocols. Telemt binds IPv4 only.
Website/Xray TLS issuance needs public DNS and access to ports 80/443. The FakeTLS
masking domain is `www.microsoft.com`, distinct from the actual proxy endpoint;
it must be reachable from Mosk.

On the new Ubuntu/Debian, install the **public** half of `pino-ssh-server-mosk`
using the provider's SSH-key option. The initial user needs root or passwordless
sudo. From the trusted desktop, after rebuilding Pino:

```bash
pino os provision install
pino os provision prepare mosk --bitwarden
# Substitute the actual initial user/IP; verify the provider's SSH fingerprint:
pino os install mosk root@203.0.113.10 ~/.ssh/mosk.pub
```

Use `ubuntu@…` or `debian@…` instead if appropriate. Bootstrap checks every Secure
Note declared by the selected profiles before changing the VPS, boots a NixOS
installer through kexec, and asks for `erase mosk` before partitioning `/dev/vda`.
It installs the exact pushed revision (including generated hardware updates),
then sends every declared note and restarts its services. This requires a clean
checkout on `origin/main`. If kexec is unavailable, boot a NixOS rescue image and
use `bootstrap rescue`. After reinstalling, verify the new SSH host fingerprint
through the provider console before updating your normal known_hosts entry.

Proxy notes contain `{"users": {"owner": "credential"}}`. For Xray, use a canonical
UUID; for telemt, a 32-character lowercase hex secret. The generator creates
independent random values and stores matching client URIs in hidden fields.
Import VLESS into an XHTTP-capable Xray client; support in the Amnezia app itself
is not assumed. Import the Telegram URI in Telegram's proxy settings. Telegram
proxying does not provide a private IP network; use AmneziaWG for that.

Only credentials are in these notes. Ports, routing and TLS paths are declared in
Nix. Systemd renders private configs below `/run/pino-xray` and `/run/pino-telemt`
from loaded credentials. Both services use dynamic unprivileged users. The
telemt control API is disabled; proxy payload logs and generated links are not
written to the journal. `logs` shows systemd lifecycle events. Neither proxy
starts until its credentials have been provisioned.

To add/revoke access, edit the appropriate `users` object in Bitwarden (distinct
credentials per named user), update that user's hidden URI, then provision the
note again. Preparation preserves existing notes and does not rotate credentials
or refresh existing URIs. When endpoints change, update the shared public manifest
and existing client URIs together.

```bash
pino os provision host mosk
# Or update a single service:
pino os provision send pino-xray-mosk mosk /etc/pino/xray/users.json xray.service
pino os provision send pino-telemt-mosk mosk /etc/pino/telemt/users.json telemt.service
pino host mosk server status
pino host mosk server xray status
pino host mosk server telemt status
pino host mosk server galene status
pino host mosk server vpn mode set private
pino host mosk os rebuild
```

`pino host` uses the local SSH alias and allocates a TTY when invoked in a terminal.
Ordinary `ssh mosk` remains available. Rebuild uses the server's checkout: pull
the desired revision there first.

VPN `private` mode allows the server and VPN peers but blocks Internet forwarding.
Create a separate device profile from a desktop with the `vpn-client` profile:

```bash
pino vpn add-client mosk phone ~/mosk-phone
```

This unlocks Bitwarden, creates or reuses `pino-vpn-client-phone-mosk`, adds its
public peer to `pino-vpn-server-mosk`, exports `mosk-phone.conf` into the new
private directory, and deploys the server note. It also creates or updates the
separate Secure Note `pino-vpn-client-phone-mosk-amnezia` containing an AmneziaVPN
`vpn://` link and exports that link as `mosk-phone.vpn`. Import the `.conf` in
AmneziaWG, or paste the link into AmneziaVPN. Both contain the same client private
key: keep both exports private. Existing clients get the link on their next
`add-client` run without rotating their keys.
New profiles route all IPv4 traffic (`AllowedIPs = 0.0.0.0/0`):
server mode `private` blocks IPv4 Internet, while `full` enables Internet and
the VPN network. IPv6 is not routed. Creating a client does not change the
server mode or the desktop's active VPN. Deployment restarts AWG, briefly interrupting
existing peers. Use one device name per device. The export must be outside Git
and must not already exist. To re-export the same client, choose a new directory;
keys are preserved. To replace a stale or private-only Bitwarden client profile,
pass `--force` and a new export directory. This preserves the device private key,
refreshes the server key and AWG settings, and keeps the client address when
available. Other server peers are preserved. Import/install the updated client
file afterwards. `--force` does not overwrite local files or rotate device keys.
If deployment fails after saving, retry the command with a new directory
(and `--force` if the server peer address still needs updating), then run `pino os provision host
mosk`. Remove the local export after importing and keep the Bitwarden note.
Both `add-client` and `remove-client` support `mosk` and `halos`; they do not
create Xray credentials. Halos client profiles use `halos.egrapa.com:585`.

To revoke a device and remove both client records:

```bash
pino vpn remove-client mosk phone
# For noninteractive use, explicitly confirm with --yes.
```

Removal asks for confirmation, removes only the peer identified by the client's
private key, saves and deploys the server note, then moves the link and client
config to Bitwarden trash. AWG restarts briefly during deployment. If deployment
or deletion fails, rerun the same removal command; the canonical client record
is kept until the last step so retries retain the peer identity. Local exports
and imported device profiles are not deleted, but the revoked peer cannot
connect. Restoring a Bitwarden trash item alone does not restore server access.

Use client `AllowedIPs = 10.77.0.0/24` (or your actual private subnet) to retain
ordinary Internet access through the client's local connection. `egress` enables
Internet only; `full` enables both. These are interface-wide IPv4 policies, not
per-peer roles. IPv6 VPN routing is not configured. Mode changes replace nftables
rules atomically. Private mode also blocks telemt through `awg0`; XHTTP rejects
private source addresses in every mode. Xray blocks private/link-local destinations,
including the VPN subnet and metadata addresses. A local reverse proxy placed in
front of Caddy would require revisiting the source-address policy. The website
and Galene remain public; their visibility is not controlled by VPN mode.

For offline integration checks, run `tests/check_server_runtime.py` under
`unshare -Urn`, passing the built Xray, telemt and Caddy binaries and generated
Caddyfile. It checks startup, website routing, real XHTTP forwarding and private
address restrictions using documentation IPs in an isolated network. Public
DNS/ACME, Telegram connectivity and remote AWG handshakes require post-deploy tests.

Galene is enabled on Mosk at `https://meet.egrapa.com/group/main/`. Store the
complete group definition in a Bitwarden Secure Note named
`pino-galene-mosk-main`, then provision it without exposing its contents:

```bash
pino os provision send pino-galene-mosk-main mosk \
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

Pino no longer manages a local recovery container. An existing
`~/.local/share/pino/secrets.luks` and its contents are left untouched; use standard
LUKS tools if you still need it. No container is created, mounted or deleted by
Pino. Never add recovery material or a Bitwarden export to Git.

All working secrets live in Bitwarden. On a new host, run:

```bash
pino os provision install
```

Pino prompts for CLI login on the first run and unlocks the vault on later
runs. There is no shell-session setup command to remember.

Store runtime payloads in uniquely named Secure Notes. VPN, hotspot and Galene
notes contain complete runtime files; Xray and telemt notes contain their `users`
JSON object, merged with public policy at startup. Names use
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
pino os provision install
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
pino os provision install pino-vpn-client-re-1-mosk /etc/amneziawg/mosk.conf
```

Or send it directly from Bitwarden to a server over SSH:

```bash
pino os provision send pino-vpn-server-mosk mosk \
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
on HTTPS; rerun `pino os provision install` after fixing the SSH key.

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

Reconnect and unlock the disk using GNOME Disks or standard LUKS tools.
Pino does not manage disk unlocking or provide a manual folder comparison UI.
Use the planned backup and restore commands below for declared data.

## Planned backups and personal datasets

Run as your normal user with an unlocked external disk. Each destination holds
one current copy; there is no dated retention or recovery of an overwritten
version. Keep the Git checkout separately too (including `.git` for offline
history). None of these commands backs up `/nix/store` or discovers personal
folders automatically.

```bash
pino backup artifacts /path/to/disk --dry-run
pino backup artifacts /path/to/disk
pino backup artifacts guitar-pro /path/to/disk
pino backup bitwarden /path/to/disk
pino backup datasets /path/to/disk
pino restore datasets documents /path/to/disk
```

Declare datasets explicitly in the host configuration, then rebuild. No personal
dataset is enabled by default. For example, inside a module accepting `config`:

```nix
pino.datasets = {
  documents.target = "${config.pino.user.home}/Documents";
  projects = {
    target = "/data/fast/projects";
    requiredMount = "/data/fast";
    exclude = [ "*/node_modules" "*/.venv" "*/build" ];
  };
};
```

Use directories that actually exist and names that identify their contents;
include the host name when two machines have different datasets. Data goes to
`pino/datasets/<name>/`. Exclusions match relative paths on both sides; an excluded
directory prunes its subtree. Symlinks, special files, overlapping roots and
unreadable directories are refused. Exclude intentional symlinks or declare their
real target separately. These are user-file copies, preserving file modes and
mtimes, not system backups preserving ownership, ACLs or extended attributes.

Dataset backup asks whether to update (keep destination-only files) or mirror
(list their deletion). `--mode update` or `--mode mirror` selects that explicitly.
Artifact backup defaults to update; mirror is opt-in. Missing sources abort a
backup, including mirror, before any copying. Restore/populate only add or update;
they never delete local extras. All conflicts require source/destination selection
before final confirmation. `--dry-run` never prompts or writes; with no explicit
mode it previews update. Empty directory creation/removal is included in the plan.

Bitwarden backup writes `pino/bitwarden/vault.encrypted.json`. It synchronizes the
vault and asks for a separate export password through the CLI's hidden prompt;
the password never appears in process arguments. It validates a portable
password-encrypted JSON export before atomically replacing the old file (0600).
Cancellation or an invalid export leaves the old backup intact. Save the export
password independently; restore by importing the file as Bitwarden JSON into
an account and entering that password. Normal populate reads the existing online
vault, not this recovery export.

**Scope:** the export contains active personal vault items. Attachments,
organization-owned items, trash, Sends and account/2FA recovery settings are
excluded; the command reports detected exclusion counts and asks you to accept
that scope. Back up those separately if used. This is not a complete account
backup. See the [Bitwarden CLI export documentation](https://bitwarden.com/help/cli/#export).

Server installation still uses `pino os install|rescue` from the desktop:
it installs and provisions in one flow. To retry only provisioning, run
`pino os provision host mosk`; on the server itself, `pino os populate` reads that
server's declared Bitwarden secrets. Reinstallation reuses existing server keys
and peer lists; it does not generate or rotate VPN/proxy credentials. With the
same endpoint and vault records, client profiles remain valid.

The new personal dataset copier does **not** back up privileged server state.
Preserve `/var/lib/galene` (including invitations/extra rooms), `/var/lib/pino/vpn`
(selected mode), and `/etc/ssh/ssh_host_*` separately with ownership intact before
erasing a server if those must survive. Otherwise SSH identity changes, VPN mode
returns to its configured default, and runtime Galene invitations are lost.
Bitwarden still restores the declared room and service credentials.

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
