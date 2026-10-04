"""Test-only fixture seeding and deliberate tampering; not an application importer."""
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/decisions/relational-storage'))
from prototype import Writer
from independent_audit import encoded, reader
from verify_export import stream


def rehash(db):
    raw, count = stream(db)
    db.execute('UPDATE archive_integrity SET sha256=?,row_count=?', (hashlib.sha256(raw).hexdigest(), count))
    db.commit()


if sys.argv[1] in ['rehash','redigest']:
    db=sqlite3.connect(sys.argv[2])
    if sys.argv[1]=='redigest':
        db.row_factory=sqlite3.Row
        decode=reader(db,json.loads((ROOT/'docs/decisions/relational-storage/catalog.json').read_text())['models'])
        sql=db.execute("SELECT sql FROM sqlite_master WHERE name='immutable_record_versions_update'").fetchone()[0]
        db.execute('DROP TRIGGER immutable_record_versions_update')
        for version,kind,pointer in db.execute('SELECT id,kind,payload_row FROM record_versions').fetchall():
            payload=decode('Payload',pointer)
            digest=hashlib.sha256((kind+':').encode()+encoded(payload)).hexdigest()
            db.execute('UPDATE record_versions SET digest=? WHERE id=?',(digest,version))
        db.executescript(sql)
    rehash(db)
else:
    # The line-oriented input is a disposable test oracle, never accepted by LogicalArchive::read.
    source, target = map(Path, sys.argv[2:])
    db = sqlite3.connect(target)
    schema = ROOT / 'docs/decisions/relational-storage'
    for name in ['typed','kernel','semantic','workflow','export']:
        db.executescript((schema / (name+'.sql')).read_text())
    writer = Writer(db, json.loads((schema/'catalog.json').read_text())['models'])
    for line in source.open():
        row = json.loads(line)
        kind = row['entry']
        if kind == 'manifest':
            manifest = row['manifest']; manifest['format'] = 'universe-relational'
            u = manifest['universe']
            db.execute('INSERT INTO universes(id,name) VALUES(?,?)', (u,manifest['name']))
            manifest_row = writer.put('ArchiveManifest', manifest)
        elif kind == 'record':
            record = row['record']; identity = record['identity']
            db.execute('INSERT INTO record_identities VALUES(?,?,?)', (u,identity['record_id'],identity['record_kind']))
            pointer = writer.put('Payload', record['payload'])
            db.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', (u,record['record_version_id'],identity['record_id'],identity['record_kind'],pointer,record['payload_digest']))
        elif kind == 'continuity':
            db.execute('INSERT INTO continuities VALUES(?,?,?,?)', (u,row['id'],row['head'],row['baseline']))
        elif kind == 'commit':
            db.execute('INSERT INTO commits VALUES(?,?,?,?,?,?,?,?,?)', (u,*[row[k] for k in ['id','continuity','parent','sequence','principal','decision','reason','digest']]))
        elif kind == 'change':
            db.execute('INSERT INTO commit_changes VALUES(?,?,?,?,?)', (u,*[row[k] for k in ['revision','record','prior','next']]))
        elif kind != 'checksum':
            raise AssertionError('unsupported test fixture family: '+kind)
    raw,count = stream(db)
    db.execute("INSERT INTO archive_integrity VALUES(1,?,'typed-row-stream',?,?,'historical_evidence_only',?)", (manifest_row,hashlib.sha256(raw).hexdigest(),count,hashlib.sha256(encoded(manifest)).hexdigest()))
    db.commit();db.close();target.chmod(0o600)
