"""Independent bounded Goal 40 truth/order oracle and typed history/wire audit.
No driver or Rust evaluator imports. Reuses Goal 39's independent chronology oracle.
The oracle covers exact, instance, universe-wide boolean propositions used by this proof;
other semantic shapes are intentionally refused by this auditor rather than guessed.
"""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from audit_g02 import check, digest, wire_calls
from relational_history import versions as relational_versions, workflows
from audit_communication_chronology import signed, classify, candidate_findings, normalized_findings


def knowledge_findings(records):
    policies=[r for r in records.values() if r['payload']['record_kind']=='rule' and r['payload'].get('knowledgePolicy')]
    result=[]
    def at(t):
        if t.get('kind')!='exact':return None
        try:return t['calendar'],signed(t['value'])
        except ValueError:return None
    def ordered(a,b):
        a,b=at(a),at(b)
        return None if not a or not b or a[0]!=b[0] else a[1]<=b[1]
    def row(ref):return records[ref['record']]
    for attitude in records.values():
        a=attitude['payload']
        if a['record_kind']!='epistemic_attitude' or a['attitude']!='knows':continue
        acq=a.get('acquisition')
        if not policies and not acq:continue
        prop=row(a['proposition']);p=prop['payload']
        matching=[r for r in policies if r['payload']['knowledgePolicy']['context']==p['context']]
        if not matching and not acq:continue
        if not matching:
            result.append({'rule_id':attitude['identity']['record_id'],'outcome':'not_established','coverage':'unsupported','evidence':[attitude['record_version_id']]})
        for rule in matching:
            evidence=[rule['record_version_id'],attitude['record_version_id']]
            def assess():
                if not acq:return None
                evidence.append(prop['record_version_id'])
                if acq['truthContext']!=p['context']:return False
                evidence.append(row(acq['truthContext'])['record_version_id'])
                validity=a['validity']
                start={'kind':'exact','calendar':validity['calendar'],'value':validity['start']['value']} if validity['kind']=='calendar_interval' and validity['start']['kind']=='exact' else validity.get('at',{})
                order=ordered(acq['time'],start)
                if order is not True:return order
                basis=acq['basis'];mode=rule['payload']['knowledgePolicy']['mode']
                if mode=='author_established':
                    return basis['kind']=='author_established' and a['basis']['kind']=='author_decision'
                if basis['kind']=='author_established':return False
                msg=row(basis['communication']);m=msg['payload'];evidence.append(msg['record_version_id'])
                if not m['actualRecipients']:return None
                if a['holder'] not in m['actualRecipients']:return False
                if basis['interpretation'] is None:return None
                if basis['interpretation']!=a['proposition'] or basis['interpretation'] not in m['content']:return False
                if m['distorted']:return None
                order=ordered(m['receivedAt'],acq['time'])
                if order is not True:return order
                rules=[r for r in records.values() if r['payload']['record_kind']=='rule' and r['payload'].get('channelChronology')]
                if not rules:return None
                matching=[r for r in rules if r['payload']['channelChronology']['channel']==m['channel']]
                for r in matching:evidence.extend([r['record_version_id'],msg['record_version_id']])
                chronology=classify(m,[r['payload']['channelChronology'] for r in rules])['outcome']
                if chronology!='supported':return False if chronology=='violated' else None
                definition=row(p['predicate']);evidence.append(definition['record_version_id'])
                check(p['quantification']=='particular' and not p.get('roles') and p['value']['kind']=='boolean' and not acq.get('world'),'oracle shape outside proof')
                bits=set();complete=True
                for fact in records.values():
                    f=fact['payload']
                    if f['record_kind']!='assertion':continue
                    q=row(f['proposition'])['payload']
                    if any(q.get(k)!=p.get(k) for k in ('subject','predicate','context','value','roles')):continue
                    check(f['scope']['applicability']['kind']=='universe_wide' and f['attributeMode']=='instance','oracle scope outside proof')
                    if f['scope']['context']!=acq['truthContext']:continue
                    v=f['validity'];t=at(acq['time']);check(t is not None,'invalid truth clock')
                    if v['kind']=='calendar_interval':
                        if v['calendar']!=t[0]:complete=False;continue
                        lo=v['start'];hi=v['end']
                        if lo['kind']!='exact' or hi['kind'] not in ('exact','unbounded'):complete=False;continue
                        if t[1]<signed(lo['value']) or hi['kind']=='exact' and t[1]>=signed(hi['value']):continue
                    else:check(False,'oracle truth validity outside proof')
                    if f['precision']!='exact' or f.get('alternatives') or f['scope'].get('realm'):complete=False;continue
                    bits.add(f['polarity']);evidence.append(fact['record_version_id'])
                if not complete:return None
                if 'refutation' in bits:return False
                return True if 'support' in bits else None
            answer=assess()
            result.append({'rule_id':rule['identity']['record_id'],'outcome':'not_established' if answer is None else 'supported' if answer else 'refuted','coverage':'unsupported' if answer is None else 'complete','evidence':sorted(set(evidence))})
    return result


def audit(directory):
    directory = Path(directory)
    report = json.loads((directory/'report.json').read_text())
    check(report['status'] == 'executed', 'runner incomplete')
    check(hashlib.sha256((directory/'package.sqlite').read_bytes()).hexdigest() == report['package_sha256'], 'package changed')
    calls = wire_calls(directory/'mcp-transcript.jsonl')
    check([{k:v for k,v in c.items() if k != 'lines'} for c in calls] == report['mcp'], 'report differs from wire')
    with closing(sqlite3.connect(f"file:{directory/'package.sqlite'}?mode=ro&immutable=1",uri=True)) as db:
        db.row_factory = sqlite3.Row
        check(db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok', 'database corrupt')
        check(not db.execute('PRAGMA foreign_key_check').fetchall(), 'foreign key failure')
        versions = relational_versions(db)
        workflow = {r['key']: json.loads(r['payload_utf8']) for r in workflows(db)}
        def snapshot(revision):
            path = []
            while revision:
                check(revision not in path, 'history cycle')
                path.append(revision)
                row = db.execute('SELECT parent_id FROM commits WHERE id=?',(revision,)).fetchone()
                check(row is not None, 'missing historical revision')
                revision = row[0]
            result = {}
            for revision in reversed(path):
                for row in db.execute('SELECT record_id,version_id FROM commit_changes WHERE revision_id=?',(revision,)):
                    if row['version_id']:
                        result[row['record_id']] = versions[row['version_id']]
                    else:
                        result.pop(row['record_id'],None)
            return result
        assessed = 0
        for key, item in workflow.items():
            if not key.startswith('validation:'):
                continue
            validation = item['validation']
            proposal = next((p for k,p in workflow.items() if k.startswith('proposal:') and p['proposal']['digest'] == item['proposal_digest']),None)
            check(proposal is not None, 'validation proposal missing')
            records = snapshot(proposal['proposal']['base_frame']['revision'])
            for change in proposal['changes']:
                if change['next'] is not None:
                    records[change['record_id']] = change['next']
                else:
                    records.pop(change['record_id'],None)
            expected = candidate_findings(records) + knowledge_findings(records)
            for finding in validation['findings']:
                want = digest([proposal['proposal']['base_frame'], proposal['proposal']['digest'],
                               validation['evaluator_version'], finding['rule_id'], finding['outcome'], finding['evidence']])
                check(finding['fingerprint'] == want, 'finding fingerprint differs')
            check(validation['input_digest'] == proposal['proposal']['digest'], 'validation input digest differs')
            check(normalized_findings(validation['findings']) == normalized_findings(expected), 'independent knowledge/chronology finding differs')
            admissible = all(f['outcome'] == 'supported' and f['coverage'] == 'complete' for f in expected)
            check(item['admissible'] == admissible, 'independent admission differs')
            check(validation['coverage'] == ('partial' if any(f['coverage'] == 'unsupported' for f in expected) else 'complete'), 'validation coverage differs')
            # Every retained run must originate from an actual MCP validation response
            # or a durable refused validation identifier captured on the wire.
            check(any(c['tool'] == 'universe_validate' and (c['result'].get('result') == validation or validation['run_id'] in json.dumps(c['result'])) for c in calls), 'validation absent from wire')
            assessed += 1
        check(assessed > 0, 'no validations audited')
        expected_cases = {
            'valid-interpreted-receipt':'legal','knowledge-before-receipt':'rejected',
            'validity-before-acquisition':'rejected','wrong-actual-recipient':'rejected',
            'receipt-without-interpretation':'unresolved','wrong-interpreted-content':'rejected',
            'distorted-content-unresolved':'unresolved','unknown-truth':'unresolved',
            'refuted-truth':'rejected','conflicting-truth':'rejected','false-belief-preserved':'legal',
            'author-basis-under-justified-policy':'rejected','unknown-acquisition-clock':'unresolved',
            'unmapped-acquisition-clock':'unresolved','unspecified-knowledge-onset':'unresolved',
            'missing-acquisition-under-policy':'unresolved','truth-correction-invalidates-dependent':'rejected',
            'later-truth-end-retains-historical-knowledge':'legal','truth-ended-before-acquisition':'unresolved',
            'truth-onset-correction-invalidates-dependent':'unresolved','atomic-truth-and-dependent-correction':'legal',
            'historical-adoption-rechecks-acquisition':'unresolved',
            'author-policy-and-established-knowledge':'legal','receipt-basis-under-author-policy':'rejected',
            'restart-policy-still-enforced':'rejected','restart-corrected-truth-still-unresolved':'unresolved',
        }
        check(len(report['cases']) == len(expected_cases) and {c['id'] for c in report['cases']} == set(expected_cases), 'case inventory differs')
        for case in report['cases']:
            proposal = case['proposal']
            stored = workflow[f"proposal:{proposal['proposal_id']}:{proposal['version']:020}"]
            check(stored['proposal'] == proposal and proposal['operations'] == case['operations'], 'case authored stimulus differs')
            checked = workflow[f"validation:{case['validation']['run_id']}"]
            check(checked['validation'] == case['validation'], 'case validation differs')
            classification = 'unresolved' if checked['validation']['coverage'] == 'partial' else ('legal' if checked['admissible'] else 'rejected')
            check(classification == expected_cases[case['id']] == case['expected'], 'case classification differs')
            check(case['admitted'] == (classification == 'legal'), 'case admission differs')
            if classification != 'legal':
                check(case['head_before'] == case['head_after'] and snapshot(case['head_before']) == snapshot(case['head_after']), 'rejected head changed')
                check(case['before'] == case['after'] and case['approval_returncode'] != 0, 'rejected authority changed')
                check(any(c['tool'] == 'universe_commit' and c['expected_error'] and c['result'] == case['commit_response'] and c['arguments']['proposal_reference']['proposal_id'] == proposal['proposal_id'] for c in calls), 'rejection absent from wire')
                check(not any(row['decision'] == proposal['digest'] for row in db.execute('SELECT decision FROM commits')), 'rejected proposal committed')
            else:
                check(case['head_before'] != case['head_after'] and case['receipt']['revision'] == case['head_after'], 'legal head disposition differs')
            for revision in (case['head_before'], case['head_after']):
                check(any(c['tool'] == 'universe_open_context' and not c['expected_error'] and c['result']['result']['frame']['revision'] == revision for c in calls), 'case head absent from wire')
        publications = report['publications']
        for publication in publications:
            proposal = publication['review']['proposal']
            stored = workflow[f"proposal:{proposal['proposal_id']}:{proposal['version']:020}"]
            check(stored['proposal'] == proposal, 'review proposal differs')
            check(stored['changes'] == publication['review']['changes'], 'review changes differ')
            receipt, args = publication['receipt'], publication['commit_arguments']
            checked = workflow[f"validation:{args['validation_run']}"]
            check(checked['admissible'] and checked['proposal_digest'] == proposal['digest'], 'publication validation binding differs')
            approvals = [a for k,a in workflow.items() if k.startswith('approval:') and k.endswith(f":{proposal['digest']}:{args['validation_run']}")]
            check(len(approvals) == 1, 'exact approval missing')
            approval = approvals[0]
            check(approval['proposal'] == args['proposal_reference'] and approval['validation_digest'] == digest(checked), 'approval binding differs')
            operation = workflow[f"operation:{receipt['operation_id']}"]
            check(operation['input']['changes'] == stored['changes'], 'commit differs from frozen review')
            sql_receipt = db.execute('SELECT * FROM operation_receipts WHERE idempotency_key=?',(args['idempotency_key'],)).fetchone()
            check(sql_receipt is not None and sql_receipt['revision_id'] == receipt['revision'] and sql_receipt['payload_digest'] == digest(operation['input']), 'SQL operation receipt differs')
            commit = db.execute('SELECT * FROM commits WHERE id=?',(receipt['revision'],)).fetchone()
            check(commit['parent_id'] == args['expected_base_revision'] and commit['decision'] == proposal['digest'], 'commit ancestry differs')
            changes = {r['record_id']:r for r in db.execute('SELECT * FROM commit_changes WHERE revision_id=?',(receipt['revision'],))}
            check(set(changes) == {c['record_id'] for c in stored['changes']}, 'commit footprint differs')
            for change in stored['changes']:
                row = changes[change['record_id']]
                check(row['prior_version'] == change['expected'], 'commit prior version differs')
                check((versions[row['version_id']] if row['version_id'] else None) == change['next'], 'committed next version differs')
            check(any(c['tool'] == 'universe_commit' and c['arguments'] == args and c['result'].get('result') == receipt and not c['expected_error'] for c in calls), 'publication absent from wire')
        raw_rows = [json.loads(line) for line in (directory/'mcp-transcript.jsonl').read_text().splitlines()]
        restart_line = [n for n,row in enumerate(raw_rows,1) if row['direction'] == 'sent' and row['frame'].get('method') == 'initialize'][1]
        contexts = {}; historical_reads=0
        for call in calls:
            if call['expected_error']:continue
            if call['tool']=='universe_open_context':
                context=call['result']['result'];contexts[context['context_id']]=context['frame']['revision']
            if call['tool']!='universe_get':continue
            args=call['arguments'];check(args['context_id'] in contexts,'missing read context')
            records=snapshot(contexts[args['context_id']]);expected=[records[rid] for rid in args['record_ids'] if rid in records]
            actual=call['result']['result']['records']
            check(sorted(actual,key=lambda r:r['record_version_id'])==sorted(expected,key=lambda r:r['record_version_id']),'historical MCP read differs')
            if contexts[args['context_id']]==report['original_revision']:historical_reads+=1
        for key in ('original_reads','historical_before_restart','historical_after_restart','current_before_restart','current_after_restart'):
            check(any(c['tool']=='universe_get' and not c['expected_error'] and c['result']['result']['records']==report[key] for c in calls),'reported read absent from wire')
        check(report['original_reads']==report['historical_before_restart']==report['historical_after_restart'],'old knowledge changed')
        check(report['current_before_restart']==report['current_after_restart'],'corrected state changed')
        head=publications[-1]['receipt']['revision']
        check(report['head_before_restart'] == report['head_after_restart'] == head, 'reported restart head differs')
        check(len(report['restart_instances']) == 1 and report['restart_instances'][0]['before'] != report['restart_instances'][0]['after'], 'engine restart identity did not change')
        opens_after_restart = [c for c in calls if c['tool'] == 'universe_open_context' and c['lines'][0] > restart_line and c['arguments']['revision']['kind'] == 'head']
        check(opens_after_restart and opens_after_restart[-1]['result']['result']['frame']['revision'] == head, 'restart head differs')
        check(db.execute('SELECT head_commit FROM continuities').fetchone()[0] == head, 'SQL final head differs')
    result = {'status':'passed','independently_assessed_validations':assessed,'mcp_calls':len(calls),
              'wire_and_normalized_storage':'passed','cases':len(expected_cases),'publications':len(publications),'historical_reads':historical_reads,'corrected_historical_reads_survive_restart':3}
    (directory/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__ == '__main__':
    print(json.dumps(audit(Path(sys.argv[1]).resolve()),indent=2))
