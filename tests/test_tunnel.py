import importlib.util
import json
from pathlib import Path
import re
import tempfile
import sys
import os
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tunnel", ROOT / "scripts/tunnel.py")
tunnel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tunnel)


class TunnelTests(unittest.TestCase):
    def test_rebuild_test_activates_test_not_switch(self):
        source = (ROOT / "modules/pino/os.sh").read_text().replace("@configDir@", "/fixture").replace("@pinoUser@", "fixture").replace("@runuser@", "/unused")
        prefix = 'id() { printf "1000\\n"; }\nhostname() { printf "test-host\\n"; }\nsudo() { printf "CALL %s\\n" "$*"; }\n'
        result = subprocess.run(["bash", "-c", prefix + source, "pino", "rebuild-test"],
                                input="y\n", capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CALL nixos-rebuild test --flake /fixture#test-host", result.stdout)
        self.assertNotIn("nixos-rebuild switch", result.stdout)

    def test_server_mode_cli_validates_and_dispatches(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pino").write_text("#!/bin/sh\nprintf '%s\\n' \"$*\"\n")
            (root / "pino").chmod(0o755)
            env = {**os.environ, "PATH": directory + ":" + os.environ["PATH"]}
            script = str(ROOT / "modules/pino/vpn.sh")
            result = subprocess.run(["bash", script, "server", "mode", "mosk", "full"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), "host mosk server vpn mode set full")
            result = subprocess.run(["bash", script, "server", "mode", "mosk", "bad"],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("host mosk", result.stdout)

    def test_desktop_proxy_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "systemctl").write_text("#!/bin/sh\nexit 0\n")
            (root / "gsettings").write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$HOME/gsettings.log\"\n")
            (root / "systemctl").chmod(0o755)
            (root / "gsettings").chmod(0o755)
            env = {**os.environ, "HOME": directory, "XDG_CONFIG_HOME": str(root / "config"),
                   "GSETTINGS": str(root / "gsettings"), "PATH": directory + ":" + os.environ["PATH"]}
            marker = root / "config/pino/chromium-proxy"
            for mode in ("chromium", "on", "off"):
                subprocess.run(["bash", str(ROOT / "modules/pino/vpn.sh"), "split", mode],
                               env=env, check=True, capture_output=True, text=True)
                self.assertEqual(marker.exists(), mode == "chromium")
            log = (root / "gsettings.log").read_text()
            self.assertIn("set org.gnome.system.proxy.socks host 127.0.0.1", log)
            self.assertIn("set org.gnome.system.proxy mode manual", log)
            self.assertTrue(log.rstrip().endswith("set org.gnome.system.proxy mode none"))

    def test_split_off_works_when_awg_is_active(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "systemctl").write_text("#!/bin/sh\n[ \"$1\" = list-units ] && echo amneziawg@mosk.service\nexit 0\n")
            (root / "gsettings").write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$HOME/gsettings.log\"\n")
            (root / "systemctl").chmod(0o755)
            (root / "gsettings").chmod(0o755)
            env = {**os.environ, "HOME": directory, "XDG_CONFIG_HOME": str(root / "config"),
                   "GSETTINGS": str(root / "gsettings"), "PATH": directory + ":" + os.environ["PATH"]}
            marker = root / "config/pino/chromium-proxy"
            marker.parent.mkdir(parents=True)
            marker.touch()
            result = subprocess.run(["bash", str(ROOT / "modules/pino/vpn.sh"), "split", "off"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(marker.exists())
            self.assertIn("set org.gnome.system.proxy mode none", (root / "gsettings.log").read_text())

    def test_supervisor_refuses_old_awg_selection_before_changing_routes(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(tunnel, "STATE", Path(directory)), \
             patch.object(tunnel, "run") as run:
            (Path(directory) / "selected.json").write_text(json.dumps({"kind": "awg", "name": "mosk"}))
            with self.assertRaises(ValueError):
                tunnel.serve()
            run.assert_not_called()

    def test_split_presets_replace_previous_rules(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(tunnel, "STATE", Path(directory)), \
             patch.object(tunnel.os, "geteuid", return_value=0), \
             patch.object(tunnel, "run", return_value=SimpleNamespace(returncode=1)):
            for command, expected in (("on", {"default": "direct", "apps": {"chromium": "vpn"}}),
                                      ("off", {"default": "vpn", "apps": {}})):
                with patch.object(sys, "argv", ["pino-tunnel", "split", command]):
                    self.assertEqual(tunnel.main(), 0)
                self.assertEqual(json.loads((Path(directory) / "split.json").read_text()), expected)
            regex = tunnel.app_rule("chromium", "vpn")["process_path_regex"][0]
            self.assertRegex("/nix/store/hash-chromium-unwrapped/libexec/chromium/chromium", regex)

    def test_split_short_commands_update_default(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(tunnel, "STATE", Path(directory)), \
             patch.object(tunnel.os, "geteuid", return_value=0), \
             patch.object(tunnel, "run", return_value=SimpleNamespace(returncode=1)):
            for value in ("direct", "vpn"):
                with patch.object(sys, "argv", ["pino-tunnel", "split", value]):
                    self.assertEqual(tunnel.main(), 0)
                self.assertEqual(json.loads((Path(directory) / "split.json").read_text())["default"], value)

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
        self.assertEqual(config["inbounds"][0]["dns_mode"], "disabled")
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

    def test_profile_dns_only_used_for_full_awg_vpn(self):
        full = {"default": "vpn", "apps": {}}
        split = {"default": "vpn", "apps": {"firefox": "direct"}}
        dns_rule = lambda kind, policy, dns: next(rule["outbound"] for rule in tunnel.router_config(kind, "halos", "eth0", policy, dns)["route"]["rules"] if rule.get("port") == 53)
        self.assertEqual(dns_rule("awg", full, True), "vpn")
        self.assertEqual(dns_rule("awg", full, False), "direct")
        self.assertEqual(dns_rule("awg", split, True), "direct")
        self.assertEqual(dns_rule("xray", full, True), "direct")
        profile = "[Interface]\nDNS = 10.77.0.1\n[Peer]\nAllowedIPs = 0.0.0.0/0\n"
        self.assertTrue(tunnel.has_profile_dns(profile))
        self.assertNotIn("DNS =", tunnel.awg_config(profile, use_profile_dns=False))
        self.assertIn("DNS =", tunnel.awg_config(profile))

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
