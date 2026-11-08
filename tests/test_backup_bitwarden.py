import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("backup_bitwarden", Path(__file__).resolve().parents[1] / "scripts/backup-bitwarden.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


def encrypted():
    return json.dumps({"encrypted": True, "passwordProtected": True, "salt": "fixture",
                       "kdfType": 0, "kdfIterations": 600000,
                       "encKeyValidation_DO_NOT_EDIT": "fixture", "data": "ciphertext"}).encode()


class BackupBitwardenTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.target = self.root / "pino/bitwarden/vault.encrypted.json"
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b"previous")

    def test_publish_replaces_only_with_portable_ciphertext(self):
        backup.publish(self.target, encrypted())
        self.assertEqual(self.target.read_bytes(), encrypted())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.target.parent.iterdir()), [self.target])

    def test_bad_export_preserves_previous(self):
        for content in (b"invalid", b'{"items": []}', b'{"encrypted": true}',
                        b'{"encrypted": true, "passwordProtected": true}'):
            with self.subTest(content=content), self.assertRaises(ValueError):
                backup.publish(self.target, content)
            self.assertEqual(self.target.read_bytes(), b"previous")

    def test_failed_atomic_replace_preserves_previous_and_cleans_temp(self):
        with patch.object(backup.os, "replace", side_effect=OSError), self.assertRaises(OSError):
            backup.publish(self.target, encrypted())
        self.assertEqual(self.target.read_bytes(), b"previous")
        self.assertEqual(list(self.target.parent.iterdir()), [self.target])

    def test_missing_kdf_parameters_preserve_previous(self):
        base = json.loads(encrypted())
        variants = [dict(base, kdfType=1), dict(base, kdfIterations=0), dict(base, kdfType=True)]
        del base['kdfIterations']
        variants.append(base)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(ValueError):
                backup.publish(self.target, json.dumps(value).encode())
            self.assertEqual(self.target.read_bytes(), b'previous')

    def test_argon2_export_requires_all_kdf_parameters(self):
        value = dict(json.loads(encrypted()), kdfType=1, kdfIterations=3,
                     kdfMemory=64, kdfParallelism=4)
        backup.publish(self.target, json.dumps(value).encode())
        self.assertEqual(json.loads(self.target.read_bytes()), value)

    def test_symlink_refused(self):
        link = self.root / "alias"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            backup.publish(link / "pino/bitwarden/vault.encrypted.json", encrypted())

    def test_cancel_does_not_export_or_replace(self):
        with patch.object(backup, "vault_json", side_effect=[[], []]), \
                patch.object(backup, "run_bw") as run, \
                patch.object(backup, "confirm", return_value=False):
            backup.backup(self.root, {"BW_SESSION": "fixture"})
        self.assertEqual([call.args[0] for call in run.call_args_list], [["sync"]])
        self.assertEqual(self.target.read_bytes(), b"previous")

    def test_exclusions_require_ack_and_password_is_never_argument(self):
        with patch.object(backup, "vault_json", side_effect=[[
                {"organizationId": "fixture", "attachments": [{}]}], [{}]]), \
                patch.object(backup, "run_bw", side_effect=[b"", encrypted()]) as run, \
                patch.object(backup, "confirm", return_value=True) as confirm:
            backup.backup(self.root, {"BW_SESSION": "fixture"})
        self.assertEqual(confirm.call_count, 2)
        self.assertEqual(run.call_args.args[0], ["export", "--format", "encrypted_json", "--password", "--raw"])
        self.assertTrue(run.call_args.kwargs["interactive"])
        self.assertEqual(self.target.read_bytes(), encrypted())


if __name__ == "__main__":
    unittest.main()
