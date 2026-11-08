#!/usr/bin/env python3
"""Plan and confirm single-copy artifact and dataset transfers."""
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile


def checked(value):
    path = Path(value).absolute()
    if '..' in path.parts:
        raise ValueError(f'Parent traversal is not allowed: {path}')
    for parent in [*reversed(path.parents), path]:
        if parent.is_symlink():
            raise ValueError(f'Symlinks are not supported: {parent}')
        if parent.exists() and parent != path and not parent.is_dir():
            raise ValueError(f'Not a directory: {parent}')
    return path


def fingerprint(path):
    checked(path)
    if not path.exists():
        return None
    info = path.stat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f'Not a regular file: {path}')
    with path.open('rb') as stream:
        checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
    return (checksum, info.st_size, info.st_mtime_ns, stat.S_IMODE(info.st_mode))


def inventory(root, excludes):
    checked(root)
    if not root.exists():
        return {}, set()
    if not root.is_dir():
        raise ValueError(f'Not a directory: {root}')
    files, directories = {}, set()

    def unreadable(error):
        # An incomplete source listing must never become a mirror deletion plan.
        raise error

    for parent, names, filenames in os.walk(root, followlinks=False, onerror=unreadable):
        for name in list(names) + filenames:
            path = Path(parent) / name
            relative = path.relative_to(root).as_posix()
            if any(fnmatch.fnmatchcase(relative, pattern) for pattern in excludes):
                if name in names:
                    names.remove(name)
                continue
            checked(path)
            if path.is_dir():
                directories.add(relative)
            else:
                files[relative] = fingerprint(path)
    return files, directories


def plan(manifest, disk, operation, name=None, mode='update', allow_missing=False):
    disk = checked(disk)
    if not disk.is_dir():
        raise ValueError(f'External disk directory does not exist: {disk}')
    kind = manifest['kind']
    if kind not in ('artifacts', 'datasets'):
        raise ValueError('Invalid manifest kind')
    entries = manifest['entries']
    if name is not None:
        if name not in entries:
            raise ValueError(f'Unknown {kind} name: {name}')
        entries = {name: entries[name]}
    pairs, roots, missing = [], [], []
    for label, spec in sorted(entries.items()):
        if not re.fullmatch(r'[a-zA-Z0-9_-]+', label):
            raise ValueError('Invalid entry name')
        if not Path(spec['target']).is_absolute():
            raise ValueError('Local targets must be absolute')
        local = checked(spec['target'])
        mount = spec.get('requiredMount')
        if mount and not os.path.ismount(checked(mount)):
            raise ValueError(f'Required filesystem is not mounted: {mount}')
        external = checked(disk / 'pino' / kind / label)
        source, target = (local, external) if operation == 'backup' else (external, local)
        for root in (source, target):
            for previous in roots:
                if root.is_relative_to(previous) or previous.is_relative_to(root):
                    raise ValueError('Sync roots must not overlap')
            roots.append(root)
        if not source.is_dir():
            if not allow_missing:
                raise ValueError(f'Source directory is missing: {source}')
            missing.append(str(source))
            continue
        excludes = spec.get('exclude', [])
        src, src_dirs = inventory(source, excludes)
        dst, dst_dirs = inventory(target, excludes)
        if src.keys() & dst_dirs or dst.keys() & src_dirs:
            raise ValueError(f'File/directory conflict in {label}')
        actions = []
        for relative, state in sorted(src.items()):
            old = dst.get(relative)
            if old is None or old[0] != state[0]:
                actions.append({'action': 'add' if old is None else 'replace',
                                'source': source / relative, 'target': target / relative,
                                'before': old, 'after': state})
        for relative in sorted(dst.keys() - src.keys()):
            actions.append({'action': 'delete' if mode == 'mirror' else 'keep',
                            'source': None, 'target': target / relative,
                            'before': dst[relative], 'after': None})
        pairs.append({'source': source, 'target': target, 'exclude': excludes,
                      'requiredMount': mount,
                      'src': (src, src_dirs), 'dst': (dst, dst_dirs), 'actions': actions,
                      'remove_dirs': sorted(dst_dirs - src_dirs, key=lambda p: (-p.count('/'), p)) if mode == 'mirror' else []})
    return pairs, missing


def apply(pairs):
    # Revalidate the entire plan before modifying any destination.
    for pair in pairs:
        mount = pair.get('requiredMount')
        if mount and not os.path.ismount(checked(mount)):
            raise ValueError(f'Required filesystem is no longer mounted: {mount}')
        if not pair['source'].is_dir() or inventory(pair['source'], pair['exclude']) != pair['src']:
            raise ValueError('Source changed since the plan; run again')
        if inventory(pair['target'], pair['exclude']) != pair['dst']:
            raise ValueError('Destination changed since the plan; run again')
    for pair in pairs:
        target = checked(pair['target'])
        target.mkdir(parents=True, exist_ok=True, mode=0o700)
        for relative in sorted(pair['src'][1]):
            checked(target / relative).mkdir(parents=True, exist_ok=True, mode=0o700)
        for action in pair['actions']:
            if action['action'] == 'keep':
                continue
            dest = checked(action['target'])
            if fingerprint(dest) != action['before']:
                raise ValueError(f'Destination changed since the plan: {dest}')
            if action['action'] == 'delete':
                dest.unlink()
                continue
            source = checked(action['source'])
            dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            fd, temporary = tempfile.mkstemp(dir=dest.parent)
            try:
                with os.fdopen(fd, 'wb') as output, source.open('rb') as stream:
                    shutil.copyfileobj(stream, output)
                    output.flush()
                    os.fsync(output.fileno())
                if fingerprint(Path(temporary))[0] != action['after'][0]:
                    raise ValueError(f'Source changed during copy: {source}')
                os.chmod(temporary, action['after'][3] & 0o777)
                os.utime(temporary, ns=(action['after'][2], action['after'][2]))
                if fingerprint(dest) != action['before']:
                    raise ValueError(f'Destination changed during copy: {dest}')
                if action['before'] is None:
                    os.link(temporary, dest)
                else:
                    os.replace(temporary, dest)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)

        for relative in pair['remove_dirs']:
            directory = checked(target / relative)
            # Excluded descendants must survive mirror operations.
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('operation', choices=('backup', 'restore'))
    parser.add_argument('arguments', nargs='+', help='[name] external-disk-directory')
    parser.add_argument('--mode', choices=('update', 'mirror'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--allow-missing', action='store_true')
    args = parser.parse_args()
    if len(args.arguments) not in (1, 2):
        parser.error('Expected [name] external-disk-directory')
    if os.geteuid() == 0:
        raise ValueError('Run as the normal user, without sudo')
    manifest = json.loads(args.manifest.read_text())
    if not manifest['entries']:
        raise ValueError(f"No {manifest['kind']} declared for this host; configure pino.{manifest['kind']} first")
    mode = args.mode
    if mode is None and manifest['kind'] == 'datasets' and args.operation == 'backup' and not args.dry_run:
        answer = input('Backup mode: [u]pdate (keep destination-only files) / [m]irror (delete them) [u]: ').strip().lower()
        if answer not in ('', 'u', 'update', 'm', 'mirror'):
            raise ValueError('Unknown backup mode')
        mode = 'mirror' if answer in ('m', 'mirror') else 'update'
    mode = mode or 'update'
    if mode == 'mirror' and args.operation == 'restore':
        raise ValueError('Restore only adds or updates files; mirror deletion is for backups')
    pairs, missing = plan(manifest, args.arguments[-1], args.operation,
                          args.arguments[0] if len(args.arguments) == 2 else None,
                          mode, args.allow_missing)
    for folder in missing:
        print(f'MISSING (skipped): {folder}')
    for pair in pairs:
        print(f"{pair['source']} -> {pair['target']}")
        for relative in pair['remove_dirs']:
            print(f'  REMOVE DIRECTORY IF EMPTY: {pair["target"] / relative}')
        for action in pair['actions']:
            print(f"  {action['action'].upper()}: {action['target']}")
            if action['action'] == 'replace':
                for label, state in (('source', action['after']), ('destination', action['before'])):
                    print(f'    {label}: {state[1]} bytes, mtime_ns={state[2]}, sha256={state[0]}')
                if not args.dry_run:
                    answer = input('Keep [s]ource or [d]estination? [d]: ').strip().lower()
                    if answer in ('', 'd', 'destination'):
                        action['action'] = 'keep'
                    elif answer not in ('s', 'source'):
                        raise ValueError('Unknown choice; nothing copied')
    if args.dry_run:
        return 2 if missing else 0
    changes = [a for p in pairs for a in p['actions'] if a['action'] != 'keep']
    new_dirs = sum(len(p['src'][1] - p['dst'][1]) + (not p['target'].exists()) for p in pairs)
    print(f'Final plan: {sum(a["action"] == "add" for a in changes)} add, '
          f'{sum(a["action"] == "replace" for a in changes)} replace, '
          f'{sum(a["action"] == "delete" for a in changes)} delete, {new_dirs} new directories.')
    if changes or new_dirs or any(p['remove_dirs'] for p in pairs):
        if input('Apply this plan? [y/N]: ').strip().lower() not in ('y', 'yes'):
            print('Cancelled; no files changed.')
            return 1
        apply(pairs)
    print('Complete.' if not missing else 'Available folders processed; missing folders remain.')
    return 2 if missing else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, EOFError, KeyboardInterrupt) as error:
        print(f'sync: {error}', file=sys.stderr)
        sys.exit(1)
