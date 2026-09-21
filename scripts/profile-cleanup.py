#!/usr/bin/env python3
"""Remove declared profile state, preserving artifacts and remaining owners."""

import argparse
import glob
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys


def contains(parent, child):
    return child == parent or parent in child.parents


def destination(value):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Cleanup requires an absolute path without '..': {path}")
    # Resolve parents, but unlink a final symlink instead of following it.
    return path.parent.resolve() / path.name


def plan(manifest, profile, remaining, config_dir):
    if profile not in manifest["profiles"] or not set(remaining) <= set(manifest["profiles"]):
        raise ValueError("Unknown profile in cleanup request")
    if profile in remaining:
        raise ValueError("Cannot clean an enabled profile")
    resources = manifest["resources"]
    selected = [r for r in resources if profile in r["owners"] and not set(remaining).intersection(r["owners"])]
    active_paths = [destination(p) for r in resources if set(remaining).intersection(r["owners"]) for p in r.get("paths", [])]
    keep = [destination(p) for p in manifest["keep"]]
    protected = [destination(p) for p in manifest["protected"] + [config_dir]]
    paths = list(dict.fromkeys(destination(p) for r in selected for p in r.get("paths", [])))
    for path in paths:
        if path == Path("/") or any(contains(path, p) for p in protected):
            raise ValueError(f"Refusing unsafe cleanup path: {path}")
        if any(contains(Path(p), path) for p in manifest.get("forbiddenTrees", [])):
            raise ValueError(f"Refusing system cleanup path: {path}")
        if any(contains(path, p) or contains(p, path) for p in active_paths):
            raise ValueError(f"Cleanup path overlaps a remaining profile: {path}")
        if any(contains(p, path) for p in keep):
            raise ValueError(f"Cleanup path is inside saved artifacts: {path}")
    return selected, paths, keep


def check_mounts(paths, keep):
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        value = line.split()[4]
        for escape, character in [(r"\040", " "), (r"\011", "\t"), (r"\012", "\n"), (r"\134", "\\")]:
            value = value.replace(escape, character)
        mount = Path(value)
        if any(contains(p, mount) for p in paths) and not any(contains(p, mount) for p in keep):
            raise ValueError(f"Unmount before removing profile data: {mount}")


def remove(path, keep):
    if any(contains(p, path) for p in keep):
        return
    if not path.exists() and not path.is_symlink():
        return
    nested = [p for p in keep if contains(path, p)]
    if nested:
        if path.is_symlink():
            raise ValueError(f"Cannot preserve artifacts through directory symlink: {path}")
        for child in path.iterdir():
            remove(child, nested)
        if not any(path.iterdir()):
            path.rmdir()
    elif path.is_symlink() or not path.is_dir():
        path.unlink()
    else:
        shutil.rmtree(path)


def user_command(manifest, account, command, extra_env=None, allowed_returncodes=(0,)):
    env = {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "XDG_CONFIG_HOME": manifest["configHome"],
        "XDG_DATA_HOME": manifest["dataHome"],
        "XDG_CACHE_HOME": manifest["cacheHome"],
        "XDG_RUNTIME_DIR": f"/run/user/{account.pw_uid}",
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{account.pw_uid}/bus",
        **(extra_env or {}),
    }
    args = [manifest["tools"]["env"], *(f"{k}={v}" for k, v in env.items()), *command]
    if os.getuid() != account.pw_uid:
        args = [manifest["tools"]["runuser"], "-u", account.pw_name, "--", *args]
    result = subprocess.run(args, stdout=subprocess.DEVNULL)
    if result.returncode not in allowed_returncodes:
        raise subprocess.CalledProcessError(result.returncode, args)


def stop_wine(manifest, account, prefix):
    command = [manifest["tools"]["timeout"], "30", manifest["tools"]["wineserver"]]
    env = {"WINEPREFIX": prefix}
    # -k returns 1 when there is no server. Still require -w to confirm exit;
    # timeouts, permission errors and other wait failures must block deletion.
    user_command(manifest, account, [*command, "-k"], env, allowed_returncodes=(0, 1))
    user_command(manifest, account, [*command, "-w"], env)


def check_running(resources, uid):
    # Linux comm is limited to 15 bytes for these ASCII executable names.
    names = {name[:15] for r in resources for name in r.get("processes", [])}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            name = (entry / "comm").read_text().strip()
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if name in names:
            raise ValueError(f"Close {name} before disabling this profile (PID {entry.name})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest")
    parser.add_argument("operation", choices=["check", "apply"])
    parser.add_argument("profile")
    parser.add_argument("config_dir")
    parser.add_argument("remaining", nargs="*")
    args = parser.parse_args()
    manifest = json.loads(Path(args.manifest).read_text())
    account = pwd.getpwnam(manifest["user"])
    for resource in manifest["resources"]:
        resource.setdefault("paths", []).extend(f"/run/user/{account.pw_uid}/{p}" for p in resource.get("runtimePaths", []))
        for pattern in resource.get("patterns", []):
            resource["paths"].extend(glob.glob(pattern))
    resources, paths, keep = plan(manifest, args.profile, args.remaining, args.config_dir)
    check_mounts(paths, keep)
    check_running(resources, account.pw_uid)
    if args.operation == "check":
        print("Disabling removes application data and settings:")
        for path in paths:
            print(f"  {path}")
        print("Saved install artifacts and data owned by remaining profiles are preserved.")
        return
    for resource in resources:
        for unit in resource.get("services", []):
            result = subprocess.run([manifest["tools"]["systemctl"], "is-active", "--quiet", unit])
            if result.returncode == 0:
                raise ValueError(f"Service is still active after rebuild: {unit}")
            if result.returncode not in (3, 4):
                raise ValueError(f"Could not verify that service is stopped: {unit}")
        if "vpnShare" in resource:
            share = resource["vpnShare"]
            marker = Path("/run/pino-vpn-share/ip_forward")
            if marker.is_file():
                previous = marker.read_text().strip()
                if previous not in ("0", "1"):
                    raise ValueError("Invalid saved VPN forwarding state")
                subprocess.run([manifest["tools"]["sysctl"], "-w", f"net.ipv4.ip_forward={previous}"], check=True, stdout=subprocess.DEVNULL)
            nmcli = manifest["tools"]["nmcli"]
            connection = subprocess.run([nmcli, "connection", "show", "id", share], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if connection.returncode == 0:
                subprocess.run([nmcli, "connection", "delete", "id", share], check=True, stdout=subprocess.DEVNULL)
            elif connection.returncode not in (10,):
                raise ValueError("Could not inspect the VPN hotspot connection")
            for table in ("pino_vpn_share", "pino_vpn_guard"):
                nft = manifest["tools"]["nft"]
                present = subprocess.run([nft, "list", "table", "inet", table], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if present.returncode == 0:
                    subprocess.run([nft, "delete", "table", "inet", table], check=True)
        for prefix in resource.get("winePrefixes", []):
            if Path(prefix).is_dir() and manifest["tools"].get("wineserver"):
                stop_wine(manifest, account, prefix)
        for key in resource.get("dconf", []):
            user_command(manifest, account, [manifest["tools"]["dbusRunSession"], "--", manifest["tools"]["dconf"], "reset", "-f", key])
    # Preflight above completes before any filesystem deletion.
    for path in paths:
        remove(path, keep)
    print(f"Removed declared state for {args.profile}.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Profile cleanup failed: {error}", file=sys.stderr)
        sys.exit(1)
