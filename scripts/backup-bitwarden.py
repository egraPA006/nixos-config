#!/usr/bin/env python3
"""Publish a portable, password-encrypted personal Bitwarden export."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run_bw(arguments, env, interactive=False):
    result = subprocess.run(
        ["bw", *arguments], env=env, stdout=subprocess.PIPE,
        stderr=None if interactive else subprocess.PIPE, check=False,
    )
    if result.returncode:
        # Never reproduce subprocess output: it may contain vault data.
        raise ValueError("Bitwarden operation failed; previous backup was preserved.")
    return result.stdout


def vault_json(arguments, env):
    try:
        return json.loads(run_bw(arguments, env))
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise ValueError("Bitwarden returned invalid JSON.") from None


def unlock(env):
    if env.get("BW_SESSION"):
        return
    status = vault_json(["status"], env).get("status")
    if status not in {"unauthenticated", "locked", "unlocked"}:
        raise ValueError("Unknown Bitwarden login state.")
    command = "login" if status == "unauthenticated" else "unlock"
    session = run_bw([command, "--raw"], env, interactive=True).decode().strip()
    if not session:
        raise ValueError("Bitwarden did not return a session.")
    env["BW_SESSION"] = session


def validate_export(data):
    try:
        value = json.loads(data)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise ValueError("Export is not valid encrypted JSON; backup unchanged.") from None
    if not isinstance(value, dict) or value.get("encrypted") is not True or value.get("passwordProtected") is not True:
        raise ValueError("Export is not portable password-encrypted JSON; backup unchanged.")
    for key in ("salt", "encKeyValidation_DO_NOT_EDIT", "data"):
        if not isinstance(value.get(key), str) or not value[key]:
            raise ValueError("Encrypted export is incomplete; backup unchanged.")
    if type(value.get("kdfType")) is not int or value["kdfType"] not in (0, 1):
        raise ValueError("Encrypted export has an unsupported KDF; backup unchanged.")
    required = ["kdfIterations"]
    if value["kdfType"] == 1:
        required += ["kdfMemory", "kdfParallelism"]
    if any(type(value.get(key)) is not int or value[key] <= 0 for key in required):
        raise ValueError("Encrypted export is missing KDF parameters; backup unchanged.")


def check_path(path):
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError("Backup paths must not contain symlinks.")


def publish(target, data):
    validate_export(data)
    check_path(target)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".vault-", delete=False) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        check_path(target)
        os.replace(temporary, target)
        temporary = None
        directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def confirm(prompt):
    return input(prompt + " [y/N] ").strip().lower() in {"y", "yes"}


def backup(external, env):
    external = Path(os.path.abspath(external))
    check_path(external)
    if not external.is_dir():
        raise ValueError("External directory must already exist and be mounted/unlocked.")
    target = external / "pino/bitwarden/vault.encrypted.json"
    check_path(target)
    if target.exists() and not target.is_file():
        raise ValueError("Backup destination is not a regular file.")
    unlock(env)
    run_bw(["sync"], env)
    items = vault_json(["list", "items"], env)
    trash = vault_json(["list", "items", "--trash"], env)
    if (not isinstance(items, list) or not isinstance(trash, list)
            or any(not isinstance(item, dict) for item in items)):
        raise ValueError("Cannot establish vault export scope.")
    attachments = sum(len(item.get("attachments") or []) for item in items)
    organization = sum(bool(item.get("organizationId")) for item in items)
    print("Scope: active personal vault items, including notes and custom fields.")
    print("Excluded: attachments, organization-owned items, trash, Sends and account/2FA recovery settings.")
    print(f"Detected exclusions: {attachments} attachments, {organization} organization items, {len(trash)} trash items.")
    if not confirm("Accept this export scope (not a complete account backup)?"):
        print("Cancelled; backup unchanged.")
        return
    print(f"{'Replace' if target.exists() else 'Create'}: {target}")
    print("Keep the export password separately: it is required to import into another account.")
    if not confirm("Export and apply this backup?"):
        print("Cancelled; backup unchanged.")
        return
    # A bare --password uses the CLI's hidden prompt, never argv or a file.
    data = run_bw(["export", "--format", "encrypted_json", "--password", "--raw"], env, interactive=True)
    publish(target, data)
    print("Saved password-encrypted personal vault export (0600).")
    print("Recovery: import this file as Bitwarden JSON and enter its export password.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("external_disk", help="Existing unlocked external disk directory")
    args = parser.parse_args()
    try:
        backup(args.external_disk, os.environ.copy())
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (OSError, EOFError):
        # No exception repr: values from the vault must never reach the terminal.
        print("Bitwarden backup did not complete. Check disk access, CLI login and export support; no unvalidated export was published.", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
