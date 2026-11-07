import copy
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("vpn_client", Path(__file__).resolve().parents[1] / "scripts/vpn-client.py")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class Vault:
    def __init__(self):
        self.items = {"pino-vpn-server-mosk": {"notes": "[Interface]\nPrivateKey = server-secret\nAddress = 10.77.0.1/24\nListenPort = 585\nS1 = 50\nH1 = 123\n"}}
        self.edits = 0

    def find(self, name, kind):
        return copy.deepcopy(self.items.get(name))

    def create(self, name, kind, **fields):
        assert name not in self.items
        self.items[name] = fields

    def edit(self, original, updated):
        self.edits += 1
        name = next(name for name, item in self.items.items() if item == original)
        self.items[name] = updated


class ClientTests(unittest.TestCase):
    def prepare(self, vault, name, force=False):
        with patch.object(client, "public_key", side_effect=lambda key: "public-" + key), \
             patch.object(client.subprocess, "run", return_value=SimpleNamespace(stdout="client-secret\n")), \
             redirect_stdout(io.StringIO()):
            return client.prepare_client(vault, "mosk", name, force=force)

    def test_private_client_and_server_key_separation(self):
        vault = Vault()
        config = self.prepare(vault, "phone")
        interface, peers = client.sections(config)
        self.assertEqual(interface["PrivateKey"], "client-secret")
        self.assertEqual(interface["Address"], "10.77.0.2/32")
        self.assertEqual(interface["S1"], "50")
        self.assertEqual(peers[0]["AllowedIPs"], "0.0.0.0/0")
        self.assertEqual(peers[0]["PublicKey"], "public-server-secret")
        self.assertNotIn("PrivateKey = client-secret", vault.items["pino-vpn-server-mosk"]["notes"])

    def test_rerun_preserves_client_and_does_not_duplicate_peer(self):
        vault = Vault()
        first = self.prepare(vault, "phone")
        self.assertEqual(self.prepare(vault, "phone"), first)
        self.assertEqual(vault.edits, 1)

    def test_pending_client_recovers_after_failed_server_edit(self):
        vault = Vault()
        with patch.object(vault, "edit", side_effect=ValueError("fixture")):
            with self.assertRaises(ValueError):
                self.prepare(vault, "phone")
        self.assertIn("pino-vpn-client-phone-mosk", vault.items)
        self.prepare(vault, "phone")
        self.assertEqual(vault.edits, 1)

    def test_allocates_around_existing_peer(self):
        vault = Vault()
        vault.items["pino-vpn-server-mosk"]["notes"] += "\n[Peer]\nPublicKey = other\nAllowedIPs = 10.77.0.2/32\n"
        self.assertIn("Address = 10.77.0.3/32", self.prepare(vault, "phone"))

    def test_rejects_name_injection(self):
        with self.assertRaises(ValueError):
            self.prepare(Vault(), "phone\n[Peer]")

    def test_force_migrates_private_profile_without_rotating_key(self):
        vault = Vault()
        self.prepare(vault, "phone")
        item = vault.items["pino-vpn-client-phone-mosk"]
        item["notes"] = item["notes"].replace("0.0.0.0/0", "10.77.0.0/24")
        before = copy.deepcopy(vault.items)
        with self.assertRaises(ValueError):
            self.prepare(vault, "phone")
        self.assertEqual(vault.items, before)
        config = self.prepare(vault, "phone", force=True)
        self.assertIn("AllowedIPs = 0.0.0.0/0", config)
        self.assertIn("PrivateKey = client-secret", config)
        self.assertEqual(vault.items["pino-vpn-server-mosk"], before["pino-vpn-server-mosk"])

    def test_force_moves_own_peer_preserving_unrelated_peer(self):
        vault = Vault()
        self.prepare(vault, "phone")
        server = vault.items["pino-vpn-server-mosk"]
        server["notes"] = server["notes"].replace("Address = 10.77.0.1/24", "Address = 10.78.0.1/24")
        other = "\n[Peer]\n# unrelated\nPublicKey = other\nAllowedIPs = 10.78.0.2/32\n"
        server["notes"] += other
        config = self.prepare(vault, "phone", force=True)
        self.assertIn("Address = 10.78.0.3/32", config)
        new_server = vault.items["pino-vpn-server-mosk"]["notes"]
        self.assertIn(other, new_server)
        self.assertEqual(new_server.count("PublicKey = public-client-secret"), 1)
        self.assertNotIn("10.77.0.2/32", new_server)

    def test_force_updates_stale_server_key(self):
        vault = Vault()
        self.prepare(vault, "phone")
        vault.items["pino-vpn-server-mosk"]["notes"] = vault.items["pino-vpn-server-mosk"]["notes"].replace("server-secret", "new-server-secret")
        config = self.prepare(vault, "phone", force=True)
        self.assertIn("PublicKey = public-new-server-secret", config)
