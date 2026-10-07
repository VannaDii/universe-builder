"""Independent numerical oracle and adversarial evidence controls for Goal 39."""
import argparse
import copy
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from audit_communication_chronology import audit, classify, I128_MIN, I128_MAX

EVIDENCE = None

class OracleTests(unittest.TestCase):
    def communication(self, sent='100', received='105', actual=None, intended=None):
        return {'channel':'radio', 'sentAt':{'kind':'exact','calendar':'cal_a','value':sent},
                'receivedAt':{'kind':'exact','calendar':'cal_a','value':received},
                'actualRecipients':['recipient-b'] if actual is None else actual,
                'intendedRecipients':['recipient-a'] if intended is None else intended}
    def contract(self, forward=True, minimum='2', maximum='8'):
        return [{'channel':'radio','forwardOnly':forward,'minimumDelay':minimum,'maximumDelay':maximum}]
    def test_inclusive_delay_bounds(self):
        for delay in (2,8):
            self.assertEqual(classify(self.communication(received=str(100+delay)),self.contract())['outcome'],'supported')
        for delay in (1,9):
            self.assertEqual(classify(self.communication(received=str(100+delay)),self.contract())['outcome'],'violated')
    def test_forward_and_explicit_reverse(self):
        c=self.communication(received='95')
        self.assertEqual(classify(c,self.contract(True,None,None))['outcome'],'violated')
        self.assertEqual(classify(c,self.contract(False,'-8','-2'))['outcome'],'supported')
        self.assertEqual(classify(c,self.contract(False,'-4',None))['outcome'],'violated')
    def test_recipient_distinctions(self):
        self.assertEqual(classify(self.communication(),self.contract())['outcome'],'supported')
        self.assertEqual(classify(self.communication(actual=[]),self.contract())['outcome'],'unknown')
        self.assertEqual(classify(self.communication(intended=[]),self.contract())['outcome'],'supported')
    def test_unresolved_clock_and_rule(self):
        c=self.communication();self.assertEqual(classify(c,[])['outcome'],'unknown')
        c['receivedAt']['calendar']='cal_b';self.assertEqual(classify(c,self.contract())['outcome'],'unknown')
        c['receivedAt']['calendar']='cal_a';c['receivedAt']['kind']='approximate';self.assertEqual(classify(c,self.contract())['outcome'],'unknown')
        c['receivedAt']=None;self.assertEqual(classify(c,self.contract())['outcome'],'unknown')
    def test_exact_signed_arithmetic_and_overflow(self):
        self.assertEqual(classify(self.communication(str(I128_MIN),str(I128_MIN+2)),self.contract())['delay'],'2')
        self.assertEqual(classify(self.communication(str(I128_MIN),str(I128_MAX)),self.contract())['outcome'],'unknown')
        self.assertEqual(classify(self.communication('1.0','5'),self.contract())['outcome'],'unknown')
        self.assertEqual(classify(self.communication('+100','+105'),self.contract())['delay'],'5')
    def test_conjunctive_rules(self):
        contracts=self.contract(False,None,None)+self.contract(True,None,None)
        self.assertEqual(classify(self.communication(received='95'),contracts)['outcome'],'violated')

class EvidenceTests(unittest.TestCase):
    def setUp(self):
        if EVIDENCE is None:
            self.skipTest('use --evidence')
        temporary = tempfile.TemporaryDirectory(prefix='communication-audit-',dir='/tmp')
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name)
        for name in ('report.json','mcp-transcript.jsonl','package.sqlite'):
            shutil.copyfile(EVIDENCE/name,self.path/name)
    def test_saved_evidence(self):
        self.assertEqual(audit(self.path)['status'],'passed')
    def mutate(self, function):
        path=self.path/'report.json';report=json.loads(path.read_text())
        function(report);path.write_text(json.dumps(report))
    def test_forged_review(self):
        self.mutate(lambda r:r['publications'][-1]['review'].update(changes=[]))
        with self.assertRaisesRegex(RuntimeError,'review changes differ'):
            audit(self.path)
    def test_forged_receipt(self):
        self.mutate(lambda r:r['publications'][-1]['receipt'].update(revision='rev_forged'))
        with self.assertRaises(RuntimeError):
            audit(self.path)
    def test_forged_historical_read(self):
        self.mutate(lambda r:r['historical_after_restart'][0]['payload'].update(distorted=True))
        with self.assertRaises(RuntimeError):
            audit(self.path)
    def test_forged_case_head(self):
        self.mutate(lambda r:next(c for c in r['cases'] if c['id']=='reversed-forward').update(head_after='rev_forged'))
        with self.assertRaises(RuntimeError):
            audit(self.path)
    def test_forged_finding(self):
        self.mutate(lambda r:next(f for f in next(c for c in r['cases'] if c['id']=='reversed-forward')['validation']['findings'] if f['outcome']=='refuted').update(outcome='supported'))
        with self.assertRaises(RuntimeError):
            audit(self.path)
    def test_changed_wire_receipt(self):
        path=self.path/'mcp-transcript.jsonl';rows=[json.loads(line) for line in path.read_text().splitlines()]
        target=next(r['frame']['params']['arguments'] for r in rows if r['direction']=='sent' and r['frame'].get('params',{}).get('name')=='universe_commit')
        target['expected_base_revision']='rev_forged'
        path.write_text('\n'.join(json.dumps(r) for r in rows)+'\n')
        with self.assertRaisesRegex(RuntimeError,'report differs from wire'):
            audit(self.path)
    def test_changed_package_hash(self):
        self.mutate(lambda r:r.update(package_sha256='forged'))
        with self.assertRaisesRegex(RuntimeError,'package changed'):
            audit(self.path)

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--evidence',type=Path)
    args,tail=parser.parse_known_args();EVIDENCE=args.evidence.resolve() if args.evidence else None
    unittest.main(argv=[__file__,*tail])
