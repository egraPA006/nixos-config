#!/usr/bin/env python3
"""Import installer folders without overwriting existing local artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").digest()


def checked(path):
    path = Path(path).absolute()
    if ".." in path.parts:
        raise ValueError(f"Parent traversal is not allowed: {path}")
    for part in [*reversed(path.parents), path]:
        if part.is_symlink():
            raise ValueError(f"Symlinks are not supported: {part}")
        if part.exists() and part != path and not part.is_dir():
            raise ValueError(f"Not a directory: {part}")
    return path


def plan(manifest, source):
    source = checked(source)
    if not source.is_dir():
        raise ValueError(f"External artifacts directory is missing: {source}")
    files = []
    destinations = set()
    for name, spec in sorted(manifest.items()):
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", name):
            raise ValueError("Invalid artifact folder name")
        if not Path(spec["target"]).is_absolute():
            raise ValueError("Artifact targets must be absolute")
        target = checked(spec["target"])
        mount = spec.get("requiredMount")
        if mount and not os.path.ismount(mount):
            raise ValueError(f"Required filesystem is not mounted: {mount}")
        folder = checked(source / name)
        if not folder.is_dir():
            raise ValueError(f"Missing external folder: {folder}")
        if target.is_relative_to(source) or source.is_relative_to(target):
            raise ValueError("Source and destination must not overlap")
        if target.exists() and not target.is_dir():
            raise ValueError(f"Not a directory: {target}")
        for entry in sorted(folder.rglob("*")):
            checked(entry)
            local = checked(target / entry.relative_to(folder))
            if entry.is_dir():
                if local.exists() and not local.is_dir():
                    raise ValueError(f"Directory conflicts with existing file: {local}")
                continue
            if not entry.is_file():
                raise ValueError(f"Not a regular file: {entry}")
            if local in destinations:
                raise ValueError(f"Overlapping artifact destinations: {local}")
            destinations.add(local)
            checksum = digest(entry)
            if local.exists():
                if not local.is_file() or digest(local) != checksum:
                    raise ValueError(f"Different local artifact already exists: {local}")
                continue
            files.append((entry, local, checksum))
    return files


def copy_files(files):
    for source, target, checksum in files:
        checked(source)
        checked(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        # Publish each complete file atomically without replacing a concurrent write.
        with tempfile.NamedTemporaryFile(dir=target.parent) as temporary:
            with source.open("rb") as stream:
                shutil.copyfileobj(stream, temporary)
            temporary.flush()
            if digest(Path(temporary.name)) != checksum:
                raise ValueError(f"External artifact changed during import: {source}")
            os.chmod(temporary.name, 0o600)
            os.link(temporary.name, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    importer = commands.add_parser("import")
    importer.add_argument("source", type=Path)
    importer.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.command == "list":
        for name, spec in sorted(manifest.items()):
            print(f"{name}/ -> {spec['target']}")
        return
    if os.geteuid() == 0:
        raise ValueError("Run as the desktop user, without sudo")
    files = plan(manifest, args.source)
    print(f"Checked {len(manifest)} folder(s); {len(files)} new file(s)", flush=True)
    if not args.dry_run:
        copy_files(files)
        print("Import complete. Run the profile's installation command next.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"artifacts: {error}", file=sys.stderr)
        sys.exit(1)
