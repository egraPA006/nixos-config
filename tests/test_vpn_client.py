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
        self.items["pino-vpn-server-mosk"] = updated


class ClientTests(unittest.TestCase):
    def prepare(self, vault, name):
        with patch.object(client, "public_key", side_effect=lambda key: "public-" + key), \
             patch.object(client.subprocess, "run", return_value=SimpleNamespace(stdout="client-secret\n")), \
             redirect_stdout(io.StringIO()):
            return client.prepare_client(vault, "mosk", name)

    def test_private_client_and_server_key_separation(self):
        vault = Vault()
        config = self.prepare(vault, "phone")
        interface, peers = client.sections(config)
        self.assertEqual(interface["PrivateKey"], "client-secret")
        self.assertEqual(interface["Address"], "10.77.0.2/32")
        self.assertEqual(interface["S1"], "50")
        self.assertEqual(peers[0]["AllowedIPs"], "10.77.0.0/24")
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
