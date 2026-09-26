import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import io
from contextlib import redirect_stdout
import unittest
from unittest.mock import patch

import bcrypt

spec = importlib.util.spec_from_file_location("server_secrets", Path(__file__).resolve().parents[1] / "scripts/server-secrets.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class FakeVault:
    def __init__(self):
        self.items = {}
        self.created = []

    def find(self, name, item_type):
        return self.items.get(name)

    def password(self):
        return "generated-test-password"

    def create(self, name, item_type, **fields):
        if name in self.items:
            raise AssertionError("Attempted overwrite")
        self.items[name] = {"name": name, "type": item_type, **fields}
        self.created.append(name)

    def edit(self, original, updated):
        self.items[original["name"]] = updated


class ServerSecretsTests(unittest.TestCase):
    def tool(self, args, **kwargs):
        if args[0] == "git":
            return subprocess.CompletedProcess(args, 128, "", "")
        return subprocess.CompletedProcess(args, 0, "test-private\n" if args[1] == "genkey" else "test-public\n", "")

    def test_mosk_files_permissions_and_password(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(setup.subprocess, "run", side_effect=self.tool):
            output = setup.prepare("mosk", Path(directory) / "notes", "test password")
            self.assertEqual(output.stat().st_mode & 0o777, 0o700)
            for file in output.iterdir():
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            room = json.loads((output / "pino-galene-mosk-main.json").read_text())
            hashed = room["users"]["admin"]["password"]["key"]
            self.assertTrue(bcrypt.checkpw(b"test password", hashed.encode()))
            self.assertNotIn("test password", (output / "pino-galene-mosk-main.json").read_text())
            with self.assertRaises(ValueError):
                setup.prepare("mosk", output, "different")

    def test_halos_has_no_room(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(setup.subprocess, "run", side_effect=self.tool):
            output = setup.prepare("halos", Path(directory) / "notes")
            self.assertEqual({p.name for p in output.iterdir()}, {"server.pub", "pino-vpn-server-halos.conf"})

    def test_git_checkout_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(setup.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "true\n", "")):
            with self.assertRaises(ValueError):
                setup.prepare("halos", Path(directory) / "notes")
            self.assertFalse((Path(directory) / "notes").exists())

    def test_password_limits(self):
        for password in ["", "x" * 73, "я" * 37]:
            with self.assertRaises(ValueError):
                setup.room_config(password)

    def test_unique_valid_headers(self):
        config = setup.vpn_config("test-key")
        headers = [int(line.split("=")[1]) for line in config.splitlines() if line.startswith("H")]
        self.assertEqual(len(set(headers)), 4)
        self.assertTrue(all(5 <= value < 2**32 for value in headers))

    def test_bitwarden_create_and_rerun(self):
        vault = FakeVault()
        output = io.StringIO()
        with patch.object(setup.subprocess, "run", side_effect=self.tool), redirect_stdout(output):
            setup.prepare_bitwarden("mosk", vault)
            original = json.dumps(vault.items, sort_keys=True)
            setup.prepare_bitwarden("mosk", vault)
        self.assertEqual(len(vault.created), 3)
        self.assertEqual(original, json.dumps(vault.items, sort_keys=True))
        self.assertNotIn("generated-test-password", output.getvalue())
        self.assertNotIn("test-private", output.getvalue())

    def test_bitwarden_resume_after_login_created(self):
        vault = FakeVault()
        vault.create("pino-galene-mosk-admin", 1, login={"username": "admin", "password": "existing-password"})
        with patch.object(setup.subprocess, "run", side_effect=self.tool), redirect_stdout(io.StringIO()):
            setup.prepare_bitwarden("mosk", vault)
        room = json.loads(vault.items["pino-galene-mosk-main"]["notes"])
        self.assertTrue(bcrypt.checkpw(b"existing-password", room["users"]["admin"]["password"]["key"].encode()))

    def test_bitwarden_existing_room_without_login_not_overwritten(self):
        vault = FakeVault()
        vault.create("pino-galene-mosk-main", 2, notes="existing-room")
        with self.assertRaises(ValueError):
            setup.prepare_bitwarden("mosk", vault)
        self.assertEqual(vault.created, ["pino-galene-mosk-main"])

    def test_bitwarden_secrets_passed_on_stdin(self):
        vault = setup.Bitwarden.__new__(setup.Bitwarden)
        vault.env = {}
        with patch.object(vault, "find", return_value=None), patch.object(vault, "json_call", return_value={}), patch.object(vault, "call") as call, redirect_stdout(io.StringIO()):
            vault.create("test", 2, notes="secret-note")
        args, kwargs = call.call_args
        self.assertEqual(args, ("create", "item"))
        item = json.loads(setup.base64.b64decode(kwargs["payload"]))
        self.assertEqual(item["notes"], "secret-note")
        self.assertEqual(item["secureNote"], {"type": 0})

    def test_bitwarden_duplicate_names_rejected(self):
        vault = setup.Bitwarden.__new__(setup.Bitwarden)
        with patch.object(vault, "json_call", return_value=[{"name": "test", "type": 2}] * 2):
            with self.assertRaises(ValueError):
                vault.find("test", 2)

    def test_rotation_preserves_vpn_peers_and_settings(self):
        vault = FakeVault()
        original = setup.vpn_config("old-key") + "\n[Peer]\nPublicKey = client-key\nAllowedIPs = 10.77.0.2/32\n"
        vault.create("pino-vpn-server-mosk", 2, notes=original)
        with patch.object(setup.subprocess, "run", side_effect=self.tool), redirect_stdout(io.StringIO()):
            setup.rotate_bitwarden("mosk", "vpn", vault)
        self.assertEqual(vault.items["pino-vpn-server-mosk"]["notes"], original.replace("old-key", "test-private"))
        backups = [item for name, item in vault.items.items() if name.startswith("pino-rotation-backup-")]
        self.assertEqual(json.loads(backups[0]["notes"])[0]["notes"], original)

    def test_galene_rotation_and_repair_preserve_other_users(self):
        vault = FakeVault()
        room = setup.room_config("old-password")
        room["users"]["guest"] = {"permissions": "present"}
        room["description"] = "Keep this room"
        vault.create("pino-galene-mosk-admin", 1, login={"username": "admin", "password": "old-password"})
        vault.create("pino-galene-mosk-main", 2, notes=json.dumps(room))
        original_edit = vault.edit

        def fail_note(original, updated):
            if original["type"] == 2:
                raise ValueError("simulated network failure")
            original_edit(original, updated)

        with patch.object(vault, "edit", side_effect=fail_note), redirect_stdout(io.StringIO()):
            with self.assertRaises(ValueError):
                setup.rotate_bitwarden("mosk", "galene", vault)
        self.assertEqual(vault.items["pino-galene-mosk-admin"]["login"]["password"], vault.password())
        with patch.object(vault, "password", side_effect=AssertionError("repair must not rotate again")), redirect_stdout(io.StringIO()):
            setup.rotate_bitwarden("mosk", "galene", vault, repair=True)
        fixed = json.loads(vault.items["pino-galene-mosk-main"]["notes"])
        self.assertEqual(fixed["description"], room["description"])
        self.assertEqual(fixed["users"]["guest"], room["users"]["guest"])
        self.assertTrue(bcrypt.checkpw(vault.password().encode(), fixed["users"]["admin"]["password"]["key"].encode()))

    def test_invalid_vpn_rotation_does_not_write(self):
        vault = FakeVault()
        vault.create("pino-vpn-server-mosk", 2, notes="[Peer]\nPrivateKey = invalid\n")
        with self.assertRaises(ValueError):
            setup.rotate_bitwarden("mosk", "vpn", vault)
        self.assertEqual(len(vault.created), 1)

    def test_edit_checks_concurrent_modification(self):
        vault = setup.Bitwarden.__new__(setup.Bitwarden)
        original = {"id": "test-id", "revisionDate": "old"}
        with patch.object(vault, "json_call", return_value={"revisionDate": "new"}), patch.object(vault, "call") as call:
            with self.assertRaises(ValueError):
                vault.edit(original, original)
            call.assert_not_called()


if __name__ == "__main__":
    unittest.main()
