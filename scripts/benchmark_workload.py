#!/usr/bin/env python3
"""Bounded headless workload and restore drill against an isolated installation."""
import argparse
import json
import platform
import statistics
import subprocess
import tempfile
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from mcp_smoke import MCP


def run(bin_dir, batches):
    with tempfile.TemporaryDirectory(prefix='ub-workload-', dir='/tmp') as directory:
        root = Path(directory) / 'installation'
        cli = bin_dir / 'universe'
        author = subprocess.check_output([str(cli), '--installation', str(root), 'init'], text=True).strip()
        def admin(*args):
            return json.loads(subprocess.check_output([str(cli), '--installation', str(root), '--profile', author, *args], text=True, timeout=30))
        clients = []
        try:
            start = time.perf_counter(); admin('status'); cold_ms = (time.perf_counter()-start)*1000
            alpha = admin('create',"--scratch-policy", 'Workload', '--first-time', '0', '--calendar', 'Days', '--tick-label', 'days')
            beta = admin('create',"--scratch-policy", 'Independent', '--first-time', '0', '--calendar', 'Days', '--tick-label', 'days')
            client = MCP(bin_dir/'universe-mcp', installation=root, profile=author); clients.append(client)
            other = MCP(bin_dir/'universe-mcp', installation=root, profile=author); clients.append(other)
            def context(c, name, u):
                return c.call('universe_open_context', {'universe':name,'continuity_id':u['continuity_id'],'revision':{'kind':'head'},'represented_context':u['context_id'],'temporal_query':{'kind':'timeless'},'temporal_systems':[],'perspective':'author'})['result']['context_id']
            writes = []
            for batch in range(batches):
                ctx = context(client,'Workload',alpha)
                ops = [{'kind':'create_entity','client_ref':f'entity-{batch}-{n}','record':{'names':[],'types':[],'worldAssociations':[],'labels':{'en':f'Fixture entity {batch*100+n}'},'metadata':{}}} for n in range(100)]
                start=time.perf_counter()
                proposal=client.call('universe_propose',{'action':'create','universe':'Workload','context_id':ctx,'operations':ops,'submission':'submitted','rationale':'Disposable bounded workload','idempotency_key':f'batch-{batch}'})['result']
                reference={k:proposal[k] for k in ('proposal_id','version','digest')}
                validation=client.call('universe_validate',{'mode':'proposal','universe':'Workload','context_id':ctx,'proposal_reference':reference,'check_scope':'universe'})['result']['execution']
                assert validation['coverage']=='complete'
                admin('approve','Workload',proposal['proposal_id'],str(proposal['version']),proposal['digest'],validation['run_id'])
                client.call('universe_commit',{'universe':'Workload','proposal_reference':reference,'expected_base_revision':proposal['base_frame']['revision'],'validation_run':validation['run_id'],'idempotency_key':f'commit-{batch}'})
                writes.append((time.perf_counter()-start)*1000)
            ctx=context(client,'Workload',alpha); other_ctx=context(other,'Independent',beta)
            def query(c,name,ctx):
                start=time.perf_counter(); result=c.call('universe_search',{'universe':name,'context_id':ctx,'query':'Fixture','typed_filters':{'record_kinds':['entity']},'limit':100})
                return (time.perf_counter()-start)*1000, result
            reads=[]; independent=[]
            with ThreadPoolExecutor(max_workers=2) as pool:
                for _ in range(30):
                    a=pool.submit(query,client,'Workload',ctx); b=pool.submit(query,other,'Independent',other_ctx)
                    elapsed,result=a.result(); reads.append(elapsed); independent.append(b.result()[0]); assert len(result['result']['hits'])==100
            doctor=admin('doctor'); before=doctor['packages']
            backup=Path(directory)/'backup'; admin('backup','Workload',str(backup))
            for c in clients: c.close()
            clients.clear(); admin('shutdown')
            deadline=time.monotonic()+5
            while (root/'engine.sock').exists() and time.monotonic()<deadline: time.sleep(.02)
            assert not (root/'engine.sock').exists()
            admin('status'); after=admin('doctor')['packages']
            assert sorted(p['storage']['heads'] for p in before)==sorted(p['storage']['heads'] for p in after)
            # A second installation is the rollback target; original remains intact.
            restored_root=Path(directory)/'restored'
            restored_author=subprocess.check_output([str(cli),'--installation',str(restored_root),'init'],text=True).strip()
            def restore_admin(*args):
                return json.loads(subprocess.check_output([str(cli),'--installation',str(restored_root),'--profile',restored_author,*args],text=True,timeout=30))
            try:
                restore_admin('restore',str(backup),'Restored')
                restored=restore_admin('doctor')['packages'][0]['storage']
                original=next(p['storage'] for p in after if p['storage']['heads']==restored['heads'])
                assert original['heads']==restored['heads']
            finally: restore_admin('shutdown')
            def summary(values):
                return {'samples':len(values),'median_ms':round(statistics.median(values),3),'max_ms':round(max(values),3)}
            return {'status':'pass','hardware':{'system':platform.system(),'machine':platform.machine(),'os':platform.mac_ver()[0]},'entities':batches*100,'cold_start_ms':round(cold_ms,3),'reviewed_100_record_batches':summary(writes),'warm_search':summary(reads),'concurrent_other_universe_search':summary(independent),'checks':['bounded schema-validated MCP queries','independent universe progress','shutdown/restart preserves heads','backup restore preserves historical heads'],'limits':'Local development measurement, not a release SLA, clean-machine proof, or cross-version upgrade certification'}
        finally:
            for c in clients: c.close()
            admin('shutdown')


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--bin-dir',type=Path,required=True); parser.add_argument('--batches',type=int,default=5); parser.add_argument('--output',type=Path)
    args=parser.parse_args(); assert 1<=args.batches<=20
    result=run(args.bin_dir.resolve(),args.batches); text=json.dumps(result,indent=2)+'\n'
    if args.output: args.output.write_text(text)
    print(text)
