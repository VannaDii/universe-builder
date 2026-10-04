"""Independent wire/storage/expected-effect audit; no runner or engine imports."""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
from relational_history import versions as relational_versions
import sys
from audit_g02 import check, digest, wire_calls
from resource_accounting import materialize, calculate


def audit(directory):
    report=json.loads((directory/'report.json').read_text()); gold=json.loads((directory/'oracle.json').read_text()); identity=json.loads((directory/'build-identity.json').read_text())
    check(report['status']=='executed','runner incomplete')
    check(hashlib.sha256((directory/'oracle.json').read_bytes()).hexdigest()==identity['resource_oracle_sha256'],'oracle changed')
    check(hashlib.sha256((directory/'package.sqlite').read_bytes()).hexdigest()==report['package_sha256'],'package changed')
    calls=wire_calls(directory/'mcp-transcript.jsonl')
    check([{k:v for k,v in c.items() if k!='lines'} for c in calls]==report['mcp'],'report differs from wire')
    expected={c['id']:c for c in gold['cases'] if c.get('mcp',True)}
    check(len(report['cases'])==len(expected) and {c['id'] for c in report['cases']}==set(expected),'case inventory differs')
    def on_wire(tool,result,p=None,error=None):
        found=[c for c in calls if c['tool']==tool and c['result']==result and (p is None or c['arguments'].get('proposal_reference',{}).get('proposal_id')==p['proposal_id']) and (error is None or c['expected_error']==error)]
        check(found,tool+' evidence absent from wire'); return found
    with closing(sqlite3.connect(f"file:{directory/'package.sqlite'}?mode=ro&immutable=1",uri=True)) as db:
        db.row_factory=sqlite3.Row
        check(db.execute('PRAGMA integrity_check').fetchone()[0]=='ok','database corrupt')
        check(not db.execute('PRAGMA foreign_key_check').fetchall(),'foreign key failure')
        workflow={}
        for row in db.execute('SELECT key,payload,digest FROM workflow_entries'):
            v=json.loads(row['payload']); check(digest(v)==row['digest'],'workflow digest differs'); workflow[row['key']]=v
        versions = relational_versions(db)
        def snapshot(rev):
            path=[]
            while rev:
                path.append(rev); row=db.execute('SELECT parent_id FROM commits WHERE id=?',(rev,)).fetchone(); check(row is not None,'missing commit'); rev=row[0]
            result={}
            for rev in reversed(path):
                for row in db.execute('SELECT record_id,version_id FROM commit_changes WHERE revision_id=?',(rev,)):
                    if row['version_id']: result[row['record_id']]=versions[row['version_id']]
                    else: result.pop(row['record_id'],None)
            return result
        def stored(p):
            v=workflow[f"proposal:{p['proposal_id']}:{p['version']:020}"]; check(v['proposal']==p,'proposal differs'); on_wire('universe_propose',next(c['result'] for c in calls if c['tool']=='universe_propose' and c['result'].get('result')==p)); return v
        def head_control(before,after,changed):
            check((before!=after)==changed,'head disposition differs')
            for rev in (before,after): check(any(c['tool']=='universe_open_context' and c['result']['result']['frame']['revision']==rev for c in calls),'head absent from wire')
        def state(response,owners,day):
            on_wire('universe_get_state',response,error=False)
            check(int(response['frame']['time']['time']['value'])==day,'wrong state time')
            records=snapshot(response['frame']['revision']); expected_rows=[]
            for row in records.values():
                a=row['payload']
                if a['record_kind']!='assertion': continue
                p=records[a['proposition']['record']]['payload']
                if p['subject']['record'] not in owners: continue
                v=a['validity']
                if v['kind']=='unknown' or v['kind']=='calendar_interval' and (v['start']['kind']=='unbounded' or int(v['start']['value'])<=day) and (v['end']['kind']=='unbounded' or day<int(v['end']['value'])): expected_rows.append(row)
            check(sorted(response['result']['assertions'],key=lambda r:r['record_version_id'])==sorted(expected_rows,key=lambda r:r['record_version_id']),'queried assertions differ from canonical history')
            return expected_rows
        # Exact review -> validation -> approval -> operation -> SQL commit bindings.
        for pub in report['publications']:
            p=pub['review']['proposal']; st=stored(p); v=pub['validation']; receipt=pub['receipt']; args=pub['commit_arguments']
            checked=workflow[f"validation:{v['run_id']}"]
            check(checked['validation']==v and checked['proposal_digest']==p['digest'] and checked['admissible'],'validation binding differs')
            check(v['coverage']=='complete' and not v['findings'] and v['evaluator_version'] in ('finite-policy-v7-resource-transitions','finite-policy-v8-cumulative-resources'),'incomplete or stale evaluator')
            approvals=[a for k,a in workflow.items() if k.startswith('approval:') and k.endswith(f":{p['digest']}:{v['run_id']}")]
            check(len(approvals)==1,'missing exact approval')
            a=approvals[0]; check(a['proposal']==args['proposal_reference'] and a['validation_digest']==digest(checked) and a['evaluator']==v['evaluator_version'] and a['author']==pub['author_selection']['author_profile'],'approval binding differs')
            check(any(c['arguments']==['review','The Cairn Archive Pilot',p['proposal_id'],str(p['version']),p['digest']] and c['returncode']==0 and json.loads(c['stdout'])==pub['review'] for c in report['author_cli']),'private review absent')
            op=workflow[f"operation:{receipt['operation_id']}"]
            check(op['input']['changes']==st['changes']==pub['review']['changes'],'frozen review differs from operation')
            kernel=db.execute('SELECT * FROM operation_receipts WHERE idempotency_key=?',(args['idempotency_key'],)).fetchone()
            check(kernel and kernel['revision_id']==receipt['revision'] and kernel['payload_digest']==digest(op['input']),'kernel receipt differs')
            commit=db.execute('SELECT * FROM commits WHERE id=?',(receipt['revision'],)).fetchone()
            check(commit['parent_id']==args['expected_base_revision'] and commit['digest']==digest(op['input']) and commit['decision']==p['digest'],'commit differs')
            changes={r['record_id']:r for r in db.execute('SELECT * FROM commit_changes WHERE revision_id=?',(receipt['revision'],))}
            check(set(changes)=={c['record_id'] for c in st['changes']},'commit footprint differs')
            for c in st['changes']:
                check(changes[c['record_id']]['prior_version']==c['expected'] and versions[changes[c['record_id']]['version_id']]==c['next'],'committed version differs from frozen review')
            on_wire('universe_commit',next(c['result'] for c in calls if c['tool']=='universe_commit' and c['result'].get('result')==receipt),error=False)
        results={}
        for row in report['cases']:
            case=expected[row['id']]; authored=materialize(gold,case); calc=calculate(authored)
            check(calc['allowed']==case['allowed'],'independent accounting differs')
            p=row['proposal'];st=stored(p);records=snapshot(p['base_frame']['revision'])
            records.update({c['record_id']:c['next'] for c in st['changes'] if c['next']})
            offset=row['offset'];rid=lambda n:f"rec_{200000+offset+n:024x}"
            event_id=rid(6);event=records[event_id]['payload']
            def bind(v):
                if isinstance(v,dict):return {k:bind(x) for k,x in v.items()}
                if isinstance(v,list):return [bind(x) for x in v]
                if isinstance(v,str):
                    if v.startswith('unv_'):return report['installation']['universe_id']
                    if v.startswith('cal_'):return event['time']['calendar']
                    for prefix in ('rec_','wld_','unit_'):
                        if v.startswith(prefix):
                            n=int(v[len(prefix):],16)
                            return report['installation']['context_id'] if prefix=='rec_' and n==10 else rid(n).replace('rec_',prefix,1)
                return v
            bound=bind(authored);bound[2]['namespace']=bound[4]['namespace']=bound[12]['namespace']='resource_'+row['id']
            bound[13]['selector']=row['id']+' A';bound[14]['selector']=row['id']+' B'
            for n,payload in enumerate(bound,1):
                payload.pop('types', None)
                if 'consequenceContract' in payload:
                    payload['consequenceContract']['kind']='action_consequences'
                if payload['record_kind']=='assertion':
                    premise=bound[int(authored[n-1]['proposition']['record'][4:],16)-1]
                    actual=records[rid(n)]['payload']
                    check(all(actual.get(k)==v for k,v in premise.items()),'premise differs: '+row['id'])
                    assertions=[r['payload'] for r in records.values() if r['payload']['record_kind']=='assertion' and r['payload']['proposition']['record']==rid(n)]
                    want={**payload,'proposition':{'universe':report['installation']['universe_id'],'record':rid(n)}}
                    check(len(assertions)==1 and all(assertions[0].get(k)==v for k,v in want.items()),'asserted evidence differs')
                else:
                    actual=records[rid(n)]['payload']
                    check(all(actual.get(k)==v for k,v in payload.items()),'frozen stimulus differs: '+row['id'])
            allowed=calc['allowed'];head_control(row['head_before'],row['head_after'],allowed)
            if allowed:
                check(row['receipt']['revision']==row['head_after'],'receipt head differs')
                pub=next(pu for pu in report['publications'] if pu['receipt']==row['receipt'])
                generated=[c['next'] for c in pub['review']['changes'] if c.get('next',{}).get('payload',{}).get('establishedBy')]
                effects=event['effects'] if event['occurrence']=='occurred' else []
                check(len(generated)==len(effects),'generated count differs')
                for e in effects:
                    identity='rec_'+hashlib.sha256(f"events-v1:{event_id}:{e['slot']}".encode()).hexdigest()[:24]
                    a=next(g for g in generated if g['identity']['record_id']==identity)['payload']
                    check(all(a[k]==e[k] for k in ('proposition','polarity','scope','validity')) and a['establishedBy']=={'event':{'universe':report['installation']['universe_id'],'record':event_id},'slot':e['slot']},'generated assertion differs')
                for day,response in row['states'].items():state(response,[rid(1),rid(2)],int(day))
            else:
                check(row['rejection']['code']=='INVALID_ARGUMENT','wrong rejection')
                on_wire('universe_validate',row['rejection'],p,error=True);on_wire('universe_commit',row['commit_rejection'],p,error=True)
                check(snapshot(row['head_before'])==snapshot(row['head_after']),'rejected canon changed')
                check(not db.execute('SELECT 1 FROM commit_changes WHERE record_id=?',(event_id,)).fetchone(),'rejected event committed')
            results[row['id']]={**calc,'head_control':'passed'}
        check({c['id'] for c in report['retcon_controls']}=={'refuted-stock','unknown-stock'},'retcon inventory differs')
        for c in report['retcon_controls']:
            p=c['proposal'];st=stored(p);before=snapshot(c['head_before']);head_control(c['head_before'],c['head_after'],False)
            check(before==snapshot(c['head_after']),'retcon changed canon')
            original=c['original'];record_id=original['identity']['record_id']
            check(before[record_id]==original and original['payload']['record_kind']=='assertion','retcon original differs')
            want={k:v for k,v in original['payload'].items() if k!='record_kind'}
            if c['id']=='refuted-stock':want['polarity']='refutation'
            else:want['validity']={'kind':'unknown'}
            check(st['proposal']['operations']==[c['operation']] and c['operation']['replacement']==want and len(st['changes'])==1 and st['changes'][0]['record_id']==record_id,'retcon stimulus differs')
            check(c['rejection']['code']=='INVALID_ARGUMENT' and c['rejection']['field']=='event.action.effects','retcon failed outside consequence validation')
            on_wire('universe_validate',c['rejection'],p,error=True);on_wire('universe_commit',c['commit_rejection'],p,error=True)
        c=next(c for c in report['cases'] if c['id']=='atomic_transfer')
        state(report['restart_state'],[f"rec_{200000+c['offset']+n:024x}" for n in (1,2)],15)
        check(report['restart_receipt']==report['publications'][-1]['receipt'],'restart receipt differs')
        final=report['cases'][-1]['head_after'];check(report['head_after_restart']==final and db.execute('SELECT head_commit FROM continuities').fetchone()[0]==final,'final head differs')
        check(db.execute('SELECT count(*) FROM operation_receipts').fetchone()[0]==len(report['publications'])+1,'unexpected receipt count')
    result={'status':'passed','cases':results,'rejected':sum(not r['allowed'] for r in results.values()),'committed':sum(r['allowed'] for r in results.values()),'mcp_calls':len(calls),'exact_frozen_assertions_queries_approvals_and_unchanged_canon':'passed','limit':'Independent program audit of single-event transitions; excludes ordering, reusable rules and prose.'}
    (directory/'audit.json').write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':print(json.dumps(audit(Path(sys.argv[1]).resolve()),indent=2))
