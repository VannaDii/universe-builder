"""Independent reconstruction oracle. No producer/service/serializer imports.

Frozen requirements: complete pages equal raw immutable stored envelopes; body
and inventory hashes agree with both independent JSON encoders and OpenSSL;
history is exact; selection/authority changes invalidate cursors; private reads
return generic errors without identifiers, counts, excerpts, hashes or cursors.
"""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def canonical(v):
    if v is None:
        return b'null'
    if v is True:
        return b'true'
    if v is False:
        return b'false'
    if isinstance(v, int):
        return str(v).encode()
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False).encode()
    if isinstance(v, list):
        return b'[' + b','.join(canonical(x) for x in v) + b']'
    if isinstance(v, dict):
        return b'{' + b','.join(canonical(k) + b':' + canonical(v[k]) for k in sorted(v)) + b'}'
    raise AssertionError('unsupported canonical value')


def digest(v, prefix=b''):
    raw = canonical(v)
    assert raw == json.dumps(v, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()
    expected = hashlib.sha256(prefix + raw).hexdigest()
    openssl = subprocess.run(['/usr/bin/openssl', 'dgst', '-sha256'], input=prefix + raw, capture_output=True, check=True)
    assert openssl.stdout.decode().strip().split()[-1] == expected
    return expected


def entries(snap):
    result = {}
    for row in snap['workflow']:
        raw = row['payload_utf8'].encode()
        assert hashlib.sha256(raw).hexdigest() == row['digest']
        value = json.loads(raw)
        assert canonical(value) == raw
        result[row['key']] = value
    return result


def run(path):
    data = gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes()
    report = json.loads(data)
    assert len(report['tools']) == 13
    cases = {c['label']: c for c in report['cases']}
    assert len(cases) == len(report['cases'])
    denials = {'bad-cursor', 'wrong-digest', 'unknown-assessment', 'cross-proposal-attachment',
        'cursor-proposal-substitution', 'obsolete-after-replacement', 'obsolete-history-after-withdrawal',
        'cursor-authority-change', 'obsolete-after-reselection', 'wrong-owner', 'wrong-owner-history',
        'wrong-owner-cursor', 'unknown-proposal', 'source-restricted', 'source-restricted-history',
        'source-restricted-cursor', 'revoked-selected', 'revoked-history', 'revoked-cursor'}
    assert denials <= cases.keys()
    page_groups = {}
    stored_envelopes = {}
    for c in report['cases']:
        label = c['label']
        raw = c['response']
        content = raw.get('structuredContent')
        text = ''.join(x['text'] for x in raw['content'] if x['type'] == 'text')
        if content is not None:
            assert json.loads(text) == content
        else:
            assert c['label'].startswith('revoked-') and raw.get('isError') is True
            assert text == 'disconnected; recover mutations using their original idempotency key', raw
        before, after = report['snapshots'][c['before']], report['snapshots'][c['after']]
        assert before['canonical_tables'] == after['canonical_tables'], label
        old, new = entries(before), entries(after)
        assert all(k in new and v == new[k] for k, v in old.items()), label
        stored_envelopes.update({k: v for k, v in old.items() if k.startswith('assessment:')})
        if raw.get('isError'):
            assert before == after, label
            if label.startswith('revoked-'):
                assert content is None and set(raw) == {'content', 'isError'}
            elif label in denials:
                assert content == {'code': 'NOT_FOUND_OR_NOT_ACCESSIBLE', 'message': 'resource'}, (label, content)
            else:
                assert label == 'reference-outside-view' and content['code'] == 'INVALID_ARGUMENT'
            continue
        assert label not in denials
        result = content['result']
        assert set(result) == {'selection', 'state', 'envelope', 'fragment'}
        proposal = result['selection']['proposal']
        args = c['arguments']
        assert proposal['proposal_id'] == args['proposal_id'] and proposal['version'] == args['version']
        stored = old[f"proposal:{proposal['proposal_id']}:{proposal['version']:020d}"]
        assert stored['proposal']['digest'] == proposal['digest']
        selections = [v for k, v in old.items() if k.startswith(f"assessment-selection:{proposal['proposal_id']}:{proposal['version']:020d}:")]
        current = max(selections, key=lambda v: v['generation']) if selections else {'proposal': proposal, 'generation': 0, 'selected': None}
        assert result['selection'] == current
        reference = args.get('assessment_reference') or current['selected']
        if reference is None:
            assert result['envelope'] is result['fragment'] is None
            assert result['state'] == {'kind': 'absent'}
            assert content['delivery'] == {'complete': True, 'cursor': None}
            continue
        envelope = old['assessment:' + reference['assessment_id']]
        assert envelope['digest'] == reference['digest']
        assert envelope['body']['proposal'] == proposal
        assert digest(envelope['body'], b'source-assessment:v1:') == envelope['digest']
        if result['state']['kind'] == 'bound':
            selected = old['assessment:' + current['selected']['assessment_id']]
            state = result['state']
            assert state['assessment_reference'] == current['selected']
            assert state['selection_generation'] == current['generation']
            assert state['inventory_count'] == len(selected['body']['declared_inventory'])
            assert state['mapping_count'] == len(selected['body']['claim_mappings'])
            assert state['unresolved_count'] == len(selected['body']['unresolved'])
            assert state['inventory_digest'] == digest(selected['body']['declared_inventory'])
        if result['envelope'] is not None:
            assert result['fragment'] is None and result['envelope'] == envelope
            assert content['delivery'] == {'complete': True, 'cursor': None}
            continue
        fragment = result['fragment']
        assert fragment['assessment_reference'] == reference
        assert fragment['total_bytes'] == len(canonical(envelope))
        group, index = label.rsplit('-', 1)
        assert index.isdigit()
        page_groups.setdefault(group, []).append((int(index), fragment, content['delivery'], args, current, result['state']))
        added = set(new) - set(old)
        if content['delivery']['complete']:
            assert not added
        else:
            cursor = content['delivery']['cursor']
            assert added == {'cursor:' + cursor}
            assert new['cursor:' + cursor]['offset'] == fragment['offset'] + len(fragment['canonical_envelope_utf8'].encode())
    reconstructions = {}
    for label, pages in page_groups.items():
        pages.sort()
        reconstructed = b''
        last_cursor = None
        for i, fragment, delivery, args, selection, state in pages:
            assert fragment['offset'] == len(reconstructed)
            if last_cursor:
                assert args['cursor'] == last_cursor
            assert selection == pages[0][4] and state == pages[0][5]
            reconstructed += fragment['canonical_envelope_utf8'].encode()
            assert len(reconstructed) <= fragment['total_bytes']
            last_cursor = delivery['cursor']
        assert [p[0] for p in pages] == list(range(len(pages)))
        assert pages[-1][2] == {'complete': True, 'cursor': None}
        assert len(reconstructed) == pages[-1][1]['total_bytes']
        envelope = json.loads(reconstructed)
        assert canonical(envelope) == reconstructed
        stored = stored_envelopes['assessment:' + envelope['assessment_id']]
        assert reconstructed == canonical(stored)
        assert digest(envelope['body'], b'source-assessment:v1:') == envelope['digest']
        reconstructions[label] = {'pages': len(pages), 'bytes': len(reconstructed), 'digest': envelope['digest']}
    expected_groups = {'selected', 'historical-after-replacement', 'historical-after-withdrawal', 'read-only-history',
                       'historical-after-restart', 'reselected', 'historical-stale-proposal'}
    assert set(reconstructions) == expected_groups
    assert all(r['pages'] > 1 for r in reconstructions.values())
    original = reconstructions['selected']['digest']
    assert all(r['digest'] == original for r in reconstructions.values())
    for review in report['reviews']:
        envelope = review['response']['assessment_review']['envelope']
        assert envelope == stored_envelopes['assessment:' + envelope['assessment_id']]
        assert envelope['digest'] == original
        assert envelope['body']['declared_inventory'] and envelope['body']['claim_mappings']
        assert envelope['body']['inventory_declaration']['exclusions'] and envelope['body']['unresolved']
    assert cases['historical-stale-proposal-0']['response']['structuredContent']['result']['state']['kind'] == 'stale'
    return {'verdict': 'pass', 'mcp_cases': len(cases), 'generic_denials': len(denials), 'author_reviews': len(report['reviews']),
            'reconstructions': reconstructions, 'transcript_sha256': hashlib.sha256(data).hexdigest(),
            'digest_checks': 'handwritten canonical encoder + Python sorted JSON + OpenSSL SHA-256'}


if __name__ == '__main__':
    print(json.dumps(run(Path(sys.argv[1])), indent=2))
