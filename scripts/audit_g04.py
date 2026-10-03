"""Independent wire/storage/expected-effect audit; no runner or engine imports."""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from audit_g02 import check, digest, wire_calls


def audit(directory):
    report=json.loads((directory/'report.json').read_text()); gold=json.loads((directory/'oracle.json').read_text()); identity=json.loads((directory/'build-identity.json').read_text())
    check(report['status']=='executed','runner incomplete')
    check(hashlib.sha256((directory/'oracle.json').read_bytes()).hexdigest()==identity['effect_oracle_sha256'],'oracle changed')
    check(hashlib.sha256((directory/'package.sqlite').read_bytes()).hexdigest()==report['package_sha256'],'package changed')
    calls=wire_calls(directory/'mcp-transcript.jsonl')
    check([{k:v for k,v in c.items() if k!='lines'} for c in calls]==report['mcp'],'report differs from wire')
    expected={c['id']:c for c in gold['cases'] if c.get('mcp',True) and c['id'] not in {'duplicate_slot','wrong_predicate','wrong_context','historical_contractless'}}
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
        versions={r['id']:json.loads(r['payload']) for r in db.execute('SELECT id,payload FROM record_versions')}
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
        def state(response,owner,day):
            on_wire('universe_get_state',response,error=False)
            check(int(response['frame']['time']['time']['value'])==day,'wrong state time')
            records=snapshot(response['frame']['revision']); expected_rows=[]
            for row in records.values():
                a=row['payload']
                if a['record_kind']!='assertion': continue
                p=records[a['proposition']['record']]['payload']
                if p['subject']['record']!=owner: continue
                v=a['validity']
                if v['kind']=='unknown' or v['kind']=='calendar_interval' and (v['start']['kind']=='unbounded' or int(v['start']['value'])<=day) and (v['end']['kind']=='unbounded' or day<int(v['end']['value'])): expected_rows.append(row)
            check(sorted(response['result']['assertions'],key=lambda r:r['record_version_id'])==sorted(expected_rows,key=lambda r:r['record_version_id']),'queried assertions differ from canonical history')
            return expected_rows
        # Exact review -> validation -> approval -> operation -> SQL commit bindings.
        for pub in report['publications']:
            p=pub['review']['proposal']; st=stored(p); v=pub['validation']; receipt=pub['receipt']; args=pub['commit_arguments']
            checked=workflow[f"validation:{v['run_id']}"]
            check(checked['validation']==v and checked['proposal_digest']==p['digest'] and checked['admissible'],'validation binding differs')
            check(v['coverage']=='complete' and not v['findings'] and v['evaluator_version']=='finite-policy-v6-declared-effects','incomplete or stale evaluator')
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
            p=row['proposal']; st=stored(p); records=snapshot(p['base_frame']['revision'])
            records.update({c['record_id']:c['next'] for c in st['changes'] if c['next']})
            event_id=f"rec_{200000+row['offset']+6:024x}"; owner=f"rec_{200000+row['offset']+1:024x}"
            # Bind each actual stimulus to the frozen authored fixture, including
            # rejected effects; checking only the outcome would allow easier cases.
            authored=json.loads(json.dumps(gold['records']))
            for m in expected[row['id']]['mutations']:
                target=authored[m['record']-1]; parts=m['path'].split('.')
                for part in parts[:-1]: target=target[int(part)] if isinstance(target,list) else target[part]
                if m['value'] is None: target.pop(parts[-1])
                else: target[parts[-1]]=m['value']
            def bind(value):
                if isinstance(value,dict): return {k:bind(v) for k,v in value.items()}
                if isinstance(value,list): return [bind(v) for v in value]
                if isinstance(value,str):
                    if value.startswith('unv_'): return report['installation']['universe_id']
                    if value.startswith('cal_'): return records[event_id]['payload']['time']['calendar']
                    if value.startswith('rec_'):
                        n=int(value[4:],16)
                        return report['installation']['context_id'] if n==10 else f"rec_{200000+row['offset']+n:024x}"
                    if value.startswith('wld_'): return f"wld_{200000+row['offset']+int(value[4:],16):024x}"
                return value
            authored=bind(authored)
            authored[2]['namespace']=authored[4]['namespace']='g04_'+row['id']
            for n,expected_payload in enumerate(authored[:7],1):
                actual=records[f"rec_{200000+row['offset']+n:024x}"]['payload']
                check(all(actual.get(k)==v for k,v in expected_payload.items()),'actual stimulus differs from independent fixture: '+row['id'])
                if n==5: check(('consequenceContract' in actual)==('consequenceContract' in expected_payload),'historical absence changed')
            evidence_prop=f"rec_{200000+row['offset']+8:024x}"
            premise=authored[3] if authored[7]['proposition']['record'].endswith(f"{200000+row['offset']+4:024x}") else authored[6]
            check(all(records[evidence_prop]['payload'].get(k)==v for k,v in premise.items()),'condition premise differs')
            evidence_assertions=[r['payload'] for r in records.values() if r['payload']['record_kind']=='assertion' and r['payload']['proposition']['record']==evidence_prop]
            expected_assertion={**authored[7],'proposition':{'universe':report['installation']['universe_id'],'record':evidence_prop}}
            check(len(evidence_assertions)==1 and all(evidence_assertions[0].get(k)==v for k,v in expected_assertion.items()),'condition assertion differs')
            event=records[event_id]['payload']; action=records[event['action']['record']]['payload']; contract=action.get('consequenceContract')
            # Independent admission calculation: no production matching/expansion helpers.
            allowed=contract is not None
            if allowed:
                slots={s['slot']:s for s in contract['slots']}; effects={e['slot']:e for e in event['effects']}
                allowed=len(effects)==len(event['effects']) and set(effects)<=set(slots)
                for key, slot in slots.items():
                    participants=[p['record'] for p in event['participants'] if p['role']==slot['target']['role']]
                    allowed=allowed and len(participants)==1
                    e=effects.get(key)
                    if e:
                        prop=records[e['proposition']['record']]['payload']; scope={'context':action['scope']['context'],'applicability':{'kind':'universe_wide'}}
                        allowed=allowed and prop['subject']==(participants[0] if len(participants)==1 else None) and prop['predicate']==slot['target']['predicate'] and prop.get('roles',[])==[] and prop['context']==scope['context'] and e['scope']==scope and e['order']==slot['order'] and prop['value']==slot['change']['value'] and e['polarity']==slot['change']['polarity'] and e['validity']['start']=={'kind':'exact','value':event['time']['value']} and e['validity']['end']=={'kind':'exact','value':str(int(event['time']['value'])+int(slot['lifetime']['count']))}
                    enabled=True
                    if event['occurrence']=='occurred' and slot['condition']['kind']=='attribute_equals':
                        condition=slot['condition']; facts=[]; unknown=False
                        for record in records.values():
                            a=record['payload']
                            if a['record_kind']!='assertion': continue
                            q=records[a['proposition']['record']]['payload']
                            if q['subject']['record']!=owner or q['predicate']!=condition['predicate']: continue
                            validity=a['validity']
                            if validity['kind']!='calendar_interval': unknown=True; continue
                            t=int(event['time']['value'])
                            if int(validity['start']['value'])<t and (validity['end']['kind']=='unbounded' or t<=int(validity['end']['value'])): facts.append((q['value'],a['polarity']))
                        support=[v for v,pol in facts if pol=='support']; refute=[v for v,pol in facts if pol=='refutation']
                        if unknown or not facts or any(v in refute for v in support): allowed=False
                        enabled=condition['value'] in support
                    if event['occurrence']=='occurred': allowed=allowed and (enabled or not e) and (not enabled or slot['presence']!='required' or e is not None)
            check(bool(allowed)==expected[row['id']]['allowed'],'independent expected-effect admission differs: '+row['id'])
            head_control(row['head_before'],row['head_after'],bool(allowed))
            if allowed:
                check(row['receipt']['revision']==row['head_after'],'receipt head differs')
                pub=next(pu for pu in report['publications'] if pu['receipt']==row['receipt'])
                generated=[c['next'] for c in pub['review']['changes'] if c.get('next',{}).get('payload',{}).get('establishedBy')]
                expected_effects=event['effects'] if event['occurrence']=='occurred' else []
                check(len(generated)==len(expected_effects),'generated count differs')
                for e in expected_effects:
                    rid='rec_'+hashlib.sha256(f"events-v1:{event_id}:{e['slot']}".encode()).hexdigest()[:24]
                    g=next(g for g in generated if g['identity']['record_id']==rid)['payload']
                    check(all(g[k]==e[k] for k in ('proposition','polarity','scope','validity')) and g['establishedBy']=={'event':{'universe':report['installation']['universe_id'],'record':event_id},'slot':e['slot']},'generated assertion differs from approved effect')
                for day,response in row['states'].items(): state(response,owner,int(day))
            else:
                check(row['rejection']['code']=='INVALID_ARGUMENT' and row['rejection']['field']=='event.action.effects','wrong rejection')
                on_wire('universe_validate',row['rejection'],p,error=True); on_wire('universe_commit',row['commit_rejection'],p,error=True)
                check(not db.execute('SELECT 1 FROM commit_changes WHERE record_id=?',(event_id,)).fetchone(),'rejected event committed')
                check(not any(k.startswith('approval:') and p['digest'] in k for k in workflow),'rejected event approved')
            results[row['id']]={'allowed':bool(allowed),'head_control':'passed'}
        for field in ('frozen_control','changed_control'):
            c=report[field]; head_control(c['before'],c['after'],False)
            on_wire('universe_propose' if field=='frozen_control' else 'universe_commit',c['rejection'],error=True)
        c=report['changed_control']; check(c['original']['digest']!=c['proposal']['digest'] and c['original']['proposal_id']==c['proposal']['proposal_id'],'changed proposal binding unchanged')
        on_wire('universe_validate',c['validation_rejection'],c['proposal'],error=True)
        g=next(c for c in report['cases'] if c['id']=='declared_grant'); state(report['restart_state'],f"rec_{200000+g['offset']+1:024x}",15)
        check(report['restart_receipt']==report['publications'][-1]['receipt'],'restart receipt differs')
        final=report['cases'][-1]['head_after']; check(report['head_after_restart']==final and db.execute('SELECT head_commit FROM continuities').fetchone()[0]==final,'final head differs')
        check(db.execute('SELECT count(*) FROM operation_receipts').fetchone()[0]==len(report['publications'])+1,'unexpected receipt count')
    result={'status':'passed','cases':results,'rejected':sum(not r['allowed'] for r in results.values()),'committed':sum(r['allowed'] for r in results.values()),'mcp_calls':len(calls),'exact_frozen_assertions_queries_approvals_and_unchanged_heads':'passed','limit':'Independent program audit; no prose/native or resource arithmetic qualification.'}
    (directory/'audit.json').write_text(json.dumps(result,indent=2)+'\n'); return result
if __name__=='__main__': print(json.dumps(audit(Path(sys.argv[1]).resolve()),indent=2))
