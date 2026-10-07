"""Saved-evidence authenticity and deliberate forgery controls for Goal 40."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from audit_knowledge_acquisition import audit
EVIDENCE=None
class EvidenceTests(unittest.TestCase):
    def setUp(self):
        if EVIDENCE is None:self.skipTest('use --evidence')
        temp=tempfile.TemporaryDirectory(prefix='g40-audit-',dir='/tmp');self.addCleanup(temp.cleanup);self.path=Path(temp.name)
        for name in ('report.json','mcp-transcript.jsonl','package.sqlite'):shutil.copyfile(EVIDENCE/name,self.path/name)
    def mutate(self,fn):
        p=self.path/'report.json';r=json.loads(p.read_text());fn(r);p.write_text(json.dumps(r))
    def test_authentic_evidence(self):self.assertEqual(audit(self.path)['status'],'passed')
    def test_forged_review(self):
        self.mutate(lambda r:r['publications'][-1]['review'].update(changes=[]))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_forged_acquisition_result(self):
        self.mutate(lambda r:r['cases'][1].update(expected='legal',admitted=True))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_forged_historical_read(self):
        self.mutate(lambda r:r['historical_after_restart'][0]['payload'].update(attitude='believes'))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_forged_restart(self):
        self.mutate(lambda r:r['restart_instances'][0].update(after=r['restart_instances'][0]['before']))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_missing_case(self):
        self.mutate(lambda r:r['cases'].pop())
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_altered_typed_package(self):
        with (self.path/'package.sqlite').open('ab') as f:f.write(b'forged')
        with self.assertRaises(RuntimeError):audit(self.path)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a=p.parse_args();EVIDENCE=a.evidence.resolve();unittest.main(argv=[__file__])
