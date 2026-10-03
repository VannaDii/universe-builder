"""Adversarial checks of the independent G02 proof auditor."""
from contextlib import closing
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest

from audit_g02 import audit

EVIDENCE = None


@unittest.skipUnless(EVIDENCE, "use --evidence with a completed G02 run")
class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="g02-audit-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        for name in ("report.json", "oracle.json", "build-identity.json", "mcp-transcript.jsonl", "package.sqlite"):
            shutil.copyfile(EVIDENCE / name, self.directory / name)

    def alter_database(self, mutation):
        path = self.directory / "package.sqlite"
        with closing(sqlite3.connect(path)) as db, db:
            mutation(db)
        report = json.loads((self.directory / "report.json").read_text())
        report["package_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        (self.directory / "report.json").write_text(json.dumps(report))

    def test_saved_proof_passes(self):
        self.assertEqual(audit(self.directory)["status"], "passed")

    def test_changed_wire_owner_fails(self):
        path = self.directory / "mcp-transcript.jsonl"
        rows = list(map(json.loads, path.read_text().splitlines()))
        q = next(r["frame"] for r in rows if r["direction"] == "sent" and
                 r["frame"].get("params", {}).get("arguments", {}).get("idempotency_key") == "dead_breath")
        q["params"]["arguments"]["operations"][0]["record"]["participants"][0]["record"]["record"] = "rec_000000000000000000030d44"
        path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
        with self.assertRaisesRegex(RuntimeError, "report differs from wire"):
            audit(self.directory)

    def test_changed_oracle_fails(self):
        path = self.directory / "oracle.json"
        oracle = json.loads(path.read_text())
        oracle["cases"][0]["allowed"] = True
        path.write_text(json.dumps(oracle))
        with self.assertRaisesRegex(RuntimeError, "oracle changed"):
            audit(self.directory)

    def test_forged_allowed_outcome_fails_even_with_rebound_oracle_hash(self):
        path = self.directory / "oracle.json"
        oracle = json.loads(path.read_text())
        oracle["cases"][0]["allowed"] = True
        path.write_text(json.dumps(oracle))
        identity_path = self.directory / "build-identity.json"
        identity = json.loads(identity_path.read_text())
        identity["g02_oracle_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        identity_path.write_text(json.dumps(identity))
        with self.assertRaisesRegex(RuntimeError, "independent capability calculation differs"):
            audit(self.directory)

    def test_missing_approval_fails(self):
        def mutate(db):
            db.execute("DROP TRIGGER workflow_entries_no_delete")
            db.execute("DELETE FROM workflow_entries WHERE key=(SELECT key FROM workflow_entries WHERE key LIKE 'approval:%' LIMIT 1)")
        self.alter_database(mutate)
        with self.assertRaisesRegex(RuntimeError, "missing exact approval"):
            audit(self.directory)

    def test_retargeted_kernel_receipt_fails(self):
        def mutate(db):
            db.execute("DROP TRIGGER immutable_operation_receipts_update")
            genesis = db.execute("SELECT id FROM commits WHERE sequence=0").fetchone()[0]
            db.execute("UPDATE operation_receipts SET revision_id=? WHERE idempotency_key='undead_speech-commit'", (genesis,))
        self.alter_database(mutate)
        with self.assertRaisesRegex(RuntimeError, "kernel receipt differs"):
            audit(self.directory)

    def test_changed_head_membership_fails(self):
        self.alter_database(lambda db: db.execute("DELETE FROM head_membership WHERE record_id='rec_000000000000000000030d87'"))
        with self.assertRaisesRegex(RuntimeError, "head membership differs"):
            audit(self.directory)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args, extra = parser.parse_known_args()
    EVIDENCE = args.evidence.resolve()
    # unittest discovery has no evidence; standalone invocation does.
    AuditTests.__unittest_skip__ = False
    unittest.main(argv=[__file__, *extra])
