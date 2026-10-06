"""Independent resource accounting and exact acceptance/history audit.
This reader uses retained typed SQL and a separately authored expected table;
it does not call the Rust continuity evaluator or consult head-membership cache.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
from audit_incremental_authoring import canonical_snapshot, encoded

EXPECTED=Path(__file__).resolve().parents[1]/'fixtures/resource-resolution/expected.json'
RID=lambda n:f'rec_{200000+int(n):024x}'
strip=lambda p:{k:v for k,v in p.items() if k!='record_kind'}

def audit(path,check_database=True):
    r=json.loads(path.read_text());e=json.loads(EXPECTED.read_text());assert r['status']=='executed'
    instructions=r['initialization_instructions']
    for phrase in ('universe_get_state','add_named_attribute','initialize_instance','resource:<predicate record ID>','universe_get_operation with the original idempotency key','continue from fresh canon facts'):
        assert phrase in instructions,phrase
    assert r['expected_sha256']==hashlib.sha256(EXPECTED.read_bytes()).hexdigest()
    assert r['cleanup']['engine_stopped'] and r['cleanup']['installation_removed'] and not Path(r['cleanup']['owned_root']).exists()
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    received=[w['frame'].get('result',{}).get('structuredContent') for w in wire if w['direction']=='received']
    delivered=[row for env in received if env and isinstance(env.get('result'),dict) for row in env['result'].get('records',[]) if isinstance(row,dict) and 'payload' in row]
    versions={}
    for row in delivered:
        assert hashlib.sha256((row['payload']['record_kind']+':').encode()+encoded(row['payload'])).hexdigest()==row['payload_digest']
        assert versions.setdefault(row['record_version_id'],row)==row
    rows=lambda key:r['snapshots'][key]['canonical']['records']
    for label,snapshot in r['snapshots'].items():
        canon=snapshot['canonical']
        if check_database:assert canonical_snapshot(path.with_suffix('.sqlite'),canon['revision'])['records']==canon['records'],label
        assert set(canon['records'])=={x['identity']['record_id'] for x in snapshot['mcp_records']}
        for row in snapshot['mcp_records']:assert row in delivered and row==canon['records'][row['identity']['record_id']],label
    def claim(canon,n):
        matches=[row for row in canon.values() if row['payload']['record_kind']=='assertion' and row['payload']['proposition']['record']==RID(n)]
        assert len(matches)==1,(n,'expected one asserted stock record');return matches[0]
    def fingerprint(canon,post):
        a=claim(canon,post)['payload'];prior=claim(canon,e['arrival']['prior'])['payload']
        world=RID(e['factual_workflow']['restricted_world']).replace('rec_','wld_')
        return hashlib.sha256(encoded([e['capability'],RID(e['policy']),canon[RID(e['policy'])]['payload'],RID(e['property']),canon[RID(e['property'])]['payload'],RID(post),strip(a),strip(canon[RID(post)]['payload']),world,[[strip(prior),strip(canon[RID(e['arrival']['prior'])]['payload'])]]])).hexdigest()
    author=next(c['stdout'].strip() for c in r['author_cli'] if c['arguments']==['init'] and c['returncode']==0)
    wf=e['factual_workflow'];actual=r['factual_workflow'];base=rows('baseline');initialized=rows('kit-initialized')
    assert all(actual[k] in received for k in ('before_initialization','after_initialization','stale_context_state','restricted_state'))
    before_obj=actual['before_initialization']['result']['objects'][0]
    after_obj=actual['after_initialization']['result']['objects'][0]
    assert before_obj['identity']==base[RID(wf['instance'])] and not before_obj['instance_facts'] and not before_obj['initialization_receipts']
    assert 'instance_state_not_established' in before_obj['unknowns']
    candidate=claim(base,wf['initial_attribute']);candidate_prop=base[candidate['payload']['proposition']['record']]['payload']
    assert candidate['payload']['attributeMode']=='initial_value' and int(candidate_prop['value']['digits'])==wf['units']
    assert candidate_prop['subject']['record']==RID(wf['definition']) and before_obj['initial_value_candidates'][0]['record']==candidate
    assert after_obj['identity']==initialized[RID(wf['instance'])] and len(after_obj['initialization_receipts'])==1 and len(after_obj['instance_facts'])==1
    assert 'instance_state_not_established' not in after_obj['unknowns']
    assert after_obj['instance_facts'][0]['applicability'] is True
    init=after_obj['instance_facts'][0]['record'];basis=init['payload']['basis']
    assert init in delivered and init==initialized[init['identity']['record_id']]
    init_prop=initialized[init['payload']['proposition']['record']]['payload']
    assert int(init_prop['value']['digits'])==wf['units'] and init_prop['subject']['record']==RID(wf['instance'])
    assert basis['kind']=='instance_initialization' and basis['start']['record']==RID(wf['start_event']) and basis['definition']['version']==candidate['record_version_id']
    start=initialized[RID(wf['start_event'])]['payload'];north=RID(wf['restricted_world']).replace('rec_','wld_')
    assert start['occurrence']=='occurred' and start['worlds']==[north] and start['time']['value']=='1'
    assert start['participants']==[{'record':{'universe':r['installation']['universe_id'],'record':RID(wf['instance'])},'role':'instance'}]
    assert actual['before_initialization']['frame']['revision']==actual['stale_context_state']['frame']['revision']==r['snapshots']['baseline']['canonical']['revision']
    assert actual['stale_context_state']['result']==actual['before_initialization']['result']
    assert actual['after_initialization']['frame']['revision']==r['snapshots']['kit-initialized']['canonical']['revision']
    restricted=actual['restricted_state'];restricted_obj=restricted['result']['objects'][0]
    assert restricted['authorization_scope']=='world-scoped grant' and restricted['world_focus']==north and restricted_obj['coverage']=='restricted'
    assert {'current_permissions_or_perspective_limit_evidence','instance_state_not_established'}<={*restricted_obj['unknowns']}
    restricted_call=next(x for x in r['mcp'] if x['tool']=='universe_get_state' and x.get('profile') and x['profile']!=author)
    assert restricted_call['profile']==r['private'][0]['request']['grant']['profile_id']
    regional=claim(initialized,wf['regional_attribute']);regional_scope=regional['payload']['scope']['applicability']
    assert regional_scope['world_ids']==[RID(wf['hidden_world']).replace('rec_','wld_')]
    assert not any(x['record']['identity']['record_id']==regional['identity']['record_id'] for x in restricted_obj['shared_attributes'])
    seed=next(x['arguments'] for x in r['mcp'] if x['tool']=='universe_propose' and x['arguments'].get('idempotency_key')=='baseline')
    assert {'introduce_definition','introduce_instance','add_named_attribute'}<={op['kind'] for op in seed['operations']}
    receipt=after_obj['initialization_receipts'][0]
    assert receipt['start']==RID(wf['start_event']) and receipt['definition']==candidate['record_version_id']
    assert receipt['assertion']==init['record_version_id'] and receipt['revision']==r['snapshots']['kit-initialized']['canonical']['revision']
    assert receipt['source_revision']==r['snapshots']['baseline']['canonical']['revision']
    if check_database:
        with closing(sqlite3.connect(path.with_suffix('.sqlite'))) as db:
            stored=db.execute('SELECT universe_id,instance_id,start_event_id,predicate_id,initial_definition_version,assertion_version,revision_id,source_revision FROM initialization_receipt WHERE instance_id=?',(RID(wf['instance']),)).fetchone()
        assert stored==(r['installation']['universe_id'],RID(wf['instance']),RID(wf['start_event']),receipt['property'],candidate['record_version_id'],init['record_version_id'],receipt['revision'],receipt['source_revision'])
    assert set(r['states'])==set(e['queries'])
    for label,(snapshot,t,balances,acceptance) in e['queries'].items():
        env=r['states'][label];assert env in received and env['delivery']['complete'] and env['world_focus'] is None
        assert env['frame']['revision']==r['snapshots'][snapshot]['canonical']['revision']
        assert env['frame']['time']['time']['value']==t
        canon=rows(snapshot);objects=env['result']['objects'];assert len(objects)==len(e['owners'])
        assert {o['identity']['identity']['record_id'] for o in objects}=={RID(n) for n in e['owners']}
        for owner,wanted in zip(e['owners'],balances):
            obj=next(o for o in objects if o['identity']['identity']['record_id']==RID(owner));assert obj['identity']==canon[RID(owner)] and obj['identity'] in delivered
            assert not obj['conflicts'] and not obj['shared_attributes'] and not obj['initial_value_candidates']
            observed=[]
            for evidence in obj['instance_facts']:
                row=evidence['record'];a=row['payload'];assert row in delivered and row==canon[row['identity']['record_id']]
                p=canon[a['proposition']['record']];assert p in delivered
                assert p['payload']['subject']['record']==RID(owner) and p['payload']['predicate']['record']==RID(e['property'])
                assert a['attributeMode']=='instance' and a['polarity']=='support' and a['precision']=='exact'
                assert a['scope']['applicability']=={'kind':'universe_wide'} and a['scope']['context']==p['payload']['context']
                assert evidence['applicability'] is True
                observed.append(int(p['payload']['value']['digits']))
                if owner==e['arrival']['owner'] and acceptance:
                    post,value=e['acceptances'][str(acceptance)];fp=fingerprint(canon,post)
                    assert observed==[value] and evidence['unknowns']==['resource_arrival_unexplained:'+fp]
                    assert 'establishedBy' not in a
                    assert a['validity']['start']['value']==e['arrival']['start'] and a['validity']['end']['value']==e['arrival']['end']
                    decision=canon[RID(acceptance)];assert decision in delivered and decision in obj['dependencies']
                    d=decision['payload'];assert d['mode']=='accept' and d['fingerprints']==[fp] and d['scope']=='resource:'+RID(post)
                    assert d['principal']==author.replace('prf_','prn_',1) and d['rationale'].strip()
                    assert 'resource_arrival_unexplained' in obj['unknowns']
                else:
                    assert not evidence['unknowns'],(label,owner)
                    if a.get('establishedBy'):
                        event=canon[a['establishedBy']['event']['record']]['payload']
                        assert any(f['slot']==a['establishedBy']['slot'] and f['proposition']==a['proposition'] for f in event['effects'])
            assert observed==([] if wanted is None else [wanted]),(label,owner,observed,wanted)
    final=rows('final');old=rows('accepted-two')
    assert rows('historical')==old and rows('restart')==final
    assert r['states']['historical']['result']==r['states']['restart-historical']['result']==r['states']['accepted-two']['result']
    assert r['states']['final']['result']==r['states']['restart']['result']
    assert RID(101) not in old and RID(100) in old
    assert final[RID(100)]==old[RID(100)] and fingerprint(old,91)!=fingerprint(final,92)
    assert rows('baseline')[RID(e['arrival']['original'])]['payload']['value']['digits']==str(e['arrival']['original_value'])
    assert final[RID(e['arrival']['prior'])]['payload']['value']['digits']=='1'
    assert claim(final,e['arrival']['prior'])['payload']['validity']['end']['value']=='5'
    policy=final[RID(e['policy'])]['payload'];assert policy['capabilities']==[e['capability']] and policy['targetPredicates']==['resolution:rounds'] and policy['commitPolicy']=='block_unless_exception' and policy['executable']
    assert set(r['cases'])==set(e['blocked'])
    for label,c in r['cases'].items():
        assert c['before']==c['after'] and c['validation']['coverage']=='complete'
        assert c['denied'] in received and c['retry'] in received and c['denied']['code']=='APPROVAL_STALE' and c['retry']['code']=='APPROVAL_STALE'
        assert any(env and env.get('result',{}).get('execution')==c['validation'] for env in received)
        assert any(f['outcome']=='not_established' and f['rule_id']==RID(e['policy']) for f in c['validation']['findings'])
        p=c['proposal'];v=c['validation']
        assert any(a['arguments']==['approve','The Cairn Archive Pilot',p['proposal_id'],str(p['version']),p['digest'],v['run_id']] and a['returncode']!=0 for a in r['author_cli'])
        assert c['head']==c['proposal']['base_frame']['revision']
    assert r['author_profile']==author
    assert r['forged_acceptance']['validation'] in received and r['forged_acceptance']['validation']['code']=='POLICY_DENIED'
    assert r['forged_acceptance']['denied'] in received and r['forged_acceptance']['before']==r['forged_acceptance']['after']
    assert r['old_approval_reuse'] in received and r['old_approval_reuse']['code']=='APPROVAL_STALE'
    assert r['old_commit_key_reuse'] in received and r['old_commit_key_reuse'].get('code')
    unresolved=r['cases']['unresolved'];changed=r['cases']['changed-claim']
    assert any(f['fingerprint']==fingerprint(old,91) and f['outcome']=='not_established' for f in unresolved['validation']['findings'])
    assert any(f['fingerprint']==fingerprint(final,92) and f['outcome']=='not_established' for f in changed['validation']['findings'])
    assert unresolved['head']==r['snapshots']['kit-initialized']['canonical']['revision']
    assert changed['head']==r['snapshots']['accepted-two']['canonical']['revision']
    assert r['cases']['uncorrected-evidence']['head']==r['snapshots']['accounted']['canonical']['revision']
    assert r['restart_denied'] in received and r['restart_denied']['code']=='APPROVAL_STALE' and r['restart_ordinary_approval_returncode']!=0
    assert [p['key'] for p in r['publications']]==[s+'-commit' for s in e['publications']]
    assert r['retry_receipts']==[p['receipt'] for p in r['publications']]
    assert len(r['recovered_operations'])==len(r['publications'])
    recovered_calls=[call for call in r['mcp'] if call['tool']=='universe_get_operation' and call['arguments'].get('operation_kind')=='commit']
    assert len(recovered_calls)==len(r['publications'])
    calls_by_key={call['arguments']['idempotency_key']:call for call in recovered_calls}
    for publication,recovered in zip(r['publications'],r['recovered_operations']):
        key=publication['commit_arguments']['idempotency_key']
        call=calls_by_key[key]
        assert recovered['idempotency_key']==key==call['arguments']['idempotency_key']
        assert recovered['result']==call['result']['result'] and recovered['result']['state']=='succeeded'
        assert recovered['result']['receipt']==publication['receipt']
        assert call['result'] in received
    for p in r['publications']:
        assert p['without_approval'] in received and p['without_approval']['code']=='APPROVAL_REQUIRED'
        v=p['validation'];assert v['coverage']=='complete'
        assert all(f['outcome'] in ('supported','not_established') for f in v['findings'])
        assert any(env and env.get('result',{}).get('execution')==v for env in received)
        assert any(env and env.get('result')==p['receipt'] for env in received)
        approval=p['approval'];assert approval['validation_run']==v['run_id'] and approval['approved']['proposal_id']==p['receipt']['proposal_id']
        assert any(c['arguments'][0]=='approve' and c['profile']==author and c['returncode']==0 and json.loads(c['stdout'])==approval for c in r['author_cli'])
    for case in (e['accounted_event'],e['reload']):
        event=final[RID(case['event'])]['payload'];assert event['time']['value']==case['time'] and event['action']['record']==RID(case['action'])
        slots=final[RID(case['action'])]['payload']['consequenceContract']['slots'];assert [s['change']['delta'] for s in slots]==case['deltas']
        for effect,(owner,post,value) in zip(event['effects'],case['post']):
            p=final[RID(post)]['payload'];assert effect['proposition']['record']==RID(post) and p['subject']['record']==RID(owner) and int(p['value']['digits'])==value
    for event_id,post,t,value in e['shots']:
        event=final[RID(event_id)]['payload'];assert event['time']['value']==t and event['action']['record']==RID(32) and event['effects'][0]['proposition']['record']==RID(post)
        assert final[RID(post)]['payload']['value']['digits']==str(value)
    assert r['event_rejection']['before']==r['event_rejection']['after']
    assert r['event_rejection']['response'] in received and 'underflow' in r['event_rejection']['response']['message'] and r['event_rejection']['denied'] in received
    assert r['reload_rejection']['before']==r['reload_rejection']['after']
    assert r['reload_rejection']['response'] in received and 'underflow' in r['reload_rejection']['response']['message'] and r['reload_rejection']['denied'] in received
    correction=e['correction'];a=claim(final,correction['replacement'])['payload']
    assert a['validity']['start']['value']=='0' and a['validity']['end']['value']=='5'
    assert int(final[RID(correction['replacement'])]['payload']['value']['digits'])==correction['corrected_value']
    assert int(rows('baseline')[RID(correction['original'])]['payload']['value']['digits'])==1
    assert claim(final,correction['later'])['payload']['validity']['start']['value']=='5'
    # The accounted event at 5 belongs to reserve 7, not unexplained reserve 9.
    assert not any(row['payload']['record_kind']=='event' and row['payload']['time']['value']==e['arrival']['start'] and any(p['record']['record']==RID(e['arrival']['owner']) for p in row['payload']['participants']) for row in final.values())
    if check_database:
        with closing(sqlite3.connect(path.with_suffix('.sqlite'))) as db:
            for p in r['publications']:assert db.execute('SELECT revision_id FROM operation_receipts WHERE idempotency_key=?',(p['key'],)).fetchall()==[(p['receipt']['revision'],)]
            for recovered in r['recovered_operations']:
                assert db.execute('SELECT revision_id FROM operation_receipts WHERE operation_kind=? AND idempotency_key=?',('commit',recovered['idempotency_key'])).fetchall()==[(recovered['result']['receipt']['revision'],)]
    assert len(r['restart_instances'])>=3 and all(x['before']!=x['after'] for x in r['restart_instances'])
    return {'status':'passed','calls':len(r['mcp']),'publications':len(r['publications']),'snapshots':len(r['snapshots']),'states':len(r['states']),'blocked_candidates':len(r['cases']),'versions':len(versions),'acceptances':2,'initializations':1,'restricted_state_views':1,'interrupted_receipt_recovered':True,'forced_restarts':len(r['restart_instances']),'acceptance_fingerprints':'reconstructed independently from exact claim, policy and predecessor contents'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args();print(json.dumps(audit(a.evidence),sort_keys=True))
