import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProvisionHostTests(unittest.TestCase):
    def run_host(self, *args, missing=""):
        source = (ROOT / "modules/pino/bitwarden.sh").read_text()
        source = source.replace("@configDir@", "/fixture")
        source = source.replace("@declaredCount@", "0")
        source = source.replace("@declaredSecrets@", ":").replace("@afterDeclared@", ":")
        mocks = '''
nix() {
  printf '%s' '[{"item":"first","target":"/etc/first","units":["one.service","two.service"]},{"item":"second","target":"/etc/second","units":[]}]'
}
bw() {
  case "$1" in
    sync) return 0 ;;
    get)
      [ "$3" != "$MISSING" ] || return 1
      printf '%s' '{"type":2,"notes":"synthetic fixture"}' ;;
    *) return 99 ;;
  esac
}
pino() { printf 'SEND'; printf ' <%s>' "$@"; printf '\\n'; }
'''
        return subprocess.run(
            ["bash", "-c", mocks + source, "fixture", "host", *args],
            env=dict(os.environ, BW_SESSION="synthetic", MISSING=missing),
            capture_output=True, text=True,
        )

    def test_sends_declared_paths_and_all_units_to_alias(self):
        result = self.run_host("mosk")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("<first> <mosk> </etc/first> <one.service> <two.service>", result.stdout)
        self.assertIn("<second> <mosk> </etc/second>", result.stdout)
        self.assertNotIn("synthetic fixture", result.stdout)

    def test_target_override(self):
        result = self.run_host("halos", "vincent@192.0.2.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("<vincent@192.0.2.1>", result.stdout)

    def test_missing_note_prevents_all_sends(self):
        result = self.run_host("mosk", missing="second")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("SEND", result.stdout)

    def test_rejects_unknown_host_and_option_target(self):
        for args in [("unknown",), ("mosk", "-oProxyCommand=bad")]:
            with self.subTest(args=args):
                result = self.run_host(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("SEND", result.stdout)
