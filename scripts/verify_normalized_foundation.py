#!/usr/bin/env python3
"""Read-only, independent SQL proof for disposable normalized kernel packages."""
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'docs/decisions/relational-storage'))
from relational_reader import reader, encoded

def verify(path,first,later):
    f=json.loads((ROOT/'fixtures/normalized-foundation/facts.json').read_text())
    c=sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True);c.row_factory=sqlite3.Row
    assert c.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    assert not c.execute('PRAGMA foreign_key_check').fetchall()
    models=json.loads((ROOT/'docs/decisions/relational-storage/catalog.json').read_text())['models']
    decode=reader(c,models)
    expected={r['record_version_id']:r for r in f['initial']+f['later']}
    rows=list(c.execute('SELECT * FROM record_versions'))
    assert len(rows)==len(expected)
    actual={}
    for r in rows:
        body=decode('Payload',r['payload_row']);e=expected[r['id']]
        assert body==e['payload'],r['id']
        assert (r['universe_id'],r['record_id'],r['kind'])==(e['identity']['universe_id'],e['identity']['record_id'],e['identity']['record_kind'])
        assert hashlib.sha256((r['kind']+':').encode()+encoded(body)).hexdigest()==r['digest']==e['payload_digest']
        actual[r['id']]=body
    # Reconstruct selected factual history from ordered immutable changes,
    # independently of the kernel and its current head/cached projections.
    def membership(revision):
        chain=[]
        while revision:
            row=c.execute('SELECT * FROM commits WHERE id=?',(revision,)).fetchone();assert row
            chain.append(row);revision=row['parent_id']
        result={}
        for commit in reversed(chain):
            for change in c.execute('SELECT * FROM commit_changes WHERE revision_id=?',(commit['id'],)):
                assert result.get(change['record_id'])==change['prior_version']
                if change['version_id'] is None:result.pop(change['record_id'])
                else:result[change['record_id']]=change['version_id']
        return result
    initial={r['identity']['record_id']:r['record_version_id'] for r in f['initial']}
    current={**initial,**{r['identity']['record_id']:r['record_version_id'] for r in f['later']}}
    assert membership(first)==initial
    assert membership(later)==current
    e=f['expectations']
    def body(n,m):return actual[m['rec_'+format(n,'024x')]]
    assert body(6,initial)['classification']==e['cedar_initial_classification']
    assert body(6,current)['classification']==e['cedar_later_classification']
    assert body(6,current)['names'][0]['text']==e['later_name']
    assert [body(16,m)['value']['value']['digits'] for m in [initial,current]]==[e['initial_height'],e['later_height']]
    assert body(16,current)['value']['unit']==e['height_unit']
    assert [body(18,m)['value']['digits'] for m in [initial,current]]==e['pistol_a_rounds']
    assert [body(20,m)['value']['digits'] for m in [initial,current]]==e['pistol_b_rounds']
    assert body(26,current)['subject']['record']==e['shared_subject']
    assert body(29,current)['attributeMode']=='initial_value'
    assert body(28,current)['subject']['record']==e['initial_value_subject']
    assert body(32,current)['scope']['applicability']['world_ids']==e['empty_worlds']
    assert body(32,current)['validity']['end']['kind']==e['unknown_end']
    assert body(24,current)['validity']['end']['kind']==e['unbounded_end']
    anchor=body(23,current);source=body(22,current)
    assert anchor['sourceVersion']['version'] in actual
    assert hashlib.sha256(f['source_text'].encode()).hexdigest()==source['digest']
    excerpt=f['source_text'].encode()[anchor['locator']['start']:anchor['locator']['end']]
    assert excerpt.decode()==anchor['excerpt']
    assert hashlib.sha256(excerpt).hexdigest()==anchor['excerptDigest']
    for table in ['record_versions','snapshot_membership']:
        columns={r['name'] for r in c.execute('PRAGMA table_info('+table+')')}
        assert not columns.intersection({'payload','membership','schema_version','storage_layout'})
    for r in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'r_*'"):
        assert all(col['type'].upper() not in ('BLOB','REAL') for col in c.execute('PRAGMA table_info("'+r[0]+'")'))
    return {'versions':len(rows),'historical_revisions':2,'independent_facts':'verified','digests':'verified','opaque_canonical_columns':False}

if __name__=='__main__':print(json.dumps(verify(*sys.argv[1:])))
