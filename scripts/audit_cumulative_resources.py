"""Independent Fraction replay plus raw wire, canonical history and receipt audit.

Imports no production evaluator, pilot runner or expected-result generator.
"""
from contextlib import closing
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from audit_g02 import check, digest, wire_calls


def replay(records):
    rows={k:v['payload'] for k,v in records.items()}
    events=sorted([(int(p['time']['value']),k,p) for k,p in rows.items() if p['record_kind']=='event' and p['occurrence']=='occurred'])
    history=[]; calculations=[]
    def pre(owner,predicate,t,world=None):
        values=[]
        for p in rows.values():
            if p['record_kind']!='assertion' or p.get('establishedBy'):continue
            q=rows[p['proposition']['record']];v=p['validity']
            applies=p['scope']['applicability']
            if applies['kind']=='worlds' and world not in applies['world_ids']:continue
            if q['subject']['record']!=owner or q['predicate']['record']!=predicate:continue
            if v['kind']=='calendar_interval' and (v['start']['kind']=='unbounded' or int(v['start']['value'])<t) and (v['end']['kind']=='unbounded' or t<=int(v['end']['value'])):
                if p['polarity']!='support':raise ValueError('refuted stock')
                values.append(q['value'])
        prior=[h for h in history if h[0]<t and h[1:3]==(owner,predicate) and (not h[4] or world in h[4])]
        if prior:values.append(prior[-1][3])
        unique={json.dumps(v,sort_keys=True) for v in values}
        if len(unique)!=1:raise ValueError('missing/conflicting balance')
        return values[0]
    try:
        uses=[]
        for t,k,e in events:
            action=rows[e['action']['record']];slots=action['consequenceContract']['slots']
            for condition in e['preconditions']:
                actual=pre(condition['subject']['ref']['record'],next(rid for rid,p in rows.items() if p['record_kind']=='property' and p['namespace']+':'+p['key']==condition['predicate']),t)
                if actual!=condition['value']['value']:raise ValueError('dependent holder requires earlier handoff')
            for effect in e['effects']:
                slot=next(s for s in slots if s['slot']==effect['slot']);p=rows[effect['proposition']['record']];owner=p['subject']['record'];predicate=p['predicate']['record'];change=slot['change']
                check(owner==next(a['record']['record'] for a in e['participants'] if a['role']==slot['target']['role']) and p['predicate']==slot['target']['predicate'],'effect owner differs from contract')
                delta=change['kind']=='delta'
                if any(u[0]==t and u[1:3]==(owner,predicate) and (delta or u[3]) and (not u[4] or not e.get('worlds') or set(u[4]) & set(e['worlds'])) for u in uses):raise ValueError('simultaneous resource use')
                uses.append((t,owner,predicate,delta,e.get('worlds',[])))
                if delta:
                    for world in e.get('worlds',[]) or [None]:
                        before=Fraction(pre(owner,predicate,t,world)['digits']);amount=Fraction(change['delta']);after=before+amount;proposed=Fraction(p['value']['digits'])
                        calculations.append({'event':k,'tick':t,'owner':owner,'world':world,'before':str(before),'delta':str(amount),'after':str(after),'proposed':str(proposed)})
                        if after!=proposed or not Fraction(change['minimum'])<=after<=Fraction(change['maximum']):raise ValueError('arithmetic')
                elif p['value']!=change['value']:raise ValueError('set mismatch')
                history.append((t,owner,predicate,p['value'],e.get('worlds',[])))
        return {'allowed':True,'calculations':calculations}
    except ValueError as e:return {'allowed':False,'reason':str(e),'calculations':calculations}


def verify_generated(records):
    rows={k:v['payload'] for k,v in records.items()};groups={};expected={}
    for event_id,e in rows.items():
        if e['record_kind']!='event' or e['occurrence']!='occurred':continue
        for effect in e['effects']:
            p=rows[effect['proposition']['record']];key=(p['subject']['record'],p['predicate']['record'])
            groups.setdefault(key,[]).append((int(e['time']['value']),event_id,effect))
    for effects in groups.values():
        effects.sort()
        for i,(tick,event_id,effect) in enumerate(effects):
            validity=json.loads(json.dumps(effect['validity']))
            if i+1<len(effects):validity['end']={'kind':'exact','value':str(effects[i+1][0])}
            generated='rec_'+hashlib.sha256(f"events-v1:{event_id}:{effect['slot']}".encode()).hexdigest()[:24]
            a=rows.get(generated);check(a is not None,'missing generated assertion')
            check(all(a[k]==effect[k] for k in ('proposition','polarity','scope')) and a['validity']==validity and a['establishedBy']=={'event':{'universe':records[event_id]['identity']['universe_id'],'record':event_id},'slot':effect['slot']},'generated assertion/endpoint differs')
            expected[generated]=a
    check({k for k,p in rows.items() if p['record_kind']=='assertion' and p.get('establishedBy')}==set(expected),'extra generated assertions')


def audit(directory):
    report=json.loads((directory/'report.json').read_text());gold=json.loads((directory/'oracle.json').read_text());identity=json.loads((directory/'build-identity.json').read_text())
    check(report['status']=='executed','runner incomplete')
    check(hashlib.sha256((directory/'oracle.json').read_bytes()).hexdigest()==identity['continuation_oracle_sha256'],'oracle changed')
    check(hashlib.sha256((directory/'package.sqlite').read_bytes()).hexdigest()==report['package_sha256'],'package changed')
    calls=wire_calls(directory/'mcp-transcript.jsonl',expected_sessions=3);check([{k:v for k,v in c.items() if k!='lines'} for c in calls]==report['mcp'],'report differs from wire')
    def on_wire(tool,result):check(any(c['tool']==tool and c['result']==result for c in calls),tool+' absent from wire')
    with closing(sqlite3.connect(f"file:{directory/'package.sqlite'}?mode=ro&immutable=1",uri=True)) as db:
        db.row_factory=sqlite3.Row;check(db.execute('PRAGMA integrity_check').fetchone()[0]=='ok','database corrupt');check(not db.execute('PRAGMA foreign_key_check').fetchall(),'foreign key failure')
        workflow={}
        for row in db.execute('SELECT key,payload,digest FROM workflow_entries'):
            v=json.loads(row['payload']);check(digest(v)==row['digest'],'workflow digest differs');workflow[row['key']]=v
        versions={r['id']:json.loads(r['payload']) for r in db.execute('SELECT id,payload FROM record_versions')}
        def snapshot(rev):
            path=[]
            while rev:
                path.append(rev);row=db.execute('SELECT parent_id FROM commits WHERE id=?',(rev,)).fetchone();check(row is not None,'missing commit');rev=row[0]
            result={}
            for rev in reversed(path):
                for row in db.execute('SELECT record_id,version_id FROM commit_changes WHERE revision_id=?',(rev,)):
                    if row['version_id']:result[row['record_id']]=versions[row['version_id']]
                    else:result.pop(row['record_id'],None)
            return result
        def candidate(p):
            st=workflow[f"proposal:{p['proposal_id']}:{p['version']:020}"];check(st['proposal']==p,'stored proposal differs');on_wire('universe_propose',next(c['result'] for c in calls if c['tool']=='universe_propose' and c['result'].get('result')==p))
            rows=snapshot(p['base_frame']['revision']);rows.update({c['record_id']:c['next'] for c in st['changes'] if c['next']});return st,rows
        accounting={}
        for pub in report['publications']:
            p=pub['review']['proposal'];st,rows=candidate(p);v=pub['validation'];receipt=pub['receipt'];args=pub['commit_arguments'];checked=workflow[f"validation:{v['run_id']}"]
            check(checked['validation']==v and checked['proposal_digest']==p['digest'] and checked['admissible'],'validation binding differs')
            check(v['coverage']=='complete' and not v['findings'] and v['evaluator_version']=='finite-policy-v8-cumulative-resources','stale/incomplete validation')
            approvals=[a for k,a in workflow.items() if k.startswith('approval:') and k.endswith(f":{p['digest']}:{v['run_id']}")];check(len(approvals)==1,'missing approval');a=approvals[0]
            check(a['proposal']==args['proposal_reference'] and a['validation_digest']==digest(checked) and a['evaluator']==v['evaluator_version'] and a['author']==pub['author_selection']['author_profile'],'approval differs')
            check(any(c['arguments']==['review','The Cairn Archive Pilot',p['proposal_id'],str(p['version']),p['digest']] and c['returncode']==0 and json.loads(c['stdout'])==pub['review'] for c in report['author_cli']),'private review absent')
            op=workflow[f"operation:{receipt['operation_id']}"];check(op['input']['changes']==st['changes']==pub['review']['changes'],'frozen changes differ')
            kernel=db.execute('SELECT * FROM operation_receipts WHERE idempotency_key=?',(args['idempotency_key'],)).fetchone();check(kernel and kernel['revision_id']==receipt['revision'] and kernel['payload_digest']==digest(op['input']),'kernel receipt differs')
            commit=db.execute('SELECT * FROM commits WHERE id=?',(receipt['revision'],)).fetchone();check(commit['parent_id']==args['expected_base_revision'] and commit['digest']==digest(op['input']) and commit['decision']==p['digest'],'commit binding differs')
            changes={r['record_id']:r for r in db.execute('SELECT * FROM commit_changes WHERE revision_id=?',(receipt['revision'],))};check(set(changes)=={c['record_id'] for c in st['changes']},'commit footprint differs')
            for c in st['changes']:check(changes[c['record_id']]['prior_version']==c['expected'] and versions[changes[c['record_id']]['version_id']]==c['next'],'committed version differs')
            on_wire('universe_commit',next(c['result'] for c in calls if c['tool']=='universe_commit' and c['result'].get('result')==receipt))
            accounting[pub['key']]=replay(rows);check(accounting[pub['key']]['allowed'],'independent committed accounting failed')
            check(snapshot(receipt['revision'])==rows,'canonical candidate differs')
            verify_generated(rows)
        check([s['index'] for s in report['shots']]==list(range(1,13)),'shot inventory differs')
        rid=lambda n:f'rec_{200000+n:024x}'
        check(gold['shots']==[int(Fraction(gold['initial_gun'])-i) for i in range(1,13)] and gold['shots'][-1]==0,'independent twelve-round oracle differs')
        for row,want in zip(report['shots'],gold['shots']):
            records=snapshot(row['receipt']['revision']);e=records[row['event']]['payload'];p=records[e['effects'][0]['proposition']['record']]['payload'];check(p['subject']['record']==rid(1) and int(p['value']['digits'])==want and int(e['time']['value'])==10+row['index'],'shot balance/time/owner differs')
        check({r['id'] for r in report['rejections']}==set(gold['rejections']),'rejection inventory differs')
        for row in report['rejections']:
            if 'proposal' in row:
                st,rows=candidate(row['proposal']);error=row['error']
                on_wire('universe_validate',error);on_wire('universe_commit',row['commit_error']);check(not db.execute('SELECT 1 FROM commits WHERE decision=?',(row['proposal']['digest'],)).fetchone(),'rejected proposal committed')
            else:
                rows=snapshot(row['before']);error=row['propose_error'];on_wire('universe_propose',error)
                check(any(c['tool']=='universe_propose' and c['arguments']==row['propose_arguments'] and c['result']==error for c in calls),'early rejection stimulus differs')
                check(row['propose_arguments']['operations']==row['operations'],'early operations differ')
                for op in row['operations']:
                    if op['kind']=='define_proposition':rows[op['client_ref']]={'payload':{'record_kind':'proposition',**op['record']}}
                    elif op['kind']=='record_event':rows[op['client_ref']]={'payload':{'record_kind':'event',**op['record']}}
                    elif op['kind']=='revise_event':rows[op['record']['record']]={'payload':{'record_kind':'event',**op['replacement']}}
                    else:raise RuntimeError('unexpected early-rejection operation')
            calc=replay(rows);check(not calc['allowed'],'independent rejection accounting differs: '+row['id']);accounting[row['id']]=calc
            check(error['code']=='INVALID_ARGUMENT' and row['before']==row['after'] and snapshot(row['before'])==snapshot(row['after']),'rejection changed canon')
            if row['id']=='retcon_stale_balances':
                check(calc['calculations'][0]['before']=='11' and calc['calculations'][0]['after']=='10' and calc['calculations'][0]['proposed']=='10','retcon first use was not valid')
                check(calc['calculations'][1]['after']=='9' and calc['calculations'][1]['proposed']=='10','unchanged successor was not rechecked')
        check({r['id'] for r in report['states']}==set(gold['states']),'state inventory differs')
        for row in report['states']:
            response=row['response'];on_wire('universe_get_state',response);day=int(response['frame']['time']['time']['value']);records=snapshot(response['frame']['revision']);expected=[]
            for r in records.values():
                a=r['payload']
                if a['record_kind']!='assertion':continue
                p=records[a['proposition']['record']]['payload'];v=a['validity']
                if p['subject']['record'] in [rid(n) for n in (1,2,3,4)] and v['kind']=='calendar_interval' and (v['start']['kind']=='unbounded' or int(v['start']['value'])<=day) and (v['end']['kind']=='unbounded' or day<int(v['end']['value'])):expected.append(r)
            check(sorted(response['result']['assertions'],key=lambda r:r['record_version_id'])==sorted(expected,key=lambda r:r['record_version_id']),'query differs from canonical history')
            amounts={};holders=[]
            for a in expected:
                p=records[a['payload']['proposition']['record']]['payload']
                if p['predicate']['record']==rid(10):amounts.setdefault(p['subject']['record'],set()).add(int(p['value']['digits']))
                else:holders.append(p['value']['ref']['record'])
            gun,supply,holder=gold['states'][row['id']];check(amounts=={rid(1):{gun},rid(4):{supply}} and holders==[rid(holder)],'independent expected balance/holder differs: '+row['id'])
        check(gold['reload']['gun']==gold['shots'][-1]+gold['reload']['amount'] and gold['reload']['supply']==gold['initial_supply']-gold['reload']['amount'],'reload oracle differs')
        check(report['old_event']==report['restart_old_event'] and report['old_event']['payload']['time']['value']=='11','old event edition changed')
        check(report['before_restart_head']==report['after_restart_head']==db.execute('SELECT head_commit FROM continuities').fetchone()[0],'restart head differs')
        for record in [report['old_event'],report['restart_old_event'],*report['restart_editions']]:
            check(any(c['tool']=='universe_get' and record in c['result'].get('result',{}).get('records',[]) for c in calls),'restart edition record absent from wire')
        instances=[json.loads(c['stdout'])['service_instance'] for c in report['author_cli'] if c['arguments']==['status'] and c['returncode']==0]
        check(len(instances)==3 and len(set(instances))==3,'engine service instances did not change twice')
        check(report['restart_editions']==[e[k] for e in report['editions'] for k in ('version','scene')],'editions/scenes changed on restart')
        check(len(report['editions'])==3,'missing scenes')
        for e in report['editions']:
            check(e['version']['payload']['binding']['revision']==e['revision'] and e['scene']['payload']['workVersion']['version']==e['version']['record_version_id'],'edition binding differs')
        check(report['retry_receipts']==[p['receipt'] for p in report['publications']],'restart retry receipts differ')
        for receipt in report['retry_receipts']:check(sum(c['tool']=='universe_commit' and c['result'].get('result')==receipt for c in calls)>=3,'retry absent from wire')
        check(db.execute('SELECT count(*) FROM operation_receipts').fetchone()[0]==len(report['publications'])+1,'unexpected kernel receipts')
    result={'status':'passed','mcp_calls':len(calls),'commits':len(report['publications']),'rejections':len(report['rejections']),'states':len(report['states']),'scenes':3,'restarts':2,'independent_accounting':accounting,'wire_history_approvals_and_restart_receipts':'passed','scope':'Cumulative declared resource accounting; reusable rules and prose excluded'}
    (directory/'audit.json').write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':print(json.dumps(audit(Path(sys.argv[1]).resolve()),indent=2))
