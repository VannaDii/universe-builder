"""Independent Goal 39 oracle and retained wire/storage audit.

Never imports the pilot or evaluator. Python integers independently calculate
signed delays, with explicit authored i128 limits and no clock conversions.
"""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from audit_g02 import check, digest, wire_calls
from relational_history import versions as relational_versions, workflows

I128_MIN = -(1 << 127)
I128_MAX = (1 << 127) - 1
CAPABILITY = 'communications.chronology.v1'


def signed(value):
    if not isinstance(value, str) or not value or value.strip() != value:
        raise ValueError('not an authored integer string')
    # Rust integer parsing accepts an optional sign, but no decimal/scientific form.
    digits = value[1:] if value[0] in '+-' else value
    if not digits or any(c not in '0123456789' for c in digits):
        raise ValueError('not exact integer ticks')
    n = int(value)
    if not I128_MIN <= n <= I128_MAX:
        raise ValueError('outside i128')
    return n


def classify(communication, contracts):
    """Return independent supported/violated/unknown result and signed delay."""
    rules = [r for r in contracts if r['channel'] == communication.get('channel')]
    if not rules:
        return {'outcome': 'unknown', 'reason': 'missing-rule', 'delay': None}
    if communication.get('receivedAt') is None:
        return {'outcome': 'unknown', 'reason': 'unreceived', 'delay': None}
    if not communication.get('actualRecipients'):
        return {'outcome': 'unknown', 'reason': 'no-actual-recipients', 'delay': None}
    sent, received = communication['sentAt'], communication['receivedAt']
    if sent['kind'] != 'exact' or received['kind'] != 'exact':
        return {'outcome': 'unknown', 'reason': 'nonexact-clock', 'delay': None}
    if sent['calendar'] != received['calendar']:
        return {'outcome': 'unknown', 'reason': 'unmapped-clocks', 'delay': None}
    try:
        delay = signed(received['value']) - signed(sent['value'])
    except ValueError:
        return {'outcome': 'unknown', 'reason': 'invalid-coordinate', 'delay': None}
    if not I128_MIN <= delay <= I128_MAX:
        return {'outcome': 'unknown', 'reason': 'delay-overflow', 'delay': None}
    violations = []
    for rule in rules:
        if rule['forwardOnly'] and delay < 0:
            violations.append('forward-order')
        if rule.get('minimumDelay') is not None and delay < signed(rule['minimumDelay']):
            violations.append('minimum-delay')
        if rule.get('maximumDelay') is not None and delay > signed(rule['maximumDelay']):
            violations.append('maximum-delay')
    return {'outcome': 'violated' if violations else 'supported',
            'reason': sorted(set(violations)), 'delay': str(delay)}


def candidate_findings(records):
    rules = [(rid, r) for rid, r in records.items()
             if r['payload']['record_kind'] == 'rule' and r['payload'].get('channelChronology')]
    if not rules:
        return []
    expected = []
    for rid, communication in records.items():
        if communication['payload']['record_kind'] != 'communication':
            continue
        matching = [(rule_id, rule) for rule_id, rule in rules
                    if rule['payload']['channelChronology']['channel'] == communication['payload'].get('channel')]
        if not matching:
            expected.append({'rule_id': rid, 'outcome': 'not_established', 'coverage': 'unsupported',
                             'evidence': [communication['record_version_id']]})
        for rule_id, rule in matching:
            result = classify(communication['payload'], [rule['payload']['channelChronology']])
            expected.append({'rule_id': rule_id,
                             'outcome': {'unknown': 'not_established', 'violated': 'refuted', 'supported': 'supported'}[result['outcome']],
                             'coverage': 'unsupported' if result['outcome'] == 'unknown' else 'complete',
                             'evidence': sorted([communication['record_version_id'], rule['record_version_id']])})
    return expected


def normalized_findings(findings):
    return sorted([{k: sorted(f[k]) if k == 'evidence' else f[k]
                    for k in ('rule_id', 'outcome', 'coverage', 'evidence')} for f in findings],
                  key=lambda f: json.dumps(f, sort_keys=True))


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
            expected = candidate_findings(records)
            for finding in validation['findings']:
                want = digest([proposal['proposal']['base_frame'], proposal['proposal']['digest'],
                               validation['evaluator_version'], finding['rule_id'], finding['outcome'], finding['evidence']])
                check(finding['fingerprint'] == want, 'finding fingerprint differs')
            check(validation['input_digest'] == proposal['proposal']['digest'], 'validation input digest differs')
            check(normalized_findings(validation['findings']) == normalized_findings(expected), 'independent chronology finding differs')
            admissible = all(f['outcome'] == 'supported' and f['coverage'] == 'complete' for f in expected)
            check(item['admissible'] == admissible, 'independent admission differs')
            check(validation['coverage'] == ('partial' if any(f['coverage'] == 'unsupported' for f in expected) else 'complete'), 'validation coverage differs')
            # Every retained run must originate from an actual MCP validation response
            # or a durable refused validation identifier captured on the wire.
            check(any(c['tool'] == 'universe_validate' and (c['result'].get('result') == validation or validation['run_id'] in json.dumps(c['result'])) for c in calls), 'validation absent from wire')
            assessed += 1
        check(assessed > 0, 'no validations audited')
        expected_cases = {
            'legacy-opt-out':'legal', 'activation-rechecks-legacy':'rejected',
            'activate-and-correct':'legal', 'forward-min-boundary':'legal',
            'forward-max-boundary':'legal', 'reversed-forward':'rejected',
            'too-fast':'rejected', 'too-slow':'rejected', 'reverse-permitted':'legal',
            'reverse-too-far':'rejected', 'reverse-too-near':'rejected',
            'simultaneous':'legal', 'different-recipient':'legal',
            'sender-is-recipient':'legal', 'multiple-actual':'legal',
            'unreceived':'unresolved', 'intended-only':'unresolved',
            'missing-channel-rule':'unresolved', 'missing-channel-identity':'unresolved',
            'unmapped-clocks':'unresolved', 'unknown-send':'unresolved',
            'delay-overflow':'unresolved', 'conjunctive-rules':'rejected',
            'restart-reversal-rejected':'rejected',
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
        invalid_contracts = report['invalid_contracts']
        check(len(invalid_contracts) == 3 and {c['id'] for c in invalid_contracts} == {'inverted','negative-forward-maximum','not-integer'}, 'invalid contract inventory differs')
        for invalid in invalid_contracts:
            check(invalid['response']['code'] == 'INVALID_ARGUMENT' and invalid['response']['field'] == 'channelChronology', 'invalid contract rejected outside chronology')
            check(any(c['tool'] == 'universe_validate' and c['expected_error'] and c['result'] == invalid['response'] and c['arguments']['proposal_reference']['proposal_id'] == invalid['proposal']['proposal_id'] for c in calls), 'invalid contract rejection absent from wire')
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
        contexts = {}
        communication_reads = {False: {}, True: {}}
        historical_reads = 0
        reads = 0
        for call in calls:
            if call['expected_error']:
                continue
            if call['tool'] == 'universe_open_context':
                context = call['result']['result']
                contexts[context['context_id']] = context['frame']['revision']
            if call['tool'] != 'universe_get':
                continue
            args = call['arguments']
            check(args['context_id'] in contexts, 'read context absent from wire')
            revision = contexts[args['context_id']]
            records = snapshot(revision)
            expected = [records[rid] for rid in args['record_ids'] if rid in records]
            actual = call['result']['result']['records']
            check(sorted(actual,key=lambda r:r['record_version_id']) == sorted(expected,key=lambda r:r['record_version_id']), 'MCP read differs from historical SQL snapshot')
            for record in actual:
                if record['payload']['record_kind'] == 'communication':
                    key = (revision, record['identity']['record_id'])
                    communication_reads[call['lines'][0] > restart_line][key] = record
            historical_reads += revision != publications[-1]['receipt']['revision']
            reads += 1
        check(reads > 0 and historical_reads > 0, 'historical reads missing')
        head = publications[-1]['receipt']['revision']
        final = snapshot(head)
        surviving_historical = set(communication_reads[False]) & set(communication_reads[True])
        corrected_history = []
        for key in surviving_historical:
            before, after = communication_reads[False][key], communication_reads[True][key]
            check(before == after, 'historical communication changed across restart')
            rid = key[1]
            if key[0] != head and (rid not in final or final[rid] != before):
                corrected_history.append(key)
        check(corrected_history, 'corrected communication historical reads across restart absent')
        for key in ('historical_before_activation','historical_before_restart','historical_after_restart','current_after_restart'):
            reported = report[key]
            check(any(c['tool'] == 'universe_get' and not c['expected_error'] and c['result']['result']['records'] == reported for c in calls), 'reported historical/current read absent from wire')
        check(report['historical_before_activation'] == report['historical_before_restart'] == report['historical_after_restart'], 'reported history differs across restart')
        check(report['head_before_restart'] == report['head_after_restart'] == head, 'reported restart head differs')
        check(len(report['restart_instances']) == 1 and report['restart_instances'][0]['before'] != report['restart_instances'][0]['after'], 'engine restart identity did not change')
        opens_after_restart = [c for c in calls if c['tool'] == 'universe_open_context' and c['lines'][0] > restart_line and c['arguments']['revision']['kind'] == 'head']
        check(opens_after_restart and opens_after_restart[-1]['result']['result']['frame']['revision'] == head, 'restart head differs')
        check(db.execute('SELECT head_commit FROM continuities').fetchone()[0] == head, 'SQL final head differs')
    result = {'status':'passed','independently_assessed_validations':assessed,'mcp_calls':len(calls),
              'wire_and_normalized_storage':'passed','cases':len(expected_cases),'publications':len(publications),'historical_reads':historical_reads,'corrected_historical_reads_survive_restart':len(corrected_history)}
    (directory/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__ == '__main__':
    print(json.dumps(audit(Path(sys.argv[1]).resolve()),indent=2))
