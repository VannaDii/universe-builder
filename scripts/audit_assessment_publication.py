"""Independent publication oracle, frozen before producing its MCP evidence.

Uses only the Python standard library. No producer, service, serializer or hash
helper imports. Reads raw workflow bytes and all observed canonical tables.
"""
import argparse
import hashlib
import json
from pathlib import Path


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()


def digest(value, prefix=b''):
    return hashlib.sha256(prefix + canonical(value)).hexdigest()


def rows(snapshot):
    found = {}
    for entry in snapshot['workflow']:
        value = json.loads(entry['payload_utf8'])
        assert canonical(value) == entry['payload_utf8'].encode(), entry['key']
        assert digest(value) == entry['digest'], entry['key']
        found[entry['key']] = value
        if entry['key'].startswith('assessment:'):
            assert value['digest'] == digest(value['body'], b'source-assessment:v1:')
    return found


def binding(checked, proposal, selection):
    report = checked['report']
    ref = {k: proposal[k] for k in ('proposal_id', 'version', 'digest')}
    assert checked['admissible'] and checked['proposal_digest'] == ref['digest']
    assert checked['validation'] == report['execution']
    assert report['submitted_input']['proposal'] == ref == selection['proposal']
    assert report['execution']['input_digest'] == ref['digest']
    state = report['assessment']
    if state['kind'] == 'bound':
        assert state['assessment_reference'] == selection['selected']
        assert state['selection_generation'] == selection['generation']
        assert state['byte_verification'] == 'verified'
    elif state['kind'] == 'absent':
        assert selection['selected'] is None
    value = {'kind':'source_validation_binding_v1','proposal':ref,
             'base_frame':proposal['base_frame'],'selection':selection,
             'submitted_input':report['submitted_input'],'assessment_state':state,
             'execution_result_digest':digest(report['execution']),
             'evaluator_version':report['execution']['evaluator_version']}
    assert report['final_binding_digest'] == digest(value, b'source-validation:v1:')
    return report['final_binding_digest']


def audit(evidence):
    assert evidence['kind'] == 'assessment-publication-mcp-v1'
    assert len(evidence['tools']) == 13
    results = []
    required = {'unapproved','stale-approval','stale-selection','withdrawal',
                'reselected-old-identity','assessed-commit','commit-retry',
                'receipt-after-restart','commit-retry-after-restart',
                'fresh-withdrawn-raw-commit','revoked-edit','revoked-profile'}
    for case in evidence['cases']:
        before, after = case['before'], case['after']
        old, new = rows(before), rows(after)
        # All historical raw bytes stay identical; failed calls append nothing.
        old_raw = {r['key']:r for r in before['workflow']}
        new_raw = {r['key']:r for r in after['workflow']}
        assert all(new_raw.get(k) == v for k,v in old_raw.items())
        if case['channel'] == 'mcp':
            raw = case['response']
            if 'structuredContent' in raw:
                assert json.loads(''.join(c['text'] for c in raw['content'] if c['type']=='text')) == raw['structuredContent']
            else:
                assert case['error'] and raw['content']
            assert bool(raw.get('isError', False)) == case['error']
        else:
            assert (case['response']['returncode'] != 0) == case['error']
        if case['error'] or case['kind'] in ('retry','read'):
            assert before == after, case['label']
        if case['kind'] in ('commit','approval','retry') and not case['error']:
            args = case['arguments']
            run = args['validation_run']
            checked = old['validation:' + run]
            proposal = old['proposal:' + args['proposal_reference']['proposal_id'] + ':' + f"{args['proposal_reference']['version']:020d}"]['proposal']
            if case['kind'] != 'retry':
                prefix = 'assessment-selection:' + proposal['proposal_id'] + ':' + f"{proposal['version']:020d}:"
                selections = sorted(k for k in old if k.startswith(prefix))
                selection = old[selections[-1]] if selections else {'proposal':args['proposal_reference'],'generation':0,'selected':None}
                final = binding(checked, proposal, selection)
                if selection['selected'] is not None:
                    envelope = old['assessment:' + selection['selected']['assessment_id']]
                    assert envelope['digest'] == selection['selected']['digest']
                    assert envelope['body']['proposal'] == args['proposal_reference']
                    for source in envelope['body']['sources']:
                        text = old['source:' + source['blob_digest']].encode()
                        assert hashlib.sha256(text).hexdigest() == source['blob_digest']
                        assert len(text) == source['byte_size']
                        for span in source['ranges']:
                            text[:span['start']].decode()
                            text[span['start']:span['end']].decode()
                if case['kind'] == 'approval':
                    key = 'approval:' + evidence['author'] + ':' + proposal['digest'] + ':' + run
                    assert new[key] == {'author':evidence['author'],'proposal':args['proposal_reference'],
                                        'validation_digest':digest(checked),'evaluator':checked['validation']['evaluator_version']}
                    assert before['canonical_tables'] == after['canonical_tables']
                else:
                    approval = old['approval:' + evidence['author'] + ':' + proposal['digest'] + ':' + run]
                    assert approval['validation_digest'] == digest(checked)
                    receipt = case['response']['structuredContent']['result']
                    assert receipt['proposal_id'] == proposal['proposal_id']
                    heads = after['canonical_tables']['continuities']
                    assert any(receipt['revision'] in row for row in heads)
                    commits = after['canonical_tables']['commits']
                    assert len(commits) == len(before['canonical_tables']['commits']) + 1
                    receipts = after['canonical_tables']['operation_receipts']
                    assert len(receipts) == len(before['canonical_tables']['operation_receipts']) + 1
                    assert any(row[3] == args['idempotency_key'] and row[5] == receipt['revision'] for row in receipts)
                results.append({'label':case['label'],'binding':final,'generation':selection['generation']})
        required.discard(case['label'])
    assert not required, required
    # Recovery compares raw durable rows; projection generation may rebuild.
    assert evidence['receipt_before_restart'] == evidence['receipt_after_restart']
    assert evidence['workflow_before_restart'] == evidence['workflow_after_restart']
    assert evidence['historical_assessments_before'] == evidence['historical_assessments_after']
    assert evidence['historical_validation_before'] == evidence['historical_validation_after']
    return {'status':'pass','oracle':'standard-library independent raw-state and binding calculator',
            'cases':len(evidence['cases']),'bindings':results,'restart_exact':True,'historical_bytes_exact':True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(json.loads(args.evidence.read_text()))
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
