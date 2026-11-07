import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BootstrapKexecTests(unittest.TestCase):
    def run_boot(self, first=0, fallback=0, transport=0, extract=0):
        source = (ROOT / "modules/pino/bootstrap.sh").read_text()
        block = source.split('  echo "Booting the RAM installer;', 1)[1]
        block = block[block.index("  set +e"):].split("\nfi\n", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "kexec").mkdir()
            runner = root / "kexec/run"
            runner.write_text(
                '#!/bin/sh\n'
                'echo "run $*" >> "$CALLS"\n'
                'if [ "$#" = 0 ]; then exit "$FIRST"; fi\n'
                'exit "$FALLBACK"\n'
            )
            runner.chmod(0o755)
            calls = root / "calls"
            env = dict(os.environ, remote_kexec_dir=directory,
                       CALLS=str(calls), FIRST=str(first), FALLBACK=str(fallback),
                       TRANSPORT=str(transport), EXTRACT=str(extract))
            result = subprocess.run(
                ["bash", "-c", '''
set -eu
initial_target=fixture
elevate=
tar() { echo extract >> "$CALLS"; return "$EXTRACT"; }
ssh_to() {
  if [ "$TRANSPORT" != 0 ]; then return "$TRANSPORT"; fi
  shift
  ( eval "$1" )
}
''' + block], env=env, capture_output=True, text=True,
            )
            return result.returncode, calls.read_text().splitlines() if calls.exists() else []

    def test_success_does_not_retry(self):
        self.assertEqual(self.run_boot(), (0, ["run "]))

    def test_load_failure_restores_archive_and_retries(self):
        self.assertEqual(self.run_boot(first=1),
                         (0, ["run ", "extract", "run --kexec-extra-flags --kexec-syscall"]))

    def test_fallback_failure_aborts(self):
        status, calls = self.run_boot(first=1, fallback=1)
        self.assertEqual(status, 1)
        self.assertEqual(len(calls), 3)

    def test_archive_failure_aborts_before_retry(self):
        self.assertEqual(self.run_boot(first=1, extract=1), (1, ["run ", "extract"]))

    def test_disconnect_does_not_retry(self):
        self.assertEqual(self.run_boot(transport=255), (0, []))
