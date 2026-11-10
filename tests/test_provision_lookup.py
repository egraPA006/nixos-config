import json
import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProvisionLookupTests(unittest.TestCase):
    def lookup(self, records):
        source = (ROOT / "modules/pino/bitwarden.sh").read_text().split('operation="${1:-}"', 1)[0]
        mock = '''
bw() {
  [ "$1" = list ] && [ "$2" = items ] && [ "$3" = --search ] || return 99
  printf '%s' "$FIXTURE"
}
stream_note pino-xray-client-re-1-halos
'''
        return subprocess.run(["bash", "-c", source + mock], capture_output=True, text=True,
                              env=dict(os.environ, FIXTURE=json.dumps(records)))

    def test_companions_and_trash_do_not_make_lookup_ambiguous(self):
        name = "pino-xray-client-re-1-halos"
        result = self.lookup([
            {"name": name + "-link", "type": 2, "notes": "companion"},
            {"name": name, "type": 2, "notes": "deleted", "deletedDate": "2026-01-01"},
            {"name": name, "type": 2, "notes": "exact fixture"},
            {"name": "prefix-" + name, "type": 2, "notes": "unrelated"},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "exact fixture\n")

    def test_no_exact_match_never_uses_companion(self):
        result = self.lookup([{"name": "pino-xray-client-re-1-halos-link", "type": 2, "notes": "hidden fixture"}])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("hidden fixture", result.stderr)

    def test_duplicate_exact_names_fail_without_exposing_contents(self):
        record = {"name": "pino-xray-client-re-1-halos", "type": 2, "notes": "hidden fixture"}
        result = self.lookup([record, record])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("hidden fixture", result.stderr)

    def test_wrong_type_is_rejected(self):
        result = self.lookup([{"name": "pino-xray-client-re-1-halos", "type": 1, "notes": "hidden fixture"}])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
