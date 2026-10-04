"""Mutation controls ensure the independent auditor rejects plausible bad delivery."""
import argparse
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
from audit_effective_object import audit

class AuditControls(unittest.TestCase):
    evidence = None

    def check_mutation(self, mutate):
        report = json.loads(self.evidence.read_text())
        wire = [json.loads(line) for line in self.evidence.with_suffix('.jsonl').read_text().splitlines()]
        old = deepcopy(report['views']['original'])
        mutate(report['views']['original']['result']['objects'][0])
        new = report['views']['original']
        # Alter the wire too: semantic checks must reject it, not just membership.
        for row in wire:
            if row['direction']=='received' and row['frame'].get('result',{}).get('structuredContent')==old:
                row['frame']['result']['structuredContent']=new
        with tempfile.TemporaryDirectory(prefix='object-audit-') as directory:
            path=Path(directory)/'report.json';path.write_text(json.dumps(report))
            path.with_suffix('.jsonl').write_text('\n'.join(json.dumps(r) for r in wire))
            with self.assertRaises((AssertionError, KeyError)), redirect_stdout(io.StringIO()):audit(path)

    def test_original_passes(self):
        with redirect_stdout(io.StringIO()):audit(self.evidence)

    def test_dropping_inherited_witness_fails(self):
        self.check_mutation(lambda o:o['shared_attributes'].pop(0))

    def test_silently_clearing_conflict_fails(self):
        self.check_mutation(lambda o:o['conflicts'].clear())

    def test_initial_candidate_as_observed_fact_fails(self):
        self.check_mutation(lambda o:o['instance_facts'].append(o['initial_value_candidates'].pop()))

    def test_unknown_as_applicable_fails(self):
        def mutate(o):
            row=next(r for r in o['shared_attributes'] if r['applicability'] is None)
            row['applicability']=True;row['unknowns']=[]
        self.check_mutation(mutate)

    def test_forged_version_fails(self):
        self.check_mutation(lambda o:o['ancestry'][0].update(record_version_id='ver_000000000000000000000999'))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a,rest=p.parse_known_args();AuditControls.evidence=a.evidence;unittest.main(argv=['audit-controls',*rest])
