"""Independent accounting oracle over typed SQLite reconstruction and MCP wire.
Expected quantities and admission outcomes are independent of driver operations.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
from audit_incremental_authoring import canonical_snapshot, encoded

EXPECTED=Path(__file__).resolve().parents[1]/'fixtures/pistol-workflow/expected.json'
RID=lambda n:f'rec_{200000+int(n):024x}'


def audit(path, check_database=True):
    e=json.loads(EXPECTED.read_text());r=json.loads(path.read_text());assert r['status']=='passed'
    assert r['expected_sha256']==hashlib.sha256(EXPECTED.read_bytes()).hexdigest()
    assert r['cleanup']['engine_stopped'] and r['cleanup']['installation_removed']
    assert not Path(r['cleanup']['owned_root']).exists()
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    received=[x['frame'].get('result',{}).get('structuredContent') for x in wire if x['direction']=='received']
    delivered=[row for env in received if env and isinstance(env.get('result'),dict) for row in env['result'].get('records',[]) if isinstance(row,dict) and 'payload' in row]
    versions={}
    for row in delivered:
        assert row['payload_digest']==hashlib.sha256((row['payload']['record_kind']+':').encode()+encoded(row['payload'])).hexdigest()
        assert versions.setdefault(row['record_version_id'],row)==row
    def rows(key):return r['snapshots'][key]['canonical']['records']
    for key,snapshot in r['snapshots'].items():
        c=snapshot['canonical']
        if check_database:assert canonical_snapshot(path.with_suffix('.sqlite'),c['revision'])['records']==c['records'],key
        assert set(c['records'])=={row['identity']['record_id'] for row in snapshot['mcp_records']}
        for row in snapshot['mcp_records']:assert row in delivered and row==c['records'][row['identity']['record_id']]
    assert set(r['states'])==set(e['queries'])
    for key,(snapshot,t,balances,holders) in e['queries'].items():
        env=r['states'][key];assert env in received and env['delivery']['complete']
        assert env['frame']['time']['time']['value']==t
        assert env['frame']['revision']==r['snapshots'][snapshot]['canonical']['revision'],key
        w=RID(61 if key=='other-world' else 60).replace('rec_','wld_');assert env['world_focus']==w
        objs=env['result']['objects'];assert len(objs)==6
        assert {o['identity']['identity']['record_id'] for o in objs}=={RID(n) for n in (4,5,8,9,18,19)}
        canon=rows(snapshot)
        for n,wanted in zip((4,5,8,9,18,19),balances):
            obj=next(o for o in objs if o['identity']['identity']['record_id']==RID(n))
            assert obj['identity']==canon[RID(n)] and obj['identity'] in delivered
            assert [a['payload']['name'] for a in obj['ancestry']]==e['ancestry'][str(n)] and obj['ancestry_complete']==(n!=9)
            assert not obj['conflicts'],key
            observed={};shared={}
            for category,target,mode in [('instance_facts',observed,'instance'),('shared_attributes',shared,'shared')]:
                for ev in obj[category]:
                    row=ev['record'];a=row['payload'];assert row in delivered and row==canon[row['identity']['record_id']]
                    assert a['attributeMode']==mode and a['polarity']=='support' and a['precision']=='exact'
                    assert ev['applicability'] is True and not ev['unknowns']
                    assert a['scope']['applicability']=={'kind':'worlds','world_ids':[w]}
                    p=canon[a['proposition']['record']];assert p in delivered
                    assert p['payload']['subject']['record']==RID(n if mode=='instance' else 17 if n==18 else 2)
                    predicate=p['payload']['predicate']['record'];target.setdefault(predicate,[]).append(p['payload']['value'])
                    if a.get('establishedBy'):
                        ev_id=a['establishedBy']['event']['record'];event=canon[ev_id]['payload']
                        assert any(f['slot']==a['establishedBy']['slot'] and f['proposition']==a['proposition'] for f in event['effects'])
            got={int(v['digits']) for v in observed.get(RID(10),[])}
            assert got==(set() if wanted is None else {wanted}),(key,n,'balance',got,wanted)
            expected_holder=holders[0 if n==4 else 1] if n in (4,5) else None
            got_holders={v['ref']['record'] for v in observed.get(RID(14),[])}
            assert got_holders==(set() if expected_holder is None else {RID(expected_holder)}),(key,n,'holder')
            assert set(observed)<= {RID(10),RID(14)}
            expected_shared=[] if key=='other-world' or n==9 else [{'kind':'boolean','value':n!=18}]
            assert shared.get(RID(15),[])==expected_shared and set(shared)<= {RID(15)}
            if n!=9:
                assert len(obj['initial_value_candidates'])==1
                assert obj['initial_value_candidates'][0]['record']['payload']['attributeMode']=='initial_value'
                assert len(obj['initialization_receipts'])==int((n==19)==(key=='other-world'))
                if obj['initialization_receipts']:
                    receipt=next(a for a in r['initialization_receipts'] if a['instance_id']==RID(n))
                    assert obj['initialization_receipts'][0]=={k:receipt[v] for k,v in [('instance','instance_id'),('start','start_event_id'),('property','predicate_id'),('definition','initial_definition_version'),('assertion','assertion_version'),('revision','revision_id'),('source_revision','source_revision')]}
                candidate=obj['initial_value_candidates'][0]['record'];assert candidate in delivered
                assert candidate==canon[candidate['identity']['record_id']]
    assert rows('historical')==rows('continued') and rows('final')==rows('restart')
    assert r['states']['restart']['result']==r['states']['final']['result']
    assert r['states']['restart-historical']['result']==r['states']['historical-at-10']['result']
    assert set(r['cases'])==set(e['admission'])
    for key,wanted in e['admission'].items():
        c=r['cases'][key];assert c['propose'] in received
        if wanted=='admitted':
            assert c['admitted'] and c['head_before']!=c['head_after']
            assert c['validation'] in received
        else:
            assert not c.get('admitted') and c['before']==c['after'] and c['head_before']==c['head_after']
            if wanted=='propose_rejected':assert c['propose']['code']=='STORAGE_FAILURE'
            else:
                assert c['validation'] in received and c['denied'] in received
                if wanted=='conflicting':
                    v=c['validation']['result']['execution'];assert v['coverage']=='complete' and any(f['outcome']=='conflicting' for f in v['findings'])
                    assert c['approval_returncode']!=0
                else:assert c['validation']['code']=='INVALID_ARGUMENT' and wanted in c['validation']['message']
    assert [p['key'] for p in r['publications']]==[key+'-commit' for key in e['publications']]
    assert r['retry_receipts']==[p['receipt'] for p in r['publications']]
    for p in r['publications']:
        v=p['validation'];assert v['coverage']=='complete' and all(f['outcome']=='supported' for f in v['findings'])
        assert any(env and env.get('result',{}).get('execution')==v for env in received)
        assert any(env and env.get('result')==p['receipt'] for env in received)
        approval=p['author_selection']['approval'];assert approval['approved']['proposal_id']==p['receipt']['proposal_id'] and approval['validation_run']==v['run_id']
        assert any(c['arguments'][0]=='approve' and c['returncode']==0 and json.loads(c['stdout'])==approval for c in r['author_cli'])
    for event_id,(owner,post,value,t) in e['effects'].items():
        for label in ('continued','final','restart'):
            event=rows(label)[RID(event_id)]['payload'];p=rows(label)[RID(post)]['payload']
            assert p['subject']['record']==RID(owner) and p['value']=={'kind':'integer','digits':str(value)}
            assert event['effects'][0]['proposition']['record']==RID(post)
            assert event['action']['record']==RID(31) and event['effects'][0]['slot']=='shot'
            assert [p['record']['record'] for p in event['participants'] if p['role']=='gun']==[RID(owner)]
            assert event['time']['value']==str(10 if event_id=='203' and label!='continued' else t)
    final=rows('final')
    uid=r['installation']['universe_id']
    assert final[RID(31)]['payload']['requirements']==[{'role':'gun','predicate':{'universe':uid,'record':RID(15)},'value':{'kind':'boolean','value':True}}]
    for n in (31,33):
        for slot in final[RID(n)]['payload']['consequenceContract']['slots']:
            assert slot['presence']=='required' and slot['target']['predicate']['record']==RID(10)
            assert slot['change']['minimum']=='0' and slot['change']['maximum']=='3' and slot['change']['unit'] is None
            assert slot['lifetime']=={'kind':'until_changed'}
    for a,delta in [(31,'-1'),(33,'2')]:assert final[RID(a)]['payload']['consequenceContract']['slots'][0]['change']['delta']==delta
    assert final[RID(33)]['payload']['consequenceContract']['slots'][1]['change']['delta']=='-2'
    for post,owner,value in [(250,4,2),(251,9,0)]:
        p=final[RID(post)]['payload'];assert p['subject']['record']==RID(owner) and p['value']['digits']==str(value)
    gap=e['gap'];p=final[RID(gap['proposition'])]['payload'];assert p['subject']['record']==RID(gap['owner']) and int(p['value']['digits'])==gap['after']
    direct=next(row['payload'] for row in final.values() if row['payload']['record_kind']=='assertion' and row['payload']['proposition']['record']==RID(gap['proposition']))
    assert 'establishedBy' not in direct and direct['validity']['start']['value']==gap['coordinate']
    assert not any(row['payload']['record_kind']=='event' and row['payload']['time']['value']==gap['coordinate'] for row in final.values())
    assert int(final[RID(gap['earlier_proposition'])]['payload']['value']['digits'])==gap['before']
    receipts=r['initialization_receipts'];assert len(receipts)==5 and {a['instance_id'] for a in receipts}=={RID(n) for n in e['initialization']}
    for receipt in receipts:
        owner=next(n for n in e['initialization'] if RID(n)==receipt['instance_id']);start,post=e['initialization'][owner]
        assert receipt['start_event_id']==RID(start) and receipt['predicate_id']==RID(10)
        definition=next(row for row in rows('definitions').values() if row['payload']['record_kind']=='assertion' and row['payload']['proposition']['record']==RID(11))
        assert receipt['initial_definition_version']==definition['record_version_id']
        initial=next(row for row in rows('started').values() if row['payload']['record_kind']=='assertion' and row['payload']['proposition']['record']==RID(post))
        assert receipt['assertion_version']==initial['record_version_id']
        assert receipt['revision_id']==r['snapshots']['started']['canonical']['revision']
        assert receipt['source_revision']==r['snapshots']['definitions']['canonical']['revision']
    if check_database:
        with closing(sqlite3.connect(path.with_suffix('.sqlite'))) as db:
            db.row_factory=sqlite3.Row
            assert [dict(row) for row in db.execute('SELECT * FROM initialization_receipt ORDER BY instance_id')]==receipts
            for p in r['publications']:assert [tuple(row) for row in db.execute('SELECT revision_id FROM operation_receipts WHERE idempotency_key=?',(p['key'],))]==[(p['receipt']['revision'],)]
    assert len(r['restart_instances'])==1 and r['restart_instances'][0]['before']!=r['restart_instances'][0]['after']
    return {'status':'passed','states':len(e['queries']),'snapshots':len(r['snapshots']),'publications':len(r['publications']),'admission_controls':len(e['admission']),'versions':len(versions),'initialization_receipts':len(receipts),'calls':len(r['mcp']),'gap':'reviewed non-event reserve increase admitted'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args();print(json.dumps(audit(a.evidence),sort_keys=True))
