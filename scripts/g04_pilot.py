"""Real MCP declared effect rejection/commit proof; disposable installations only."""
import argparse
from contextlib import closing
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import traceback
from continuity_gap_pilot import ROOT, RecordedSession, build_identity, save, sha
from mlx_authoring_smoke import require
from pilot_support import NAME

ORACLE = ROOT / 'fixtures/action-effects/expected.json'
SKIP = {'duplicate_slot', 'wrong_predicate', 'wrong_context', 'historical_contractless'}

def exercise(s, report, oracle):
    seed = s.propose([{'kind':'create_entity','client_ref':s.rid(99),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{},'metadata':{}}}], 'g04-seed')
    report['seed'] = s.publish(seed, 'g04-seed-commit')
    report['cases'] = []
    for i, case in enumerate(oracle['cases']):
        if case['id'] in SKIP or not case.get('mcp',True): continue
        rows = deepcopy(oracle['records'])
        for m in case['mutations']:
            node = rows[m['record']-1]
            path = m['path'].split('.')
            for key in path[:-1]: node = node[int(key)] if isinstance(node,list) else node[key]
            if m['value'] is None: node.pop(path[-1])
            else: node[path[-1]] = deepcopy(m['value'])
        offset = 1000 + i*100
        def remap(value):
            if isinstance(value, dict): return {k:remap(v) for k,v in value.items()}
            if isinstance(value, list): return [remap(v) for v in value]
            if isinstance(value,str):
                if value.startswith('unv_'): return s.uid
                if value.startswith('cal_'): return s.calendar
                if value.startswith('rec_'):
                    n = int(value[4:],16)
                    return s.u['context_id'] if n == 10 else s.rid(offset+n)
                if value.startswith('wld_'): return s.rid(offset+int(value[4:],16)).replace('rec_','wld_',1)
            return value
        rows = remap(rows)
        rows[2]['namespace'] = 'g04_' + case['id']
        rows[4]['namespace'] = 'g04_' + case['id']
        operations = []
        for n, row in enumerate(rows,1):
            body = {k:v for k,v in row.items() if k != 'record_kind'}
            if row['record_kind'] == 'assertion':
                # Reserve a separate equivalent proposition for direct evidence.
                premise = deepcopy(rows[int(oracle['records'][7]['proposition']['record'][4:],16)-1])
                if case['id'].startswith('conditional_false'): premise = deepcopy(rows[6])
                premise.pop('record_kind')
                body['proposition'] = s.rr(offset+n)
                operations.append({'kind':'assert_proposition','client_ref':s.rid(offset+n),'proposition':premise,'assertion':body})
            else:
                kind = {'entity':'create_entity','property':'define_property','proposition':'define_proposition','action_definition':'define_action','event':'record_event'}[row['record_kind']]
                operations.append({'kind':kind,'client_ref':s.rid(offset+n),'record':body})
        if case['id'] == 'wrong_world':
            operations.append({'kind':'create_world','client_ref':s.rid(offset+32),'record':{'selector':'Wrong world','labels':{},'metadata':{}}})
        before = s.open()['frame']['revision']
        p = s.propose(operations, case['id'])
        result = {'id':case['id'], 'offset':offset, 'proposal':p, 'head_before':before}
        if case['allowed']:
            result['receipt'] = s.publish(p, case['id']+'-commit')
            result['states'] = {str(t):s.state([s.rid(offset+1)],t) for t in (11,15,16)}
            pub = report['publications'][-1]
            if case['id'] == 'declared_grant':
                report['grant_publication'] = pub
                generated = next(c['next'] for c in pub['review']['changes'] if c.get('next',{}).get('payload',{}).get('establishedBy'))
                # A raw edit to generated state must fail before freezing.
                body = deepcopy(generated['payload']); body.pop('record_kind'); body.pop('establishedBy'); body['polarity']='refutation'
                args = {'action':'create','universe':NAME,'context_id':s.ctx,'operations':[{'kind':'supersede_assertion','record':s.rr(generated['identity']['record_id']),'expected_version':generated['record_version_id'],'replacement':body,'rationale':'Tamper control'}], 'submission':'submitted','rationale':'Frozen assertion control','idempotency_key':'tamper'}
                head = s.open()['frame']['revision']
                report['frozen_control'] = {'arguments':args,'rejection':s.call('universe_propose',args,error=True),'before':head,'after':s.open()['frame']['revision']}
                # Change the exact approved proposal; old approval/run cannot publish it.
                pending_event = deepcopy(operations[5])
                pending_event['client_ref'] = s.rid(offset+50)
                pending_event['record']['time'] = s.instant(21)
                pending_event['record']['effects'][0]['validity'] = s.interval(21,26)
                pending = s.propose([pending_event], 'pending-grant')
                pv = s.validate(pending)
                require(s.approval(pending,pv).returncode==0,'pending author approval failed')
                revised_ops = deepcopy([pending_event])
                revised_ops[0]['record']['effects'] = []
                args = {'action':'revise','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(pending),'operations':revised_ops,'submission':'submitted','rationale':'Changed effects must invalidate approval','idempotency_key':'changed-effects'}
                revised = s.call('universe_propose',args)['result']
                report['changed_control'] = {'original':pending,'validation':pv,'proposal':revised,'before':head,'rejection':s.call('universe_commit',s.commit_args(revised,pv,'stale-effect-approval'),error=True),'validation_rejection':s.validate(revised,error=True),'after':s.open()['frame']['revision']}
        else:
            result['rejection'] = s.validate(p,error=True)
            require(result['rejection']['code']=='INVALID_ARGUMENT' and result['rejection']['field']=='event.action.effects', f"{case['id']}: {result['rejection']}")
            result['commit_arguments'] = s.commit_args(p,report['publications'][-1]['validation'],case['id']+'-denied')
            result['commit_rejection'] = s.call('universe_commit',result['commit_arguments'],error=True)
        result['head_after'] = s.open()['frame']['revision']
        require((result['head_after'] != before) == case['allowed'], 'head control differs')
        report['cases'].append(result)
    s.restart()
    report['head_after_restart'] = s.open()['frame']['revision']
    g = next(c for c in report['cases'] if c['id']=='declared_grant')
    report['restart_state'] = s.state([s.rid(g['offset']+1)],15)
    pub = report['publications'][-1]
    report['restart_receipt'] = s.call('universe_commit',pub['commit_arguments'])['result']


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--output',type=Path,required=True); args=parser.parse_args()
    output=args.output.resolve(); output.mkdir(parents=True,exist_ok=False)
    started=time.monotonic(); report={'status':'failed','scope':'G04 declared set effects; excludes resource arithmetic, simultaneous spending and prose/native qualification'}
    command=['cargo','build','--locked','-p','universe-cli','-p','universe-engine','-p','universe-mcp']
    build=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    save(output/'build.json',{'command':command,'returncode':build.returncode,'stdout':build.stdout,'stderr':build.stderr}); require(build.returncode==0,'build failed')
    identity=build_identity(ROOT/'target/debug',{}); identity['effect_oracle_sha256']=sha(ORACLE); save(output/'build-identity.json',identity)
    (output/'oracle.json').write_bytes(ORACLE.read_bytes())
    try:
        with tempfile.TemporaryDirectory(prefix='g04-',dir='/tmp') as directory:
            with (output/'mcp-transcript.jsonl').open('w') as wire:
                s=RecordedSession(directory,ROOT/'target/debug',report,wire=wire)
                try:
                    s.start(); report['installation']=s.u
                    exercise(s,report,json.loads(ORACLE.read_text())); report['status']='executed'
                finally:
                    s.close()
                    dbs=list((s.root/'packages').rglob('*.sqlite'))
                    if len(dbs)==1:
                        with closing(sqlite3.connect(dbs[0])) as source, closing(sqlite3.connect(output/'package.sqlite')) as dest: source.backup(dest)
                        report['package_sha256']=sha(output/'package.sqlite')
                    save(output/'report.json',report)
        for script, tail, dest in [('audit_g04.py',[str(output)],'audit-execution.json'),('test_g04_pilot.py',['--evidence',str(output),'-v'],'audit-negative-tests.json')]:
            result=subprocess.run([sys.executable,str(ROOT/'scripts'/script),*tail],capture_output=True,text=True)
            save(output/dest,{'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr}); require(result.returncode==0,result.stderr)
            require('skipped' not in result.stderr,'proof tests were skipped')
        final=build_identity(ROOT/'target/debug',{})
        require(final['source_sha256']==identity['source_sha256'] and final['binaries']==identity['binaries'] and sha(ORACLE)==identity['effect_oracle_sha256'],'source/binary/oracle changed')
        save(output/'result.json',{'status':'passed','seconds':time.monotonic()-started,'cases':len(report['cases'])})
    except Exception:
        report['error']=traceback.format_exc(); save(output/'report.json',report); raise
    finally:
        save(output/'evidence-manifest.json',{str(p.relative_to(output)):sha(p) for p in sorted(output.rglob('*')) if p.is_file() and p.name!='evidence-manifest.json'})
    print('PASS: audited real MCP declared effects:',output)
if __name__=='__main__': main()
