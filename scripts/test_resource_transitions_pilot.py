"""Adversarial controls for the independent resource proof auditor."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from audit_resource_transitions import audit
EVIDENCE=None
class AuditTests(unittest.TestCase):
    def setUp(self):
        if EVIDENCE is None: self.skipTest('use --evidence')
        self.temp=tempfile.TemporaryDirectory(prefix='resource-audit-',dir='/tmp'); self.addCleanup(self.temp.cleanup); self.path=Path(self.temp.name)
        for f in ('report.json','oracle.json','build-identity.json','mcp-transcript.jsonl','package.sqlite'): shutil.copyfile(EVIDENCE/f,self.path/f)
    def test_saved_proof(self): self.assertEqual(audit(self.path)['status'],'passed')
    def mutate_report(self,fn):
        p=self.path/'report.json'; r=json.loads(p.read_text()); fn(r); p.write_text(json.dumps(r))
    def test_forged_head(self):
        self.mutate_report(lambda r:r['cases'][1].update(head_after=r['cases'][0]['head_before']))
        with self.assertRaises(RuntimeError): audit(self.path)
    def test_changed_query(self):
        self.mutate_report(lambda r:r['cases'][0]['states']['15']['result'].update(assertions=[]))
        with self.assertRaises(RuntimeError): audit(self.path)
    def test_changed_review(self):
        self.mutate_report(lambda r:r['publications'][1]['review'].update(changes=[]))
        with self.assertRaises(RuntimeError): audit(self.path)
    def test_wire_owner(self):
        p=self.path/'mcp-transcript.jsonl'; rows=list(map(json.loads,p.read_text().splitlines()))
        q=next(r['frame'] for r in rows if r['direction']=='sent' and r['frame'].get('params',{}).get('arguments',{}).get('idempotency_key')=='consumption')
        q['params']['arguments']['operations'][5]['record']['participants']=[]
        p.write_text('\n'.join(map(json.dumps,rows))+'\n')
        with self.assertRaisesRegex(RuntimeError,'report differs from wire'): audit(self.path)
    def test_changed_oracle(self):
        p=self.path/'oracle.json'; g=json.loads(p.read_text()); g['cases'][0]['allowed']=False; p.write_text(json.dumps(g))
        with self.assertRaisesRegex(RuntimeError,'oracle changed'): audit(self.path)
    def test_rehashed_forged_accounting_expectation(self):
        p=self.path/'oracle.json';g=json.loads(p.read_text());g['cases'][0]['allowed']=False;p.write_text(json.dumps(g))
        identity=self.path/'build-identity.json';v=json.loads(identity.read_text());v['resource_oracle_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();identity.write_text(json.dumps(v))
        with self.assertRaisesRegex(RuntimeError,'independent accounting differs'):audit(self.path)
if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--evidence',type=Path); args,tail=parser.parse_known_args(); EVIDENCE=args.evidence.resolve() if args.evidence else None; unittest.main(argv=[__file__,*tail])
