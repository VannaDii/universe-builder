"""Real MCP exact resource validation/commit proof in a disposable installation."""
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

from resource_accounting import materialize

ORACLE = ROOT / 'fixtures/resource-transitions/expected.json'

def exercise(s, report, oracle):
    seed=s.propose([{'kind':'create_entity','client_ref':s.rid(99),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{},'metadata':{}}}], 'resource-seed')
    report['seed']=s.publish(seed,'resource-seed-commit'); report['cases']=[]
    for i,case in enumerate(oracle['cases']):
        if not case.get('mcp',True): continue
        rows=materialize(oracle,case); offset=1000+i*100
        def remap(v):
            if isinstance(v,dict): return {k:remap(x) for k,x in v.items()}
            if isinstance(v,list): return [remap(x) for x in v]
            if isinstance(v,str):
                if v.startswith('unv_'):return s.uid
                if v.startswith('cal_'):return s.calendar
                for prefix in ('rec_','wld_','unit_'):
                    if v.startswith(prefix):
                        n=int(v[len(prefix):],16)
                        return s.u['context_id'] if prefix=='rec_' and n==10 else s.rid(offset+n).replace('rec_',prefix,1)
            return v
        rows=remap(rows);rows[2]['namespace']=rows[4]['namespace']=rows[12]['namespace']='resource_'+case['id']
        rows[13]['selector']=case['id']+' A';rows[14]['selector']=case['id']+' B'
        operations=[]
        for n,row in enumerate(rows,1):
            body={k:v for k,v in row.items() if k!='record_kind'}
            if row['record_kind']=='assertion':
                # Reference mutations must select the authored premise as well.
                original=materialize(oracle,case)[n-1]['proposition']['record']
                premise=deepcopy(rows[int(original[4:],16)-1]);premise.pop('record_kind')
                body['proposition']=s.rr(offset+n)
                operations.append({'kind':'assert_proposition','client_ref':s.rid(offset+n),'proposition':premise,'assertion':body})
            else:
                kind={'entity':'create_entity','property':'define_property','proposition':'define_proposition','action_definition':'define_action','event':'record_event','unit':'define_unit','world':'create_world','item_power':'define_item_power'}[row['record_kind']]
                operations.append({'kind':kind,'client_ref':s.rid(offset+n),'record':body})
        before=s.open()['frame']['revision'];p=s.propose(operations,case['id'])
        result={'id':case['id'],'offset':offset,'proposal':p,'head_before':before}
        if case['allowed']:
            result['receipt']=s.publish(p,case['id']+'-commit')
            result['states']={str(t):s.state([s.rid(offset+1),s.rid(offset+2)],t) for t in (10,11,15)}
        else:
            result['rejection']=s.validate(p,error=True)
            require(result['rejection']['code']=='INVALID_ARGUMENT',str(result['rejection']))
            result['commit_arguments']=s.commit_args(p,report['publications'][-1]['validation'],case['id']+'-denied')
            result['commit_rejection']=s.call('universe_commit',result['commit_arguments'],error=True)
        result['head_after']=s.open()['frame']['revision']
        require((result['head_after']!=before)==case['allowed'],'head changed incorrectly');report['cases'].append(result)
    report['retcon_controls']=[]
    c=next(c for c in report['cases'] if c['id']=='consumption')
    pub=next(pu for pu in report['publications'] if pu['receipt']==c['receipt'])
    premise=next(change['next'] for change in pub['review']['changes'] if change.get('next',{}).get('payload',{}).get('record_kind')=='assertion' and change['next']['payload']['proposition']['record']==s.rid(c['offset']+8))
    for key,field,value in [('refuted-stock','polarity','refutation'),('unknown-stock','validity',{'kind':'unknown'})]:
        replacement=deepcopy(premise['payload']);replacement.pop('record_kind');replacement[field]=value
        operation={'kind':'supersede_assertion','record':s.rr(premise['identity']['record_id']),'expected_version':premise['record_version_id'],'replacement':replacement,'rationale':key}
        before=s.open()['frame']['revision'];p=s.propose([operation],key)
        rejection=s.validate(p,error=True);commit_rejection=s.call('universe_commit',s.commit_args(p,report['publications'][-1]['validation'],key+'-denied'),error=True)
        after=s.open()['frame']['revision'];require(before==after,'retcon moved head')
        report['retcon_controls'].append({'id':key,'proposal':p,'original':premise,'operation':operation,'rejection':rejection,'commit_rejection':commit_rejection,'head_before':before,'head_after':after})
    s.restart();report['head_after_restart']=s.open()['frame']['revision']
    c=next(c for c in report['cases'] if c['id']=='atomic_transfer')
    report['restart_state']=s.state([s.rid(c['offset']+1),s.rid(c['offset']+2)],15)
    pub=report['publications'][-1];report['restart_receipt']=s.call('universe_commit',pub['commit_arguments'])['result']

def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--output',type=Path,required=True); args=parser.parse_args()
    output=args.output.resolve(); output.mkdir(parents=True,exist_ok=False)
    started=time.monotonic(); report={'status':'failed','scope':'Exact single-event resource transitions; excludes multi-event ordering, reusable rules and prose qualification'}
    command=['cargo','build','--locked','-p','universe-cli','-p','universe-engine','-p','universe-mcp']
    build=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    save(output/'build.json',{'command':command,'returncode':build.returncode,'stdout':build.stdout,'stderr':build.stderr}); require(build.returncode==0,'build failed')
    identity=build_identity(ROOT/'target/debug',{}); identity['resource_oracle_sha256']=sha(ORACLE); save(output/'build-identity.json',identity)
    (output/'oracle.json').write_bytes(ORACLE.read_bytes())
    try:
        with tempfile.TemporaryDirectory(prefix='resource_transitions-',dir='/tmp') as directory:
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
        for script, tail, dest in [('audit_resource_transitions.py',[str(output)],'audit-execution.json'),('test_resource_transitions_pilot.py',['--evidence',str(output),'-v'],'audit-negative-tests.json')]:
            result=subprocess.run([sys.executable,str(ROOT/'scripts'/script),*tail],capture_output=True,text=True)
            save(output/dest,{'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr}); require(result.returncode==0,result.stderr)
            require('skipped' not in result.stderr,'proof tests were skipped')
        final=build_identity(ROOT/'target/debug',{})
        require(final['source_sha256']==identity['source_sha256'] and final['binaries']==identity['binaries'] and sha(ORACLE)==identity['resource_oracle_sha256'],'source/binary/oracle changed')
        save(output/'result.json',{'status':'passed','seconds':time.monotonic()-started,'cases':len(report['cases'])})
    except Exception:
        report['error']=traceback.format_exc(); save(output/'report.json',report); raise
    finally:
        save(output/'evidence-manifest.json',{str(p.relative_to(output)):sha(p) for p in sorted(output.rglob('*')) if p.is_file() and p.name!='evidence-manifest.json'})
    print('PASS: audited real MCP resource transitions:',output)
if __name__=='__main__': main()
