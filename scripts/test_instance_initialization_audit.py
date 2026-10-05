"""Coherent forged canonical/wire evidence must fail the independent oracle."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from audit_instance_initialization import audit, encoded

EVIDENCE = None
RID = lambda n: f'rec_{200000+n:024x}'


def rewrite(value, mutation):
    if isinstance(value, dict):
        if 'payload' in value and 'payload_digest' in value and 'identity' in value:
            mutation(value)
            value['payload_digest'] = hashlib.sha256(
                (value['payload']['record_kind'] + ':').encode() + encoded(value['payload'])
            ).hexdigest()
        for child in value.values():
            rewrite(child, mutation)
    elif isinstance(value, list):
        for child in value:
            rewrite(child, mutation)


class AuditControls(unittest.TestCase):
    def check_mutation(self, record_mutation=None, tree_mutation=None):
        report = json.loads(EVIDENCE.read_text())
        wire = [json.loads(line) for line in EVIDENCE.with_suffix('.jsonl').read_text().splitlines()]
        if record_mutation:
            rewrite(report, record_mutation)
            rewrite(wire, record_mutation)
        if tree_mutation:
            tree_mutation(report, wire)
        with tempfile.TemporaryDirectory(prefix='initialization-audit-') as directory:
            path = Path(directory) / 'proof.json'
            path.write_text(json.dumps(report))
            path.with_suffix('.jsonl').write_text('\n'.join(json.dumps(row) for row in wire) + '\n')
            with self.assertRaises(AssertionError):
                audit(path)

    def test_original(self):
        audit(EVIDENCE)

    def test_consumption_refilled(self):
        def mutate(record):
            if record['identity']['record_id'] == RID(120):
                record['payload']['value'] = {'kind': 'integer', 'digits': '9'}
        self.check_mutation(mutate)

    def test_initial_candidate_promoted_to_instance(self):
        def mutate(record):
            if record['payload'].get('proposition', {}).get('record') == RID(13):
                record['payload']['attributeMode'] = 'instance'
        self.check_mutation(mutate)

    def test_initialization_marker_replaced(self):
        def mutate(record):
            if record['payload'].get('basis', {}).get('kind') == 'instance_initialization':
                record['payload']['basis'] = {'kind': 'imported_claim'}
        self.check_mutation(mutate)

    def test_authored_world_scope_erased(self):
        def mutate(record):
            if record['payload'].get('basis', {}).get('kind') == 'instance_initialization':
                record['payload']['scope']['applicability'] = {'kind': 'universe_wide'}
        self.check_mutation(mutate)

    def test_unresolved_candidate_forged_exact(self):
        def mutate(record):
            if record['payload'].get('proposition', {}).get('record') == RID(16):
                record['payload']['precision'] = 'exact'
        self.check_mutation(mutate)

    def test_corrected_history_rewritten(self):
        def mutate(record):
            if record['identity']['record_id'] == RID(100):
                record['payload']['value'] = {'kind': 'integer', 'digits': '8'}
        self.check_mutation(mutate)

    def test_coherent_receipt_start_misbinding(self):
        def visit(value):
            if isinstance(value, dict):
                if value.get('instance_id') == RID(4) and 'start_event_id' in value:
                    value['start_event_id'] = RID(111)
                if value.get('instance') == RID(4) and 'start' in value:
                    value['start'] = RID(111)
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
        def mutate(report, wire):
            visit(report)
            visit(wire)
        self.check_mutation(tree_mutation=mutate)

    def test_historical_receipt_leaked_from_future(self):
        def mutate(report, wire):
            old = report['states']['historical-c-before-init']
            forged = deepcopy(old)
            forged['result']['objects'][0]['initialization_receipts'] = deepcopy(
                report['states']['final']['result']['objects'][2]['initialization_receipts'])
            report['states']['historical-c-before-init'] = forged
            for row in wire:
                if row['direction'] == 'received' and row['frame'].get('result', {}).get('structuredContent') == old:
                    row['frame']['result']['structuredContent'] = forged
        self.check_mutation(tree_mutation=mutate)

    def test_failed_publication_partial_receipt(self):
        def mutate(report, wire):
            report['publication_failure']['after']['initialization_receipt'] += 1
        self.check_mutation(tree_mutation=mutate)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--evidence', type=Path, required=True)
    args, rest = p.parse_known_args()
    EVIDENCE = args.evidence
    unittest.main(argv=[__file__, *rest])
