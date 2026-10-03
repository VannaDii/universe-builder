"""Real stdio MCP selected-validation proofs in an owned disposable installation."""
import argparse
import copy
import json
import sqlite3
import tempfile
import time
from pathlib import Path
from assessment_mcp_pilot import assessment
from audit_validation_binding import verify
from pilot_support import NAME, PilotSession


def validate(s, p):
    return s.call('universe_validate', {'mode':'proposal', 'universe':NAME, 'context_id':s.ctx,
        'proposal_reference':s.reference(p), 'check_scope':'universe'})['result']


def review(s, p):
    return s.call('universe_get_proposal', {'universe':NAME, 'proposal_id':p['proposal_id'],
        'version':p['version'], 'view_group':'assessment'})['result']


def attach(s, p, body, generation, key):
    return s.call('universe_propose', {'action':'attach_assessment', 'universe':NAME, 'context_id':s.ctx,
        'proposal_reference':s.reference(p), 'expected_selection_generation':generation,
        'body':body, 'idempotency_key':key})['result']


def queued(s, p, key):
    initial=s.call('universe_validate', {'mode':'queued_proposal','universe':NAME,'context_id':s.ctx,
        'proposal_reference':s.reference(p),'check_scope':'universe','idempotency_key':key})['result']
    assert initial['final_binding_digest'] is None
    oid=initial['execution']['operation_id']
    for _ in range(200):
        status=s.call('universe_get_operation', {'lookup':'id','universe':NAME,'operation_id':oid})['result']
        if status['state']=='succeeded': return oid,status['validation']
        assert status['state'] not in ('failed','cancelled','interrupted'),status
        time.sleep(.02)
    raise AssertionError('queued validation timed out')


def run(bin_dir, output):
    report={'kind':'selected-validation-mcp-proof-v1','bindings':[], 'independent':[], 'mcp':[]}
    with tempfile.TemporaryDirectory(prefix='validation-binding-',dir='/tmp') as directory:
        s=PilotSession(directory,bin_dir,report)
        try:
            s.start()
            text='Exact café bytes.\n';path=Path(directory)/'source.txt';path.write_text(text)
            staged=s.admin('stage-source',NAME,'Selected validation',path)
            entity={'kind':'create_entity','client_ref':s.rid(1),'record':{'names':[],'types':[],
                'worldAssociations':[],'labels':{'en':'Dependency'},'metadata':{}}}
            ops=staged['operations']+[entity];p=s.propose(ops,'candidate')
            viewed=s.call('universe_get_proposal',{'universe':NAME,'proposal_id':p['proposal_id'],'version':p['version']})['result']
            body=assessment(s,p,viewed,text)
            dep=next(c['next'] for c in viewed['compiled_changes'] if c['next'] and c['next']['payload']['record_kind']=='entity')
            body['dependencies']=[{'universe':s.uid,'record':dep['identity']['record_id'],'version':dep['record_version_id']}]

            def record(label,result):
                current=review(s,p)
                case={'label':label,'proposal':p,'validation':result,'selection':current['selection'],'envelope':current['envelope'],'source_bytes_utf8':{'passage':text}}
                report['independent'].append(verify(case));report['bindings'].append(case)
                return result

            absent=record('absent',validate(s,p))
            assert s.approval(p,absent['execution']).returncode==0
            report['approved_before_selection']=True
            first=attach(s,p,body,0,'first');a=record('selected',validate(s,p))
            # Earlier generation-zero evidence loses exact author authority.
            assert s.approval(p,absent['execution'],check=False).returncode!=0
            # Assessment-aware publication integration is intentionally unavailable.
            assert s.approval(p,a['execution'],check=False).returncode!=0
            s.call('universe_commit',s.commit_args(p,absent['execution'],'obsolete-run'),error=True)
            oid,q=queued(s,p,'queued-selected');record('queued-selected',q)
            replacement=copy.deepcopy(body);replacement['assessor']['assessed_at']='2026-10-03T00:00:01Z'
            second=attach(s,p,replacement,1,'replacement');assert first['selected']!=second['selected']
            record('replacement',validate(s,p))
            s.call('universe_propose',{'action':'select_assessment','universe':NAME,'context_id':s.ctx,
                'proposal_reference':s.reference(p),'expected_selection_generation':2,'assessment_reference':None,'idempotency_key':'withdraw'})
            record('withdrawn',validate(s,p))
            unresolved=copy.deepcopy(body)
            unresolved.update(declared_inventory=[{'item_id':'i','source_key':'passage','range':{'start':0,'end':5},
                'material_kind':'description','statement':'Uncertain material','mapping_ids':[],'unresolved_ids':['u']}],
                inventory_declaration={'kind':'material_inventory_declared','exclusions':[],'rationale':'Declared uncertain material'},
                unresolved=[{'unresolved_id':'u','item_ids':['i'],'reason':'unrepresented_material','detail':'Explicit unresolved material'}],conclusion='unresolved')
            attach(s,p,unresolved,3,'unresolved');record('unresolved',validate(s,p))
            false_clean=copy.deepcopy(unresolved);false_clean['conclusion']='consistent_with_declared_inventory'
            s.call('universe_propose',{'action':'attach_assessment','universe':NAME,'context_id':s.ctx,
                'proposal_reference':s.reference(p),'expected_selection_generation':4,'body':false_clean,'idempotency_key':'false-clean'},error=True)
            # Completed queued evidence remains immutable after selection changes/restart.
            s.restart()
            recovered=s.call('universe_get_operation',{'lookup':'id','universe':NAME,'operation_id':oid})['result']['validation']
            assert recovered==q
            report['queued_recovery_equal']=True
            changed=copy.deepcopy(ops);changed[2]['record']['labels']['en']='Changed dependency'
            revised=s.call('universe_propose',{'action':'revise','universe':NAME,'context_id':s.ctx,
                'proposal_reference':s.reference(p),'operations':changed,'submission':'submitted','rationale':'Changed dependency','idempotency_key':'revision'})['result']
            stale=record('changed-dependency',validate(s,p))
            assert stale['assessment']['kind']=='stale' and 'dependency_changed' in stale['assessment']['reasons']
            assert stale['submitted_input']['kind']=='record_candidate'
            report['revised_proposal']=revised
            # Only unrestricted author review may disclose a missing body whose
            # dependency visibility can no longer be established.
            s.client.close();s.agent=s.author;s.connect();s.open()
            # Explicit retention-loss corruption only in this owned fixture.
            selected=review(s,p)['selection']['selected'];package=s.root/'packages'/(s.uid+'.sqlite')
            with sqlite3.connect(package) as db:
                db.execute('DROP TRIGGER workflow_entries_no_delete')
                db.execute('DELETE FROM workflow_entries WHERE key=?',('assessment:'+selected['assessment_id'],))
                db.execute("CREATE TRIGGER workflow_entries_no_delete BEFORE DELETE ON workflow_entries BEGIN SELECT RAISE(ABORT, 'immutable workflow entry'); END")
            unavailable=record('missing-assessment-record-only',validate(s,p))
            assert unavailable['assessment']=={'kind':'unavailable','reason':'missing_retained_material'}
            # Missing bytes still fail source verification even with unusable assessment.
            with sqlite3.connect(package) as db:
                db.execute('DROP TRIGGER workflow_entries_no_delete')
                db.execute('DELETE FROM workflow_entries WHERE key=?',('source:'+body['sources'][0]['blob_digest'],))
                db.execute("CREATE TRIGGER workflow_entries_no_delete BEFORE DELETE ON workflow_entries BEGIN SELECT RAISE(ABORT, 'immutable workflow entry'); END")
            s.call('universe_validate',{'mode':'proposal','universe':NAME,'context_id':s.ctx,
                'proposal_reference':s.reference(p),'check_scope':'universe'},error=True)
            report['source_integrity_denial']=True
        finally:
            s.close()
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(f"PASS: {len(report['bindings'])} independently reproduced MCP bindings; replacement, withdrawal, unresolved, dependencies, retention, restart and obsolete authority denial")

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--bin-dir',type=Path,default=Path('target/debug'));parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();run(args.bin_dir.resolve(),args.output)
