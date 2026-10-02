"""Actual stdio MCP scope checks against a separately maintained response oracle.

No service implementation or scope/hash helper is imported. Temporary owned
installations only; author source staging and exact approval use the CLI.
"""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import sqlite3
import time
from jsonschema import Draft202012Validator
from pilot_support import NAME, PilotSession
from mcp_smoke import MCP

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = json.loads((ROOT/'fixtures/validation-scope/expected.json').read_text())

def assert_response(name, result, proposal=None):
    expected = EXPECTED[name]
    if name == 'restricted':
        assert result == expected, result
        return
    assert set(result) == {'kind','execution','submitted_input','assessment','final_binding_digest'}, result
    actual = {'kind':result['kind'], 'coverage':result['execution']['coverage'],
              'input_kind':result['submitted_input']['kind'],'assessment':result['assessment'],
              'has_final_binding':result['final_binding_digest'] is not None}
    if 'includes_sources' in expected: actual['includes_sources']=result['submitted_input']['includes_sources']
    assert actual == expected, (name, actual, expected)
    if proposal is not None:
        assert result['submitted_input']['proposal'] == PilotSession.reference(proposal)
    if result['final_binding_digest'] is not None:
        binding = {'kind':'source_validation_binding_v1','proposal':PilotSession.reference(proposal),
            'base_frame':proposal['base_frame'],'selection':{'proposal':PilotSession.reference(proposal),'generation':0,'selected':None},
            'submitted_input':result['submitted_input'],'assessment_state':result['assessment'],
            'execution_result_digest':hashlib.sha256(canonical(result['execution'])).hexdigest(),
            'evaluator_version':result['execution']['evaluator_version']}
        assert hashlib.sha256(b'source-validation:v1:'+canonical(binding)).hexdigest()==result['final_binding_digest']

def canonical(value):
    return json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()

def entity(s,n):
    return {'kind':'create_entity','client_ref':s.rid(n),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{'en':f'Entity {n}'},'metadata':{}}}

def validation(s,p):
    return s.call('universe_validate',{'mode':'proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe'})['result']

def publish(s,p,r,key):
    core=r['execution'];args=s.commit_args(p,core,key)
    s.call('universe_commit',args,error=True)
    s.approval(p,core)
    receipt=s.call('universe_commit',args)['result']
    assert s.call('universe_commit',args)['result']==receipt
    s.open()
    return receipt

def queued(s,p,key):
    r=s.call('universe_validate',{'mode':'queued_proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe','idempotency_key':key})['result']
    if 'execution' in r:
        assert r['final_binding_digest'] is None
        r=r['execution']
    for _ in range(200):
        status=s.call('universe_get_operation',{'lookup':'id','universe':NAME,'operation_id':r['operation_id']})['result']
        if status['state']=='succeeded': return r['operation_id'],status
        assert status['state'] not in ['failed','cancelled'],status
        time.sleep(.02)
    raise AssertionError('queued timeout')

def current(bin_dir,report):
    with tempfile.TemporaryDirectory(prefix='input-scope-') as directory:
        s=PilotSession(directory,bin_dir,report)
        try:
            s.start()
            for name,n in [('structured',1),('source_only',2),('mixed',3)]:
                ops=[] if name=='source_only' else [entity(s,n)]
                if name!='structured':
                    path=Path(directory)/f'{name}.txt';path.write_text('Mara crossed the closed door.\n')
                    ops+=s.admin('stage-source',NAME,name,path)['operations']
                p=s.propose(ops,name,rationale='Whole manuscript continuity assessed (unsupported caller claim)');r=validation(s,p);assert_response(name,r,p)
                report[name]={'proposal':p,'validation':r,'receipt':publish(s,p,r,name+'-commit')}
                if name=='structured':
                    # Source history later present in canon must not relabel this input.
                    saved=p
            p=s.propose([entity(s,4)],'after-sources');r=validation(s,p);assert_response('structured',r,p)
            oid,status=queued(s,p,'queued');assert_response('structured',status['validation'],p)
            report['queued']=status
            retry=s.call('universe_validate',{'mode':'queued_proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe','idempotency_key':'queued'})['result']
            assert retry==status['validation'];report['completed_queue_retry']=retry
            s.restart()
            status=s.call('universe_get_operation',{'lookup':'id','universe':NAME,'operation_id':oid})['result']
            assert_response('structured',status['validation'],p)
            report['restart']=status
            query=s.call('universe_validate',{'mode':'inline','universe':NAME,'context_id':s.ctx,'operations':[entity(s,5)],'check_scope':'universe'})['result']
            assert_response('query',query);assert query['submitted_input']['frame']==p['base_frame'];report['query']=query
            # World scope forces private evaluation without leaking its fingerprints.
            world={'kind':'create_world','client_ref':s.rid(20),'record':{'selector':'Visible','aliases':[],'labels':{'en':'Visible'}}}
            wp=s.propose([world],'world');wr=validation(s,wp);publish(s,wp,wr,'world-commit')
            wid='wld_'+s.rid(20)[4:]
            s.admin('grant',s.agent,s.uid,'--world',wid,'--propose','--edit')
            s.client.close();s.connect();s.open()
            restricted=s.call('universe_validate',{'mode':'inline','universe':NAME,'context_id':s.ctx,'operations':[entity(s,99)],'check_scope':'universe'})['result']
            assert_response('restricted',restricted);report['restricted']=restricted
        finally:s.close()

def legacy(old_bin,new_bin,report):
    with tempfile.TemporaryDirectory(prefix='scope-legacy-') as directory:
        s=PilotSession(directory,old_bin,report)
        try:
            s.start()
            # Read the old binary's actual contracts; new strict schemas never accept v2 validation.
            for tool in s.client.request('tools/list',{})['tools']:
                if tool['name'] in ('universe_validate','universe_get_operation'):
                    s.client.schemas[tool['name']] = (Draft202012Validator(tool['inputSchema']),Draft202012Validator(tool['outputSchema']))
            p=s.propose([entity(s,1)],'legacy');oid,status=queued(s,p,'legacy-queued')
            core=status['validation'];assert 'kind' not in core
            s.approval(p,core)
            report['old_status']=status
            s.close()
            db=next(s.root.joinpath('packages').rglob('*.sqlite'))
            with sqlite3.connect(db) as conn:
                retained={key:hashlib.sha256(payload).hexdigest() for key,payload in conn.execute('SELECT key,payload FROM workflow_entries')}
            s.bin_dir=new_bin;s.admin('status');s.connect();s.open()
            s.bin_dir=old_bin
            mismatch=s.cli('status',profile=s.author,check=False)
            s.bin_dir=new_bin
            assert mismatch.returncode!=0
            report['v2_handshake_denied']={'returncode':mismatch.returncode,'stderr':mismatch.stderr}
            view=s.call('universe_get_operation',{'lookup':'id','universe':NAME,'operation_id':oid})['result']
            assert_response('legacy',view['validation'],p);report['new_legacy_status']=view
            approval=s.approval(p,core,check=False);assert approval.returncode!=0
            report['legacy_approval_denied']=approval.stderr
            head=s.open()['frame']['revision']
            report['legacy_commit_denied']=s.call('universe_commit',s.commit_args(p,core,'legacy-denied'),error=True)
            assert s.open()['frame']['revision']==head
            fresh=validation(s,p);assert_response('structured',fresh,p)
            report['fresh_validation']=fresh;report['fresh_receipt']=publish(s,p,fresh,'fresh')
            with sqlite3.connect(db) as conn:
                current={key:hashlib.sha256(payload).hexdigest() for key,payload in conn.execute('SELECT key,payload FROM workflow_entries')}
            assert all(current[key]==digest for key,digest in retained.items())
            report['preserved_v2_entries']={'count':len(retained),'all_bytes_unchanged':True}
        finally:s.close()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--old-bin-dir',type=Path,required=True);args=ap.parse_args()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    report={'status':'failed','mcp':[], 'expected_fixture_sha256':hashlib.sha256((ROOT/'fixtures/validation-scope/expected.json').read_bytes()).hexdigest(), 'binaries':{str(directory):{name:hashlib.sha256((directory/name).read_bytes()).hexdigest() for name in ('universe','universe-engine','universe-mcp')} for directory in (args.old_bin_dir,ROOT/'target/debug')}}
    try:
        current(ROOT/'target/debug',report)
        report['legacy_run']={'mcp':[]};legacy(args.old_bin_dir,ROOT/'target/debug',report['legacy_run'])
        report['status']='passed'
    finally:args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: structured/source-only/mixed/query/restricted/queued/restart/legacy MCP validation, exact approval, commit/retry and legacy denial')
if __name__=='__main__':main()
