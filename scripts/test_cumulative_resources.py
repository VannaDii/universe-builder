"""Independent replay regressions and adversarial checks of saved MCP evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from audit_cumulative_resources import audit, replay
ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=None
class AccountingTests(unittest.TestCase):
    def test_focused_independent_accounting(self):
        gold=json.loads((ROOT/'fixtures/resource-transitions/cumulative.json').read_text())
        for case in gold['cases']:
            with self.subTest(case=case['id']):
                records={f'rec_{i+1:024x}':{'payload':p} for i,p in enumerate(case['records'])}
                self.assertEqual(replay(records)['allowed'],case['allowed'])
class AuditTests(unittest.TestCase):
    def setUp(self):
        if EVIDENCE is None:self.skipTest('supply --evidence for saved MCP audit')
        self.temp=tempfile.TemporaryDirectory(prefix='cumulative-audit-',dir='/tmp');self.addCleanup(self.temp.cleanup);self.path=Path(self.temp.name)
        for f in ('report.json','oracle.json','build-identity.json','mcp-transcript.jsonl','package.sqlite'):shutil.copyfile(EVIDENCE/f,self.path/f)
    def mutate(self,fn):
        p=self.path/'report.json';r=json.loads(p.read_text());fn(r);p.write_text(json.dumps(r))
    def test_saved_proof(self):self.assertEqual(audit(self.path)['status'],'passed')
    def test_forged_state(self):
        self.mutate(lambda r:r['states'][0]['response']['result'].update(assertions=[]))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_missing_retry_receipt(self):
        self.mutate(lambda r:r['retry_receipts'].pop())
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_forged_old_edition(self):
        self.mutate(lambda r:r['restart_old_event']['payload']['time'].update(value='10'))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_changed_review(self):
        self.mutate(lambda r:r['publications'][1]['review'].update(changes=[]))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_changed_head(self):
        self.mutate(lambda r:r.update(after_restart_head=r['shots'][0]['receipt']['revision']))
        with self.assertRaises(RuntimeError):audit(self.path)
    def test_changed_wire_owner(self):
        p=self.path/'mcp-transcript.jsonl';rows=list(map(json.loads,p.read_text().splitlines()))
        q=next(r['frame'] for r in rows if r['direction']=='sent' and r['frame'].get('params',{}).get('arguments',{}).get('idempotency_key')=='shot-1');q['params']['arguments']['operations'][0]['record']['subject']['record']=f'rec_{200002:024x}';p.write_text('\n'.join(map(json.dumps,rows)))
        with self.assertRaisesRegex(RuntimeError,'report differs from wire'):audit(self.path)
    def test_rehashed_false_oracle(self):
        p=self.path/'oracle.json';g=json.loads(p.read_text());g['states']['final_restart'][0]=3;p.write_text(json.dumps(g))
        identity=self.path/'build-identity.json';v=json.loads(identity.read_text());v['continuation_oracle_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();identity.write_text(json.dumps(v))
        with self.assertRaisesRegex(RuntimeError,'independent expected balance'):audit(self.path)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--evidence',type=Path);a,tail=parser.parse_known_args();EVIDENCE=a.evidence.resolve() if a.evidence else None;unittest.main(argv=[__file__,*tail])
