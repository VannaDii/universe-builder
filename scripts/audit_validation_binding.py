"""Independent final-binding calculator; imports no Rust/service digest helper."""
import argparse
import hashlib
import json
from pathlib import Path


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def digest(value, domain=b''):
    return hashlib.sha256(domain + canonical(value)).hexdigest()


def verify(case):
    result, proposal, selection = (case[k] for k in ('validation', 'proposal', 'selection'))
    assert result['kind'] == 'evaluated'
    reference = {k: proposal[k] for k in ('proposal_id', 'version', 'digest')}
    assert selection['proposal'] == reference
    assert result['execution']['input_digest'] == reference['digest']
    assert result['submitted_input']['proposal'] == reference
    state = result['assessment']
    if state['kind'] == 'bound':
        envelope = case['envelope']
        assert envelope['digest'] == digest(envelope['body'], b'source-assessment:v1:')
        assert selection['selected'] == {k: envelope[k] for k in ('assessment_id', 'digest')}
        assert state['assessment_reference'] == selection['selected']
        assert state['selection_generation'] == selection['generation']
        body = envelope['body']
        # The inventory hash owns ordered items; the body hash owns accounting.
        assert state['inventory_digest'] == digest(body['declared_inventory'])
        assert state['inventory_count'] == len(body['declared_inventory'])
        assert state['mapping_count'] == len(body['claim_mappings'])
        assert state['unresolved_count'] == len(body['unresolved'])
        assert state['declared_conclusion'] == body['conclusion']
        assert result['submitted_input']['sources'] == body['sources']
        assert result['submitted_input']['inventory_digest'] == state['inventory_digest']
        assert state['byte_verification'] == 'verified'
        for source in body['sources']:
            raw = case['source_bytes_utf8'][source['key']].encode('utf-8')
            assert hashlib.sha256(raw).hexdigest() == source['blob_digest']
            assert len(raw) == source['byte_size']
            for span in source['ranges']:
                assert 0 <= span['start'] < span['end'] <= len(raw)
                raw[:span['start']].decode('utf-8')
                raw[span['start']:span['end']].decode('utf-8')
        if body['unresolved']:
            assert state['declared_conclusion'] != 'consistent_with_declared_inventory'
    else:
        assert result['submitted_input']['kind'] == 'record_candidate'
        if state['kind'] == 'absent':
            assert selection['selected'] is None
    binding = {'kind': 'source_validation_binding_v1', 'proposal': reference,
               'base_frame': proposal['base_frame'], 'selection': selection,
               'submitted_input': result['submitted_input'], 'assessment_state': state,
               'execution_result_digest': digest(result['execution']),
               'evaluator_version': result['execution']['evaluator_version']}
    calculated = digest(binding, b'source-validation:v1:')
    assert result['final_binding_digest'] == calculated
    return {'label': case['label'], 'execution_digest': binding['execution_result_digest'],
            'final_binding_digest': calculated, 'assessment': state['kind'],
            'selection_generation': selection['generation'], 'binding': binding}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text())
    result = {'independent_calculator': 'python-json-sha256', 'proofs': [verify(c) for c in evidence['bindings']]}
    if args.output:
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(result, ensure_ascii=False))

if __name__ == '__main__':
    main()
