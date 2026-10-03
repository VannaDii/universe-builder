"""Real stdio MCP review, pagination, history and permission qualification.

Disposable owned installation; raw SQLite reads are observations, not fixtures
injected into production state. No assessed validation/approval is claimed.
"""
import argparse
import copy
import gzip
import json
from pathlib import Path
import tempfile

from assessment_mcp_pilot import assessment, snapshot
from pilot_support import NAME, PilotSession


def run(bin_dir, output):
    report = {'kind': 'assessment-review-transcript-v1', 'cases': [], 'snapshots': {}, 'mcp': [], 'reviews': []}
    with tempfile.TemporaryDirectory(prefix='arv-', dir='/tmp') as directory:
        s = PilotSession(directory, bin_dir, report)
        try:
            s.start()
            report['tools'] = s.client.request('tools/list', {})['tools']
            report['owner'] = s.agent
            text = 'Exact café 日本語 🌙 bytes.\n'
            path = Path(directory) / 'source.txt'
            path.write_text(text)
            source_ops = s.admin('stage-source', NAME, 'Review source', path)['operations']
            entity = {'kind': 'create_entity', 'client_ref': s.rid(1), 'record': {
                'names': [], 'types': [], 'worldAssociations': [], 'labels': {'en': 'Review subject'}, 'metadata': {}}}
            p = s.propose(source_ops + [entity], 'review-proposal')
            read_args = {'universe': NAME, 'universe_id': s.uid, 'proposal_id': p['proposal_id'], 'version': p['version'], 'view_group': 'assessment'}

            def case(label, args, error=False, validate=True):
                before = snapshot(s)
                if validate:
                    s.client.schemas['universe_get_proposal'][0].validate(args)
                raw = s.client.request('tools/call', {'name': 'universe_get_proposal', 'arguments': args})
                assert bool(raw.get('isError', False)) == error, (label, raw)
                content = raw.get('structuredContent')
                if content is not None:
                    assert json.loads(''.join(c['text'] for c in raw['content'] if c['type'] == 'text')) == content
                else:
                    assert error and label.startswith('revoked-'), (label, raw)
                if not error:
                    s.client.schemas['universe_get_proposal'][1].validate(content)
                after = snapshot(s)
                assert before['canonical_tables'] == after['canonical_tables'], label
                if error:
                    assert before == after, label
                report['snapshots'][label + '-before'] = before
                report['snapshots'][label + '-after'] = after
                report['cases'].append({'label': label, 'profile': s.agent, 'arguments': copy.deepcopy(args), 'response': raw,
                                        'before': label + '-before', 'after': label + '-after'})
                return content

            def pages(label, args):
                args = copy.deepcopy(args)
                first = None
                for i in range(100):
                    page = case(f'{label}-{i}', args)
                    if first is None:
                        first = page
                    if page['delivery']['complete']:
                        return first
                    args['cursor'] = page['delivery']['cursor']
                raise AssertionError('review did not finish')

            case('absent', read_args)
            viewed = s.call('universe_get_proposal', {k: v for k, v in read_args.items() if k != 'view_group'})['result']
            b = assessment(s, p, viewed, text)
            context = s.get([s.u['context_id']])[0]
            subject = next(c['next'] for c in viewed['compiled_changes'] if c['record_id'] == s.rid(1))
            def vr(record):
                return {'universe': s.uid, 'record': record['identity']['record_id'], 'version': record['record_version_id']}
            subject_ref, context_ref = vr(subject), vr(context)
            b['dependencies'] = [subject_ref, context_ref]
            b['inventory_declaration'] = {'kind': 'material_inventory_declared', 'rationale': 'Synthetic review accounting; no semantic qualification.',
                'exclusions': [{'source_key': 'passage', 'range': {'start': 0, 'end': len(text.encode())}, 'reason': 'Synthetic exclusion café 🌙 ' + str(i)} for i in range(31)]}
            for i in range(61):
                judgment = ['supported', 'contradicted', 'unresolved'][i % 3]
                item_id, mapping_id, unresolved_id = f'i-{i}', f'm-{i}', f'u-{i}'
                b['declared_inventory'].append({'item_id': item_id, 'source_key': 'passage', 'range': {'start': 0, 'end': len(text.encode())},
                    'material_kind': 'description', 'statement': ('Synthetic café 🌙 inventory. ' * 55) + str(i),
                    'mapping_ids': [mapping_id], 'unresolved_ids': [unresolved_id] if judgment == 'unresolved' else []})
                b['claim_mappings'].append({'mapping_id': mapping_id, 'item_ids': [item_id], 'referents': [subject_ref], 'context': context_ref,
                    'world': None, 'realm': None, 'story_time': s.instant(10), 'narration_position': {'kind': 'not_applicable'},
                    'reader_position': {'kind': 'not_applicable'}, 'occurrence': 'occurred', 'modality': 'asserted',
                    'semantic': {'kind': 'source_description', 'subject': subject_ref, 'depiction': 'subjective', 'implied_claims': []},
                    'candidate_links': [{'kind': 'proposed_record', 'version': subject_ref}, {'kind': 'unchanged_record', 'version': context_ref}],
                    'judgment': judgment, 'rationale': ('Synthetic mapping rationale 日本語. ' * 30) + str(i)})
                if judgment == 'unresolved':
                    b['unresolved'].append({'unresolved_id': unresolved_id, 'item_ids': [item_id], 'reason': 'interpretation_disagreement',
                        'detail': 'Synthetic unresolved material café 🌙 ' + str(i)})
            b['conclusion'] = 'inconsistent'
            def attach(body, generation, key):
                return s.call('universe_propose', {'action': 'attach_assessment', 'universe': NAME, 'context_id': s.ctx,
                    'proposal_reference': s.reference(p), 'expected_selection_generation': generation, 'body': body, 'idempotency_key': key})['result']
            a = attach(b, 0, 'review-a')
            report['proposal'] = p
            first = pages('selected', read_args)
            old = {**read_args, 'cursor': first['delivery']['cursor']}
            report['reviews'].append({'label': 'selected-author', 'response': s.admin('review', NAME, p['proposal_id'], p['version'], p['digest'])})
            case('bad-cursor', {**read_args, 'cursor': 'not-a-cursor'}, True)
            case('reference-outside-view', {**read_args, 'view_group': 'payload', 'assessment_reference': a['selected']}, True, False)
            case('wrong-digest', {**read_args, 'assessment_reference': {**a['selected'], 'digest': '0' * 64}}, True)
            case('unknown-assessment', {**read_args, 'assessment_reference': {**a['selected'], 'assessment_id': 'asm_' + '0' * 24}}, True)
            # Another proposal's attachment must not be retrievable under this proposal.
            other_ops = s.admin('stage-source', NAME, 'Other source', path)['operations']
            other = s.propose(other_ops, 'other-proposal')
            other_view = s.call('universe_get_proposal', {'universe': NAME, 'proposal_id': other['proposal_id'], 'version': other['version']})['result']
            other_body = assessment(s, other, other_view, text)
            other_selection = s.call('universe_propose', {'action': 'attach_assessment', 'universe': NAME, 'context_id': s.ctx,
                'proposal_reference': s.reference(other), 'expected_selection_generation': 0, 'body': other_body, 'idempotency_key': 'other-attachment'})['result']
            case('cross-proposal-attachment', {**read_args, 'assessment_reference': other_selection['selected']}, True)
            case('cursor-proposal-substitution', {**old, 'proposal_id': other['proposal_id']}, True)
            replacement = copy.deepcopy(b)
            replacement['assessor']['assessed_at'] = '2026-10-03T00:00:01Z'
            second = attach(replacement, 1, 'review-b')
            case('obsolete-after-replacement', old, True)
            historical_args = {**read_args, 'assessment_reference': a['selected']}
            hist = pages('historical-after-replacement', historical_args)
            s.call('universe_propose', {'action': 'select_assessment', 'universe': NAME, 'context_id': s.ctx,
                'proposal_reference': s.reference(p), 'expected_selection_generation': 2, 'assessment_reference': None, 'idempotency_key': 'withdraw-assessment'})
            case('obsolete-history-after-withdrawal', {**historical_args, 'cursor': hist['delivery']['cursor']}, True)
            case('withdrawn-selection', read_args)
            pages('historical-after-withdrawal', historical_args)
            # No propose permission is required for an otherwise authorized read.
            s.admin('grant', s.agent, s.uid)
            case('cursor-authority-change', {**historical_args, 'cursor': hist['delivery']['cursor']}, True)
            pages('read-only-history', historical_args)
            s.admin('grant', s.agent, s.uid, '--propose', '--edit', '--protected')
            s.restart()
            pages('historical-after-restart', historical_args)
            # Returning to A still changes generation, so its old cursor stays obsolete.
            s.call('universe_propose', {'action': 'select_assessment', 'universe': NAME, 'context_id': s.ctx,
                'proposal_reference': s.reference(p), 'expected_selection_generation': 3, 'assessment_reference': a['selected'], 'idempotency_key': 'reselect-a'})
            case('obsolete-after-reselection', old, True)
            current = pages('reselected', read_args)
            original = s.agent
            s.client.close()
            s.agent = s.admin('enroll')['profile_id']
            s.admin('grant', s.agent, s.uid, '--propose', '--edit', '--protected')
            s.connect()
            case('wrong-owner', read_args, True)
            case('wrong-owner-history', historical_args, True)
            case('wrong-owner-cursor', {**read_args, 'cursor': current['delivery']['cursor']}, True)
            case('unknown-proposal', {**read_args, 'proposal_id': 'prp_' + '0' * 24}, True)
            s.client.close(); s.agent = original; s.connect(); s.open()
            # Revise the proposal: old version and attachments remain exact history.
            revised = s.call('universe_propose', {'action': 'revise', 'universe': NAME, 'context_id': s.ctx,
                'proposal_reference': s.reference(p), 'operations': source_ops + [entity], 'submission': 'submitted',
                'rationale': 'Synthetic version two', 'idempotency_key': 'revision-two'})['result']
            pages('historical-stale-proposal', historical_args)
            case('version-two-absent', {**read_args, 'version': revised['version']})
            report['reviews'].append({'label': 'stale-author', 'response': s.admin('review', NAME, p['proposal_id'], p['version'], p['digest'])})
            # An accessible world proposal is a positive control for hidden sources.
            world_id = 'wld_' + s.rid(40)[4:]
            world = {'kind': 'create_world', 'client_ref': s.rid(40), 'record': {'selector': 'Visible', 'aliases': [], 'labels': {'en': 'Visible'}}}
            scope_ops = s.admin('stage-source', NAME, 'Scope source', path)['operations']
            setup = s.propose([world] + scope_ops, 'scope-setup')
            setup_view = s.call('universe_get_proposal', {'universe': NAME, 'proposal_id': setup['proposal_id'], 'version': setup['version']})['result']
            s.publish(setup, 'scope-setup-commit')
            scoped_entity = copy.deepcopy(entity)
            scoped_entity['client_ref'] = s.rid(41)
            scoped_entity['record']['worldAssociations'] = [{'world': world_id, 'role': 'setting', 'validity': {'kind': 'unspecified'}, 'qualifiers': {}}]
            scoped = s.propose([scoped_entity], 'scope-proposal')
            scope_body = assessment(s, scoped, setup_view, text)
            scope_body['inventory_declaration']['rationale'] = 'Private assessment café 🌙'
            selected = s.call('universe_propose', {'action': 'attach_assessment', 'universe': NAME, 'context_id': s.ctx,
                'proposal_reference': s.reference(scoped), 'expected_selection_generation': 0, 'body': scope_body, 'idempotency_key': 'scope-attachment'})['result']
            scoped_args = {**read_args, 'proposal_id': scoped['proposal_id'], 'version': scoped['version']}
            case('small-envelope', scoped_args)
            # Restrict this same MCP session between calls; no reconnect is needed.
            s.admin('grant', s.agent, s.uid, '--world', world_id, '--propose', '--edit', '--protected')
            s.call('universe_get_proposal', {k: v for k, v in scoped_args.items() if k != 'view_group'})
            case('source-restricted', scoped_args, True)
            case('source-restricted-history', {**scoped_args, 'assessment_reference': selected['selected']}, True)
            case('source-restricted-cursor', {**historical_args, 'cursor': current['delivery']['cursor']}, True)
            s.admin('grant', s.agent, s.uid, '--propose', '--edit', '--protected')
            case('restored-access', scoped_args)
            s.admin('revoke', s.agent)
            case('revoked-selected', scoped_args, True)
            case('revoked-history', historical_args, True)
            case('revoked-cursor', old, True)
            report['final_snapshot'] = snapshot(s)
        finally:
            s.close()
    output.mkdir(parents=True, exist_ok=True)
    (output / 'transcript.json.gz').write_bytes(gzip.compress((json.dumps(report, ensure_ascii=False, indent=2) + '\n').encode(), mtime=0))
    print(f'PASS: {len(report["cases"])} actual MCP review cases; {len(report["reviews"])} author reviews')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin-dir', type=Path, default=Path('target/debug'))
    parser.add_argument('--output', type=Path, default=Path('docs/evidence/assessment-review'))
    args = parser.parse_args()
    run(args.bin_dir.resolve(), args.output)
