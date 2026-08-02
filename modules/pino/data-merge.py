import datetime
import hashlib
import os
import shutil
import sys
from pathlib import Path


MTIME_TOLERANCE = 1.0


def files(root: Path) -> dict[Path, os.stat_result]:
    result = {}
    for directory, _, names in os.walk(root):
        directory_path = Path(directory)
        for name in names:
            path = directory_path / name
            if path.is_symlink():
                print(f"Skipping unsupported symbolic link: {path}", file=sys.stderr)
                continue
            result[path.relative_to(root)] = path.stat()
    return result


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def timestamp(value: float) -> str:
    return datetime.datetime.fromtimestamp(value).astimezone().strftime("%Y-%m-%d %H:%M:%S %z")


def copy_medium(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def keep_both(source: Path, destination: Path) -> Path:
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    candidate = destination.with_name(f"{destination.stem}.medium-{stamp}{destination.suffix}")
    counter = 1
    while candidate.exists():
        candidate = destination.with_name(
            f"{destination.stem}.medium-{stamp}-{counter}{destination.suffix}"
        )
        counter += 1
    copy_medium(source, candidate)
    return candidate


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: data-merge.py <medium-directory> <local-directory>", file=sys.stderr)
        return 2

    medium_root = Path(sys.argv[1])
    local_root = Path(sys.argv[2])
    medium = files(medium_root)
    local = files(local_root)
    differences = []

    for relative, medium_stat in sorted(medium.items()):
        local_stat = local.get(relative)
        if local_stat is None:
            differences.append((relative, "medium-only", medium_stat, None))
            continue
        same_time = abs(medium_stat.st_mtime - local_stat.st_mtime) <= MTIME_TOLERANCE
        if same_time and medium_stat.st_size == local_stat.st_size:
            continue
        if same_time:
            kind = "conflict"
        elif medium_stat.st_mtime > local_stat.st_mtime:
            kind = "medium-newer"
        else:
            kind = "local-newer"
        differences.append((relative, kind, medium_stat, local_stat))

    if not differences:
        print("No medium files need merging into local.")
        return 0

    counts = {kind: 0 for kind in ("medium-only", "medium-newer", "local-newer", "conflict")}
    for _, kind, _, _ in differences:
        counts[kind] += 1
    print("Merge plan (medium is read-only):")
    for kind, count in counts.items():
        print(f"  {kind:14} {count}")
    print("  local-only files are preserved and not shown")
    print()

    accept_suggestions = False
    copied = 0
    for relative, kind, medium_stat, local_stat in differences:
        source = medium_root / relative
        destination = local_root / relative
        suggestion = "m" if kind in ("medium-only", "medium-newer") else "l"

        if accept_suggestions:
            choice = suggestion
        else:
            print(relative)
            print(f"  medium: {timestamp(medium_stat.st_mtime)}, {medium_stat.st_size} bytes")
            if local_stat is None:
                print("  local:  missing")
            else:
                print(f"  local:  {timestamp(local_stat.st_mtime)}, {local_stat.st_size} bytes")
            if kind == "conflict" and digest(source) == digest(destination):
                print("  contents are identical")
                continue
            print(f"  status: {kind}; suggested: {'use medium' if suggestion == 'm' else 'keep local'}")
            prompt = "  [m] use medium  [l] keep local  [b] keep both  [s] skip  [a] accept suggestions for all: "
            choice = input(prompt).strip().lower() or suggestion

        if choice == "a":
            accept_suggestions = True
            choice = suggestion
        if choice == "m":
            copy_medium(source, destination)
            copied += 1
        elif choice == "b":
            copied_path = keep_both(source, destination)
            print(f"  copied as {copied_path.name}")
            copied += 1
        elif choice not in ("l", "s"):
            print("  unknown choice; skipped")

    print(f"Merge complete: {copied} medium file(s) copied locally; medium unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
