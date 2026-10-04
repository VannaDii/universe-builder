"""Corruption controls for the independent MCP proof audit."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from audit_ancestor_applicability import audit

EVIDENCE=None
class AuditControls(unittest.TestCase):
    def check_mutation(self, mutate_report=None, mutate_wire=None):
        with tempfile.TemporaryDirectory(prefix='ancestor-audit-') as directory:
            path=Path(directory)/'report.json'
            report=json.loads(EVIDENCE.read_text())
            wire=[json.loads(line) for line in EVIDENCE.with_suffix('.jsonl').read_text().splitlines()]
            if mutate_report:mutate_report(report)
            if mutate_wire:mutate_wire(wire,report)
            path.write_text(json.dumps(report));path.with_suffix('.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in wire))
            with self.assertRaises(AssertionError):audit(path)
    def test_real_wire_passes(self):
        self.assertEqual(audit(EVIDENCE)['status'],'passed')
    def test_history_rewrite_fails(self):
        self.check_mutation(lambda r:r['history']['after_restart']['before'][0]['payload'].update(parent=None))
    def test_false_commit_denial_fails(self):
        def mutate(wire,report):
            for item in wire:
                frame=item['frame']
                if item['direction']=='received' and frame.get('result',{}).get('isError'):
                    frame['result']['isError']=False
        self.check_mutation(mutate_wire=mutate)
    def test_relabelled_unresolved_case_fails(self):
        def mutate(report):
            report['cases']['unclassified_property']['proposal']=deepcopy(report['cases']['cedar_property']['proposal'])
        self.check_mutation(mutate_report=mutate)
    def test_forged_publication_receipt_fails(self):
        self.check_mutation(lambda r:r['publications'][0]['receipt'].update(revision=r['history']['corrected']))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a,rest=p.parse_known_args();EVIDENCE=a.evidence;unittest.main(argv=['test_ancestor_applicability_audit',*rest])
