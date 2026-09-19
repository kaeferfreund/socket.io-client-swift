#!/usr/bin/env python3
"""Offline checks for review evidence and shell fail-fast behavior."""
import collections
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ReviewRegressions(unittest.TestCase):
    def test_inventory_summary_matches_every_csv_row(self):
        with (ROOT / "Documentation/JavaScriptTestInventory.csv").open(newline="") as source:
            rows = list(csv.DictReader(source))
        summary = json.loads((ROOT / "Documentation/ReviewEvidence/InventorySummary.json").read_text())
        self.assertEqual({row["upstream_sha"] for row in rows}, {summary["upstream_sha"]})
        actual = collections.Counter(row["status"] for row in rows)
        recorded = {key: count for key, count in summary["review_statuses"].items() if count}
        self.assertEqual(dict(actual), recorded)
        runtime = collections.Counter(row["package"] for row in rows if row["scope"] == "runtime-declaration")
        self.assertEqual(dict(runtime), summary["runtime_by_package"])
        self.assertEqual(len(rows) - sum(runtime.values()), summary["typescript_type_declarations"])

    def test_mktemp_failure_stops_before_prepare_or_compilation(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            (temp / "mktemp").write_text("#!/bin/sh\nexit 73\n")
            (temp / "node").write_text('#!/bin/sh\ntouch "$SENTINEL"\nexit 0\n')
            (temp / "swiftc").write_text('#!/bin/sh\ntouch "$SENTINEL"\nexit 0\n')
            for name in ("mktemp", "node", "swiftc"):
                (temp / name).chmod(0o755)
            environment = dict(os.environ, PATH=str(temp) + os.pathsep + os.environ["PATH"], SENTINEL=str(temp / "ran"))
            result = subprocess.run([shutil.which("bash"), str(ROOT / "scripts/test-parser-parity.sh"), directory],
                                    cwd=directory, env=environment, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 73, result.stderr.decode())
            self.assertFalse((temp / "ran").exists())

if __name__ == "__main__":
    unittest.main()
