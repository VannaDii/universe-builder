#!/usr/bin/env python3
"""Independent trusted-table readback of the disposable logical archive."""
import hashlib
import json
import sqlite3
import sys
from pathlib import Path
from independent_audit import reader

HERE=Path(__file__).resolve().parent

def stream(db):
    rows=[]
    tables=[r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") if not r[0].startswith(('sqlite_','search_index')) and r[0] not in ['archive_integrity','r_archive_manifest']]
    for table in tables:
        cols=[r[1] for r in db.execute('PRAGMA table_info("'+table+'")')]
        order=[r[1] for r in sorted(db.execute('PRAGMA table_info("'+table+'")'),key=lambda r:r[5]) if r[5]] or cols
        query='SELECT '+','.join('"'+k+'"' for k in cols)+' FROM "'+table+'" ORDER BY '+','.join('"'+k+'"' for k in order)
        for record in db.execute(query):
            cells=[['bytes',v.hex()] if isinstance(v,bytes) else ['null',None] if v is None else ['integer',v] if isinstance(v,int) else ['text',v] for v in record]
            rows.append([table,cols,cells])
    return json.dumps(rows,ensure_ascii=False,separators=(',',':')).encode(),len(rows)

if __name__=='__main__':
    db=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True);db.row_factory=sqlite3.Row
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok';assert not db.execute('PRAGMA foreign_key_check').fetchall()
    receipt=db.execute('SELECT * FROM archive_integrity').fetchone()
    raw,count=stream(db);assert hashlib.sha256(raw).hexdigest()==receipt['sha256'];assert count==receipt['row_count']
    decode=reader(db,json.loads((HERE/'catalog.json').read_text())['models'])
    manifest=decode('ArchiveManifest',receipt['manifest_row'])
    assert manifest['complete'] and manifest['includes_history'] and manifest['includes_workflow']
    assert receipt['authority_state']=='historical_evidence_only'
    assert not db.execute("SELECT 1 FROM sqlite_master WHERE name IN ('profiles','grants','credential','catalog','audit')").fetchall()
    print(json.dumps({'typed_archive':'verified','copied_rows':count,'history_and_receipts':'preserved','installation_authority':'absent','manifest':manifest,'sha256':receipt['sha256']}))
