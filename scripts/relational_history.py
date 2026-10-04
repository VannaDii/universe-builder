"""Read-only canonical history reconstruction for normalized MCP audits.

Uses the independently implemented decision-package reader, never the Rust
codec, evaluator or pilot runner. Every version must reproduce its stored hash.
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/decisions/relational-storage'))
from independent_audit import reader, encoded


def versions(db):
    models = json.loads((ROOT / 'docs/decisions/relational-storage/catalog.json').read_text())['models']
    decode = reader(db, models)
    result = {}
    for row in db.execute('SELECT * FROM record_versions'):
        payload = decode('Payload', row['payload_row'])
        assert payload['record_kind'] == row['kind'], 'record kind mismatch'
        actual = hashlib.sha256((row['kind'] + ':').encode() + encoded(payload)).hexdigest()
        assert actual == row['digest'], 'canonical digest mismatch: ' + row['id']
        result[row['id']] = {
            'record_version_id': row['id'],
            'identity': {'universe_id': row['universe_id'], 'record_id': row['record_id'], 'record_kind': row['kind']},
            'payload': payload,
            'payload_digest': row['digest'],
        }
    return result


if __name__ == '__main__':
    import sqlite3
    db = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    expected = json.loads(Path(sys.argv[2]).read_text())
    actual = versions(db)
    assert actual == {r['record_version_id']: r for r in expected}
    print(json.dumps({'versions': len(actual), 'original_digests': 'verified'}))
