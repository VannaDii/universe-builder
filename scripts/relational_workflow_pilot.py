"""Disposable real MCP contention and interrupted typed-publication proof."""
import argparse
import copy
import json
from pathlib import Path
import sqlite3
import tempfile
from assessment_mcp_pilot import assessment, snapshot
from pilot_support import NAME, PilotSession


def run(bin_dir, output):
    report = {'kind':'relational-workflow-mcp','mcp':[]}
    with tempfile.TemporaryDirectory(prefix='rwf-',dir='/tmp') as directory:
        s=PilotSession(directory,bin_dir,report)
        try:
            s.start()
            text='Exact relational café evidence.\n'
            path=Path(directory)/'source.txt';path.write_text(text)
            p=s.propose(s.admin('stage-source',NAME,'Relational publication',path)['operations'],'relational')
            viewed=s.call('universe_get_proposal',{'universe':NAME,'proposal_id':p['proposal_id'],'version':p['version']})['result']
            body=assessment(s,p,viewed,text)
            args={'action':'attach_assessment','universe':NAME,'context_id':s.ctx,'proposal_reference':s.reference(p),
                  'expected_selection_generation':0,'body':body,'idempotency_key':'interrupted'}
            dbpath=s.root/'packages'/(s.uid+'.sqlite')
            def sql(statement):
                with sqlite3.connect(dbpath) as db: db.execute(statement)
            def typed_counts():
                with sqlite3.connect(dbpath) as db:
                    return {name:db.execute('SELECT count(*) FROM "'+name+'"').fetchone()[0]
                        for name, in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'r_%'")}
            sql("CREATE TRIGGER inject_interrupted_workflow BEFORE INSERT ON workflow_entries WHEN NEW.family='AssessmentReceipt' BEGIN SELECT RAISE(ABORT,'injected publication interruption'); END")
            before=snapshot(s);counts=typed_counts()
            raw=s.client.request('tools/call',{'name':'universe_propose','arguments':args})
            assert raw.get('isError'),raw
            after=snapshot(s)
            assert before==after and counts==typed_counts()
            report['interruption']={'arguments':args,'response':raw,'before':before,'after':after,'typed_rows_before':counts,'typed_rows_after':typed_counts()}
            sql('DROP TRIGGER inject_interrupted_workflow')
            contenders=[copy.deepcopy(args),copy.deepcopy(args)]
            contenders[0]['idempotency_key']='race-a'
            contenders[1]['idempotency_key']='race-b'
            contenders[1]['body']['assessor']['assessed_at']='2026-10-03T00:00:01Z'
            report['race_before']=snapshot(s)
            ids=[]
            # Both public requests are in flight before any reply is consumed.
            for contender in contenders:
                s.client.schemas['universe_propose'][0].validate(contender)
                s.client.seq+=1;ids.append(s.client.seq)
                s.client.write({'jsonrpc':'2.0','id':s.client.seq,'method':'tools/call','params':{'name':'universe_propose','arguments':contender}})
            responses={}
            while len(responses)<2:
                response=s.client.responses.get(timeout=30)
                if isinstance(response,Exception): raise response
                if 'id' not in response: s.client.notifications.append(response);continue
                assert response['id'] in ids and 'error' not in response
                responses[response['id']]=response['result']
            assert sum(not r.get('isError',False) for r in responses.values())==1
            report['contenders']=[{'arguments':a,'response':responses[i]} for a,i in zip(contenders,ids)]
            report['race_after']=snapshot(s)
            winner=next(c for c in report['contenders'] if not c['response'].get('isError',False))
            s.restart()
            report['restart']=snapshot(s)
            retry_args=copy.deepcopy(winner['arguments']);retry_args['context_id']=s.ctx
            # Context is checked before recovery; the request binding excludes
            # the current context token and preserves the original receipt.
            retry=s.client.request('tools/call',{'name':'universe_propose','arguments':retry_args})
            assert retry==winner['response'],(retry,winner)
            report['retry']={'arguments':retry_args,'response':retry,'after':snapshot(s)}
            for c in report['contenders']:
                if not c['response'].get('isError',False):s.client.schemas['universe_propose'][1].validate(c['response']['structuredContent'])
        finally:s.close()
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,separators=(',',':'))+'\n')
    print('PASS: interrupted typed publication, concurrent selection CAS, restart exact retry')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--bin-dir',type=Path,default=Path('target/debug'));p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();run(a.bin_dir.resolve(),a.output)
