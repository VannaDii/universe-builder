#!/usr/bin/env python3
"""Independent transcript/state oracle; imports no producer or Rust serializer."""
import gzip
import hashlib
import json
from pathlib import Path
import sys


def canonical(value):
    if value is None:
        return b'null'
    if value is True:
        return b'true'
    if value is False:
        return b'false'
    if isinstance(value, int):
        return str(value).encode()
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False).encode()
    if isinstance(value, list):
        return b'[' + b','.join(map(canonical, value)) + b']'
    if isinstance(value, dict):
        return b'{' + b','.join(canonical(k) + b':' + canonical(value[k]) for k in sorted(value)) + b'}'
    raise AssertionError('unsupported canonical type')


def entries(snapshot):
    result = {}
    for row in snapshot['workflow']:
        raw = row['payload_utf8'].encode()
        assert hashlib.sha256(raw).hexdigest() == row['digest'], row['key']
        value = json.loads(raw)
        assert canonical(value) == raw, row['key']
        result[row['key']] = value
    assert len(result) == len(snapshot['workflow'])
    return result


def run(path):
    report = json.loads(gzip.decompress(path.read_bytes()) if path.suffix=='.gz' else path.read_bytes())
    names = {t['name'] for t in report['tools']}
    expected = {'universe_search', 'universe_describe', 'universe_open_context', 'universe_get',
                'universe_get_state', 'universe_get_context', 'universe_validate', 'universe_propose',
                'universe_get_proposal', 'universe_get_impact', 'universe_commit', 'universe_get_operation',
                'universe_cancel_operation'}
    assert names == expected, names
    cases = {c['label']: c for c in report['cases']}
    assert len(cases) == len(report['cases'])
    positive = {'attachment', 'replacement', 'reselection', 'withdrawal'}
    retries = {'attachment-retry': 'attachment', 'attachment-retry-after-replacement': 'attachment',
               'selection-retry-after-withdrawal': 'reselection', 'withdrawal-retry': 'withdrawal',
               'attachment-retry-after-restart': 'attachment', 'withdrawal-retry-after-restart': 'withdrawal'}
    negative = {'impersonation', 'stale-attachment', 'stale-selection', 'mismatched-body-retry',
                'mismatched-generation-retry', 'mismatched-reference-retry', 'no-change',
                'missing-nullable-selection', 'unknown-body-field', 'wrong-proposal-owner',
                'permission-denied-retry', 'permission-denied-attachment', 'permission-denied-selection'}
    assert (positive | set(retries) | negative) <= cases.keys()
    results = {}
    preserved_rows = 0
    for label, case in cases.items():
        before = report['snapshots'][case['before']]
        after = report['snapshots'][case['after']]
        old, new = entries(before), entries(after)
        raw = case['response']
        content = raw['structuredContent']
        assert json.loads(''.join(c['text'] for c in raw['content'] if c['type'] == 'text')) == content
        assert before['canonical_tables'] == after['canonical_tables'], label
        assert all(k in new and canonical(v) == canonical(new[k]) for k, v in old.items()), label
        preserved_rows += len(old)
        assert {k: v for k, v in old.items() if k.startswith('proposal:')} == {
            k: v for k, v in new.items() if k.startswith('proposal:')}, label
        assert case['arguments']['action'] in {'attach_assessment', 'select_assessment'}
        if raw.get('isError'):
            assert before == after, label
            assert not any(k in content for k in ['selected', 'generation', 'assessment_id', 'digest', 'body']), label
            if label in {'impersonation', 'wrong-proposal-owner', 'permission-denied-retry',
                         'permission-denied-attachment', 'permission-denied-selection', 'source-scope-denied'}:
                assert content == {'code': 'NOT_FOUND_OR_NOT_ACCESSIBLE', 'message': 'resource'}
            if label.startswith('mismatched-'):
                assert content['code'] == 'IDEMPOTENCY_KEY_REUSED'
            if label.startswith('stale-'):
                assert content['code'] == 'APPROVAL_STALE'
            continue
        result = content['result']
        results[label] = result
        if label in retries:
            assert before == after, label
            assert result == results[retries[label]], label
            continue
        assert label in positive or label.startswith('source-scope-'), label
        if label in positive:
            assert result['generation'] == ['attachment', 'replacement', 'reselection', 'withdrawal'].index(label) + 1
        reference = result['proposal']
        assert reference == case['arguments']['proposal_reference']
        generation = case['arguments']['expected_selection_generation'] + 1
        assert result['generation'] == generation
        key = f"assessment-selection:{reference['proposal_id']}:{reference['version']:020d}:{generation:020d}"
        assert new[key] == result
        added = set(new) - set(old)
        assert sum(k.startswith('assessment-receipt:') for k in added) == 1
        assert sum(k.startswith('assessment-selection:') for k in added) == 1
        receipt = next(new[k] for k in added if k.startswith('assessment-receipt:'))
        args = case['arguments']
        fingerprint = [reference, args['expected_selection_generation'], args.get('body'), args.get('assessment_reference')]
        assert receipt['request_digest'] == hashlib.sha256(canonical(fingerprint)).hexdigest()
        assert receipt['selection'] == result
        if case['arguments']['action'] == 'attach_assessment':
            assert len(added) == 3
            selected = result['selected']
            envelope = new['assessment:' + selected['assessment_id']]
            body = case['arguments']['body']
            assert envelope['body'] == body
            assert receipt['envelope'] == envelope
            assert body['assessor']['principal'] == case['authenticated_profile'].replace('prf_', 'prn_', 1)
            assert hashlib.sha256(b'source-assessment:v1:' + canonical(body)).hexdigest() == envelope['digest'] == selected['digest']
            proposal = new[f"proposal:{reference['proposal_id']}:{reference['version']:020d}"]
            assert body['base_frame'] == proposal['proposal']['base_frame']
            assert body['proposal']['digest'] == proposal['proposal']['digest']
            for source in body['sources']:
                source_version = source['source_version']
                source_record = next(c['next'] for c in proposal['changes'] if c['next'] and c['next']['record_version_id'] == source_version['version'])
                assert source_record['identity']['universe_id'] == source_version['universe']
                assert source_record['identity']['record_id'] == source_version['record']
                assert source_record['payload']['record_kind'] == 'source_version'
                assert source_record['payload']['digest'] == source['blob_digest']
                assert source_record['payload']['byteSize'] == source['byte_size']
                data = new['source:' + source['blob_digest']].encode()
                assert hashlib.sha256(data).hexdigest() == source['blob_digest']
                assert len(data) == source['byte_size']
                for span in source['ranges']:
                    assert 0 <= span['start'] < span['end'] <= len(data)
                    data[:span['start']].decode(); data[:span['end']].decode()
        else:
            assert len(added) == 2
            assert result['selected'] == case['arguments']['assessment_reference']
            if result['selected']:
                assert receipt['envelope'] == new['assessment:' + result['selected']['assessment_id']]
            else:
                assert receipt['envelope'] is None
    for label in negative:
        assert cases[label]['response'].get('isError') is True, label
    assert results['attachment']['selected'] != results['replacement']['selected']
    assert results['reselection']['selected'] == results['attachment']['selected']
    assert results['withdrawal']['selected'] is None
    source_denials = [c for label, c in cases.items() if label.startswith('source-scope-') and c['response'].get('isError')]
    assert source_denials, 'missing independent source/dependency visibility denial'
    return {'verdict': 'pass', 'cases': len(cases), 'independently_checked_preserved_rows': preserved_rows,
            'transcript_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'oracle': 'A01-A11; source/code/test inspection required for A12'}


if __name__ == '__main__':
    print(json.dumps(run(Path(sys.argv[1] if len(sys.argv) > 1 else 'docs/evidence/assessment-mcp/transcript.json')), indent=2))
