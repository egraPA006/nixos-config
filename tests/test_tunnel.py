import importlib.util
import json
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tunnel", ROOT / "scripts/tunnel.py")
tunnel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tunnel)


class TunnelTests(unittest.TestCase):
    def test_cleanup_never_touches_network_without_ownership_marker(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(tunnel, "RUNTIME", Path(directory)), patch.object(tunnel, "run") as run:
            tunnel.cleanup_owned()
            run.assert_not_called()

    def test_cleanup_removes_only_reserved_resources_after_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(tunnel, "RUNTIME", Path(directory)):
            marker = Path(directory) / "owned.json"
            marker.write_text(json.dumps({"kind": "xray", "name": "halos"}))
            def result(*args, **kwargs):
                if "-j" in args:
                    return SimpleNamespace(returncode=0, stdout=json.dumps([
                        {"priority": 9000}, {"priority": 9002}, {"priority": 32766}]))
                return SimpleNamespace(returncode=0, stdout="")
            with patch.object(tunnel, "run", side_effect=result) as run:
                tunnel.cleanup_owned()
                self.assertFalse(marker.exists())
                self.assertFalse(any("32766" in call.args for call in run.call_args_list))
                self.assertTrue(any(call.args == ("ip", "link", "delete", "pino-tun") for call in run.call_args_list))

    def test_nix_wrapper_application_rule_and_exact_path(self):
        rule = tunnel.app_rule("firefox", "direct")
        expression = rule["process_path_regex"][0]
        self.assertRegex("/nix/store/hash-firefox/bin/.firefox-wrapped", expression)
        self.assertIsNone(re.search(expression, "/usr/bin/notfirefox"))
        self.assertEqual(tunnel.app_rule("/opt/browser", "vpn")["process_path"], ["/opt/browser"])

    def test_dns_preserves_system_resolver_and_awg_ipv6_cannot_fall_back(self):
        config = tunnel.router_config("awg", "halos", "eth0", {"default": "vpn", "apps": {"firefox": "direct"}})
        self.assertNotIn("dns", config)
        rules = config["route"]["rules"]
        self.assertEqual(rules[0], {"port": 53, "action": "route", "outbound": "direct"})
        self.assertEqual(rules[1]["outbound"], "direct")
        self.assertEqual(rules[2], {"ip_version": 6, "action": "reject"})
        self.assertEqual(config["route"]["final"], "vpn")

    def test_only_selected_apps_vpn_rejects_their_ipv6(self):
        config = tunnel.router_config("awg", "halos", "eth0", {"default": "direct", "apps": {"curl": "vpn"}})
        self.assertEqual(config["route"]["rules"][1]["ip_version"], 6)
        self.assertEqual(config["route"]["rules"][2]["outbound"], "vpn")
        self.assertEqual(config["route"]["final"], "direct")

    def test_awg_routing_fields_replaced_and_shell_hooks_refused(self):
        config = tunnel.awg_config("[Interface]\nPrivateKey = fixture\nTable = auto\nDNS = 1.1.1.1\nFwMark = 99\n[Peer]\nAllowedIPs = 0.0.0.0/0\n")
        self.assertIn("Table = off\nFwMark = 2024\n[Peer]", config)
        self.assertIn("DNS = 1.1.1.1", config)
        self.assertNotIn("99", config)
        with self.assertRaises(ValueError):
            tunnel.awg_config("[Interface]\nPostUp = echo bad\n[Peer]\n")

    def test_xray_bootstrap_keeps_verified_tls_and_marks_transport(self):
        config = {"outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": "halos.egrapa.com", "port": 443}]},
                                "streamSettings": {"network": "xhttp", "security": "tls", "tlsSettings": {"serverName": "halos.egrapa.com"}}}]}
        output = tunnel.xray_config(config, "eth0", resolve=lambda *args: [(None, None, None, None, ("203.0.113.1", 443))])
        self.assertEqual(output["outbounds"][0]["settings"]["vnext"][0]["address"], "203.0.113.1")
        self.assertEqual(output["outbounds"][0]["streamSettings"]["tlsSettings"]["serverName"], "halos.egrapa.com")
        self.assertEqual(output["outbounds"][0]["streamSettings"]["sockopt"]["mark"], 2024)
        self.assertNotIn("203.0.113.1", json.dumps(config))
        config["outbounds"][0]["streamSettings"]["tlsSettings"]["allowInsecure"] = True
        with self.assertRaises(ValueError):
            tunnel.xray_config(config, "eth0")


if __name__ == "__main__":
    unittest.main()
