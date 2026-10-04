#!/usr/bin/env python3
"""Independent read-only reconstruction. Imports neither generator nor writer.
Uses the reviewable physical catalog, direct SELECTs and an independently
implemented decoder/hash path. Input oracle is supplied before storage writes.
"""
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent

def quote(s):return '"'+s.replace('"','""')+'"'
def encoded(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()

def reader(db,models):
    def decode(model,reference,trail=()):
        spec=models[model];kind=spec['kind']
        if kind=='null':assert reference is None;return None
        if kind=='boolean':assert reference in (0,1);return bool(reference)
        if kind=='integer':return int(reference)
        if kind=='number':return float(reference)
        if kind=='string':return reference
        marker=(model,reference);assert marker not in trail,'cyclic value/expression'
        trail=trail+(marker,)
        rows=db.execute('SELECT * FROM '+quote(spec['table'])+' WHERE __row_id=?',(reference,)).fetchall()
        assert len(rows)==1,(model,reference)
        row=rows[0]
        if kind in ('object','tuple'):
            fields={}
            for key,field in spec['fields'].items():
                state=row[key+'__state'];value=row[key]
                assert state in (0,1,2)
                assert state!=0 or not field['required']
                if state==0:assert value is None;continue
                if state==1:assert value is None;fields[key]=None
                else:fields[key]=decode(field['model'],value,trail)
            return fields if kind=='object' else [fields[str(i)] for i in range(len(fields))]
        if kind=='union':
            branch=row['variant'];assert 0<=branch<len(spec['variants'])
            for i in range(len(spec['variants'])):
                assert i==branch or row['v'+str(i)] is None
            return decode(spec['variants'][branch],row['v'+str(branch)],trail)
        key='ordinal' if kind=='array' else 'name'
        entries=db.execute('SELECT '+key+',item FROM '+quote(spec['table']+'_items')+' WHERE owner=? ORDER BY '+key,(reference,)).fetchall()
        if kind=='array':
            assert [r[0] for r in entries]==list(range(len(entries))),'noncontiguous ordered collection'
            return [decode(spec['item'],r[1],trail) for r in entries]
        return {r[0]:decode(spec['item'],r[1],trail) for r in entries}
    return decode

def audit(path,canonical_oracle,extra_oracle):
    models=json.loads((HERE/'catalog.json').read_text())['models']
    db=sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True);db.row_factory=sqlite3.Row
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    decode=reader(db,models)
    expected={row['name']:row for row in json.loads(Path(canonical_oracle).read_text())}
    extra={row['name']:row for row in json.loads(Path(extra_oracle).read_text())}
    decoded=[]
    for root in db.execute('SELECT * FROM proof_roots ORDER BY name'):
        actual=decode(root['model'],root['row_id'])
        if root['name'] in expected:
            oracle=expected[root['name']]
            assert actual==oracle['value'],root['name']
            raw=encoded(actual);assert raw.decode()==oracle['canonical']
            # Current recipe contains v1 twice, even for a payload requiring v2.
            prefix=(actual['record_kind']+':v1:v1:').encode()
            digest=hashlib.sha256(prefix+raw).hexdigest()
            assert digest==oracle['digest']==root['expected_digest']
        else:
            oracle=extra[root['name']];assert actual==oracle['value'],root['name']
            digest=hashlib.sha256(encoded(actual)).hexdigest()
            assert digest==root['expected_digest']
        decoded.append((root['name'],digest))
    assert len(decoded)==len(expected)+len(extra)
    forbidden=[];tables=[]
    for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'search_index%' AND name NOT LIKE 'sqlite_%'"):
        table=row[0];tables.append(table)
        for col in db.execute('PRAGMA table_info('+quote(table)+')'):
            if col['type'].upper() in ('BLOB','REAL') and (table,col['name']) not in [('source_content','utf8_content'),('media_chunk','content')]:forbidden.append((table,col['name']))
    assert not forbidden,forbidden
    workflows=0
    for r in db.execute('SELECT * FROM workflow_entries'):
        body=decode(r['family'],r[r['family']]);assert hashlib.sha256(encoded(body)).hexdigest()==r['digest'];workflows+=1
    for r in db.execute('SELECT * FROM source_content'):
        assert hashlib.sha256(r['utf8_content']).hexdigest()==r['digest'];assert len(r['utf8_content'])==r['byte_size']
    authority_tables={'profiles','grants','grant_limits','catalog','audit'}
    assert not authority_tables.intersection(tables),'installation authority leaked into package'
    db.close()
    return {'workflow_envelope_bindings':workflows,'source_content':'digest and bytes exact','installation_authority_in_package':False,'canonical_round_trips':len(expected),'closed_union_and_workflow_round_trips':len(extra),
        'canonical_families':len([n for n in expected if n.startswith('family:')]),
        'integrity':'ok','foreign_keys':'ok','application_blob_or_real_columns':forbidden,
        'reconstruction_digest':hashlib.sha256(encoded(decoded)).hexdigest(),'tables_inspected':len(tables)}

if __name__=='__main__':print(json.dumps(audit(*sys.argv[1:])))
