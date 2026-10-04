"""Independent read-only archive inspection; never uses the Rust codec."""
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/decisions/relational-storage'))
from independent_audit import reader, encoded
from verify_export import stream
from relational_history import versions, workflows


def inspect(path):
    db = sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    raw, count = stream(db)
    integrity = db.execute('SELECT * FROM archive_integrity').fetchone()
    assert hashlib.sha256(raw).hexdigest() == integrity['sha256']
    assert count == integrity['row_count']
    assert integrity['checksum_recipe'] == 'typed-row-stream'
    assert integrity['authority_state'] == 'historical_evidence_only'
    decode = reader(db, json.loads((ROOT / 'docs/decisions/relational-storage/catalog.json').read_text())['models'])
    manifest = decode('ArchiveManifest', integrity['manifest_row'])
    assert hashlib.sha256(encoded(manifest)).hexdigest() == integrity['manifest_sha256']
    assert manifest['format'] == 'universe-relational'
    assert manifest['includes_history']
    assert manifest['complete'] == (manifest['omitted_records'] == 0)
    assert manifest['universe'] == db.execute('SELECT id FROM universes').fetchone()[0]
    assert not db.execute("SELECT 1 FROM sqlite_master WHERE name IN ('profiles','grants','credential','catalog','audit')").fetchall()
    canonical = versions(db)
    evidence = workflows(db)
    if not manifest['includes_workflow']:
        assert db.execute('SELECT count(*) FROM workflow_entries').fetchone()[0] == 0
        assert db.execute('SELECT count(*) FROM operation_receipts').fetchone()[0] == 0
    if len(sys.argv)>2:
        original=sqlite3.connect('file:'+sys.argv[2]+'?mode=ro',uri=True); original.row_factory=sqlite3.Row
        assert canonical==versions(original)
        assert evidence==workflows(original)
        for table in ['record_identities','commits','continuities','commit_changes','world_name_reservations','operation_receipts','import_record_digest','continuity_name','source_content','media_chunk']:
            assert sorted(map(tuple,db.execute('SELECT * FROM '+table)),key=repr)==sorted(map(tuple,original.execute('SELECT * FROM '+table)),key=repr),table
    return {'manifest': manifest, 'typed_rows': count, 'versions': len(canonical), 'workflow_and_content_entries': len(evidence), 'checksum': integrity['sha256'], 'archive_digest':hashlib.sha256(('typed-row-stream:'+integrity['sha256']+':manifest:'+integrity['manifest_sha256']).encode()).hexdigest()}


if __name__ == '__main__':
    print(json.dumps(inspect(Path(sys.argv[1])), ensure_ascii=False))
