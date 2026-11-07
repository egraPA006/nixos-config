import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("proxy_config", ROOT / "scripts/proxy-config.py")
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)

UUID = "12345678-1234-4234-8234-123456789abc"
HEX = "123456789abcdef0123456789abcdef0"


class ProxyConfigTests(unittest.TestCase):
    def test_xray_binds_loopback_and_blocks_private_destinations(self):
        data = json.loads(proxy.render("xray", {"port": 10080, "path": "/pino-xhttp"},
                                       {"users": {"owner": UUID}}))
        inbound = data["inbounds"][0]
        self.assertEqual(inbound["listen"], "127.0.0.1")
        self.assertEqual(inbound["streamSettings"]["network"], "xhttp")
        self.assertEqual(inbound["settings"]["clients"], [{"email": "owner", "id": UUID}])
        rule = data["routing"]["rules"][0]
        self.assertIn("10.0.0.0/8", rule["ip"])
        self.assertIn("169.254.0.0/16", rule["ip"])
        self.assertIn("fc00::/7", rule["ip"])
        self.assertEqual(rule["outboundTag"], "blocked")

    def test_telemt_only_fake_tls_no_admin_api_or_link_logging(self):
        data = tomllib.loads(proxy.render("telemt", {"port": 2443, "tlsDomain": "example.com"},
                                         {"users": {"owner": HEX}}))
        self.assertEqual(data["general"]["modes"], {"classic": False, "secure": False, "tls": True})
        self.assertEqual(data["general"]["links"]["show"], [])
        self.assertFalse(data["server"]["api"]["enabled"])
        self.assertEqual(data["access"]["users"], {"owner": HEX})

    def test_rejects_empty_invalid_and_shared_credentials(self):
        for kind, invalid in [("xray", "bad"), ("xray", "0" * 32),
                              ("telemt", "a" * 31), ("telemt", "0" * 32)]:
            with self.subTest(kind=kind, invalid=invalid), self.assertRaises(ValueError):
                proxy.users(kind, {"users": {"owner": invalid}})
        for invalid in [None, {}, {"users": []}, {"users": {}},
                        {"users": {"bad\nname": UUID}},
                        {"users": {"a": UUID, "b": UUID}}]:
            with self.assertRaises(ValueError):
                proxy.users("xray", invalid)

    def test_runtime_file_is_private_and_error_does_not_disclose_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = root / "settings"
            credentials = root / "credentials"
            output = root / "config"
            settings.write_text(json.dumps({"port": 10080, "path": "/pino-xhttp"}))
            credentials.write_text(json.dumps({"users": {"owner": UUID}}))
            command = [sys.executable, str(ROOT / "scripts/proxy-config.py"), "xray",
                       str(settings), str(credentials), str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            original = output.read_bytes()
            credentials.write_text('{"users":{"owner":"do-not-disclose-this"}}')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("do-not-disclose-this", result.stdout + result.stderr)
            self.assertEqual(output.read_bytes(), original)
