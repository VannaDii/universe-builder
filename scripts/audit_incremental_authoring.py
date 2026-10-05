"""Independent relational reconstruction and received-wire Goal 30 assertions.

No service/compiler code or cached membership projection is used for readback.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'docs/decisions/relational-storage'))
from independent_audit import reader, encoded


def canonical_snapshot(package, revision):
    with closing(sqlite3.connect('file:'+str(package)+'?mode=ro',uri=True)) as db:
        db.row_factory=sqlite3.Row
        assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        models=json.loads((ROOT/'docs/decisions/relational-storage/catalog.json').read_text())['models']
        decode=reader(db,models)
        versions={}
        for r in db.execute('SELECT * FROM record_versions'):
            payload=decode('Payload',r['payload_row'])
            assert hashlib.sha256((r['kind']+':').encode()+encoded(payload)).hexdigest()==r['digest']
            versions[r['id']]={'record_version_id':r['id'],'identity':{'universe_id':r['universe_id'],'record_id':r['record_id'],'record_kind':r['kind']},'payload':payload,'payload_digest':r['digest']}
        chain=[];at=revision
        while at:
            commit=db.execute('SELECT * FROM commits WHERE id=?',(at,)).fetchone();assert commit
            chain.append(commit);at=commit['parent_id']
        membership={}
        for commit in reversed(chain):
            for c in db.execute('SELECT * FROM commit_changes WHERE revision_id=?',(commit['id'],)):
                assert membership.get(c['record_id'])==c['prior_version']
                if c['version_id'] is None:membership.pop(c['record_id'])
                else:membership[c['record_id']]=c['version_id']
        return {'revision':revision,'records':{rid:versions[version] for rid,version in membership.items()},'verified_versions':len(versions)}


def audit(path):
    report=json.loads(path.read_text())
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    received=[r['frame'].get('result',{}).get('structuredContent') for r in wire if r['direction']=='received']
    delivered=[r for response in received if response and isinstance(response.get('result'),dict) for r in response['result'].get('records',[])]
    rid=lambda n:f'rec_{200000+n:024x}'
    for label,snapshot in report['snapshots'].items():
        canonical=snapshot['canonical']['records']
        assert set(canonical)=={r['identity']['record_id'] for r in snapshot['mcp_records']}
        for record in canonical.values():
            assert hashlib.sha256((record['payload']['record_kind']+':').encode()+encoded(record['payload'])).hexdigest()==record['payload_digest']
        for r in snapshot['mcp_records']:
            assert r in delivered,('not delivered',label)
            assert all(r[k]==canonical[r['identity']['record_id']][k] for k in canonical[r['identity']['record_id']]),label
    rows=lambda label:report['snapshots'][label]['canonical']['records']
    payload=lambda label,n:rows(label)[rid(n)]['payload']
    tree=payload('minimal',1)
    assert tree=={'record_kind':'entity_type','namespace':'incremental','key':'tree','labels':{},'name':'Tree','parent':None,'parentResolution':'root','applicability':{'kind':'universe_wide'},'classificationExecutable':True}
    minimal=payload('minimal',4)
    assert minimal['classification'] is None and minimal['classificationResolution']=='unclassified'
    assert minimal['names']==[{'text':'North tree','language':None,'community':None,'role':None,'validity':{'kind':'unknown'}}]
    assert minimal['labels']==minimal['metadata']=={}
    assert minimal['worldAssociations']==[{'world':rid(60).replace('rec_','wld_'),'role':'setting','validity':{'kind':'unknown'},'qualifiers':{}}]
    classified=payload('tree',4);cedar=payload('cedar',4)
    assert classified=={**minimal,'classification':rid(1),'classificationResolution':'resolved'}
    assert cedar=={**classified,'classification':rid(2)}
    assert rows('minimal')[rid(4)]['identity']==rows('cedar')[rid(4)]['identity']
    assert payload('cedar',2)['parent']==rid(1)
    assert rows('attributes')[rid(4)]==rows('tree')[rid(4)]
    for n,key,subject,mode,value in [(10,'climbable',1,'shared',{'kind':'boolean','value':True}),(11,'climbing_hazard',4,'instance',{'kind':'text','text':'Broken upper branch'}),(12,'inspection_note',4,'instance',{'kind':'text','text':'Growth inspection pending'}),(28,'climbing_hazard',5,'instance',{'kind':'text','text':'Loose bark'})]:
        canonical=rows('reuse');proposition=canonical[rid(n)]['payload']
        assert proposition['subject']['record']==rid(subject) and proposition['value']==value
        predicate=canonical[proposition['predicate']['record']]['payload']
        assert predicate['namespace']=='incremental' and predicate['key']==key
        assertions=[r['payload'] for r in canonical.values() if r['payload']['record_kind']=='assertion' and r['payload']['proposition']['record']==rid(n)]
        assert len(assertions)==1
        a=assertions[0]
        assert a['attributeMode']==mode and a['polarity']=='support' and a['precision']==('unresolved' if n==12 else 'exact')
        assert a['basis']=={'kind':'author_decision','note':'Author: '+key}
        assert 'establishedBy' not in a
        assert a['scope']['context']==proposition['context']
        assert a['scope']['applicability']=={'kind':'worlds','world_ids':[rid(60).replace('rec_','wld_')]}
        if n==12:assert a['validity']=={'kind':'unknown'}
        else:
            assert a['validity']['start']=={'kind':'exact','value':'0'} and a['validity']['end']=={'kind':'exact','value':'30'}
    properties=[r['payload']['key'] for r in rows('reuse').values() if r['payload']['record_kind']=='property']
    assert sorted(properties)==['climbable','climbing_hazard','inspection_note']
    assert rows('restart')==rows('reuse')
    assert rows('historical')==rows('minimal')
    for control in report['controls']:
        assert control['response'] in received
        assert control['before']==control['after'] and control['response'].get('code'),control['key']
    for label in ['invalid_value','authority']:
        assert report[label]['before']==report[label]['after']
    assert report['invalid_value']['approval_exit']!=0
    assert report['invalid_value']['validation']['code']=='INVALID_ARGUMENT'
    assert report['authority']['denied'].get('code')
    assert all(rid(n) not in rows('restart') for n in [3,20,21,22,24,25,26,27,30])
    assert any(response and response.get('result')==report['state'] for response in received)
    state=report['state'];obj=state['objects'][0]
    assert obj['identity']['identity']['record_id']==rid(4)
    assert [r['identity']['record_id'] for r in obj['ancestry']]==[rid(2),rid(1)]
    assert len(obj['shared_attributes'])==1
    assert len(obj['instance_facts'])==2
    assert obj['instance_facts'][1]['applicability'] is None or obj['instance_facts'][0]['applicability'] is None
    second=report['second_state']['objects'][0]
    assert any(response and response.get('result')==report['second_state'] for response in received)
    assert len(second['shared_attributes'])==1 and len(second['instance_facts'])==1
    assert second['instance_facts'][0]['record']['payload']['proposition']['record']==rid(28)
    assert not any(r['payload'].get('key') in ('height','unit','growth_conditions') for r in rows('restart').values())
    failure=report['publication_failure']
    assert failure['before']==failure['after'] and failure['canonical_before']==failure['canonical_after']
    assert failure['response'].get('code')=='STORAGE_FAILURE'
    assert len(report['publications'])==5
    for p in report['publications']:
        assert p['validation']['coverage']=='complete'
        assert any(response and response.get('result')==p['receipt'] for response in received)
        approval=p['author_selection']['approval']
        assert approval['approved']['proposal_id']==p['receipt']['proposal_id']
        assert approval['validation_run']==p['validation']['run_id']
    print(f'PASS: {len(report["snapshots"])} independent canonical snapshots, 5 approved commits, {len(report["controls"])} atomic rejection controls, retry/restart, identity/scope/evidence/unknowns')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args();audit(a.evidence)
