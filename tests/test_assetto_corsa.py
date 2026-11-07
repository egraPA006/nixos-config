import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile


spec = importlib.util.spec_from_file_location("assetto", Path(__file__).resolve().parents[1] / "scripts/assetto-corsa.py")
assetto = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assetto)


class AssettoTests(unittest.TestCase):
    def test_cm_transparency_preserves_other_records_and_file_mode(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "Values.data"
            plain = b"version: 2\nother\tunchanged\\nvalue\nappearance_disallowTransparency\tFalse\nlast\tkeep"
            # LZF literal blocks, as used by CM's storage writer.
            encoded = b"\x0b" + b"".join(bytes([len(plain[i:i+32])-1]) + plain[i:i+32]
                                         for i in range(0, len(plain), 32))
            path.write_bytes(encoded)
            path.chmod(0o600)
            assetto.cm_disable_transparency(path)
            self.assertEqual(assetto.decode_cm_storage(path.read_bytes()),
                             plain.replace(b"Transparency\tFalse", b"Transparency\tTrue"))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            first = path.read_bytes()
            assetto.cm_disable_transparency(path)
            self.assertEqual(path.read_bytes(), first)
            self.assertEqual(list(Path(folder).iterdir()), [path])

    def test_cm_lzf_backreferences_and_malformed_storage(self):
        self.assertEqual(assetto.decode_cm_storage(b"\x0b\x02abc\x80\x02"), b"abcabcabc")
        for data in (b"\x0b\x20\xff", b"\x0b\x05ab", b"\x0b\xe0"):
            with self.assertRaises(ValueError):
                assetto.decode_cm_storage(data)

    def test_cm_extended_physics_preserves_unrelated_preferences(self):
        path = self.root / "Values.data"
        path.write_bytes(b"version: 2\nother\tkeep\nCarObject:bmw_z4:UseExtendedPhysics\t0")
        path.chmod(0o600)
        assetto.cm_enable_settings(path, ["CarObject:bmw_z4:UseExtendedPhysics"])
        self.assertEqual(assetto.decode_cm_storage(path.read_bytes()),
                         b"version: 2\nother\tkeep\nCarObject:bmw_z4:UseExtendedPhysics\t1")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            assetto.cm_enable_settings(path, ["CarObject:new:UseExtendedPhysics", "other\tbad"])
        self.assertEqual(path.read_bytes(), before)

    def test_cm_weather_controller_is_idempotent_and_rejects_record_injection(self):
        path = self.root / "Values.data"
        original = b"version: 2\nother\tkeep\n.wfx-ctr-base\tbase"
        path.write_bytes(original)
        assetto.cm_enable_settings(path, [], "pureCtrl static")
        self.assertEqual(assetto.decode_cm_storage(path.read_bytes()),
                         original.replace(b"\tbase", b"\tpureCtrl static"))
        before = path.read_bytes()
        assetto.cm_enable_settings(path, [], "pureCtrl static")
        self.assertEqual(path.read_bytes(), before)
        with self.assertRaises(ValueError):
            assetto.cm_enable_settings(path, [], "base\nother\tvalue")
        self.assertEqual(path.read_bytes(), before)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / "game"
        self.game.mkdir()
        self.state = self.root / "state"

    def test_road_tyres_reject_invalid_ids_and_disable_previous_configuration(self):
        writer = assetto.Writer(self.state)
        with self.assertRaises(ValueError):
            assetto.road_tyres({"roadTyreCompounds": {"bmw_z4": 0, "bad'name": 1}}, self.game, writer)
        self.assertFalse((self.game / "apps").exists())
        assetto.road_tyres({"roadTyreCompounds": {"bmw_z4": 0}}, self.game, writer)
        script = self.game / "apps/lua/PinoRoadTyres/PinoRoadTyres.lua"
        self.assertIn("['bmw_z4'] = 0", script.read_text())
        assetto.road_tyres({"roadTyreCompounds": {}}, self.game, writer)
        self.assertNotIn("bmw_z4", script.read_text())

    def archive(self, name, files):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as archive:
            for key, value in files.items():
                archive.writestr(key, value)
        return {"source": str(path), "sha256": assetto.digest(path)}

    def config(self):
        return {"contentManager": self.archive("cm.zip", {"Content Manager.exe": b"manager"}),
                "csp": None, "mods": []}

    def test_install_backup_idempotency_and_steam_repair(self):
        config = self.config()
        launcher = self.game / "AssettoCorsa.exe"
        launcher.write_bytes(b"original")
        writer = assetto.Writer(self.state)
        assetto.apply(config, self.game, self.state, writer)
        self.assertEqual(launcher.read_bytes(), b"manager")
        saved = writer.backup / str(launcher).lstrip("/")
        self.assertEqual(saved.read_bytes(), b"original")
        again = assetto.Writer(self.state)
        assetto.apply(config, self.game, self.state, again)
        self.assertEqual(again.changed, 0)
        launcher.write_bytes(b"steam repaired")
        assetto.apply(config, self.game, self.state, again)
        self.assertEqual(launcher.read_bytes(), b"manager")
        self.assertEqual(saved.read_bytes(), b"original")

    def test_bad_mod_does_not_replace_launcher(self):
        config = self.config()
        config["mods"] = [self.archive("bad.zip", {"../escape": b"bad"})]
        with self.assertRaises(ValueError):
            assetto.apply(config, self.game, self.state, assetto.Writer(self.state))
        self.assertFalse((self.game / "AssettoCorsa.exe").exists())

    def test_checksum_mismatch_does_not_write_game(self):
        config = self.config()
        config["contentManager"]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            assetto.apply(config, self.game, self.state, assetto.Writer(self.state))
        self.assertEqual(list(self.game.iterdir()), [])

    def test_reject_destination_symlink(self):
        (self.game / "content").symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            assetto.Writer(self.state).write(self.game, "content/escape", io.BytesIO(b"bad"))
        self.assertFalse((self.root / "escape").exists())

    def test_strip_prefix_and_track_destination(self):
        config = self.config()
        track = self.archive("track.zip", {"release/mytrack/data.ini": b"track", "readme": b"skip"})
        track.update(stripPrefix="release", destination="content/tracks")
        config["mods"] = [track]
        assetto.apply(config, self.game, self.state, assetto.Writer(self.state))
        self.assertEqual((self.game / "content/tracks/mytrack/data.ini").read_bytes(), b"track")
        self.assertFalse((self.game / "readme").exists())

    def test_discover_secondary_library_with_spaces(self):
        steamapps = self.root / ".local/share/Steam/steamapps"
        steamapps.mkdir(parents=True)
        library = self.root / "HDD Steam"
        game = library / "steamapps/common/assettocorsa"
        game.mkdir(parents=True)
        (game / "acs.exe").touch()
        (steamapps / "libraryfolders.vdf").write_text('"path" "' + str(library) + '"')
        found, prefix = assetto.discover(home=self.root)
        self.assertEqual(found, game)
        self.assertEqual(prefix, library / "steamapps/compatdata/244210/pfx")

    def test_graphics_preserves_resolution_and_filter(self):
        cfg = self.root / "drive_c/users/steamuser/Documents/Assetto Corsa/cfg"
        cfg.mkdir(parents=True)
        video = cfg / "video.ini"
        video.write_text("[VIDEO]\nWIDTH=2560\n[POST_PROCESS]\nFILTER=pure\n")
        assetto.graphics({"videoSettings": {"VIDEO": {"AASAMPLES": "4"}}},
                        self.root, assetto.Writer(self.state))
        self.assertIn("WIDTH=2560", video.read_text())
        self.assertIn("FILTER=pure", video.read_text())
        self.assertIn("AASAMPLES=4", video.read_text())

    def test_weather_settings_preserve_other_sections(self):
        root = self.root / "cfg"
        root.mkdir()
        (root / "weather.ini").write_text("[BASIC]\nENABLED=0\n[MISC]\nKEEP=1\n")
        assetto.merge_ini(root, "weather.ini", {"BASIC": {"IMPLEMENTATION": "Pure LCS"}},
                         assetto.Writer(self.state))
        self.assertIn("KEEP=1", (root / "weather.ini").read_text())
        self.assertIn("IMPLEMENTATION=Pure LCS", (root / "weather.ini").read_text())

    def test_named_presets_preserve_user_presets_and_reject_unsafe_names(self):
        prefix = self.root / "prefix"
        folder = prefix / "drive_c/users/steamuser/AppData/Local/AcTools Content Manager/Presets/Quick Drive"
        folder.mkdir(parents=True)
        personal = folder / "My setup.cmpreset"
        personal.write_text("personal")
        config = {"quickDrivePresets": {"Pino/Track": {"CarId": "car"}}}
        assetto.quick_drive_presets(config, prefix, assetto.Writer(self.state))
        self.assertTrue((folder / "Pino/Track.cmpreset").is_file())
        self.assertEqual(personal.read_text(), "personal")
        writer = assetto.Writer(self.state)
        assetto.quick_drive_presets(config, prefix, writer)
        self.assertEqual(writer.changed, 0)
        for names in ({"../escape": {}}, {"/absolute": {}}, {"Case": {}, "case": {}}):
            with self.assertRaises(ValueError):
                assetto.quick_drive_presets({"quickDrivePresets": names}, prefix, writer)

    def test_drift_settings_preserve_wheel_bindings_and_are_repeatable(self):
        prefix = self.root / "prefix"
        root = prefix / "drive_c/users/steamuser/Documents/Assetto Corsa/cfg"
        root.mkdir(parents=True)
        (root / "video.ini").write_text("[VIDEO]\nWIDTH=1920\n")
        controls = root / "controls.ini"
        controls.write_text("[STEER]\nJOY=0\nAXLE=0\n[GEARUP]\nBUTTON=13\n[SHIFTER]\nACTIVE=1\n")
        config = {"videoSettings": {}, "quickDrivePreset": {"CarId": "test-car"}, "settings": {
            "controls.ini": {"SHIFTER": {"ACTIVE": "0"}},
            "assists.ini": {"ASSISTS": {"AUTO_CLUTCH": "1"}},
            "extension/neck.ini": {"BASIC": {"ENABLED": "1"}},
        }}
        assetto.graphics(config, prefix, assetto.Writer(self.state))
        self.assertIn("BUTTON=13", controls.read_text())
        self.assertIn("AXLE=0", controls.read_text())
        self.assertIn("ACTIVE=0", controls.read_text())
        self.assertIn("AUTO_CLUTCH=1", (root / "assists.ini").read_text())
        preset = prefix / "drive_c/users/steamuser/AppData/Local/AcTools Content Manager/Presets/Quick Drive/Pino Drift.cmpreset"
        self.assertIn('"test-car"', preset.read_text())
        writer = assetto.Writer(self.state)
        assetto.graphics(config, prefix, writer)
        self.assertEqual(writer.changed, 0)

    def test_steam_discovery_link_preserves_existing_file(self):
        source = self.root / ".local/share/Steam/config/loginusers.vdf"
        source.parent.mkdir(parents=True)
        source.touch()
        prefix = self.root / "prefix"
        assetto.link_steam_users(prefix, self.root)
        target = prefix / "drive_c/Program Files (x86)/Steam/config/loginusers.vdf"
        self.assertEqual(target.resolve(), source)
        assetto.link_steam_users(prefix, self.root)
        target.unlink()
        target.write_text("existing")
        assetto.link_steam_users(prefix, self.root)
        self.assertEqual(target.read_text(), "existing")

    def steam_config(self, app='"244210" { "LaunchOptions" "old" }'):
        return ('"UserLocalConfigStore" { // preserve comment\n'
                '"Software" { "Valve" { "Steam" { "apps" { '
                '"123" { "LaunchOptions" "other game" } ' + app + ' } } } } '
                '"unrelated" "a\\\\b\\\"c" }')

    def test_existing_runtimes_do_not_run_wine(self):
        declared = ["dotnet48", "d3dcompiler_47", "d3dx11_43", "win10"]
        (self.root / "winetricks.log").write_text("remove_mono internal\n" + "\n".join(declared))
        with patch.object(assetto.subprocess, "run") as run:
            assetto.install_runtimes(self.root, declared)
            run.assert_not_called()

    def test_missing_dotnet_restores_windows_version_after_installation(self):
        log = self.root / "winetricks.log"
        log.write_text("d3dcompiler_47\nd3dx11_43\nwin10\n")
        declared = ["dotnet48", "d3dcompiler_47", "d3dx11_43", "win10"]
        with patch.object(assetto.subprocess, "run") as run:
            run.side_effect = lambda *args, **kwargs: log.write_text("\n".join(declared))
            assetto.install_runtimes(self.root, declared)
            run.assert_called_once_with(["protontricks", "--no-background-wineserver", "244210",
                                         "-q", "dotnet48", "win10"], check=True)

    def test_runtime_installation_without_completion_is_rejected(self):
        with patch.object(assetto.subprocess, "run"), self.assertRaisesRegex(ValueError, "did not record"):
            assetto.install_runtimes(self.root, ["dotnet48", "win10"])

    def test_launch_options_changes_only_target_value(self):
        before = self.steam_config()
        options = 'PROTON_ENABLE_WAYLAND=0 WINEDLLOVERRIDES="dwrite=n,b" %command%'
        after = assetto.steam_launch_options(before, options)
        self.assertEqual(after, before.replace('"old"',
                         '"PROTON_ENABLE_WAYLAND=0 WINEDLLOVERRIDES=\\"dwrite=n,b\\" %command%"'))
        self.assertEqual(assetto.steam_launch_options(after, options), after)

    def test_launch_options_creates_missing_game_and_preserves_crlf(self):
        before = self.steam_config(app="").replace("\n", "\r\n")
        after = assetto.steam_launch_options(before, "new %command%")
        self.assertIn('"244210"', after)
        self.assertIn('"LaunchOptions"\t\t"new %command%"', after)
        self.assertIn('"123" { "LaunchOptions" "other game" }', after)
        self.assertNotIn("\n", after.replace("\r\n", ""))
        self.assertEqual(assetto.steam_launch_options(after, "new %command%"), after)

    def test_invalid_vdf_is_rejected(self):
        for text in ('"x" {', '"x" "1" "X" "2"', '"x" nope'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                assetto.steam_launch_options(text, "new")

    def test_steam_running_prevents_writes_to_all_accounts(self):
        paths = []
        for account in ("1", "2"):
            path = self.root / f".local/share/Steam/userdata/{account}/config/localconfig.vdf"
            path.parent.mkdir(parents=True)
            path.write_text(self.steam_config())
            path.chmod(0o600)
            paths.append(path)
        with patch.object(assetto.subprocess, "run") as run:
            run.return_value.returncode = 0
            with self.assertRaisesRegex(ValueError, "Close Steam"):
                assetto.configure_steam("new", self.root)
            self.assertTrue(all(p.read_text() == self.steam_config() for p in paths))
            run.return_value.returncode = 1
            assetto.configure_steam("new", self.root)
            self.assertTrue(all('"LaunchOptions" "new"' in p.read_text() for p in paths))
            self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in paths))
            run.return_value.returncode = 0
            assetto.configure_steam("new", self.root)  # Already correct: no writes needed.


if __name__ == "__main__":
    unittest.main()
