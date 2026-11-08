import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('data_sync', Path(__file__).resolve().parents[1] / 'scripts/data_sync.py')
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.disk = self.root / 'disk'
        self.disk.mkdir()
        self.local = self.root / 'local'
        self.local.mkdir()
        self.external = self.disk / 'pino/datasets/documents'
        self.manifest = {'kind': 'datasets', 'entries': {'documents': {'target': str(self.local)}}}

    def plan(self, **kwargs):
        return sync.plan(self.manifest, self.disk, 'backup', **kwargs)[0]

    def test_roundtrip_and_idempotence(self):
        (self.local / 'note').write_text('personal fixture')
        (self.local / 'empty').mkdir()
        sync.apply(self.plan())
        self.assertEqual((self.external / 'note').read_text(), 'personal fixture')
        self.assertTrue((self.external / 'empty').is_dir())
        self.assertEqual(self.plan()[0]['actions'], [])
        (self.local / 'note').unlink()
        sync.apply(sync.plan(self.manifest, self.disk, 'restore')[0])
        self.assertEqual((self.local / 'note').read_text(), 'personal fixture')

    def test_plan_does_not_write_and_update_retains_extra(self):
        (self.local / 'new').write_text('new')
        self.external.mkdir(parents=True)
        (self.external / 'old').write_text('old')
        plan = self.plan()
        self.assertFalse((self.external / 'new').exists())
        sync.apply(plan)
        self.assertTrue((self.external / 'old').exists())

    def test_mirror_preserves_excluded_tree(self):
        self.external.mkdir(parents=True)
        (self.external / 'old').write_text('old')
        (self.external / 'empty').mkdir()
        (self.external / 'cache').mkdir()
        (self.external / 'cache/keep').write_text('keep')
        self.manifest['entries']['documents']['exclude'] = ['cache']
        sync.apply(self.plan(mode='mirror'))
        self.assertFalse((self.external / 'old').exists())
        self.assertFalse((self.external / 'empty').exists())
        self.assertTrue((self.external / 'cache/keep').exists())

    def test_missing_source_cannot_delete(self):
        self.external.mkdir(parents=True)
        (self.external / 'keep').write_text('keep')
        self.local.rmdir()
        with self.assertRaises(ValueError):
            self.plan(mode='mirror')
        self.assertTrue((self.external / 'keep').exists())

    def test_unreadable_source_directory_cannot_delete_backup(self):
        (self.local / 'private').mkdir()
        self.external.mkdir(parents=True)
        (self.external / 'private').mkdir()
        (self.external / 'private/keep').write_text('backup fixture')
        original_scandir = sync.os.scandir

        def unreadable(path):
            if Path(path) == self.local / 'private':
                raise PermissionError('Unreadable source fixture')
            return original_scandir(path)

        with patch.object(sync.os, 'scandir', side_effect=unreadable):
            with self.assertRaises(PermissionError):
                self.plan(mode='mirror')
        self.assertEqual((self.external / 'private/keep').read_text(), 'backup fixture')

    def test_source_and_destination_mutations_abort_before_copy(self):
        (self.local / 'new').write_text('new')
        plan = self.plan()
        (self.local / 'new').write_text('changed')
        with self.assertRaises(ValueError):
            sync.apply(plan)
        self.assertFalse(self.external.exists())
        plan = self.plan()
        self.external.mkdir(parents=True)
        (self.external / 'concurrent').write_text('keep')
        with self.assertRaises(ValueError):
            sync.apply(plan)
        self.assertFalse((self.external / 'new').exists())

    def test_symlinks_and_overlap_rejected(self):
        (self.local / 'link').symlink_to(self.root)
        with self.assertRaises(ValueError):
            self.plan()
        (self.local / 'link').unlink()
        self.manifest['entries']['documents']['target'] = str(self.disk)
        with self.assertRaises(ValueError):
            self.plan()

    def test_cross_dataset_overlap_rejected(self):
        self.manifest['entries']['other'] = {'target': str(self.local / 'sub')}
        with self.assertRaises(ValueError):
            self.plan()
        self.assertFalse(self.external.exists())

    def test_populate_skips_missing_and_processes_available(self):
        self.manifest['kind'] = 'artifacts'
        source = self.disk / 'pino/artifacts/documents'
        source.mkdir(parents=True)
        (source / 'installer').write_text('fixture')
        self.manifest['entries']['missing'] = {'target': str(self.root / 'missing')}
        pairs, missing = sync.plan(self.manifest, self.disk, 'restore', allow_missing=True)
        self.assertEqual(len(missing), 1)
        sync.apply(pairs)
        self.assertTrue((self.local / 'installer').exists())

    def test_type_conflicts_preflight_all_entries(self):
        (self.local / 'thing').mkdir()
        self.external.mkdir(parents=True)
        (self.external / 'thing').write_text('keep')
        with self.assertRaises(ValueError):
            self.plan()
        self.assertEqual((self.external / 'thing').read_text(), 'keep')

    def test_replacement_can_be_declined(self):
        (self.local / 'note').write_text('source')
        self.external.mkdir(parents=True)
        (self.external / 'note').write_text('destination')
        plan = self.plan()
        plan[0]['actions'][0]['action'] = 'keep'
        sync.apply(plan)
        self.assertEqual((self.external / 'note').read_text(), 'destination')

    def run_cli(self, arguments, answers=()):
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps(self.manifest))
        with patch.object(sync.sys, 'argv', ['sync', str(manifest), *arguments]), \
                patch.object(sync.os, 'geteuid', return_value=1000), \
                patch('builtins.input', side_effect=answers) as prompt, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            result = sync.main()
        return result, output.getvalue(), prompt.call_count

    def test_dry_run_lists_deletes_without_prompts_or_writes(self):
        self.external.mkdir(parents=True)
        (self.external / 'old').write_text('keep until approved')
        result, output, prompts = self.run_cli(['backup', str(self.disk), '--mode', 'mirror', '--dry-run'])
        self.assertEqual((result, prompts), (0, 0))
        self.assertIn('DELETE:', output)
        self.assertTrue((self.external / 'old').exists())

    def test_cli_conflict_selection_then_cancel_leaves_destination(self):
        (self.local / 'note').write_text('source')
        self.external.mkdir(parents=True)
        (self.external / 'note').write_text('destination')
        result, _, prompts = self.run_cli(['backup', str(self.disk), '--mode', 'update'], ['s', 'n'])
        self.assertEqual((result, prompts), (1, 2))
        self.assertEqual((self.external / 'note').read_text(), 'destination')

    def test_cli_conflict_selection_then_apply_copies_source(self):
        (self.local / 'note').write_text('source')
        self.external.mkdir(parents=True)
        (self.external / 'note').write_text('destination')
        result, _, prompts = self.run_cli(['backup', str(self.disk), '--mode', 'update'], ['s', 'y'])
        self.assertEqual((result, prompts), (0, 2))
        self.assertEqual((self.external / 'note').read_text(), 'source')

    def test_mount_disappearing_after_plan_prevents_writes(self):
        self.manifest['entries']['documents']['requiredMount'] = str(self.local)
        (self.local / 'new').write_text('fixture')
        with patch.object(sync.os.path, 'ismount', return_value=True):
            planned = self.plan()
        with patch.object(sync.os.path, 'ismount', return_value=False):
            with self.assertRaises(ValueError):
                sync.apply(planned)
        self.assertFalse(self.external.exists())
