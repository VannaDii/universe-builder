"""G05 qualification entrypoint used by continuity_gap_pilot --g05."""
from contextlib import closing
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import traceback
from continuity_gap_pilot import ROOT, RecordedSession, build_identity, save, sha
from continuity_gap.g05 import exercise
from mlx_authoring_smoke import require
from pilot_support import NAME


def stale_evaluator(s, report, old_bin, new_bin):
    s.start()
    from jsonschema import Draft202012Validator
    for tool in s.client.request('tools/list',{})['tools']:
        if tool['name'] in ('universe_validate','universe_get_operation'):
            s.client.schemas[tool['name']]=(Draft202012Validator(tool['inputSchema']),Draft202012Validator(tool['outputSchema']))
    report['installation']=s.u
    p=s.propose([{'kind':'create_entity','client_ref':s.rid(90),'record':{'names':[],'types':[],'worldAssociations':[],'labels':{'en':'Old evaluator candidate'},'metadata':{}}}],'old-candidate')
    queued=s.call('universe_validate',{'mode':'queued_proposal','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),'check_scope':'universe','idempotency_key':'old-validation'})['result']
    import time
    for _ in range(100):
        status=s.call('universe_get_operation',{'lookup':'id','universe':NAME,'operation_id':queued['operation_id']})['result']
        if status['state']=='completed': break
        time.sleep(.05)
    v=status['validation'];require(v['coverage']=='complete','old evaluation did not complete')
    require(v['evaluator_version']=='finite-policy-v3-owner-attributes','old binary does not represent pre-G05 evaluator')
    require(s.approval(p,v).returncode==0,'old approval failed')
    report['old_proposal']=p;report['old_validation']=v
    report['old_status']=status
    report['head_before']=s.open()['frame']['revision']
    s.close();s.bin_dir=new_bin;s.admin('status');s.connect();s.open()
    report['stale_commit']=s.call('universe_commit',s.commit_args(p,v,'stale-evaluator'),error=True)
    approval=s.approval(p,v,check=False)
    require(approval.returncode!=0,'old evaluator was accepted for new approval')
    report['stale_approval']={'returncode':approval.returncode,'stderr':approval.stderr}
    report['head_after_denial']=s.open()['frame']['revision']
    report['historical_status']=s.call('universe_get_operation',{'lookup':'id','universe':NAME,'operation_id':queued['operation_id']})['result']
    require(report['historical_status']['validation']['execution']==status['validation'] and report['historical_status']['validation']['assessment']=={'kind':'unavailable_legacy'} and report['historical_status']['validation']['final_binding_digest'] is None,'old evidence incorrectly upgraded')
    fresh=s.validate(p);require(fresh['evaluator_version']!=v['evaluator_version'],'evaluator did not change')
    s.approval(p,fresh)
    args=s.commit_args(p,fresh,'fresh-evaluator')
    report['fresh_validation']=fresh;report['fresh_commit']=s.call('universe_commit',args)['result']
    report['fresh_arguments']=args
    s.restart()
    report['restarted_entity']=s.get([s.rid(90)])


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--old-bin-dir',type=Path,required=True)
    args=parser.parse_args(argv)
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    command=['cargo','build','--locked','-p','universe-cli','-p','universe-engine','-p','universe-mcp']
    build=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    save(output/'build.json',{'command':command,'returncode':build.returncode,'stderr':build.stderr})
    require(build.returncode==0,'build failed; see build.json')
    bin_dir=ROOT/'target/debug';identity=build_identity(bin_dir,{'command':command,'returncode':0})
    identity['old_binaries']={name:sha(args.old_bin_dir/name) for name in ('universe','universe-engine','universe-mcp')}
    save(output/'build-identity.json',identity)
    for name in ('run-a','run-b','evaluator-upgrade'):
        dest=output/name;dest.mkdir();report={'status':'failed','scope':'G05 synthetic public workflow'}
        with tempfile.TemporaryDirectory(prefix='g05-',dir='/tmp') as directory:
            with (dest/'mcp-transcript.jsonl').open('w') as wire:
                s=RecordedSession(directory,args.old_bin_dir if name=='evaluator-upgrade' else bin_dir,report,wire=wire)
                try:
                    if name=='evaluator-upgrade': stale_evaluator(s,report,args.old_bin_dir,bin_dir)
                    else:
                        s.start();report['installation']=s.u;exercise(s,report)
                    report['status']='executed'
                except Exception:
                    report['error']=traceback.format_exc();raise
                finally:
                    s.close()
                    dbs=list((s.root/'packages').rglob('*.sqlite'))
                    if dbs:
                        with closing(sqlite3.connect(dbs[0])) as src, closing(sqlite3.connect(dest/'package.sqlite')) as db:src.backup(db)
                        report['package_sha256']=sha(dest/'package.sqlite')
                    save(dest/'report.json',report)
        audited=subprocess.run([sys.executable,str(ROOT/'scripts/audit_g05.py'),str(dest)],capture_output=True,text=True)
        save(dest/'audit-execution.json',{'returncode':audited.returncode,'stdout':audited.stdout,'stderr':audited.stderr})
        require(audited.returncode==0,f'audit failed: {audited.stderr}')
        print(f'PASS: {name}',flush=True)
    audits=[json.loads((output / name / 'audit.json').read_text()) for name in ('run-a','run-b')]
    require(audits[0]['equivalence']==audits[1]['equivalence'],'fresh installations differ')
    negative=subprocess.run([sys.executable,str(ROOT/'scripts/test_g05_pilot.py'),'--evidence',str(output/'run-a'),'-v'],capture_output=True,text=True)
    save(output/'audit-negative-tests.json',{'returncode':negative.returncode,'stdout':negative.stdout,'stderr':negative.stderr})
    require(negative.returncode==0,'negative audit tests failed')
    require(build_identity(bin_dir,{})['source_sha256']==identity['source_sha256'],'source changed during proof')
    save(output/'evidence-manifest.json',{str(p.relative_to(output)):sha(p) for p in sorted(output.rglob('*')) if p.is_file()})
    save(output/'comparison.json',{'status':'passed','fresh_installations':2,'evaluator_upgrade':True})

if __name__=='__main__':main()
