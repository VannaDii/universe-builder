"""Audit MCP wire evidence against the separately authored admission oracle."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def audit(path):
    report=json.loads(path.read_text())
    oracle=json.loads((ROOT/'fixtures/ancestor-applicability/oracle.json').read_text())
    wire=[json.loads(line) for line in path.with_suffix('.jsonl').read_text().splitlines()]
    pending=None; pairs=[]
    for item in wire:
        frame=item['frame']
        if item['direction']=='sent' and frame.get('method')=='tools/call':
            assert pending is None
            pending=frame
        elif item['direction']=='received' and pending and frame.get('id')==pending['id']:
            pairs.append((pending['params'],frame['result']));pending=None
    assert pending is None
    assert set(report['cases'])==set(oracle['admission'])
    outcomes={}
    for name,expected in oracle['admission'].items():
        row=report['cases'][name];proposal=row['proposal']
        validations=[response for request,response in pairs if request['name']=='universe_validate' and request['arguments'].get('proposal_reference',{}).get('proposal_id')==proposal['proposal_id']]
        assert validations,name
        response=validations[0]
        if response.get('isError'):
            assert response['structuredContent']['code']=='INVALID_ARGUMENT',(name,response)
            actual='illegal'
        else:
            v=response['structuredContent']['result']['execution']
            if v['coverage']=='partial':
                assert v['unsupported_capabilities'],name
                actual='unresolved'
            else:
                assert v['coverage']=='complete',name
                actual='illegal' if any(f['outcome']!='supported' for f in v['findings']) else 'legal'
        assert actual==expected,(name,expected,actual)
        denials=[response for request,response in pairs if request['name']=='universe_commit' and request['arguments'].get('idempotency_key')==name+'-denied']
        assert len(denials)==1 and denials[0].get('isError'),name
        if name=='definition_retcon_revalidates_event':
            assert response.get('isError') and response['structuredContent']['field']=='event.action.requirements'
        if name in ('property_definition_revalidates_fact','relation_definition_revalidates_participant','universe_wide_cannot_widen_type'):
            assert response.get('isError') and response['structuredContent']['field']=='candidate'
        outcomes[name]=actual
    history=report['history']
    assert history['original']!=history['corrected']
    assert history['before_restart']==history['after_restart']
    before=history['before_restart']['before'];after=history['before_restart']['after']
    assert before[0]['payload']['parent']!=after[0]['payload']['parent']
    assert before[1]==after[1], 'instance changed during ancestry correction'
    assert before[2]['payload']['record_kind']=='event'
    # All historical records must be actual delivered MCP records, not merely
    # the proof driver's asserted reconstruction.
    delivered=[r for request,response in pairs if request['name']=='universe_get' and not response.get('isError') for r in response['structuredContent']['result']['records']]
    assert all(r in delivered for r in before+after)
    assert len(report['publications'])>=4
    for publication in report['publications']:
        receipt=publication['receipt']
        committed=[response['structuredContent']['result'] for request,response in pairs if request['name']=='universe_commit' and request['arguments'].get('idempotency_key')==publication['key'] and not response.get('isError')]
        assert len(committed)==2 and committed[0]==committed[1]==receipt
    return {'status':'passed','cases':outcomes,'wire_tool_calls':len(pairs),'publications':len(report['publications']), 'history_restart':'exact original/corrected parent and instance/event records', 'report_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'wire_sha256':hashlib.sha256(path.with_suffix('.jsonl').read_bytes()).hexdigest()}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('report',type=Path);p.add_argument('--output',type=Path);a=p.parse_args();result=audit(a.report)
    if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
