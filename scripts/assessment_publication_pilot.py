"""Actual stdio validate -> private author approve -> public commit proof.

The auditor is a separate executable and is never imported by this producer.
All data and installations are synthetic and disposable.
"""
import argparse
import copy
import json
from pathlib import Path
import tempfile
from assessment_mcp_pilot import assessment, snapshot
from pilot_support import NAME, PilotSession


def durable(snap):
    return [r for r in snap['workflow'] if not r['key'].startswith('context:')]


def run(bin_dir, output):
    report = {'kind':'assessment-publication-mcp-v1','cases':[], 'mcp':[]}
    with tempfile.TemporaryDirectory(prefix='asp-', dir='/tmp') as directory:
        s = PilotSession(directory, bin_dir, report)
        try:
            s.start()
            report['author'] = s.author
            report['tools'] = s.client.request('tools/list', {})['tools']
            text = 'Exact café bytes.\n'
            path = Path(directory)/'source.txt'
            path.write_text(text)
            p = s.propose(s.admin('stage-source',NAME,'Publication proof',path)['operations'],'assessed')
            viewed = s.call('universe_get_proposal',{'universe':NAME,'proposal_id':p['proposal_id'],'version':p['version']})['result']
            body = assessment(s,p,viewed,text)

            def mcp(label, tool, args, kind='read', error=False):
                before = snapshot(s)
                s.client.schemas[tool][0].validate(args)
                raw = s.client.request('tools/call',{'name':tool,'arguments':args})
                assert bool(raw.get('isError', False)) == error, (label,raw)
                if not error:
                    s.client.schemas[tool][1].validate(raw['structuredContent'])
                after = snapshot(s)
                report['cases'].append({'label':label,'tool':tool,'channel':'mcp','kind':kind,'error':error,
                    'arguments':copy.deepcopy(args),'response':raw,'before':before,'after':after})
                return raw.get('structuredContent', raw) if error else raw['structuredContent']['result']

            def validate(label, proposal):
                return mcp(label,'universe_validate',{'mode':'proposal','universe':NAME,'context_id':s.ctx,
                    'proposal_reference':s.reference(proposal),'check_scope':'universe'},kind='validation')

            def approve(label, proposal, result, error=False):
                before = snapshot(s)
                command = s.approval(proposal,result['execution'],check=False)
                assert (command.returncode != 0) == error, (label,command.stderr)
                report['cases'].append({'label':label,'channel':'author-cli','kind':'approval','error':error,
                    'arguments':s.commit_args(proposal,result['execution'],'approval-audit'),
                    'response':{'returncode':command.returncode,'stdout':command.stdout,'stderr':command.stderr},
                    'before':before,'after':snapshot(s)})

            def attach(label, proposal, body, generation):
                return mcp(label,'universe_propose',{'action':'attach_assessment','universe':NAME,'context_id':s.ctx,
                    'proposal_reference':s.reference(proposal),'expected_selection_generation':generation,
                    'body':body,'idempotency_key':label},kind='selection')

            def select(label, proposal, generation, selected):
                return mcp(label,'universe_propose',{'action':'select_assessment','universe':NAME,'context_id':s.ctx,
                    'proposal_reference':s.reference(proposal),'expected_selection_generation':generation,
                    'assessment_reference':selected,'idempotency_key':label},kind='selection')

            absent = validate('initial-raw-validation',p)
            approve('initial-raw-approval',p,absent)
            first = attach('first-attachment',p,body,0)
            checked = validate('assessed-validation',p)
            mcp('unapproved','universe_commit',s.commit_args(p,checked['execution'],'unapproved'),kind='commit',error=True)
            approve('assessed-approval',p,checked)
            mcp('stale-approval','universe_commit',s.commit_args(p,absent['execution'],'stale-approval'),kind='commit',error=True)
            replacement = copy.deepcopy(body)
            replacement['assessor']['assessed_at'] = '2026-10-03T00:00:01Z'
            attach('replacement',p,replacement,1)
            approve('approval-after-replacement',p,checked,error=True)
            mcp('stale-selection','universe_commit',s.commit_args(p,checked['execution'],'stale-selection'),kind='commit',error=True)
            select('reselect-original',p,2,first['selected'])
            mcp('reselected-old-identity','universe_commit',s.commit_args(p,checked['execution'],'aba'),kind='commit',error=True)
            rebound = validate('reselected-validation',p)
            approve('reselected-approval',p,rebound)
            select('withdraw-selection',p,3,None)
            approve('approval-after-withdrawal',p,rebound,error=True)
            mcp('withdrawal','universe_commit',s.commit_args(p,rebound['execution'],'withdrawal'),kind='commit',error=True)
            select('restore-assessment',p,4,first['selected'])
            final = validate('final-assessed-validation',p)
            approve('final-assessed-approval',p,final)
            args = s.commit_args(p,final['execution'],'assessed-commit')
            receipt = mcp('assessed-commit','universe_commit',args,kind='commit')
            assert mcp('commit-retry','universe_commit',args,kind='retry') == receipt
            snap = snapshot(s)
            report['receipt_before_restart'] = receipt
            report['workflow_before_restart'] = durable(snap)
            report['historical_assessments_before'] = [r for r in snap['workflow'] if r['key'].startswith(('assessment:','assessment-selection:','assessment-request:'))]
            report['historical_validation_before'] = [r for r in snap['workflow'] if r['key'].startswith('validation:')]
            s.restart()
            after = snapshot(s)
            report['workflow_after_restart'] = durable(after)
            report['historical_assessments_after'] = [r for r in after['workflow'] if r['key'].startswith(('assessment:','assessment-selection:','assessment-request:'))]
            report['historical_validation_after'] = [r for r in after['workflow'] if r['key'].startswith('validation:')]
            recovered = mcp('receipt-after-restart','universe_get_operation',{'lookup':'key','universe':NAME,
                'operation_kind':'commit','idempotency_key':'assessed-commit'},kind='read')['receipt']
            report['receipt_after_restart'] = recovered
            assert recovered == receipt
            assert mcp('commit-retry-after-restart','universe_commit',args,kind='retry') == receipt

            # A fresh explicit withdrawal binds generation 2 and preserves raw archiving.
            raw = s.propose(s.admin('stage-source',NAME,'Raw after withdrawal',path)['operations'],'raw-after-withdrawal')
            raw_view = s.call('universe_get_proposal',{'universe':NAME,'proposal_id':raw['proposal_id'],'version':raw['version']})['result']
            attach('raw-attachment',raw,assessment(s,raw,raw_view,text),0)
            select('raw-withdrawal',raw,1,None)
            fresh = validate('fresh-withdrawn-validation',raw)
            assert fresh['assessment']['kind'] == 'absent'
            approve('fresh-withdrawn-approval',raw,fresh)
            mcp('fresh-withdrawn-raw-commit','universe_commit',s.commit_args(raw,fresh['execution'],'fresh-raw'),kind='commit')
            s.open()

            entity = {'kind':'create_entity','client_ref':s.rid(90),'record':{'names':[],'types':[],
                'worldAssociations':[],'labels':{'en':'Revocation control'},'metadata':{}}}
            denied = s.propose([entity],'revocation-proposal')
            v = validate('revocation-validation',denied)
            approve('revocation-approval',denied,v)
            denied_args = s.commit_args(denied,v['execution'],'revoked')
            s.admin('grant',s.agent,s.uid,'--propose')
            mcp('revoked-edit','universe_commit',denied_args,kind='commit',error=True)
            s.admin('grant',s.agent,s.uid,'--propose','--edit','--protected')
            s.admin('revoke',s.agent)
            mcp('revoked-profile','universe_commit',denied_args,kind='commit',error=True)
        except Exception as error:
            report['failure'] = {'type':type(error).__name__,'message':str(error)}
            output.parent.mkdir(parents=True, exist_ok=True)
            (output.parent/'failed-attempt.json').write_text(json.dumps(report, ensure_ascii=False, separators=(',', ':')) + '\n')
            raise
        finally:
            s.close()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f"PASS: {len(report['cases'])} publication MCP/author cases")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin-dir',type=Path,default=Path('target/debug'))
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    run(args.bin_dir.resolve(), args.output)
