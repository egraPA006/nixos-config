#!/usr/bin/env python3
"""Populate an installed host using its declarative profile setup steps."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys


def execute(command):
    try:
        return subprocess.run(command, check=False).returncode
    except OSError:
        print("Could not start the declared command.", file=sys.stderr)
        return 1


def populate(config, disk=None, skip_secrets=False, runner=execute):
    results = []

    def record(name, status):
        results.append((name, status))

    if config["provision"]:
        if skip_secrets:
            record("Bitwarden", "skipped (--skip-secrets)")
        else:
            print("\nBitwarden: installing declared secrets", flush=True)
            record("Bitwarden", "ready" if runner(["pino", "os", "provision", "install"]) == 0 else "failed")
    if disk and config["artifacts"]:
        print("\nArtifacts: compare disk and local installers", flush=True)
        status = runner(["pino", "restore", "artifacts", str(disk)])
        record("Artifacts", "ready" if status == 0 else "pending" if status == 2 else "failed")

    for name, step in config["steps"].items():
        print(f"\n{name}", flush=True)
        mount = step.get("requiredMount")
        if mount and not os.path.ismount(mount):
            print(f"Mount {mount}, then run populate again.")
            record(name, "pending")
            continue
        if step.get("requiresSession") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            print("Log in to the graphical desktop and run populate from its terminal.")
            record(name, "pending")
            continue
        check = step.get("prerequisite")
        if check:
            status = runner([check])
            if status:
                record(name, "pending" if status == 2 else "failed")
                continue
        record(name, "ready" if runner(step["command"]) == 0 else "failed")

    print("\nPopulate results:")
    for name, status in results:
        print(f"  {name}: {status}")
    if any(status in ("pending", "failed") for _, status in results):
        print("Resolve the messages above, then run the same populate command again.")
    if any(status == "failed" for _, status in results):
        return 1
    return 2 if any(status == "pending" for _, status in results) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("disk", nargs="?", type=Path)
    parser.add_argument("--skip-secrets", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.manifest.read_text())
    if pwd.getpwuid(os.getuid()).pw_name != config["user"]:
        parser.error(f"Run as {config['user']}, without sudo; provisioning requests sudo when needed.")
    if args.disk and not args.disk.is_dir():
        parser.error("The external disk directory does not exist; mount/unlock it first.")
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "pino"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state / "populate.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another populate is running for this user.")
        return populate(config, args.disk, args.skip_secrets)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"populate: {error}", file=sys.stderr)
        sys.exit(1)
