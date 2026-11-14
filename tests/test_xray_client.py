import copy
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("xray_client", Path(__file__).resolve().parents[1] / "scripts/xray-client.py")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class Vault:
    def __init__(self):
        self.env = {}
        self.items = {"pino-xray-halos": {"notes": json.dumps({"users": {
            "owner": "11111111-1111-4111-8111-111111111111"}})}}

    def find(self, name, kind):
        return copy.deepcopy(self.items.get(name))

    def create(self, name, kind, **fields):
        assert name not in self.items
        self.items[name] = fields

    def edit(self, old, new):
        name = next(name for name, value in self.items.items() if value == old)
        self.items[name] = copy.deepcopy(new)

    def delete(self, old):
        name = next(name for name, value in self.items.items() if value == old)
        del self.items[name]


class XrayClientTests(unittest.TestCase):
    def test_retry_preserves_identity_and_other_users(self):
        vault = Vault()
        config, uri = client.prepare_client(vault, "halos", "re-1")
        before = copy.deepcopy(vault.items)
        self.assertEqual((config, uri), client.prepare_client(vault, "halos", "re-1"))
        self.assertEqual(before, vault.items)
        self.assertIn("@halos.egrapa.com:443?", uri)
        self.assertIn("type=xhttp", uri)
        self.assertEqual(json.loads(config)["inbounds"][0]["listen"], "127.0.0.1")
        users = json.loads(vault.items["pino-xray-halos"]["notes"])["users"]
        self.assertEqual(set(users), {"owner", "re-1"})
        self.assertNotEqual(users["owner"], users["re-1"])

    def test_failed_revoke_keeps_client_and_retry_redeploys(self):
        vault = Vault()
        client.prepare_client(vault, "halos", "ari")
        with patch.object(client, "deploy_server", side_effect=ValueError("offline")):
            with self.assertRaises(ValueError):
                client.remove_client(vault, "halos", "ari")
        self.assertIn("pino-xray-client-ari-halos", vault.items)
        self.assertNotIn("ari", json.loads(vault.items["pino-xray-halos"]["notes"])["users"])
        with patch.object(client, "deploy_server") as deploy:
            client.remove_client(vault, "halos", "ari")
            deploy.assert_called_once_with(vault, "halos")
        self.assertEqual(set(vault.items), {"pino-xray-halos"})

    def test_refuses_last_user_and_conflicting_identity(self):
        vault = Vault()
        before = copy.deepcopy(vault.items)
        with self.assertRaises(ValueError):
            client.remove_client(vault, "halos", "owner")
        self.assertEqual(before, vault.items)
        client.prepare_client(vault, "halos", "ari")
        payload = json.loads(vault.items["pino-xray-halos"]["notes"])
        payload["users"]["ari"] = "22222222-2222-4222-8222-222222222222"
        vault.items["pino-xray-halos"]["notes"] = json.dumps(payload)
        before = copy.deepcopy(vault.items)
        with self.assertRaises(ValueError):
            client.prepare_client(vault, "halos", "ari")
        with self.assertRaises(ValueError):
            client.remove_client(vault, "halos", "ari")
        self.assertEqual(before, vault.items)

    def test_retry_after_server_save_failure_reuses_client(self):
        vault = Vault()
        with patch.object(vault, "edit", side_effect=ValueError("offline")):
            with self.assertRaises(ValueError):
                client.prepare_client(vault, "halos", "pa")
        identifier = client.client_id(vault.items["pino-xray-client-pa-halos"])
        client.prepare_client(vault, "halos", "pa")
        self.assertEqual(identifier, json.loads(vault.items["pino-xray-halos"]["notes"])["users"]["pa"])

    def test_deploy_failure_has_recovery_and_no_credentials(self):
        with patch.dict(client.os.environ, {"PINO_PROVISION_SEND": "/fixture/send"}), patch.object(client.subprocess, "run", return_value=SimpleNamespace(returncode=1)) as run:
            with self.assertRaisesRegex(ValueError, "without an export directory"):
                client.deploy_server(Vault(), "halos")
            self.assertEqual(run.call_args.args[0], ["/fixture/send", "send", "pino-xray-halos",
                                                   "halos", "/etc/pino/xray/users.json", "xray.service"])


if __name__ == "__main__":
    unittest.main()
