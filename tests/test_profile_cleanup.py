import copy
import importlib.util
import os
from pathlib import Path
import shlex
import subprocess
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cleanup", ROOT / "scripts/profile-cleanup.py")
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pino-cleanup-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.config = self.home / "config"
        self.music = self.home / "music full"
        self.installs = self.music / "installs"
        self.shared = self.home / "shared"
        self.manifest = {
            "profiles": ["music-full", "guitar-pro"],
            "protected": [str(self.home), str(self.config)],
            "keep": [str(self.installs)],
            "resources": [
                {"owners": ["music-full"], "paths": [str(self.music)]},
                {"owners": ["music-full", "guitar-pro"], "paths": [str(self.shared)]},
            ],
        }

    def touch(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("fixture")

    def apply(self, remaining=()):
        _, paths, keep = cleanup.plan(self.manifest, "music-full", remaining, str(self.config))
        for path in paths:
            cleanup.remove(path, keep)

    def test_preserves_artifacts_removes_plugins_settings_and_old_prefixes(self):
        artifacts = [self.installs / "setup.exe", self.installs / "library/samples.wav"]
        installed = [self.music / "wine-prefix/old.dll", self.music / "wine-prefix-new/new.dll",
                     self.music / "installed/stamp", self.music / "plugins/win/plugin.dll"]
        for path in artifacts + installed:
            self.touch(path)
        self.apply()
        self.assertTrue(all(path.exists() for path in artifacts))
        self.assertTrue(all(not path.exists() for path in installed))
        self.apply()  # Retrying cleanup is harmless.

    def test_shared_state_waits_for_last_owner(self):
        state = self.shared / "state"
        self.touch(state)
        self.apply(["guitar-pro"])
        self.assertTrue(state.exists())
        self.apply()
        self.assertFalse(self.shared.exists())

    def test_does_not_follow_symlinks_or_delete_external_library(self):
        outside = self.root / "library/sample.wav"
        self.touch(outside)
        self.music.mkdir(parents=True)
        (self.music / "linked-library").symlink_to(outside.parent, target_is_directory=True)
        (self.music / "broken-link").symlink_to(self.root / "absent")
        self.apply()
        self.assertTrue(outside.exists())
        self.assertFalse(self.music.exists())

    def test_rejects_home_config_and_artifact_roots(self):
        for path in [self.home, self.config, self.installs, self.installs / "setup.exe", Path("/")]:
            with self.subTest(path=path):
                manifest = copy.deepcopy(self.manifest)
                manifest["resources"][0]["paths"] = [str(path)]
                with self.assertRaises(ValueError):
                    cleanup.plan(manifest, "music-full", [], str(self.config))

    def test_rejects_overlap_with_other_profile(self):
        self.manifest["resources"].append({"owners": ["guitar-pro"], "paths": [str(self.music / "other")]})
        with self.assertRaises(ValueError):
            self.apply(["guitar-pro"])

    def test_rejects_parent_symlink_to_protected_directory(self):
        alias = self.root / "alias"
        self.config.mkdir(parents=True)
        alias.symlink_to(self.home, target_is_directory=True)
        self.manifest["resources"][0]["paths"] = [str(alias / "config")]
        with self.assertRaises(ValueError):
            self.apply()

    def test_refuses_enabled_unknown_or_relative_targets(self):
        for name, remaining in [("unknown", []), ("music-full", ["music-full"]), ("music-full", ["unknown"])]:
            with self.assertRaises(ValueError):
                cleanup.plan(self.manifest, name, remaining, str(self.config))
        self.manifest["resources"][0]["paths"] = ["relative/path"]
        with self.assertRaises(ValueError):
            self.apply()

    def test_forbids_system_tree_children(self):
        self.manifest["forbiddenTrees"] = ["/nix", "/proc"]
        for path in ["/nix/store/example", "/proc/1"]:
            self.manifest["resources"][0]["paths"] = [path]
            with self.assertRaises(ValueError):
                self.apply()

    def test_mounts_are_rejected_except_preserved_artifacts(self):
        mount = str(self.music / "mounted").replace(" ", r"\040")
        entry = f"1 0 8:1 / {mount} rw - ext4 /dev/example rw\n"
        with patch.object(Path, "read_text", return_value=entry):
            with self.assertRaises(ValueError):
                cleanup.check_mounts([self.music], [self.installs])
            cleanup.check_mounts([self.music], [self.music / "mounted"])


class WineCleanupTests(unittest.TestCase):
    def run_stop(self, codes):
        manifest = {
            "configHome": "/home/test/.config", "dataHome": "/home/test/.local/share",
            "cacheHome": "/home/test/.cache",
            "tools": {"env": "env", "timeout": "timeout", "wineserver": "wineserver"},
        }
        account = SimpleNamespace(pw_dir="/home/test", pw_name="test", pw_uid=os.getuid())
        results = [subprocess.CompletedProcess([], code) for code in codes]
        with patch.object(cleanup.subprocess, "run", side_effect=results) as run:
            cleanup.stop_wine(manifest, account, "/tmp/test-prefix")
            self.assertEqual([call.args[0][-1] for call in run.call_args_list], ["-k", "-w"])

    def test_already_stopped_server_still_checks_wait(self):
        self.run_stop([1, 0])

    def test_running_server_stops_and_waits(self):
        self.run_stop([0, 0])

    def test_wait_error_or_timeout_blocks_cleanup(self):
        for status in (1, 124):
            with self.subTest(status=status), self.assertRaises(subprocess.CalledProcessError):
                self.run_stop([1, status])

    def test_kill_timeout_blocks_cleanup(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_stop([124])


class ProfileCommandTests(unittest.TestCase):
    def run_scenario(self, rebuild_fails=False, check_fails=False, cleanup_fails=False, enabled=True):
        with tempfile.TemporaryDirectory(prefix="pino-disable-") as temporary:
            root = Path(temporary)
            config = root / "config"
            profiles = config / "hosts/test-host/active-profiles.nix"
            profiles.parent.mkdir(parents=True)
            initial = '[ "music-full" "guitar-pro" ]\n' if enabled else '[ "guitar-pro" ]\n'
            profiles.write_text(initial)
            log = root / "events"
            binary = root / "bin"
            binary.mkdir()
            scripts = {
                "hostname": "echo test-host",
                "sudo": 'exec "$@"',
                "nixos-rebuild": f"echo rebuild >> {shlex.quote(str(log))}\nexit {int(rebuild_fails)}",
                "cleanup": f'''echo "$*" >> {shlex.quote(str(log))}
case "$1" in check) exit {int(check_fails)} ;; apply) exit {int(cleanup_fails)} ;; esac''',
            }
            for name, body in scripts.items():
                target = binary / name
                target.write_text("#!/bin/sh\n" + body + "\n")
                target.chmod(0o755)
            source = (ROOT / "modules/pino/profile.sh").read_text()
            for key, value in {
                "@validProfiles@": "music-full guitar-pro",
                "@profileDescriptions@": "Music Guitar", "@profileGroups@": "desktop:music-full,guitar-pro",
                "@configDir@": str(config), "@cleanup@": shlex.quote(str(binary / "cleanup")),
            }.items():
                source = source.replace(key, value)
            script = root / "profile.sh"
            script.write_text("set -euo pipefail\n" + source)
            env = dict(os.environ, PATH=str(binary) + ":" + os.environ["PATH"])
            env.pop("NIXOS_CONFIG_DIR", None)
            result = subprocess.run(["bash", str(script), "disable", "music-full"], env=env, capture_output=True, text=True)
            failed = rebuild_fails or check_fails or cleanup_fails
            self.assertEqual(result.returncode != 0, failed, result.stderr)
            events = log.read_text().splitlines()
            self.assertTrue(events[0].startswith("check music-full "))
            self.assertTrue(events[0].endswith(" guitar-pro"))
            if check_fails or rebuild_fails:
                self.assertFalse(any(e.startswith("apply ") for e in events))
                self.assertEqual(profiles.read_text(), initial)
            else:
                self.assertTrue(events[-1].startswith("apply music-full "))
                self.assertNotIn('"music-full"', profiles.read_text())
            self.assertEqual("rebuild" in events, enabled and not check_fails)

    def test_success(self):
        self.run_scenario()

    def test_rebuild_failure_preserves_data_and_profile_file(self):
        self.run_scenario(rebuild_fails=True)

    def test_preflight_failure_does_not_rebuild(self):
        self.run_scenario(check_fails=True)

    def test_failed_cleanup_reports_failure_without_reenabling(self):
        self.run_scenario(cleanup_fails=True)

    def test_retry_already_disabled(self):
        self.run_scenario(enabled=False)


if __name__ == "__main__":
    unittest.main()
