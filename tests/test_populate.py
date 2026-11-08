import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


populate = load("populate", "populate.py")
assetto = load("assetto_populate", "assetto-corsa.py")


class PopulateTests(unittest.TestCase):
    def run_populate(self, config, results, **kwargs):
        calls = []

        def runner(command):
            calls.append(command)
            return results.get(tuple(command), 0)

        with contextlib.redirect_stdout(io.StringIO()):
            status = populate.populate(config, runner=runner, **kwargs)
        return status, calls

    def test_pending_app_does_not_block_ready_app(self):
        config = {"provision": False, "artifacts": False, "steps": {
            "assetto": {"prerequisite": "check-game", "command": ["game-setup"]},
            "music": {"command": ["music-setup"]},
        }}
        status, calls = self.run_populate(config, {("check-game",): 2})
        self.assertEqual(status, 2)
        self.assertEqual(calls, [["check-game"], ["music-setup"]])
        status, calls = self.run_populate(config, {})
        self.assertEqual(status, 0)
        self.assertIn(["game-setup"], calls)

    def test_failed_vault_and_incomplete_import_do_not_block_local_apps(self):
        config = {"provision": True, "artifacts": True, "steps": {"app": {"command": ["install"]}}}
        status, calls = self.run_populate(config, {
            ("pino", "os", "provision", "install"): 1,
            ("pino", "restore", "artifacts", "/disk"): 2,
        }, disk=Path("/disk"))
        self.assertEqual(status, 1)
        self.assertEqual(calls[-1], ["install"])

    def test_server_without_disk_provisions_only(self):
        config = {"provision": True, "artifacts": False, "steps": {}}
        status, calls = self.run_populate(config, {})
        self.assertEqual((status, calls), (0, [["pino", "os", "provision", "install"]]))

    def test_missing_mount_prevents_application_writes(self):
        config = {"provision": False, "artifacts": False, "steps": {
            "app": {"requiredMount": "/data/fast", "command": ["install"]}}}
        with patch.object(populate.os.path, "ismount", return_value=False):
            status, calls = self.run_populate(config, {})
        self.assertEqual((status, calls), (2, []))

    def test_graphical_setup_is_pending_in_ssh_session(self):
        config = {"provision": False, "artifacts": False, "steps": {
            "app": {"requiresSession": True, "command": ["install"]}}}
        with patch.dict(os.environ, {}, clear=True):
            status, calls = self.run_populate(config, {})
        self.assertEqual((status, calls), (2, []))

    def test_failed_check_is_not_reported_as_pending(self):
        config = {"provision": False, "artifacts": False, "steps": {
            "app": {"prerequisite": "broken-check", "command": ["install"]}}}
        status, calls = self.run_populate(config, {("broken-check",): 1})
        self.assertEqual((status, calls), (1, [["broken-check"]]))

    def test_skip_vault_is_explicit_and_does_not_prompt(self):
        config = {"provision": True, "artifacts": False, "steps": {}}
        status, calls = self.run_populate(config, {}, skip_secrets=True)
        self.assertEqual((status, calls), (0, []))


class AssettoPrerequisiteTests(unittest.TestCase):
    def test_missing_game_is_action_required_without_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with contextlib.redirect_stdout(io.StringIO()) as output:
                result = assetto.check_populate({"gameDir": str(root / "game")})
            self.assertEqual(result, 2)
            self.assertIn("Install Assetto Corsa", output.getvalue())
            self.assertEqual(list(root.iterdir()), [])

    def test_first_game_launch_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            game = Path(temporary) / "steamapps/common/assettocorsa"
            game.mkdir(parents=True)
            (game / "acs.exe").touch()
            with contextlib.redirect_stdout(io.StringIO()) as output:
                result = assetto.check_populate({"gameDir": str(game)})
            self.assertEqual(result, 2)
            self.assertIn("launch the game once", output.getvalue())


if __name__ == "__main__":
    unittest.main()
