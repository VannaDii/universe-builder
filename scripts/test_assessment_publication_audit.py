"""Ensure the independent publication oracle rejects misleading proof evidence."""
import copy
import json
from pathlib import Path
import unittest
from audit_assessment_publication import audit


class PublicationOracleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((Path(__file__).resolve().parents[1] /
            'docs/evidence/assessment-publication/transcript.json').read_text())

    def test_original_transcript(self):
        self.assertEqual(audit(self.evidence)['status'], 'pass')

    def test_earlier_validation_cannot_authorize_final_selection(self):
        evidence = copy.deepcopy(self.evidence)
        earlier = next(c for c in evidence['cases'] if c['label']=='assessed-validation')
        commit = next(c for c in evidence['cases'] if c['label']=='assessed-commit')
        commit['arguments']['validation_run'] = earlier['response']['structuredContent']['result']['execution']['run_id']
        with self.assertRaises(AssertionError):
            audit(evidence)

    def test_rejected_commit_cannot_move_head(self):
        evidence = copy.deepcopy(self.evidence)
        rejected = next(c for c in evidence['cases'] if c['label']=='stale-selection')
        rejected['after']['canonical_tables']['continuities'][0][2] = 'forged head'
        with self.assertRaises(AssertionError):
            audit(evidence)

    def test_restart_cannot_retarget_receipt_or_history(self):
        for field in ('receipt_after_restart','historical_assessments_after','historical_validation_after'):
            with self.subTest(field=field):
                evidence = copy.deepcopy(self.evidence)
                evidence[field] = {} if isinstance(evidence[field], dict) else []
                with self.assertRaises(AssertionError):
                    audit(evidence)


if __name__ == '__main__':
    unittest.main()
