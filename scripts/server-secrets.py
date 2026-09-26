#!/usr/bin/env python3
"""Prepare local Bitwarden note files without printing secret contents."""

import argparse
import base64
import copy
import getpass
import json
import os
import re
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile

import bcrypt


class Bitwarden:
    def __init__(self):
        self.env = os.environ.copy()
        status = self.json_call("status").get("status")
        if status == "unauthenticated":
            raise ValueError("Run bw login first, then retry")
        if status != "unlocked":
            if not sys.stdin.isatty():
                raise ValueError("Unlock Bitwarden in a terminal first")
            self.env["PINO_BW_PASSWORD"] = getpass.getpass("Bitwarden master password: ")
            try:
                session = self.call("unlock", "--passwordenv", "PINO_BW_PASSWORD", "--raw").strip()
            finally:
                self.env.pop("PINO_BW_PASSWORD", None)
            if not session:
                raise ValueError("Bitwarden unlock returned no session")
            self.env["BW_SESSION"] = session
        self.call("sync")

    def call(self, *args, payload=None):
        result = subprocess.run(
            ["bw", *args], input=payload, capture_output=True, text=True, env=self.env,
        )
        if result.returncode:
            # CLI output can contain decrypted vault data, so do not relay it.
            raise ValueError(f"Bitwarden {args[0]} failed; check login/network and retry")
        return result.stdout

    def json_call(self, *args):
        try:
            return json.loads(self.call(*args))
        except json.JSONDecodeError:
            raise ValueError("Bitwarden returned invalid JSON") from None

    def find(self, name, item_type):
        items = [item for item in self.json_call("list", "items", "--search", name)
                 if item.get("name") == name and not item.get("deletedDate")]
        if len(items) > 1:
            raise ValueError(f"Multiple Bitwarden items named {name}; resolve duplicates first")
        if items and items[0].get("type") != item_type:
            raise ValueError(f"Wrong Bitwarden item type for {name}")
        return items[0] if items else None

    def create(self, name, item_type, **fields):
        # Recheck before writing, including after a partially successful run.
        if self.find(name, item_type):
            raise ValueError(f"Bitwarden item {name} appeared during preparation; retry")
        item = self.json_call("get", "template", "item")
        item.update(name=name, type=item_type, **fields)
        if item_type == 2:
            item["secureNote"] = {"type": 0}
        encoded = base64.b64encode(json.dumps(item).encode()).decode()
        self.call("create", "item", payload=encoded)
        print(f"Created Bitwarden item: {name}")

    def password(self):
        return self.call("generate", "--length", "32", "--uppercase", "--lowercase", "--number", "--special").strip()

    def edit(self, original, updated):
        current = self.json_call("get", "item", original["id"])
        for field in ("revisionDate", "name", "type", "notes", "login"):
            if current.get(field) != original.get(field):
                raise ValueError("Bitwarden item changed during rotation; retry after reviewing it")
        encoded = base64.b64encode(json.dumps(updated).encode()).decode()
        self.call("edit", "item", original["id"], payload=encoded)


def replace_vpn_key(config, private):
    section = None
    replacements = 0
    lines = config.splitlines(keepends=True)
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("["):
            section = stripped.lower()
        if section == "[interface]" and re.match(r"^\s*PrivateKey\s*=", line, re.I):
            lines[index] = f"PrivateKey = {private}\n"
            replacements += 1
    if replacements != 1:
        raise ValueError("VPN note must contain exactly one Interface PrivateKey")
    return "".join(lines)


def rotate_bitwarden(host, scope, vault, repair=False):
    if scope == "galene" and host != "mosk":
        raise ValueError("Galene is only configured on mosk")
    if scope == "galene":
        login = vault.find("pino-galene-mosk-admin", 1)
        note = vault.find("pino-galene-mosk-main", 2)
        if not login or not note:
            raise ValueError("Create both Galene records before rotating")
        if (login.get("login") or {}).get("username") != "admin":
            raise ValueError("Galene Login must use username admin")
        try:
            room = json.loads(note["notes"])
            if not isinstance(room["users"]["admin"], dict):
                raise ValueError()
        except (ValueError, KeyError, TypeError):
            raise ValueError("Galene note must contain a valid users.admin object") from None
        password = login["login"].get("password") if repair else vault.password()
        if not isinstance(password, str):
            raise ValueError("Galene Login has no password")
        room["users"]["admin"]["password"] = room_config(password)["users"]["admin"]["password"]
        updated = copy.deepcopy(note)
        updated["notes"] = json.dumps(room, indent=2)
        originals = [login, note]
    else:
        note = vault.find(f"pino-vpn-server-{host}", 2)
        if not note or not isinstance(note.get("notes"), str):
            raise ValueError("Create the VPN server note before rotating")
        # Validate the existing note before generating a replacement key.
        replace_vpn_key(note["notes"], "validation")
        private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
        if not private:
            raise ValueError("awg did not generate a private key")
        updated = copy.deepcopy(note)
        updated["notes"] = replace_vpn_key(note["notes"], private)
        originals = [note]
    backup = f"pino-rotation-backup-{host}-{scope}-{secrets.token_hex(8)}"
    vault.create(backup, 2, notes=json.dumps(originals))
    print(f"Recovery snapshot saved in Bitwarden: {backup}")
    if scope == "galene" and not repair:
        changed_login = copy.deepcopy(login)
        changed_login["login"]["password"] = password
        vault.edit(login, changed_login)
    try:
        vault.edit(note, updated)
    except (ValueError, OSError, subprocess.CalledProcessError):
        if scope == "galene":
            print("Rotation incomplete. Rerun with --bitwarden --repair-galene to match the note to the saved Login.", file=sys.stderr)
        raise
    print(f"Updated {scope} in Bitwarden only; the running server has NOT changed.")
    if scope == "vpn":
        print("Peers and network settings were preserved. Update the server public key on every client when deploying.")
    print("Deploy the updated note using pino provision send; retain the recovery snapshot until verified.")


def prepare_bitwarden(host, vault):
    vpn_name = f"pino-vpn-server-{host}"
    vpn = vault.find(vpn_name, 2)
    if vpn and not (vpn.get("notes") or "").strip():
        raise ValueError(f"Existing {vpn_name} is empty; fill it or remove it manually")
    login_name = "pino-galene-mosk-admin"
    room_name = "pino-galene-mosk-main"
    if host == "mosk":
        login = vault.find(login_name, 1)
        room = vault.find(room_name, 2)
        if room and not login:
            raise ValueError(f"{room_name} already exists; save its existing admin password in {login_name} first")
        password = (login.get("login") or {}).get("password") if login else vault.password()
        if not isinstance(password, str) or not password or len(password.encode()) > 72:
            raise ValueError("Galene admin password must contain 1–72 UTF-8 bytes")
        if login and login.get("login", {}).get("username") != "admin":
            raise ValueError(f"{login_name} must use username admin")
        if room:
            try:
                admin = json.loads(room["notes"])["users"]["admin"]
                credential = admin["password"]
                matches = credential["type"] == "bcrypt" and bcrypt.checkpw(password.encode(), credential["key"].encode())
                matches = matches and admin["permissions"] == "op"
            except (ValueError, KeyError, TypeError, AttributeError):
                matches = False
            if not matches:
                raise ValueError("Existing Galene note and admin Login do not match; no items were changed")
        if not login:
            vault.create(login_name, 1, login={
                "username": "admin", "password": password,
                "uris": [{"uri": "https://meet.egrapa.com/group/main/", "match": None}],
                "totp": None,
            })
        if not room:
            vault.create(room_name, 2, notes=json.dumps(room_config(password), indent=2))
    if not vpn:
        private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
        if not private:
            raise ValueError("awg did not generate a private key")
        vault.create(vpn_name, 2, notes=vpn_config(private))
    print("Bitwarden records ready. Existing records were preserved; no plaintext export files were created.")
    print("New VPN configs have no peers. Existing SSH keys are unchanged.")


def vpn_config(private_key):
    headers = set()
    while len(headers) < 4:
        headers.add(secrets.randbelow(2**32 - 5) + 5)
    h1, h2, h3, h4 = sorted(headers)
    return f"""[Interface]
PrivateKey = {private_key}
Address = 10.77.0.1/24
ListenPort = 585
Jc = 4
Jmin = 40
Jmax = 70
S1 = 50
S2 = 60
H1 = {h1}
H2 = {h2}
H3 = {h3}
H4 = {h4}
"""


def room_config(password):
    encoded = password.encode("utf-8")
    if not encoded or len(encoded) > 72:
        raise ValueError("Galene password must contain 1–72 UTF-8 bytes")
    hashed = bcrypt.hashpw(encoded, bcrypt.gensalt(rounds=12)).decode("ascii")
    return {"users": {"admin": {
        "password": {"type": "bcrypt", "key": hashed},
        "permissions": "op",
    }}}


def write_private(path, contents):
    with path.open("x", encoding="utf-8") as target:
        os.chmod(path, 0o600)
        target.write(contents)


def prepare(host, output, password=None):
    output = output.expanduser().resolve()
    if output.exists():
        raise ValueError("Output directory already exists; choose a new directory")
    ancestor = output.parent
    while not ancestor.exists():
        ancestor = ancestor.parent
    git = subprocess.run(
        ["git", "-C", str(ancestor), "rev-parse", "--is-inside-work-tree"],
        capture_output=True, text=True, check=False,
    )
    if git.returncode == 0 and git.stdout.strip() == "true":
        raise ValueError("Choose an output directory outside any Git checkout")

    # Compute everything before creating the output directory. Never echo tool
    # stderr or exception command arguments, which might contain key material.
    private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
    public = subprocess.run(
        ["awg", "pubkey"], input=private + "\n", capture_output=True, text=True, check=True,
    ).stdout.strip()
    if not private or not public:
        raise ValueError("awg did not generate a key pair")
    room = room_config(password) if host == "mosk" else None
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    try:
        write_private(output / f"pino-vpn-server-{host}.conf", vpn_config(private))
        write_private(output / "server.pub", public + "\n")
        if room is not None:
            write_private(output / "pino-galene-mosk-main.json", json.dumps(room, indent=2) + "\n")
    except BaseException:
        shutil.rmtree(output)
        raise
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", choices=["mosk", "halos"])
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--bitwarden", action="store_true", help="Create missing Bitwarden records directly, without local exports")
    operations = parser.add_mutually_exclusive_group()
    operations.add_argument("--rotate", choices=["galene", "vpn"], help="Rotate selected existing Bitwarden secrets, preserving a recovery snapshot")
    operations.add_argument("--repair-galene", action="store_true", help="Repair the Galene note using the current Login password after an interrupted rotation")
    args = parser.parse_args()
    output = args.output or Path(tempfile.gettempdir()) / f"pino-{args.host}-{secrets.token_hex(8)}"
    os.umask(0o077)
    password = None
    try:
        if (args.rotate or args.repair_galene) and not args.bitwarden:
            raise ValueError("Rotation and repair require --bitwarden")
        if args.bitwarden:
            if args.output:
                raise ValueError("Do not specify an output directory with --bitwarden")
            if args.rotate or args.repair_galene:
                scope = args.rotate or "galene"
                if not sys.stdin.isatty():
                    raise ValueError("Run rotation in a terminal to confirm the change")
                confirmation = f"{args.host} {scope}"
                print("This changes Bitwarden records, not the running server. VPN rotation requires updating clients.")
                if input(f"Type '{confirmation}' to continue: ") != confirmation:
                    raise ValueError("Cancelled; no secrets changed")
                rotate_bitwarden(args.host, scope, Bitwarden(), repair=args.repair_galene)
            else:
                prepare_bitwarden(args.host, Bitwarden())
            return 0
        if args.host == "mosk":
            if not sys.stdin.isatty():
                raise ValueError("Run in a terminal to enter the Galene password privately")
            password = getpass.getpass("Galene admin password: ")
            if password != getpass.getpass("Repeat password: "):
                raise ValueError("Passwords do not match")
        output = prepare(args.host, output, password)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        message = str(error) if isinstance(error, ValueError) else "File or key generation failed"
        print(message, file=sys.stderr)
        return 1
    print(f"Created private files in {output}")
    print(f"Bitwarden Secure Note pino-vpn-server-{args.host}: use pino-vpn-server-{args.host}.conf as Notes")
    if args.host == "mosk":
        print("Bitwarden Secure Note pino-galene-mosk-main: use pino-galene-mosk-main.json as Notes")
    print("VPN has no peers yet; add client public keys and distinct /32 addresses before connecting clients.")
    print("Copy S1, S2 and H1–H4 to client configs. Default server VPN mode is private.")
    print("Existing SSH keys in Bitwarden are not changed.")
    print("After saving and checking the Bitwarden notes, delete this output directory.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
