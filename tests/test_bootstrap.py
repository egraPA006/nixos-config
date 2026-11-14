import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BootstrapKexecTests(unittest.TestCase):
    def test_low_memory_installer_enables_temporary_swap(self):
        source = (ROOT / "scripts/server-stage.sh").read_text()
        block = source.split("swap_file=/mnt/.pino-install.swap", 1)[1].split('if [ -n "$ssh_key_file" ]', 1)[0]
        script = '''
set -eu
awk() { case "$1" in *MemTotal*) echo 2000000;; *SwapTotal*) echo 0;; *) echo 8000000;; esac; }
df() { echo fixture; }
fallocate() { echo allocated; }
chmod() { :; }
mkswap() { :; }
swapon() { echo enabled; }
swap_file="$SWAP_TEST_ROOT/.pino-install.swap"
''' + block + '\n[ "$created_swap" = true ]\n'
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["bash", "-c", script], env=dict(os.environ, SWAP_TEST_ROOT=directory), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("allocated", result.stdout)
        self.assertIn("enabled", result.stdout)

    def test_hardware_is_transferred_without_git_mutations(self):
        source = (ROOT / "modules/pino/bootstrap.sh").read_text()
        self.assertNotIn('git -C "$BOOTSTRAP_CONFIG_DIR" commit', source)
        self.assertNotIn('git -C "$BOOTSTRAP_CONFIG_DIR" push', source)
        self.assertIn('scp_to "$hardware_tmp" "$installer_target:/root/nixos-config/hosts/$host/hardware.nix"', source)

    def test_installer_receives_committed_archive_without_downloading_git(self):
        source = (ROOT / "modules/pino/bootstrap.sh").read_text()
        self.assertIn('git -C "$BOOTSTRAP_CONFIG_DIR" archive --format=tar.gz', source)
        self.assertIn('tar -xzf /tmp/pino-config.tar.gz -C /root/nixos-config', source)
        self.assertNotIn("#git' --command", source)
        self.assertIn("git reset --mixed '$install_revision'", source)

    def test_low_installer_memory_aborts_before_disk_changes(self):
        source = (ROOT / "modules/pino/bootstrap.sh").read_text()
        block = source.split('available_kib="$(ssh_to', 1)[1].split('\necho "Refreshing', 1)[0]
        block = 'available_kib="$(ssh_to' + block
        prefix = 'installer_target=fixture\nssh_to() { printf "%s\\n" "$AVAILABLE"; }\n'
        for available, expected in (("151688", 1), ("800000", 0), ("bad", 1)):
            result = subprocess.run(["bash", "-c", prefix + block],
                                    env=dict(os.environ, AVAILABLE=available), capture_output=True, text=True)
            self.assertEqual(result.returncode, expected)

    def test_note_preflight_rejects_ambiguous_records(self):
        source = (ROOT / "modules/pino/bootstrap.sh").read_text()
        function = source.split("check_note() {", 1)[1].split("\n}\n", 1)[0]
        script = '''
check_note() {
''' + function + '''
}
bw() { printf '%s' "$FIXTURE"; }
check_note wanted
'''
        import json
        note = {"name": "wanted", "type": 2, "notes": "fixture"}
        for records, expected in (([note], 0), ([note, note], 1), ([], 1)):
            result = subprocess.run(["bash", "-c", script],
                                    env=dict(os.environ, FIXTURE=json.dumps(records)),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, expected)
            self.assertNotIn("fixture", result.stdout)

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
