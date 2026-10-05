"""Independent Goal 31 factual, receipt, history and received-wire oracle.

No initializer/compiler/evaluator imports. Canonical bodies use the existing
handwritten encoder; balances and bindings below are independently specified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'docs/decisions/relational-storage'))
from independent_audit import encoded


def audit(path):
    report=json.loads(path.read_text());assert report['status']=='passed'
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    received=[r['frame'].get('result',{}).get('structuredContent') for r in wire if r['direction']=='received']
    delivered=[r for envelope in received if envelope and isinstance(envelope.get('result'),dict) for r in envelope['result'].get('records',[]) if isinstance(r,dict) and 'payload' in r and 'record_version_id' in r]
    versions={}
    for record in delivered:
        digest=hashlib.sha256((record['payload']['record_kind']+':').encode()+encoded(record['payload'])).hexdigest()
        assert digest==record['payload_digest']
        old=versions.setdefault(record['record_version_id'],record);assert old==record
    rid=lambda n:f'rec_{200000+n:024x}'
    for label,snapshot in report['snapshots'].items():
        canonical=snapshot['canonical']['records']
        assert set(canonical)=={r['identity']['record_id'] for r in snapshot['mcp_records']}
        for record in canonical.values():
            assert record in delivered,(label,'record not received')
            assert record==versions[record['record_version_id']]
        assert all(r==canonical[r['identity']['record_id']] for r in snapshot['mcp_records'])
    for response in report['states'].values():
        assert response in received,'state not received'
    rows=lambda label:report['snapshots'][label]['canonical']['records']
    props=lambda state:{r['identity']['record_id']:r['payload'] for r in state['propositions']}
    expected={
        'a-start':{4:7},'shot-a-one':{4:6},'source-edit-before-b':{4:6},
        'b-start':{4:6,5:3},'definition-edit':{4:6,5:3},'consumed':{4:5,5:3},
        **{label:{4:5,5:3} for label in ('rename','refinement','holder-transfer','another-mention','another-scene','restart','historical')},
        'corrected-start':{4:8,5:None},'corrected':{4:6,5:3},
        'conflict':{8:None},'unresolved':{8:None},'historical-c-before-init':{8:None},'c-start':{4:6,5:3,8:9},
        'missing-current-stock':{8:None},'final':{4:6,5:3,8:9},
    }
    for label,balances in expected.items():
        state=report['states'][label]['result'];by_id={o['identity']['identity']['record_id']:o for o in state['objects']};propositions=props(state)
        assert set(by_id)=={rid(n) for n in balances},label
        for n,value in balances.items():
            object=by_id[rid(n)];actual=[]
            assert object['initialization_history_coverage']=='complete'
            for row in object['instance_facts']:
                a=row['record']['payload'];assert a['attributeMode']=='instance'
                p=propositions[a['proposition']['record']]
                if p['predicate']['record']!=rid(10):continue
                assert p['subject']['record']==rid(n) and a['polarity']=='support' and a['precision']=='exact' and row['applicability'] is True
                actual.append(p['value'])
            assert actual==([] if value is None else [{'kind':'integer','digits':str(value)}]),(label,n,actual,value)
            for row in object['initial_value_candidates']:
                assert row['record']['payload']['attributeMode']=='initial_value'
    # Every raw SQL receipt binds original immutable evidence and exact revisions.
    final_receipts=report['snapshots']['final']['all_receipts'];assert len(final_receipts)==3
    assert {r['instance_id'] for r in final_receipts}=={rid(4),rid(5),rid(8)}
    field_map={'instance_id':'instance','start_event_id':'start','predicate_id':'property','initial_definition_version':'definition','assertion_version':'assertion','revision_id':'revision','source_revision':'source_revision'}
    starts={4:(101,100,7,'a-start','definitions'),5:(111,110,3,'b-start','source-three'),8:(130,132,9,'c-start','resolved-candidate')}
    for receipt in final_receipts:
        n=next(n for n in starts if rid(n)==receipt['instance_id']);start,prop,value,admission,source_snapshot=starts[n]
        assert receipt['universe_id']==report['installation']['universe_id']
        assert receipt['start_event_id']==rid(start) and receipt['predicate_id']==rid(10)
        assert receipt['revision_id']==report['snapshots'][admission]['canonical']['revision']
        if source_snapshot:assert receipt['source_revision']==report['snapshots'][source_snapshot]['canonical']['revision']
        original=versions[receipt['assertion_version']];a=original['payload'];basis=a['basis']
        assert a['attributeMode']=='instance' and a['polarity']=='support' and a['precision']=='exact'
        assert basis['kind']=='instance_initialization' and basis['source_revision']==receipt['source_revision']
        assert basis['start']['record']==rid(start) and basis['definition']['version']==receipt['initial_definition_version']
        assert a['proposition']['record']==rid(prop)
        admitted=rows(admission);assert admitted[original['identity']['record_id']]==original
        p=admitted[rid(prop)]['payload'];assert p['subject']['record']==rid(n) and p['predicate']['record']==rid(10) and p['value']=={'kind':'integer','digits':str(value)}
        event=versions[basis['start']['version']];assert event==admitted[rid(start)] and event['payload']['occurrence']=='occurred'
        assert any(participant['record']['record']==rid(n) for participant in event['payload']['participants'])
        assert a['validity']['calendar']==event['payload']['time']['calendar'] and a['validity']['start']['value']==event['payload']['time']['value']
        source=versions[receipt['initial_definition_version']];assert source['identity']['record_id']==basis['definition']['record']
        source_a=source['payload'];assert source_a['attributeMode']=='initial_value' and source_a['precision']=='exact' and source_a['polarity']=='support'
        source_p=admitted[source_a['proposition']['record']]['payload'];assert source_p['subject']['record']==rid(1) and source_p['value']==p['value']
        assert a['scope']['applicability']=={'kind':'worlds','world_ids':[rid(60).replace('rec_','wld_')]}
        assert source_a['scope']['applicability']=={'kind':'universe_wide'}
    # Original receipts persist unchanged across every ordinary edit and retcon.
    original=report['snapshots']['consumed']['all_receipts'];assert len(original)==2
    assert report['bindings']['original_receipts']==original
    for label in ('mutations','corrected','conflict','unresolved'):
        assert report['snapshots'][label]['all_receipts']==original
    assert rows('mutations')==rows('historical-after-correction')
    assert rows('mutations')[rid(4)]['identity']==rows('corrected')[rid(4)]['identity']
    assert rows('mutations')[rid(4)]['payload']['classification']==rid(3)
    assert rows('mutations')[rid(3)]['payload']['parent']==rid(2)
    assert [n['text'] for n in rows('mutations')[rid(4)]['payload']['names']]==['Pistol A','North pistol']
    assert rows('mutations')[rid(43)]['payload']['value']=={'kind':'integer','digits':'7'}
    assert not any(r['payload']['record_kind']=='assertion' and r['payload']['proposition']['record']==rid(43) for r in rows('mutations').values())
    for label in ('conflict','unresolved'):
        object=report['states'][label]['result']['objects'][0]
        assert len(object['initial_value_candidates'])==2 and object['initialization_receipts']==[]
        assert len(object['conflicts'])==1 and object['conflicts'][0]['initial_values']
        assert object['conflicts'][0]['applicability'] is (True if label=='conflict' else None)
        precision={row['record']['payload']['precision'] for row in object['initial_value_candidates']}
        assert precision==({'exact'} if label=='conflict' else {'exact','unresolved'})
    # Public receipts are admitted-revision evidence, not today's corrected stock.
    for label,balances in expected.items():
        response=report['states'][label];revision=response['frame']['revision']
        for object in response['result']['objects']:
            owner=object['identity']['identity']['record_id']
            actual=object['initialization_receipts']
            candidates=[r for r in final_receipts if r['instance_id']==owner]
            if label in ('conflict','unresolved','historical-c-before-init'):candidates=[]
            assert actual==[{dest:r[source] for source,dest in field_map.items()} for r in candidates],label
    control_keys={c['key'] for c in report['controls']}
    assert control_keys=={'later-start-no-refill','same-start-no-refill','stale-source','conflicting-start-no-partial','unresolved-start-no-partial','expired-stock-no-bootstrap'}
    errors=[r['frame']['result']['structuredContent'] for r in wire if r['direction']=='received' and r['frame'].get('result',{}).get('isError')]
    for c in report['controls']:
        assert c['before']==c['after']
        assert c['response'] in errors and c['response'].get('code') in ('INVALID_ARGUMENT','STORAGE_FAILURE')
    failure=report['publication_failure'];assert failure['before']==failure['after'] and failure['receipts_before']==failure['receipts_after']==original
    assert failure['canonical_before']==failure['canonical_after']
    assert failure['response'] in errors and failure['response']['code']=='STORAGE_FAILURE'
    assert failure['before']['initialization_receipt']==2
    publications=report['publications'];assert len(publications)==18
    for publication in publications:
        assert publication['validation']['coverage']=='complete'
        assert publication['review']['latest'] is True
        assert publication['author_selection']['approval']['validation_run']==publication['validation']['run_id']
    # Exact proposal replay and restart reuse the same frozen result.
    proposals=[r for r in report['mcp'] if r['tool']=='universe_propose' and r['arguments'].get('idempotency_key')=='start-a']
    assert len(proposals)==3 and proposals[0]['result']['result']==proposals[1]['result']['result']==proposals[2]['result']['result']
    for key in ('start-a-commit','start-b-commit','start-c-commit'):
        calls=[r for r in report['mcp'] if r['tool']=='universe_commit' and r['arguments']['idempotency_key']==key and not r['expected_error']]
        assert len(calls)>=2 and all(r['result']['result']==calls[0]['result']['result'] for r in calls)
    return {'snapshots':len(report['snapshots']),'state_oracles':len(expected),'receipts':3,'reviewed_publications':len(publications),'rejected_controls':len(control_keys),'delivered_versions':len(versions)}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args();print(json.dumps(audit(a.evidence),sort_keys=True))
