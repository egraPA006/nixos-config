#!/usr/bin/env python3
"""Apply declared ZIP mods to a Steam-owned Assetto Corsa installation."""
import argparse
import configparser
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
import zlib


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def discover(override=None, home=None):
    if override:
        candidates = [Path(override)]
    else:
        home = home or Path.home()
        steam = home / ".local/share/Steam"
        if not steam.is_dir():
            steam = home / ".steam/steam"
        libraries = [steam]
        vdf = steam / "steamapps/libraryfolders.vdf"
        if vdf.exists():
            libraries += [Path(p.replace("\\\\", "\\")) for p in
                          re.findall(r'"path"\s+"([^"]+)"', vdf.read_text())]
        candidates = [p / "steamapps/common/assettocorsa" for p in libraries]
    games = {p.resolve() for p in candidates if (p / "acs.exe").is_file()}
    if len(games) != 1:
        raise ValueError("Install Assetto Corsa in Steam, or set assettoCorsa.gameDir to one installation.")
    game = games.pop()
    prefix = game.parent.parent / "compatdata/244210/pfx"
    return game, prefix


def relative(value):
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "\\" in value or ":" in value:
        raise ValueError(f"Unsafe relative path: {value}")
    return path


def destination(root, name):
    path = root
    for part in relative(name).parts:
        path /= part
        if path.is_symlink():
            raise ValueError(f"Refusing to overwrite through symlink: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"Destination is not a regular file: {path}")
    return path


def archive_file(spec, state):
    source = spec["source"]
    if source.startswith("https://"):
        path = state / "installs" / (spec["sha256"] + ".zip")
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=path.parent) as tmp:
                subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                                "--proto", "=https", "--proto-redir", "=https", "--retry", "2",
                                "--output", tmp.name, source], check=True)
                if digest(Path(tmp.name)) != spec["sha256"]:
                    raise ValueError("Downloaded archive checksum mismatch")
                shutil.copyfile(tmp.name, path)
    else:
        path = Path(source)
        if not path.is_absolute():
            raise ValueError("Local archive paths must be absolute")
    if digest(path) != spec["sha256"]:
        raise ValueError(f"Archive checksum mismatch: {path}")
    return path


def members(archive, spec, manager=False):
    prefix = relative(spec.get("stripPrefix", ""))
    target = relative(spec.get("destination", ""))
    result = []
    seen = set()
    for entry in archive.infolist():
        path = relative(entry.filename)
        if stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError(f"Archive contains symlink: {entry.filename}")
        if entry.is_dir() or not path.is_relative_to(prefix):
            continue
        path = path.relative_to(prefix)
        if manager:
            if str(path) != "Content Manager.exe":
                continue
            path = PurePosixPath("AssettoCorsa.exe")
        name = str(target / path)
        if name.casefold() in seen:
            raise ValueError(f"Duplicate archive destination: {name}")
        seen.add(name.casefold())
        result.append((entry, name))
    if not result:
        raise ValueError("No matching files in archive; check stripPrefix")
    return result


class Writer:
    def __init__(self, state):
        self.state = state
        self.backup = None
        self.changed = 0

    def write(self, root, name, stream):
        path = destination(root, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
            temporary = Path(tmp.name)
            try:
                shutil.copyfileobj(stream, tmp)
                tmp.flush()
                if path.exists() and digest(path) == digest(temporary):
                    return
                if self.backup is None:
                    folder = self.state / "backups"
                    folder.mkdir(parents=True, exist_ok=True)
                    self.backup = Path(tempfile.mkdtemp(prefix="apply-", dir=folder))
                # Mirror absolute paths so backups from game and Documents cannot collide.
                saved = self.backup / str(path).lstrip("/")
                if path.exists() and not saved.exists():
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, saved)
                with (self.backup / "changes.jsonl").open("a") as log:
                    log.write(json.dumps({"path": str(path), "existed": path.exists()}) + "\n")
                os.chmod(temporary, 0o644)
                os.replace(temporary, path)
                self.changed += 1
            finally:
                temporary.unlink(missing_ok=True)


def apply(config, game, state, writer):
    specs = [(config["contentManager"], True)]
    if config["csp"]:
        specs.append((config["csp"], False))
    specs.extend((spec, False) for spec in config["mods"])
    # Validate every archive and destination before changing game files.
    plans = []
    for spec, manager in specs:
        path = archive_file(spec, state)
        with zipfile.ZipFile(path) as archive:
            items = members(archive, spec, manager)
            for _, name in items:
                destination(game, name)
            bad = archive.testzip()
            if bad:
                raise ValueError(f"Corrupt archive member: {bad}")
        plans.append((path, items))
    for path, items in plans:
        print(f"Applying {path.name}", flush=True)
        with zipfile.ZipFile(path) as archive:
            for entry, name in items:
                with archive.open(entry) as stream:
                    writer.write(game, name, stream)


def merge_ini(root, name, settings, writer):
    path = destination(root, name)
    parser = configparser.ConfigParser(interpolation=None, inline_comment_prefixes=(";",))
    parser.optionxform = str
    parser.read(path)
    for section, values in settings.items():
        if not parser.has_section(section):
            parser.add_section(section)
        for key, value in values.items():
            parser.set(section, key, value)
    output = io.StringIO()
    parser.write(output, space_around_delimiters=False)
    writer.write(root, name, io.BytesIO(output.getvalue().encode()))


def decode_cm_storage(data):
    """CM Storage.cs supports plain v2, raw Deflate (0) and LZF (11)."""
    if data.startswith(b"\x0b"):
        output = bytearray()
        index = 1
        try:
            while index < len(data):
                control = data[index]
                index += 1
                if control < 32:
                    count = control + 1
                    if index + count > len(data):
                        raise ValueError("Truncated CM storage")
                    output.extend(data[index:index + count])
                    index += count
                else:
                    count = control >> 5
                    offset = len(output) - ((control & 31) << 8) - 1
                    if count == 7:
                        count += data[index]
                        index += 1
                    offset -= data[index]
                    index += 1
                    if offset < 0:
                        raise ValueError("Invalid CM storage reference")
                    for _ in range(count + 2):
                        output.append(output[offset])
                        offset += 1
                if len(output) > 32 * 1024 * 1024:
                    raise ValueError("CM storage exceeds size limit")
        except IndexError:
            raise ValueError("Truncated CM storage") from None
        return bytes(output)
    if data.startswith(b"version: "):
        return data
    try:
        decoder = zlib.decompressobj(-15)
        output = decoder.decompress(data[1:] if data.startswith(b"\0") else data, 32 * 1024 * 1024)
        if not decoder.eof:
            raise ValueError("Invalid or oversized CM storage")
        return output
    except zlib.error:
        raise ValueError("Unsupported CM storage compression") from None


def cm_enable_settings(path, keys, weather_controller=None):
    # This file can contain encrypted credentials: no Writer backup or logging.
    original = path.read_bytes() if path.exists() else b"version: 2"
    decoded = decode_cm_storage(original)
    lines = decoded.split(b"\n")
    if lines[0].rstrip(b"\r") != b"version: 2":
        raise ValueError("Unsupported CM storage version; file left unchanged")
    preferences = {}
    for name in keys:
        if not re.fullmatch(r"appearance_disallowTransparency|CarObject:[a-zA-Z0-9_-]+:UseExtendedPhysics", name):
            raise ValueError("Unsupported CM preference")
        preferences[name] = b"1" if name.startswith("CarObject:") else b"True"
    if weather_controller is not None:
        if not re.fullmatch(r"[a-zA-Z0-9_ -]+", weather_controller):
            raise ValueError("Invalid weather controller ID")
        preferences[".wfx-ctr-base"] = weather_controller.encode()
    changed = False
    for name, value in preferences.items():
        key = name.encode() + b"\t"
        matches = [i for i, line in enumerate(lines) if line.startswith(key)]
        if len(matches) > 1:
            raise ValueError("Duplicate CM setting; file left unchanged")
        if matches:
            index = matches[0]
            current = lines[index][len(key):].rstrip(b"\r")
            if current == value or (name != ".wfx-ctr-base" and current.lower() in (b"true", b"1")):
                continue
            lines[index] = key + value + (b"\r" if lines[index].endswith(b"\r") else b"")
        else:
            lines.append(key + value)
        changed = True
    if not changed:
        return
    encoder = zlib.compressobj(wbits=-15)
    updated = b"\0" + encoder.compress(b"\n".join(lines)) + encoder.flush()
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        temporary = Path(tmp.name)
        try:
            tmp.write(updated)
            tmp.flush()
            os.chmod(temporary, stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600)
            if path.exists() and path.read_bytes() != original:
                raise ValueError("CM settings changed during setup; close CM and retry")
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def cm_disable_transparency(path):
    cm_enable_settings(path, ["appearance_disallowTransparency"])


def quick_drive_presets(config, prefix, writer):
    presets = dict(config.get("quickDrivePresets", {}))
    if config.get("quickDrivePreset") is not None:
        presets.setdefault("Pino Drift", config["quickDrivePreset"])
    cm = prefix / "drive_c/users/steamuser/AppData/Local/AcTools Content Manager"
    plans = []
    seen = set()
    for name, preset in presets.items():
        relative(name)
        if not name or name.endswith("/") or name.casefold() in seen:
            raise ValueError(f"Invalid or duplicate preset name: {name}")
        seen.add(name.casefold())
        target = f"Presets/Quick Drive/{name}.cmpreset"
        destination(cm, target)
        plans.append((target, json.dumps(preset, indent=2).encode() + b"\n"))
    for target, data in plans:
        writer.write(cm, target, io.BytesIO(data))


def road_tyres(config, game, writer):
    compounds = config.get("roadTyreCompounds", {})
    if not compounds and (game is None or not (game / "apps/lua/PinoRoadTyres/manifest.ini").exists()):
        return
    entries = []
    for car, compound in compounds.items():
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", car) or type(compound) is not int or compound < 0:
            raise ValueError("Invalid road tyre compound")
        entries.append(f"  ['{car}'] = {compound},")
    if game is None:
        raise ValueError("Game directory required for road tyre selection")
    manifest = "[ABOUT]\nNAME=Pino Road Tyres\nAUTHOR=Pino\nVERSION=1\nDESCRIPTION=Select declared road tyres once before offline driving\n\n[CORE]\nLAZY=NONE\n"
    script = "local compounds = {\n" + "\n".join(entries) + "\n}\n" + """
local done = false
local elapsed = 0
function script.update(dt)
  if done then return end
  elapsed = elapsed + dt
  local sim = ac.getSim()
  local compound = compounds[ac.getCarID(0)]
  if sim.isOnlineRace or compound == nil or elapsed > 30 then
    done = true
    return
  end
  if sim.isInMainMenu then
    local setup = ac.INIConfig.parse(ac.stringifyCurrentSetup())
    setup:set('TYRES', 'VALUE', compound)
    if ac.loadSetup(setup:serialize()) then
      ac.log('Pino Road Tyres: selected compound ' .. compound)
      done = true
    end
  end
end
"""
    for name, data in {"manifest.ini": manifest, "PinoRoadTyres.lua": script}.items():
        writer.write(game, "apps/lua/PinoRoadTyres/" + name, io.BytesIO(data.encode()))


def graphics(config, prefix, writer, game=None):
    root = (prefix / "drive_c/users/steamuser/Documents/Assetto Corsa/cfg").resolve()
    if not (root / "video.ini").is_file():
        raise ValueError("Launch the original game once to create video.ini first")
    merge_ini(root, "video.ini", config["videoSettings"], writer)
    if config.get("weatherSettings"):
        merge_ini(root, "extension/weather_fx.ini", config["weatherSettings"], writer)
    for name, settings in config.get("settings", {}).items():
        merge_ini(root, name, settings, writer)
    road_tyres(config, game, writer)
    quick_drive_presets(config, prefix, writer)
    preferences = [f"CarObject:{car}:UseExtendedPhysics" for car in config.get("extendedPhysicsCars", [])]
    if config.get("disableWindowsTransparency", False):
        preferences.append("appearance_disallowTransparency")
    controller = config.get("weatherSettings", {}).get("BASIC", {}).get("CONTROLLER")
    if preferences or controller is not None:
        cm_enable_settings(prefix / "drive_c/users/steamuser/AppData/Local/AcTools Content Manager/Values.data",
                           preferences, controller)
        print("CM: declared preferences applied")


def link_steam_users(prefix, home=None):
    home = home or Path.home()
    sources = [home / ".local/share/Steam/config/loginusers.vdf",
               home / ".steam/steam/config/loginusers.vdf"]
    target = prefix / "drive_c/Program Files (x86)/Steam/config/loginusers.vdf"
    if target.exists() or target.is_symlink():
        return
    for source in sources:
        if source.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            # CM needs Steam account discovery. Link without reading or copying
            # account data into the repository, manifest or backups.
            target.symlink_to(source)
            return
    raise ValueError("Log in to native Steam first: loginusers.vdf was not found")


def missing_runtimes(prefix, declared):
    log = prefix / "winetricks.log"
    installed = {line.split()[0] for line in log.read_text().splitlines() if line.strip()} if log.exists() else set()
    return [verb for verb in declared if verb not in installed]


def install_runtimes(prefix, declared):
    missing = missing_runtimes(prefix, declared)
    if not missing:
        print("Declared .NET/DirectX runtime fixes already installed")
        return
    # dotnet48 can change the Windows version even if win10 was applied before.
    if "win10" in declared:
        missing = [verb for verb in missing if verb != "win10"] + ["win10"]
    subprocess.run(["protontricks", "--no-background-wineserver", "244210", "-q", *missing], check=True)
    if missing_runtimes(prefix, declared):
        raise ValueError("Runtime installation did not record all declared components; check protontricks output")


def steam_launch_options(text, value):
    """Change one VDF leaf, preserving all other text, comments and escaping."""
    tokens = []
    token_re = re.compile(r'\s+|//[^\n]*|"(?:\\.|[^"\\])*"|[{}]')
    pos = 0
    while pos < len(text):
        match = token_re.match(text, pos)
        if not match:
            raise ValueError("Unsupported Steam VDF syntax; file left unchanged")
        token = match.group()
        if not token.isspace() and not token.startswith("//"):
            tokens.append((token, match.start(), match.end()))
        pos = match.end()
    index = 0

    def block(nested=False):
        nonlocal index
        entries = {}
        while index < len(tokens):
            raw, start, end = tokens[index]
            index += 1
            if raw == "}":
                if not nested:
                    raise ValueError("Unexpected Steam VDF closing brace")
                return entries, start
            if not raw.startswith('"') or index == len(tokens):
                raise ValueError("Invalid Steam VDF entry")
            key = raw[1:-1].casefold()
            if key in entries:
                raise ValueError("Duplicate Steam VDF key; file left unchanged")
            raw, start, end = tokens[index]
            index += 1
            if raw == "{":
                children, closing = block(True)
                entries[key] = (children, closing, closing)
            elif raw.startswith('"'):
                entries[key] = (None, start, end)
            else:
                raise ValueError("Invalid Steam VDF value")
        if nested:
            raise ValueError("Unclosed Steam VDF block")
        return entries, len(text)

    entries, _ = block()
    path = ["userlocalconfigstore", "software", "valve", "steam", "apps", "244210", "launchoptions"]
    encoded = '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
    newline = "\r\n" if "\r\n" in text else "\n"
    closing = len(text)
    for depth, key in enumerate(path):
        if key not in entries:
            addition = '"LaunchOptions"\t\t' + encoded
            for parent in reversed(path[depth:-1]):
                addition = '"' + parent + '"' + newline + "{" + newline + addition + newline + "}"
            return text[:closing] + newline + addition + newline + text[closing:]
        children, start, end = entries[key]
        if depth == len(path) - 1:
            if children is not None:
                raise ValueError("Steam LaunchOptions is not a string")
            # Steam uses backslash escaping for quotes and backslashes.
            current = re.sub(r'\\([\\"])', r'\1', text[start + 1:end - 1])
            if current == value:
                return text
            return text[:start] + encoded + text[end:]
        if children is None:
            raise ValueError("Steam configuration path is not a block")
        entries, closing = children, start
    return text


def configure_steam(value, home=None):
    home = home or Path.home()
    roots = [home / ".local/share/Steam", home / ".steam/steam"]
    paths = sorted({p.resolve() for root in roots for p in root.glob("userdata/*/config/localconfig.vdf")})
    if not paths:
        raise ValueError("Log in to Steam once, then close it and run launch-options again")
    changes = []
    for path in paths:
        original = path.read_bytes()
        updated = steam_launch_options(original.decode("utf-8"), value).encode("utf-8")
        if updated != original:
            changes.append((path, original, updated))
    if changes:
        running = subprocess.run(["pgrep", "-x", "steam|steamwebhelper"], stdout=subprocess.DEVNULL)
        if running.returncode != 1:
            raise ValueError("Close Steam completely, then run launch-options or apply again")
    for path, original, updated in changes:
        # Do not back up or log whole Steam configs: they can contain private data.
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
            temporary = Path(tmp.name)
            try:
                tmp.write(updated)
                tmp.flush()
                os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
                if path.read_bytes() != original:
                    raise ValueError("Steam config changed during setup; retry with Steam closed")
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)
    print(f"Steam launch options: {len(changes)} account(s) updated")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("action", choices=["status", "setup", "apply", "deps", "graphics", "launch-options"])
    args = parser.parse_args()
    config = json.loads(args.manifest.read_text())
    if args.action == "launch-options":
        configure_steam(config["launchOptions"])
        return
    game, prefix = discover(config["gameDir"])
    print(f"Game: {game}\nProton prefix: {prefix}")
    if args.action == "status":
        print(f"Archives and backups: {config['stateDir']}")
        print(f"CSP: {config['csp']['source'] if config['csp'] else 'not declared'}")
        print(f"Additional mods: {len(config['mods'])}")
        print("Missing runtime fixes: " + (", ".join(missing_runtimes(prefix, config["winetricks"])) or "none"))
        return
    if not (prefix / "system.reg").is_file():
        raise ValueError("Select Proton-GE in Steam, launch the game once and close it first")
    # CSP renames the running game's main thread (and Linux process comm).
    running = subprocess.run(["pgrep", "-x", "AssettoCorsa.ex|acs.exe|acs_x86.exe|AC: ?main thread|Content Manager"],
                             stdout=subprocess.DEVNULL)
    if running.returncode == 0:
        raise ValueError("Close Assetto Corsa and Content Manager first")
    state = Path(config["stateDir"])
    state.mkdir(parents=True, exist_ok=True)
    with (state / "setup.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        writer = Writer(state)
        try:
            if args.action in ("apply", "setup"):
                configure_steam(config["launchOptions"])
                install_runtimes(prefix, config["winetricks"])
                apply(config, game, state, writer)
            if args.action in ("graphics", "setup"):
                graphics(config, prefix, writer, game)
            if args.action in ("deps", "setup"):
                install_runtimes(prefix, config["winetricks"])
                link_steam_users(prefix)
                # Fonts are pinned Nix assets: no Winetricks network installer or
                # fragile Wine cmd.exe environment probing is needed here.
                fonts = list(Path(config["fontsDir"]).glob("*.ttf"))
                if not fonts:
                    raise ValueError("No core fonts found in the declared font package")
                # CSP also opens Segoe UI directly in Windows/Fonts. It is not
                # part of corefonts, but Steam already ships it with the game.
                game_fonts = game / "content/fonts"
                if not (game_fonts / "segoeui.ttf").is_file():
                    raise ValueError("Missing game font content/fonts/segoeui.ttf; verify Assetto Corsa in Steam")
                fonts.extend(sorted(game_fonts.glob("segoeui*.ttf")))
                for font in fonts:
                    with font.open("rb") as stream:
                        writer.write(prefix, "drive_c/windows/Fonts/" + font.name, stream)
                # Nix renames these files; CSP opens their Windows filenames
                # directly instead of resolving the installed font family.
                for source, target in {
                    "Verdana_Bold.ttf": "verdanab.ttf",
                    "Verdana_Italic.ttf": "verdanai.ttf",
                    "Verdana_Bold_Italic.ttf": "verdanaz.ttf",
                }.items():
                    with (Path(config["fontsDir"]) / source).open("rb") as stream:
                        writer.write(prefix, "drive_c/windows/Fonts/" + target, stream)
                subprocess.run(["protontricks", "-c",
                                'wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" '
                                '/v dwrite /t REG_SZ /d native,builtin /f', "244210"], check=True)
        finally:
            print(f"Changed files: {writer.changed}")
            if writer.backup:
                print(f"Backups and change log: {writer.backup}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"assetto-corsa: {error}", file=sys.stderr)
        sys.exit(1)
