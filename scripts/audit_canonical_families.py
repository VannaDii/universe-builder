"""Independent, read-only reconstruction of remaining-family MCP evidence.

Imports the separate SQL reader, never the pilot, Rust writer or evaluator.
Replay immutable commits; bind every public snapshot and reviewed assignment to
relational versions; compare original authored specimens and exact source/media.
"""
import argparse
import base64
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3
from relational_history import versions, workflows, ROOT


def substitute(value, bindings):
    if isinstance(value,dict):return {k:substitute(v,bindings) for k,v in value.items()}
    if isinstance(value,list):return [substitute(v,bindings) for v in value]
    return bindings[value[1:]] if isinstance(value,str) and value.startswith('$') else value


def contains(actual, authored):
    """Defaults may be emitted; every authored field/order/value must be exact."""
    if isinstance(authored,dict):
        assert isinstance(actual,dict)
        for key,value in authored.items():
            if key=='roles' and value==[] and key not in actual:continue
            assert key in actual,key
            contains(actual[key],value)
    elif isinstance(authored,list):
        assert isinstance(actual,list) and len(actual)==len(authored)
        for a,e in zip(actual,authored):contains(a,e)
    else:assert actual==authored,(actual,authored)


def audit(directory):
    directory=Path(directory)
    with closing(sqlite3.connect('file:'+str(directory/'package.sqlite')+'?mode=ro',uri=True)) as db:
        db.row_factory=sqlite3.Row
        return inspect(directory,db)


def inspect(directory,db):
    directory=Path(directory);r=json.loads((directory/'report.json').read_text())
    assert r['status']=='executed',r.get('error')
    f=json.loads((ROOT/'fixtures/canonical-families/records.json').read_text())
    assert json.loads((directory/'fixture.json').read_text())==f
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    v=versions(db);workflow=workflows(db)
    def membership(revision):
        chain=[];seen=set()
        while revision:
            assert revision not in seen;seen.add(revision)
            c=db.execute('SELECT * FROM commits WHERE id=?',(revision,)).fetchone();assert c
            chain.append(c);revision=c['parent_id']
        m={}
        for c in reversed(chain):
            for change in db.execute('SELECT * FROM commit_changes WHERE revision_id=? ORDER BY record_id',(c['id'],)):
                assert m.get(change['record_id'])==change['prior_version']
                if change['version_id'] is None:m.pop(change['record_id'])
                else:
                    body=v[change['version_id']];assert body['identity']['record_id']==change['record_id']
                    m[change['record_id']]=change['version_id']
        return m
    snapshots={}
    for snap in r['snapshots']:
        m=membership(snap['revision']);expected={i:v[version] for i,version in m.items()}
        actual={row['identity']['record_id']:row for row in snap['records']}
        assert len(actual)==len(snap['records']) and actual==expected,snap['label']
        snapshots[snap['label']]=actual
    original=snapshots['original'];b=r['bindings']
    assert snapshots['original-after-correction']==snapshots['original-restart']==original
    assert snapshots['corrected']==snapshots['corrected-restart']
    assert snapshots['adopted']==snapshots['adopted-restart']==snapshots['final-restart']
    for name,authored in f['records'].items():
        contains(original[b[name]]['payload'],substitute(authored,b))
        assert snapshots['adopted'][b[name]]['payload']==original[b[name]]['payload']
        if name!='rule':assert snapshots['adopted'][b[name]]['record_version_id']!=original[b[name]]['record_version_id']
    corrected=snapshots['corrected']
    assert corrected[b['appearance']]['payload']['physical_description']==f['corrected_description']
    assert corrected[b['work_version']]['payload']['binding']=={'kind':'segments','segments':[
        {'segment':'opening α','continuity':b['continuity'],'revision':r['snapshots'][0]['revision']},
        {'segment':'ending α','continuity':b['continuity'],'revision':b['source_revision']}]}
    assert corrected[b['saga']]['payload']['memberships'][0]['order']==2
    for name in ('scene','passage'):
        assert corrected[b[name]]==original[b[name]]
        pin=corrected[b[name]]['payload']['workVersion']
        assert v[pin['version']]==original[b['work_version']]
        assert pin['version']!=corrected[b['work_version']]['record_version_id']
    text=f['source_text'].encode();digest=hashlib.sha256(text).hexdigest()
    content=db.execute('SELECT * FROM source_content WHERE digest=?',(digest,)).fetchone()
    assert content['utf8_content']==text and content['byte_size']==len(text)
    source=original[b['source_version']]['payload'];assert source['digest']==digest and source['byteSize']==len(text)
    anchor=original[b['anchor']]['payload'];start,end=anchor['locator']['start'],anchor['locator']['end']
    excerpt=text[start:end];assert excerpt.decode()==anchor['excerpt']==f['excerpt']
    assert hashlib.sha256(excerpt).hexdigest()==anchor['excerptDigest']
    assert v[anchor['sourceVersion']['version']]==r['source']
    media=r['image'];data=base64.b64decode(media['base64'],validate=True);d=hashlib.sha256(data).hexdigest()
    chunks=list(db.execute('SELECT * FROM media_chunk WHERE digest=? ORDER BY ordinal',(d,)))
    assert len(chunks)>=2 and [row['ordinal'] for row in chunks]==list(range(len(chunks)))
    assert b''.join(row['content'] for row in chunks)==data
    assert all(len(row['content'])==row['byte_size'] for row in chunks)
    asset=original[b['image']]['payload'];assert asset['digest']==d and asset['byte_size']==len(data)
    assert d==f['media']['sha256']
    assert asset['width']==f['media']['width'] and asset['height']==f['media']['height'] and asset['original_name']==f['media']['original_name']
    # No promotion of epistemic/communication/plan records into objective facts/events.
    assert not any(row['payload']['record_kind'] in ('assertion','event') for row in original.values())
    assert r['epistemic_state']['result']['assertions']==[]
    for pub in r['publications']:
        m=membership(pub['receipt']['revision'])
        for change in pub['review']['changes']:
            nxt=change['next'];assert nxt and v[nxt['record_version_id']]==nxt
            assert m[change['record_id']]==nxt['record_version_id']
        assert pub['author_selection']['approval']['approved']=={k:pub['review']['proposal'][k] for k in ('proposal_id','version','digest')}
    for control in r['controls']:
        assert control['before']==control['after'] and control['head_before']==control['head_after']
        assert control['proposal_response'].get('isError') or control['validation_rejection']['code'] in ('INVALID_ARGUMENT','POLICY_DENIED')
        assert not db.execute('SELECT 1 FROM operation_receipts WHERE idempotency_key=?',(control['key']+'-commit',)).fetchone()
    assert r['no_grant']=={'code':'POLICY_DENIED','message':'operation unavailable; verify current profile, grant, or package state'}
    assert r['restricted_read']=={'code':'NOT_FOUND_OR_NOT_ACCESSIBLE','message':'resource'}
    assert set(r['restricted_reads'])=={'appearance','source_version','image','secret','communication','realm','memory','goal'}
    assert all(value==r['restricted_read'] for value in r['restricted_reads'].values())
    assert r['revoked_read']=={'isError':True,'content':[{'type':'text','text':'disconnected; recover mutations using their original idempotency key'}]}
    assert r['restarts']==len(r['restart_instances'])==2
    assert all(i['before']!=i['after'] for i in r['restart_instances'])
    # Actual wire evidence must carry successful publications/readbacks and errors.
    wire=[json.loads(line) for line in (directory/'mcp-transcript.jsonl').read_text().splitlines()]
    sent=[w['frame'] for w in wire if w['direction']=='sent' and w['frame'].get('method')=='tools/call']
    received=[w['frame']['result'] for w in wire if w['direction']=='received' and 'result' in w['frame']]
    commits=[x for x in sent if x['params']['name']=='universe_commit']
    assert len(commits)>=3*len(r['publications'])
    assert sum(x.get('isError',False) for x in received)>=len(r['publications'])+3
    wire_records={}

    wire_receipts=[]
    for response in received:
        if response.get('isError'):continue
        result=response.get('structuredContent',{}).get('result',{})
        if isinstance(result,dict) and result.get('records'):
            revision=response['structuredContent']['frame']['revision']
            wire_records.setdefault(revision,[]).extend(result['records'])
        if isinstance(result,dict) and 'revision' in result:wire_receipts.append(result)
    for snap in r['snapshots']:
        assert all(row in wire_records.get(snap['revision'],[]) for row in snap['records']),'snapshot absent from MCP wire'
    for pub in r['publications']:
        assert pub['receipt'] in wire_receipts,'receipt absent from MCP wire'
    # Reconcile the owning enum, foundation fixture and new observed families.
    owning=(ROOT/'crates/universe-domain/src/records.rs').read_text()
    family_enum=re.search(r'pub enum RecordKind \{(.*?)\n\}',owning,re.S)[1]
    families={re.sub(r'(?<!^)(?=[A-Z])','_',name.strip()).lower() for name in family_enum.split(',') if name.strip()}
    foundation={x['payload']['record_kind'] for x in json.loads((ROOT/'fixtures/normalized-foundation/facts.json').read_text())['initial']}
    observed={row['payload']['record_kind'] for row in original.values()}
    previous={'rule','action_definition','event','assertion'}
    assert len(families)==38 and families==observed|foundation|previous
    return {'status':'passed','families':len(families),'observed_families':sorted(observed),'versions':len(v),
        'workflow_bodies':len(workflow),'publications':len(r['publications']),'mcp_calls':len(sent),
        'snapshots':len(r['snapshots']),'restarts':r['restarts'],'rejected_candidates':len(r['controls']),
        'source_sha256':digest,'media_sha256':d,'media_chunks':len(chunks),'history':'independent commit replay',
        'limitations':['Realm/Secret public creation absent; bootstrap uses existing Kernel and public historical adoption.',
            'Native UI, live-package conversion and broader evaluator semantics are outside this qualification.']}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args()
    print(json.dumps(audit(a.evidence),indent=2))
