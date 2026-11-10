import copy
import base64
import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
import unittest
import zlib
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

    def delete(self, original):
        name = next(name for name, item in self.items.items() if item == original)
        del self.items[name]


class ClientTests(unittest.TestCase):
    def remove(self, vault, name):
        with patch.object(client, "public_key", side_effect=lambda key: "public-" + key), \
             redirect_stdout(io.StringIO()):
            client.remove_client(vault, "mosk", name)

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

    def test_force_updates_peer_with_inline_header_comment(self):
        vault = Vault()
        self.prepare(vault, "phone")
        server = vault.items["pino-vpn-server-mosk"]
        server["notes"] = server["notes"].replace("[Peer]", "[Peer] # phone")
        server["notes"] = server["notes"].replace("Address = 10.77.0.1/24", "Address = 10.78.0.1/24")
        self.prepare(vault, "phone", force=True)
        self.assertIn("[Peer] # phone", vault.items["pino-vpn-server-mosk"]["notes"])
        self.assertNotIn("10.77.0.2/32", vault.items["pino-vpn-server-mosk"]["notes"])

    def test_conflicting_other_peer_is_rejected_before_any_write(self):
        vault = Vault()
        self.prepare(vault, "phone")
        vault.items["pino-vpn-server-mosk"]["notes"] += "\n[Peer]\nPublicKey = other\nAllowedIPs = 10.77.0.2/32\n"
        before = copy.deepcopy(vault.items)
        with self.assertRaises(ValueError):
            self.prepare(vault, "phone")
        self.assertEqual(vault.items, before)

    def test_invalid_port_is_not_echoed_or_saved(self):
        vault = Vault()
        vault.items["pino-vpn-server-mosk"]["notes"] = vault.items["pino-vpn-server-mosk"]["notes"].replace("ListenPort = 585", "ListenPort = sensitive-fixture")
        before = copy.deepcopy(vault.items)
        with self.assertRaises(ValueError) as error:
            self.prepare(vault, "phone")
        self.assertNotIn("sensitive-fixture", str(error.exception))
        self.assertEqual(vault.items, before)

    def test_force_preserves_server_preshared_key(self):
        vault = Vault()
        self.prepare(vault, "phone")
        vault.items["pino-vpn-server-mosk"]["notes"] += "PresharedKey = synthetic-psk\n"
        config = self.prepare(vault, "phone", force=True)
        self.assertIn("PresharedKey = synthetic-psk", config)

    def test_amnezia_link_matches_import_schema_and_qcompress(self):
        vault = Vault()
        config = self.prepare(vault, "phone")
        link = vault.items["pino-vpn-client-phone-mosk-amnezia"]["notes"]
        self.assertTrue(link.startswith("vpn://"))
        encoded = link[6:]
        packed = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        raw = zlib.decompress(packed[4:])
        self.assertEqual(int.from_bytes(packed[:4], "big"), len(raw))
        payload = json.loads(raw)
        self.assertEqual(payload["defaultContainer"], "amnezia-awg")
        protocol = payload["containers"][0]["awg"]
        self.assertTrue(protocol["isThirdPartyConfig"])
        last = json.loads(protocol["last_config"])
        self.assertEqual(last["config"], config)
        self.assertEqual(last["client_priv_key"], "client-secret")
        self.assertEqual(last["hostName"], "vpn.egrapa.com")
        self.assertEqual(last["port"], 585)
        self.assertEqual(last["allowed_ips"], ["0.0.0.0/0"])
        self.assertEqual(last["S1"], "50")
        self.assertEqual(last["persistent_keep_alive"], "25")
        self.assertNotIn("PrivateKey = server-secret", raw.decode())

    def test_existing_client_backfills_link(self):
        vault = Vault()
        config = self.prepare(vault, "phone")
        del vault.items["pino-vpn-client-phone-mosk-amnezia"]
        self.assertEqual(self.prepare(vault, "phone"), config)
        self.assertIn("pino-vpn-client-phone-mosk-amnezia", vault.items)

    def test_force_refreshes_link(self):
        vault = Vault()
        self.prepare(vault, "phone")
        before = vault.items["pino-vpn-client-phone-mosk-amnezia"]["notes"]
        vault.items["pino-vpn-server-mosk"]["notes"] += "PresharedKey = synthetic-psk\n"
        self.prepare(vault, "phone", force=True)
        self.assertNotEqual(vault.items["pino-vpn-client-phone-mosk-amnezia"]["notes"], before)

    def test_removal_preserves_unrelated_peer_and_deploys_before_deleting(self):
        vault = Vault()
        self.prepare(vault, "phone")
        other = "[Peer] # unrelated\nPublicKey = other\nAllowedIPs = 10.77.0.3/32\n"
        vault.items["pino-vpn-server-mosk"]["notes"] += other
        def deploy(vault, host):
            self.assertIn("pino-vpn-client-phone-mosk", vault.items)
            self.assertIn("pino-vpn-client-phone-mosk-amnezia", vault.items)
            self.assertNotIn("public-client-secret", vault.items["pino-vpn-server-mosk"]["notes"])
        with patch.object(client, "deploy_server", side_effect=deploy) as deployment:
            self.remove(vault, "phone")
            deployment.assert_called_once_with(vault, "mosk")
        self.assertEqual(set(vault.items), {"pino-vpn-server-mosk"})
        self.assertIn(other, vault.items["pino-vpn-server-mosk"]["notes"])

    def test_failed_removal_deployment_retains_records_and_can_retry(self):
        vault = Vault()
        self.prepare(vault, "phone")
        with patch.object(client, "deploy_server", side_effect=ValueError("fixture")):
            with self.assertRaises(ValueError):
                self.remove(vault, "phone")
        self.assertIn("pino-vpn-client-phone-mosk", vault.items)
        self.assertIn("pino-vpn-client-phone-mosk-amnezia", vault.items)
        with patch.object(client, "deploy_server") as deployment:
            self.remove(vault, "phone")
            deployment.assert_called_once()

    def test_partial_vault_removal_can_retry(self):
        vault = Vault()
        self.prepare(vault, "phone")
        delete = vault.delete
        def fail_canonical(item):
            if item == vault.items["pino-vpn-client-phone-mosk"]:
                raise ValueError("fixture")
            delete(item)
        with patch.object(client, "deploy_server"), patch.object(vault, "delete", side_effect=fail_canonical):
            with self.assertRaises(ValueError):
                self.remove(vault, "phone")
        self.assertIn("pino-vpn-client-phone-mosk", vault.items)
        self.assertNotIn("pino-vpn-client-phone-mosk-amnezia", vault.items)
        with patch.object(client, "deploy_server"):
            self.remove(vault, "phone")
            self.remove(vault, "phone")

    def test_orphan_link_is_not_deleted_without_peer_identity(self):
        vault = Vault()
        self.prepare(vault, "phone")
        del vault.items["pino-vpn-client-phone-mosk"]
        before = copy.deepcopy(vault.items)
        with self.assertRaises(ValueError):
            self.remove(vault, "phone")
        self.assertEqual(vault.items, before)

    def test_deploy_uses_current_pino_namespace(self):
        vault = SimpleNamespace(env={})
        with patch.object(client.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
            client.deploy_server(vault, "mosk")
        self.assertEqual(run.call_args.args[0][:4], ["pino", "os", "provision", "send"])

    def test_duplicate_peer_removal_fails_without_changes(self):
        vault = Vault()
        self.prepare(vault, "phone")
        vault.items["pino-vpn-server-mosk"]["notes"] += "[Peer]\nPublicKey = public-client-secret\nAllowedIPs = 10.77.0.9/32\n"
        before = copy.deepcopy(vault.items)
        with patch.object(client, "deploy_server") as deployment:
            with self.assertRaises(ValueError):
                self.remove(vault, "phone")
            deployment.assert_not_called()
        self.assertEqual(vault.items, before)

    def test_link_creation_failure_can_retry_without_new_device(self):
        vault = Vault()
        create = vault.create
        def fail_link(name, kind, **fields):
            if name.endswith("-amnezia"):
                raise ValueError("fixture")
            create(name, kind, **fields)
        with patch.object(vault, "create", side_effect=fail_link):
            with self.assertRaises(ValueError):
                self.prepare(vault, "phone")
        config = vault.items["pino-vpn-client-phone-mosk"]["notes"]
        self.assertEqual(self.prepare(vault, "phone"), config)
        self.assertEqual(vault.items["pino-vpn-server-mosk"]["notes"].count("[Peer]"), 1)
