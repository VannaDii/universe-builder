"""Independent read-only inspection of a disposable Goal 24 installation.
Never prints credentials or hashes. Called by the real-client integration test.
"""
import hashlib
import json
from pathlib import Path
import sqlite3
import stat
import sys

root, report, archive = map(Path, sys.argv[1:])
expected = json.loads(report.read_text())
schema_root = Path(__file__).resolve().parents[1] / 'docs/decisions/relational-storage'

def open_readonly(path):
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    db = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    return db

def schema(db):
    return db.execute("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()

installation = open_readonly(root / 'installation.sqlite')
normative = sqlite3.connect(':memory:')
normative.executescript((schema_root / 'installation.sql').read_text())
assert schema(installation) == schema(normative)
assert installation.execute('SELECT worlds_state,entities_state,predicates_state,continuities_state,expires_at,delegated_commit,allow_shared FROM grants WHERE profile=? AND universe=?', (expected['profile_id'], expected['universe_id'])).fetchone() == ('listed', 'listed', 'listed', 'listed', str(expected['limits']['expires_at']), 1, 1)
for table, column, values in [
    ('grant_worlds', 'world', expected['worlds']),
    ('grant_entities', 'entity', expected['limits']['entities']),
    ('grant_predicates', 'predicate', expected['limits']['predicates']),
    ('grant_continuities', 'continuity', expected['limits']['continuities']),
]:
    assert installation.execute(f'SELECT {column} FROM {table} WHERE profile=? AND universe=? ORDER BY ordinal', (expected['profile_id'], expected['universe_id'])).fetchall() == [(v,) for v in values]

assert stat.S_IMODE((root / 'profiles').stat().st_mode) == 0o700
secrets = []
for path in (root / 'profiles').iterdir():
    assert path.suffix == '.sqlite'
    credential = open_readonly(path)
    reference = sqlite3.connect(':memory:')
    reference.executescript((schema_root / 'credential.sql').read_text())
    assert schema(credential) == schema(reference)
    rows = credential.execute('SELECT profile_id,credential FROM credential').fetchall()
    assert len(rows) == 1 and rows[0][0] == path.stem
    profile, secret = rows[0]
    digest = hashlib.sha256(secret.encode()).hexdigest()
    assert installation.execute('SELECT hash FROM profiles WHERE id=?', (profile,)).fetchone() == (digest,)
    secrets.extend([secret.encode(), digest.encode()])

export = open_readonly(archive)
assert export.execute('SELECT includes_workflow FROM r_archive_manifest WHERE __row_id=(SELECT manifest_row FROM archive_integrity)').fetchone() == (0,)
assert export.execute('SELECT count(*) FROM workflow_entries').fetchone() == (0,)
assert export.execute('SELECT count(*) FROM operation_receipts').fetchone() == (0,)
for path in root.glob('packages/*.sqlite'):
    package = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    assert not set(name for name, _ in schema(package)) & {'credential','profiles','grants','grant_worlds','grant_entities','grant_predicates','grant_continuities','catalog','audit'}
for output in [report, archive, *root.glob('packages/*')]:
    if output.is_file():
        content = output.read_bytes()
        assert all(secret not in content for secret in secrets)
print('PASS: approved schemas, ordered grants, exact credential hashes, private modes, credential-free report/export/package')
