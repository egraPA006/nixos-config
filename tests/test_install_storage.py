"""Exercise destructive storage planning using regular files and fake commands only."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StorageTests(unittest.TestCase):
    def run_partition(self, keep=True, answer="erase re-1\n", label="pino-fast", duplicate=False, mounted=""):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binaries = root / "bin"
            binaries.mkdir()
            disks = [root / name for name in ("system", "fast", "slow")]
            for disk in disks:
                disk.touch()
            calls = root / "calls"
            stub = binaries / "stub"
            stub.write_text('''#!/usr/bin/env bash
set -eu
name="${0##*/}"
case "$name" in
  id) echo 0 ;;
  findmnt)
    if [ -n "$MOUNTED" ] && [[ "${!#}" == *"$MOUNTED" ]]; then exit 0; fi
    exit 1 ;;
  lsblk)
    disk="${!#}"
    case "$*" in
      "-dnro TYPE "*) echo disk ;;
      "-dnro FSTYPE "*) echo ext4 ;;
      "-dnro LABEL "*)
        case "$disk" in *fast1) echo "$FAST_LABEL" ;; *slow1) echo pino-slow ;; esac ;;
      "-nrpo NAME,PARTLABEL "*)
        case "$disk" in
          *system) printf '%s1 pino-boot\\n%s2 pino-root\\n' "$disk" "$disk" ;;
          *fast) echo "$disk"1 pino-fast ;;
          *slow) echo "$disk"1 pino-slow ;;
        esac ;;
      "-nrpo NAME "*) printf '%s\\n%s1\\n%s2\\n' "$disk" "$disk" "$disk" ;;
    esac ;;
  *) printf '%s %s\\n' "$name" "$*" >> "$CALLS" ;;
esac
''')
            stub.chmod(0o755)
            for name in ("id", "lsblk", "findmnt", "sgdisk", "wipefs", "partprobe", "udevadm",
                         "mkfs.vfat", "mkfs.ext4", "mount", "install"):
                (binaries / name).symlink_to(stub)
            # Keep all production control flow; substitute only block-device validation.
            source = (ROOT / "scripts/partition.sh").read_text().replace('[ -b "$disk" ]', '[ -f "$disk" ]')
            script = root / "partition.sh"
            script.write_text(source)
            args = ["bash", str(script), "re-1"] + (["--keep-data"] if keep else [])
            args.extend(str(disk) for disk in (disks if not duplicate else [disks[0], disks[0], disks[2]]))
            result = subprocess.run(args, input=answer, capture_output=True, text=True,
                                    env=dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                                             CALLS=str(calls), FAST_LABEL=label, MOUNTED=mounted))
            mutations = calls.read_text() if calls.exists() else ""
            return result, mutations, disks

    def test_keep_data_only_formats_system(self):
        result, calls, disks = self.run_partition()
        self.assertEqual(result.returncode, 0, result.stderr)
        for disk in disks[1:]:
            for line in calls.splitlines():
                if line.startswith(("wipefs ", "sgdisk ", "mkfs.")):
                    self.assertNotIn(str(disk), line)
        self.assertIn("mkfs.ext4 -F -L pino-root", calls)
        self.assertIn(f"mount -t ext4 -o noatime {disks[1]}1 /mnt/data/fast", calls)

    def test_fresh_formats_all_three(self):
        result, calls, _ = self.run_partition(keep=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mkfs.ext4 -F -L pino-fast", calls)
        self.assertIn("mkfs.ext4 -F -L pino-slow", calls)

    def test_invalid_filesystem_label_fails_before_wipe(self):
        result, calls, _ = self.run_partition(label="wrong")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_cancel_changes_nothing(self):
        result, calls, _ = self.run_partition(answer="no\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_duplicate_disks_rejected(self):
        result, calls, _ = self.run_partition(duplicate=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_mounted_first_partition_refused_even_if_last_unmounted(self):
        result, calls, _ = self.run_partition(mounted="system1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_mounted_whole_disk_refused(self):
        result, calls, _ = self.run_partition(mounted="system")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")
