"""Independent Cedar oracle over received MCP and reconstructed typed SQLite.

Expected facts are authored separately from the driver, compiler and evaluator.
No active head-membership cache or writer code supplies snapshot authority.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
from audit_incremental_authoring import canonical_snapshot, encoded

ROOT=Path(__file__).resolve().parents[1]
EXPECTED=ROOT/'fixtures/cedar-workflow/expected.json'
RID=lambda n:f'rec_{200000+n:024x}'


def audit(path, check_database=True):
    expected=json.loads(EXPECTED.read_text())
    report=json.loads(path.read_text());assert report['status']=='passed'
    assert report['expected_sha256']==hashlib.sha256(EXPECTED.read_bytes()).hexdigest()
    assert report['cleanup']['engine_stopped'] and report['cleanup']['installation_removed']
    assert not Path(report['cleanup']['owned_root']).exists()
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    received=[row['frame'].get('result',{}).get('structuredContent') for row in wire if row['direction']=='received']
    delivered=[r for envelope in received if envelope and isinstance(envelope.get('result'),dict) for r in envelope['result'].get('records',[]) if isinstance(r,dict) and 'payload' in r]
    versions={}
    for row in delivered:
        digest=hashlib.sha256((row['payload']['record_kind']+':').encode()+encoded(row['payload'])).hexdigest()
        assert digest==row['payload_digest']
        assert versions.setdefault(row['record_version_id'],row)==row
    for label,snapshot in report['snapshots'].items():
        captured=snapshot['canonical']
        if check_database:
            actual=canonical_snapshot(path.with_suffix('.sqlite'),captured['revision'])
            assert actual['records']==captured['records'],(label,'typed database differs')
        assert set(captured['records'])=={r['identity']['record_id'] for r in snapshot['mcp_records']}
        for row in snapshot['mcp_records']:
            assert row in delivered and row==captured['records'][row['identity']['record_id']],label
    rows=lambda label:report['snapshots'][label]['canonical']['records']
    payload=lambda label,n:rows(label)[RID(n)]['payload']
    tree=payload('definition',1)
    assert tree=={'record_kind':'entity_type',**expected['definition'],'labels':{},'parent':None,'parentResolution':'root','applicability':{'kind':'universe_wide'},'classificationExecutable':True}
    assert not any(r['payload']['record_kind'] in ('property','unit','entity','action_definition') for r in rows('definition').values())
    first=payload('minimal',4);cedar=payload('cedar',4)
    assert first['classification']==RID(1) and first['classificationResolution']=='resolved'
    assert first['names'][0]['text']==expected['instance']['name']
    assert first['names'][0]['validity']['start']['value']==expected['instance']['exists_from']
    assert cedar=={**first,'classification':RID(2)}
    assert rows('minimal')[RID(4)]['identity']==rows('unresolved')[RID(4)]['identity']
    assert payload('cedar',2)['parent']==RID(1)
    assert not any(r['payload']['record_kind']=='unit' or r['payload'].get('key') in ('height','adequate_water','growing_season') for r in rows('cedar').values())
    unit=payload('height',40)
    assert unit['key']==expected['change']['unit_key'] and unit['dimension']==expected['change']['dimension']
    properties={r['payload']['key']:r['identity']['record_id'] for r in rows('height').values() if r['payload']['record_kind']=='property'}
    assert report['properties']==properties
    assert set(report['states'])==set(expected['states'])
    world=RID(60).replace('rec_','wld_')
    frame_context=report['installation']['context_id']
    for label,wanted in expected['states'].items():
        envelope=report['states'][label];assert envelope in received and envelope['delivery']['complete']
        revision_label,day=expected['queries'][label]
        canonical=rows(revision_label)
        assert envelope['frame']['revision']==report['snapshots'][revision_label]['canonical']['revision']
        assert envelope['frame']['time']['time']['value']==day
        assert envelope['world_focus']==world
        state=envelope['result'];assert len(state['objects'])==1
        obj=state['objects'][0]
        assert obj['identity']['identity']['record_id']==RID(4)
        assert obj['identity'] in delivered and obj['identity']==canonical[RID(4)]
        assert [r['payload']['name'] for r in obj['ancestry']]==([wanted['classification'],'Tree'] if wanted['classification']=='Cedar' else ['Tree'])
        assert obj['ancestry_complete'] and not obj['initial_value_candidates'] and not obj['conflicts']
        propositions={r['identity']['record_id']:r for r in [*state['propositions'],*obj['dependencies']] if r['payload']['record_kind']=='proposition'}
        observed={};shared={}
        for category,target,mode,owner in [('instance_facts',observed,'instance',4),('shared_attributes',shared,'shared',1)]:
            for evidence in obj[category]:
                row=evidence['record'];assert row in delivered and row==canonical[row['identity']['record_id']]
                a=row['payload'];assert a['attributeMode']==mode and a['polarity']=='support'
                assert a['scope']['applicability']=={'kind':'worlds','world_ids':[world]}
                assert a['scope']['context']['record']==frame_context
                proposition=propositions[a['proposition']['record']];assert proposition in delivered
                p=proposition['payload'];assert p['subject']['record']==RID(owner)
                key=next(k for k,rid in properties.items() if rid==p['predicate']['record'])
                assert key not in target,(label,'multiple visible values',key)
                target[key]=(p['value'],evidence,a)
                if key=='adequate_water' and label=='unresolved':
                    assert a['validity']['kind']==expected['unknown_water']['validity'] and a['precision']==expected['unknown_water']['precision']
                    assert evidence['applicability'] is None and evidence['unknowns']
                else:
                    assert evidence['applicability'] is True and a['precision']=='exact'
        wanted_height=wanted['height']
        keys=set() if label=='before_existence' else {'exists','physical_location'}
        if label not in ('minimal','before_existence'):keys.add('climbing_hazard')
        if wanted_height is not None:keys.add('height')
        if label in ('corrected_before','corrected_after','restart_before','restart_after','unresolved'):keys.add('adequate_water')
        assert set(observed)==keys,(label,'unexpected or missing facts')
        assert observed.get('height',(None,))[0]==(None if wanted_height is None else {'kind':'quantity','value':{'kind':'integer','digits':wanted_height},'unit':RID(40).replace('rec_','unit_')}),(label,'height')
        if wanted_height is not None:
            a=observed['height'][2]
            later=label in ('after_change','far_future','corrected_after','historical_after','restart_after','restart_historical','unresolved')
            assert a['validity']['start']['value']==('10' if later else '0')
            assert a['validity']['end']==({'kind':'unbounded'} if later else {'kind':'exact','value':'10'})
            if later:
                assert a.get('establishedBy')=={'event':{'universe':report['installation']['universe_id'],'record':RID(51)},'slot':'height'}
            else: assert 'establishedBy' not in a
        if wanted.get('existence_established',True):
            assert observed['exists'][0]=={'kind':'boolean','value':True}
            assert observed['physical_location'][0]=={'kind':'text','text':expected['instance']['location']}
        else:
            assert not observed and not shared and obj['coverage']=='partial'
        if label not in ('minimal','before_existence'):
            assert shared['grows'][0]=={'kind':'boolean','value':expected['shared']['grows']}
            assert observed['climbing_hazard'][0]=={'kind':'text','text':expected['instance_only']['climbing_hazard']}
            assert set(shared)=={'grows'} and 'grows' not in observed
        if wanted_height is not None:
            growth=next(r['record'] for r in obj['behavioral_requirements'] if r['record']['identity']['record_id']==RID(55))
            assert growth in delivered
            assert [next(k for k,rid in properties.items() if rid==q['predicate']['record']) for q in growth['payload']['requirements']]==expected['growth_requirements']
            assert 'growing_season' not in observed
            if label in ('before_change','after_change','far_future','historical_before','historical_after','restart_historical'):
                assert 'adequate_water' not in observed
        if label=='unresolved':assert obj['coverage']=='partial' and obj['unknowns']
        assert report['read_counts'][label]['before']==report['read_counts'][label]['after']
    assert report['retained_state'] in received
    assert report['retained_state']['result']==report['states']['before_change']['result']
    assert report['retained_state']['frame']==report['states']['before_change']['frame']
    assert rows('historical')==rows('changed')
    assert rows('corrected')==rows('restart')
    for left,right in [('corrected_before','restart_before'),('corrected_after','restart_after'),('historical_after','restart_historical')]:
        assert report['states'][left]['result']==report['states'][right]['result']
    assert set(report['cases'])==set(expected['admission'])
    for key,status in expected['admission'].items():
        case=report['cases'][key];assert case['rejection'] in received and case['denied'] in received
        assert case['denied'].get('code') and case['before']==case['after']
        if key.startswith('conflicting_'):
            v=case['rejection']['result']['execution']
            assert v['coverage']=='complete' and any(f['outcome']=='conflicting' and len(f['evidence'])==2 for f in v['findings'])
        else:
            assert case['rejection']['code']=='INVALID_ARGUMENT'
            message=case['rejection']['message']
            if key=='partial_height_correction':assert 'pre-value plus declared change' in message
            else:
                requirement='growing_season' if key=='missing_season' else 'adequate_water'
                assert 'required attribute cedar_workflow:'+requirement in message
                assert 'on entity '+RID(4) in message
                assert ('complete: false' if status=='unresolved' else 'complete: true') in message
    assert report['context'] in received and report['context']['delivery']['complete']
    context_rows=report['context']['result']['records']
    assert {RID(n) for n in (1,2,4,10,11,12,13)} <= {r['identity']['record_id'] for r in context_rows}
    assert all(r==rows('cedar')[r['identity']['record_id']] for r in context_rows)
    impact=report['correction_impact'];assert impact in received and impact['delivery']['complete']
    assert impact['result']['coverage']=='complete' and RID(51) in impact['result']['records']
    before={r['identity']['record_id']:r for r in report['affected_before']}
    after={r['identity']['record_id']:r for r in report['affected_after']}
    assert all(r in delivered for r in [*before.values(),*after.values()])
    assert before[RID(51)]['record_version_id']!=after[RID(51)]['record_version_id']
    assert before[RID(51)]['payload']['effects'][0]['proposition']['record']==RID(52)
    assert after[RID(51)]['payload']['effects'][0]['proposition']['record']==RID(81)
    assert payload('changed',52)['value']['value']['digits']=='31' and payload('corrected',81)['value']['value']['digits']==expected['correction']['downstream_height']
    assert payload('corrected',83)['value']['value']['digits']==expected['correction']['earlier_height']
    action=payload('corrected',50)['consequenceContract']['slots'][0]
    assert action['change']['delta']==expected['change']['delta'] and action['change']['unit']==RID(40).replace('rec_','unit_')
    assert payload('corrected',51)['time']['value']==expected['change']['time']
    assert [p['key'] for p in report['publications']]==[k+'-commit' for k in ['minimal-tree','existence-location','capability-hazard','refine-cedar','height-and-conditions','authored-behavior','authored-height-change','author-water-answer','complete-height-correction','unresolved-water']]
    for publication in report['publications']:
        validation=publication['validation'];assert validation['coverage']=='complete' and all(f['outcome']=='supported' for f in validation['findings'])
        assert any(r and r.get('result',{}).get('execution')==validation for r in received)
        assert any(r and r.get('result')==publication['receipt'] for r in received)
        approval=publication['author_selection']['approval']
        assert approval['approved']['proposal_id']==publication['receipt']['proposal_id'] and approval['validation_run']==validation['run_id']
        assert any(c['arguments'][0]=='approve' and c['returncode']==0 and json.loads(c['stdout'])==approval for c in report['author_cli'])
    if check_database:
        with closing(sqlite3.connect('file:'+str(path.with_suffix('.sqlite'))+'?mode=ro',uri=True)) as db:
            for p in report['publications']:
                receipts=db.execute('SELECT revision_id FROM operation_receipts WHERE idempotency_key=?',(p['key'],)).fetchall()
                assert receipts==[(p['receipt']['revision'],)],'receipt not durable or duplicated'
    assert len(report['restart_instances'])==2 and all(r['before']!=r['after'] for r in report['restart_instances'])
    return {'status':'passed','snapshots':len(report['snapshots']),'states':len(expected['states']),'admission_controls':len(expected['admission']),'publications':len(report['publications']),'versions':len(versions),'typed_database':'reconstructed for every revision','impact':'conservative full-universe closure; authored delta event inspected'}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args();print(json.dumps(audit(a.evidence),sort_keys=True))
