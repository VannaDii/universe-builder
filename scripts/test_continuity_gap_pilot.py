"""Adversarial checks for the independent auditor, using copied proof artifacts.

Run after qualification:
python scripts/test_continuity_gap_pilot.py --evidence docs/evidence/continuity-gap-RUN/run-a
Uses existing unittest; changes only fresh temporary copies, never baseline tests.
"""
from contextlib import closing
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest

from audit_continuity_gap import audit, canonical, digest

EVIDENCE = None


class EvidenceAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gap-audit-negative-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        for name in ("oracle.json", "baseline.json", "build-identity.json"):
            shutil.copyfile(EVIDENCE.parent / name, root / name)
        self.directory = root / "run"
        self.directory.mkdir()
        for name in ("report.json", "package.sqlite", "mcp-transcript.jsonl"):
            shutil.copyfile(EVIDENCE / name, self.directory / name)

    def alter_database(self, mutation):
        path = self.directory / "package.sqlite"
        with closing(sqlite3.connect(path)) as db, db:
            mutation(db)
        # Rebind the snapshot hash so the semantic audit, not the outer digest,
        # must catch the deliberate inconsistency.
        report_path = self.directory / "report.json"
        report = json.loads(report_path.read_text())
        report["package_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        report_path.write_text(json.dumps(report))

    def test_saved_evidence_passes(self):
        self.assertEqual(audit(self.directory)["status"], "passed")

    def test_changed_wire_request_is_rejected(self):
        path = self.directory / "mcp-transcript.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        request = next(r for r in rows if r["direction"] == "sent"
                       and r["frame"].get("params", {}).get("name") == "universe_propose")
        request["frame"]["params"]["arguments"]["rationale"] = "tampered"
        path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
        with self.assertRaisesRegex(RuntimeError, "does not match actual wire"):
            audit(self.directory)

    def test_missing_exact_approval_is_rejected(self):
        def mutate(db):
            db.execute("DROP TRIGGER workflow_entries_no_delete")
            # Remove a publication approval while preserving SQL integrity.
            report = json.loads((self.directory / "report.json").read_text())
            pub = report["publications"][0]
            suffix = f":{pub['review']['proposal']['digest']}:{pub['validation']['run_id']}"
            db.execute("DELETE FROM workflow_entries WHERE key LIKE ?", ("approval:%" + suffix,))
        self.alter_database(mutate)
        with self.assertRaisesRegex(RuntimeError, "lacks exact admissible approval"):
            audit(self.directory)

    def test_kernel_receipt_retargeting_is_rejected(self):
        def mutate(db):
            db.execute("DROP TRIGGER immutable_operation_receipts_update")
            genesis = db.execute("SELECT id FROM commits WHERE sequence=0").fetchone()[0]
            db.execute("UPDATE operation_receipts SET revision_id=? WHERE idempotency_key='G01-commit'", (genesis,))
        self.alter_database(mutate)
        with self.assertRaisesRegex(RuntimeError, "kernel receipt/input mismatch"):
            audit(self.directory)

    def test_resulting_head_mutation_is_rejected(self):
        def mutate(db):
            db.execute("DELETE FROM head_membership WHERE record_id='rec_000000000000000000030da4'")
        self.alter_database(mutate)
        with self.assertRaisesRegex(RuntimeError, "result absent from restarted head"):
            audit(self.directory)

    def test_source_text_mutation_is_rejected(self):
        def mutate(db):
            db.execute("DROP TRIGGER workflow_entries_no_update")
            key = db.execute("SELECT key FROM workflow_entries WHERE key LIKE 'source:%'").fetchone()[0]
            text = "Mara is dead. Iven has white hair."
            db.execute("UPDATE workflow_entries SET payload=?,digest=? WHERE key=?", (canonical(text), digest(text), key))
        self.alter_database(mutate)
        with self.assertRaisesRegex(RuntimeError, "source text/digest mismatch"):
            audit(self.directory)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args, extra = parser.parse_known_args()
    EVIDENCE = args.evidence.resolve()
    unittest.main(argv=[__file__, *extra])
