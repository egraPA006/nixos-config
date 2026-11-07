import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("artifacts", Path(__file__).resolve().parents[1] / "scripts/artifacts.py")
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "external"
        self.folder = self.source / "music-full"
        self.folder.mkdir(parents=True)
        (self.folder / "setup.exe").write_bytes(b"installer fixture")
        self.target = self.root / "local"
        self.manifest = {"music-full": {"target": str(self.target)}}

    def test_import_and_retry_preserve_extra_files(self):
        files = artifacts.plan(self.manifest, self.source)
        self.assertFalse(self.target.exists())
        artifacts.copy_files(files)
        self.assertEqual((self.target / "setup.exe").read_bytes(), b"installer fixture")
        (self.target / "extra").write_text("keep")
        self.assertEqual(artifacts.plan(self.manifest, self.source), [])
        self.assertTrue((self.target / "extra").exists())

    def test_conflict_aborts_before_any_copy(self):
        self.target.mkdir()
        (self.folder / "aaa.exe").write_bytes(b"new")
        (self.target / "setup.exe").write_bytes(b"different")
        with self.assertRaises(ValueError):
            artifacts.plan(self.manifest, self.source)
        self.assertFalse((self.target / "aaa.exe").exists())

    def test_missing_folder_or_mount(self):
        with patch.object(artifacts.os.path, "ismount", return_value=False):
            self.manifest["music-full"]["requiredMount"] = "/data/fast"
            with self.assertRaises(ValueError):
                artifacts.plan(self.manifest, self.source)
        self.manifest["music-full"].pop("requiredMount")
        self.manifest["guitar-pro"] = {"target": str(self.root / "guitar")}
        with self.assertRaises(ValueError):
            artifacts.plan(self.manifest, self.source)
        self.assertFalse(self.target.exists())

    def test_symlinks_on_either_side_are_rejected(self):
        link = self.folder / "link"
        link.symlink_to(self.folder / "setup.exe")
        with self.assertRaises(ValueError):
            artifacts.plan(self.manifest, self.source)
        link.unlink()
        self.target.symlink_to(self.folder, target_is_directory=True)
        with self.assertRaises(ValueError):
            artifacts.plan(self.manifest, self.source)

    def test_source_changed_after_preflight(self):
        files = artifacts.plan(self.manifest, self.source)
        (self.folder / "setup.exe").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            artifacts.copy_files(files)
        self.assertFalse((self.target / "setup.exe").exists())

    def test_concurrent_destination_is_not_replaced(self):
        files = artifacts.plan(self.manifest, self.source)
        self.target.mkdir()
        (self.target / "setup.exe").write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            artifacts.copy_files(files)
        self.assertEqual((self.target / "setup.exe").read_bytes(), b"keep")
