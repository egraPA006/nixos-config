import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("clashmi_profile", Path(__file__).resolve().parents[1] / "scripts/clashmi-profile.py")
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class ClashMiProfileTests(unittest.TestCase):
    def test_sync_preserves_other_profiles_and_updates_subscription(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            secret = home / ".config/pino/clashmi-subscription"
            secret.parent.mkdir(parents=True)
            secret.write_text("https://example.test/subscription-a\n")
            target = home / ".local/share/com.nebula.clashmi/profiles.json"
            target.parent.mkdir(parents=True)
            target.write_text(json.dumps({"current_id": "existing.yaml", "profiles": [{"id": "existing.yaml"}]}))
            profile.sync(home)
            data = json.loads(target.read_text())
            self.assertEqual(data["current_id"], "existing.yaml")
            self.assertEqual(len(data["profiles"]), 2)
            self.assertEqual(data["profiles"][1]["url"], "https://example.test/subscription-a")
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            secret.write_text("https://example.test/subscription-b\n")
            profile.sync(home)
            data = json.loads(target.read_text())
            self.assertEqual(len(data["profiles"]), 2)
            self.assertEqual(data["profiles"][1]["url"], "https://example.test/subscription-b")

    def test_invalid_subscription_preserves_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            secret = home / ".config/pino/clashmi-subscription"
            secret.parent.mkdir(parents=True)
            secret.write_text("not a url")
            with self.assertRaises(ValueError):
                profile.sync(home)
            self.assertFalse((home / ".local/share/com.nebula.clashmi/profiles.json").exists())


if __name__ == "__main__":
    unittest.main()
