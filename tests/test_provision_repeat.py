import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RepeatProvisionTests(unittest.TestCase):
    def provision(self, target, active=True, restart_ok=True):
        source = (Path(__file__).resolve().parents[1] / "modules/pino/bitwarden.sh").read_text()
        functions = source.split('operation="${1:-}"', 1)[0].replace("@cmp@", "cmp")
        mock = '''
stream_note() { printf '%s\\n' 'synthetic fixture'; }
sudo() {
  case "$1" in
    chown) return 0 ;;
    systemctl)
      if [ "$2" = is-active ]; then
        [ "$ACTIVE" = yes ] || [ "$4" = fixture.service ]
      else
        printf 'RESTART\\n'
        [ "$RESTART_OK" = yes ]
      fi ;;
    *) "$@" ;;
  esac
}
install_note fixture "$TARGET" fixture.service dependent.service
'''
        return subprocess.run(["bash", "-c", functions + mock],
                              env=dict(os.environ, TARGET=str(target),
                                       ACTIVE="yes" if active else "no",
                                       RESTART_OK="yes" if restart_ok else "no"),
                              capture_output=True, text=True)

    def test_failed_restart_is_retried_even_when_secret_already_matches(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "secret"
            first = self.provision(target, active=False, restart_ok=False)
            self.assertNotEqual(first.returncode, 0)
            self.assertTrue(target.is_file())
            before = target.stat().st_mtime_ns
            again = self.provision(target, active=False)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(again.stdout.count("RESTART"), 1)
            self.assertEqual(target.stat().st_mtime_ns, before)

    def test_unchanged_secret_with_failed_service_is_not_reported_ready(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "secret"
            target.write_text("synthetic fixture\n")
            result = self.provision(target, active=False, restart_ok=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("Already provisioned", result.stdout)

    def test_unchanged_secret_repairs_permissions_without_restart(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "secret"
            target.write_text("synthetic fixture\n")
            target.chmod(0o644)
            before = target.stat().st_mtime_ns
            result = self.provision(target)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("RESTART", result.stdout)
            self.assertNotIn("synthetic fixture", result.stdout + result.stderr)
            self.assertEqual(target.stat().st_mtime_ns, before)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_symlink_destination_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = root / "original"
            original.write_text("unchanged")
            target = root / "secret"
            target.symlink_to(original)
            result = self.provision(target)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(original.read_text(), "unchanged")
            self.assertNotIn("RESTART", result.stdout)


if __name__ == "__main__":
    unittest.main()
