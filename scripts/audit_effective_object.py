"""Independent expected-table audit of received MCP envelopes and exact sources."""
import argparse
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def audit(path):
    report=json.loads(path.read_text())
    expected=json.loads((ROOT/'fixtures/effective-object/expected.json').read_text())
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    received=[r['frame'].get('result',{}).get('structuredContent') for r in wire if r['direction']=='received']
    rid=lambda n:f'rec_{200000+n:024x}'
    number=lambda r:int(r.removeprefix('rec_'),16)-200000
    sources={r['record_version_id']:r for r in report['source_records']}
    if 'current_action' in report: sources[report['current_action']['record_version_id']]=report['current_action']
    delivered_records=[r for response in received if response and isinstance(response.get('result'),dict) for r in response['result'].get('records',[])]
    assert all(r in delivered_records for r in sources.values()), 'provenance must come from actual MCP record delivery'
    for label,response in report['views'].items():
        assert response in received, ('not an actual wire response',label)
        frame=response['frame']
        original=label in ('original','historical','restart_historical','unclassified')
        if original: revision=report['revisions']['original']
        elif label in ('current','later','expired','predicate','restart_current'): revision=report['revisions']['current']
        elif label in ('other_context','character'): revision=report['publications'][2]['receipt']['revision']
        else: revision=report['scalar_seed_revision']
        assert frame['revision']==revision, ('revision pin',label)
        assert frame['time']['time']['value']==str(25 if label=='later' else 31 if label=='expired' else 15)
        assert frame['perspective']==({'character':rid(4)} if label=='character' else 'author')
        if label in ('other_context','character'):assert frame['context']['record']==rid(70)
        world=rid(61).replace('rec_','wld_') if label=='world_b' else rid(60).replace('rec_','wld_') if label in ('world','restricted') else None
        assert response['world_focus']==world
        assert response['delivery']['complete']

        obj=response['result']['objects'][0]
        assert obj['identity']['identity']['record_id']==rid(5 if label=='unclassified' else expected['identity'])
        assert [number(r['identity']['record_id']) for r in obj['ancestry']]==([] if label=='unclassified' else expected['ancestry'])
        assert obj['ancestry_complete']==(label!='unclassified')
        assert obj['identity']==sources[obj['identity']['record_version_id']]
        deps={r['identity']['record_id']:r for r in obj['dependencies']}
        def rows(field):
            result=[]
            for candidate in obj[field]:
                r=candidate['record'];a=r['payload'];p=deps[a['proposition']['record']]['payload'];v=p['value']
                value=int(v['digits']) if v['kind']=='integer' else v['value']
                result.append([number(p['subject']['record']),number(p['predicate']['record']),a['polarity'],value,candidate['applicability']])
                assert r==sources[r['record_version_id']], ('assertion provenance changed',label)
                if candidate['applicability'] is None: assert set(candidate['unknowns']) & {'temporal_applicability','world_applicability'}
            return sorted(result)
        actual={k:rows(f) for k,f in [('shared','shared_attributes'),('instance','instance_facts'),('initial','initial_value_candidates')]}
        actual['actions']=[number(r['record']['identity']['record_id']) for r in obj['behavioral_requirements']]
        actual['rules']=[number(r['record']['identity']['record_id']) for r in obj['rules']]
        actual['conflicts']=[[number(c['predicate']),c['initial_values'],c['applicability']] for c in obj['conflicts']]
        table={k:expected[k] for k in actual}
        if label=='unclassified':table=expected['unclassified']
        if label=='unclassified':assert all(e['applicability'] is None for e in obj['behavioral_requirements']+obj['rules'])
        if label in ('scalar_current','scalar_restart','world','world_b','restricted'):table={**table,'shared':table['shared']+[expected['scalar_shared']],'conflicts':expected['scalar_conflicts']}
        if label=='expired':table=expected['expired']
        if label in ('world','restricted'):table={**table,'shared':[r for r in table['shared'] if r[1]!=14]}
        if label=='world_b':table={**table,'shared':[r if r[1]!=14 else [*r[:4],True] for r in table['shared']]}
        if label in ('other_context','character'):table={k:[] for k in actual};table['rules']=[21] if label=='other_context' else []
        if label=='predicate':table={**table,'shared':[],'instance':[[4,12,'support',2,True]],'initial':expected['initial'],'conflicts':[]}
        for k in actual: assert actual[k]==sorted(table[k]), (label,k,actual[k],table[k])
        assert obj['coverage']==('restricted' if label in ('restricted','character') else ('complete' if label=='predicate' else expected['coverage'])),label
        for c in obj['conflicts']:
            assert len(c['assertions'])==2
            assert all(v in sources for v in c['assertions'])
        for r in obj['dependencies']+obj['ancestry']+[e['record'] for e in obj['behavioral_requirements']+obj['rules']]:
            assert r==sources[r['record_version_id']], ('dependency provenance changed',label)
        if label not in ('expired','other_context','character'):
            action=obj['behavioral_requirements'][0]['record']['payload']
            historical=label in ('original','historical','restart_historical','unclassified')
            assert action['requirements'][0]['value']['value']==expected['historical_requirement' if historical else 'current_requirement']
        counts=report['immutability'][label];assert counts['before']==counts['after']
    assert report['views']['historical']['result']==report['views']['restart_historical']['result']
    assert report['views']['current']['result']==report['views']['restart_current']['result']
    assert report['views']['scalar_current']['result']==report['views']['scalar_restart']['result']
    assert report['revoked'].get('isError') and report['grant_changed_context'].get('isError')
    raw_received=[r['frame'].get('result') for r in wire if r['direction']=='received']
    assert report['revoked'] in raw_received and report['grant_changed_context'] in raw_received
    brief=report['context'];assert brief in received and brief['delivery']['complete']
    records=brief['result']['records']
    assert rid(20) in {r['identity']['record_id'] for r in records}
    assert all(r in records for r in report['source_records'] if r['payload']['record_kind']!='world' and r['identity']['record_id'] not in (rid(5),rid(37),rid(38)))
    hidden=[r for r in report['source_records'] if r['payload'].get('proposition',{}).get('record')==rid(36) or r['identity']['record_id']==rid(36)]
    encoded=json.dumps(report['views']['restricted'])
    assert all(r['identity']['record_id'] not in encoded and r['record_version_id'] not in encoded for r in hidden)
    print(f'PASS: {len(report["views"])} actual MCP views, exact provenance, context closure, nonmutation, restart, revocation')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args();audit(a.evidence)
