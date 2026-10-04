"""Separate standard-library oracle for real MCP relational publication controls."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
from audit_assessment_publication import rows, canonical


def audit(e):
    assert e['kind']=='relational-workflow-mcp'
    failed=e['interruption']
    assert failed['response']['isError'] and failed['response']['structuredContent']['code']=='STORAGE_FAILURE'
    assert failed['before']==failed['after']
    assert failed['typed_rows_before']==failed['typed_rows_after']
    old,new=rows(e['race_before']),rows(e['race_after'])
    assert e['race_before']['canonical_tables']==e['race_after']['canonical_tables']
    assert all(new[k]==v for k,v in old.items())
    contenders=e['contenders']
    assert len(contenders)==2 and sum(not c['response'].get('isError',False) for c in contenders)==1
    assert contenders[0]['arguments']['expected_selection_generation']==contenders[1]['arguments']['expected_selection_generation']==0
    winner=next(c for c in contenders if not c['response'].get('isError',False))
    loser=next(c for c in contenders if c['response'].get('isError',False))
    assert loser['response']['structuredContent']['code']=='APPROVAL_STALE'
    selection=winner['response']['structuredContent']['result']
    assert selection['generation']==1 and selection['proposal']==winner['arguments']['proposal_reference']
    attachment=new['assessment:'+selection['selected']['assessment_id']]
    assert attachment['body']==winner['arguments']['body']
    assert attachment['digest']==selection['selected']['digest']==hashlib.sha256(b'source-assessment:v1:'+canonical(attachment['body'])).hexdigest()
    fresh={k:v for k,v in new.items() if k not in old}
    assert len(fresh)==3
    assert sum(k.startswith('assessment-selection:') for k in fresh)==1
    assert sum(k.startswith('assessment-receipt:') for k in fresh)==1
    receipt=next(v for k,v in fresh.items() if k.startswith('assessment-receipt:'))
    assert receipt['envelope']==attachment and receipt['selection']==selection
    for snap in [e['restart'],e['retry']['after']]:
        actual=rows(snap)
        assert all(actual[k]==v for k,v in new.items())
        rebuilt={'projection_state','projection_heads','reference_index','typed_projection','world_projection','narrative_projection'}
        durable=lambda tables:{k:v for k,v in tables.items() if k not in rebuilt and not k.startswith('search_index')}
        assert durable(snap['canonical_tables'])==durable(e['race_after']['canonical_tables'])
    assert e['retry']['response']==winner['response']
    return {'interrupted_publication':'atomic, no orphan typed rows','selection_race':'one winner, one stale denial','restart_retry':'exact receipt','independent_body_and_workflow_hashes':'verified'}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);p.add_argument('--output',type=Path)
    a=p.parse_args();result=audit(json.loads(gzip.decompress(a.evidence.read_bytes()) if a.evidence.suffix=='.gz' else a.evidence.read_bytes()));raw=json.dumps(result,indent=2)+'\n'
    if a.output:a.output.write_text(raw)
    print(raw,end='')
