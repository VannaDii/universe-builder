"""Tamper proof artifacts in temporary copies to qualify the independent audit."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest
from audit_g05 import audit
EVIDENCE=None

class AuditTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='g05-negative-',dir='/tmp');self.addCleanup(self.temp.cleanup)
  self.root=Path(self.temp.name)
  for name in ('report.json','mcp-transcript.jsonl','package.sqlite'):shutil.copyfile(EVIDENCE/name,self.root/name)
 def mutate(self,fn):
  with sqlite3.connect(self.root/'package.sqlite') as db:fn(db)
  p=self.root/'report.json';r=json.loads(p.read_text());r['package_sha256']=hashlib.sha256((self.root/'package.sqlite').read_bytes()).hexdigest();p.write_text(json.dumps(r))
 def test_original_passes(self):self.assertEqual(audit(self.root)['status'],'passed')
 def test_changed_wire_is_rejected(self):
  p=self.root/'mcp-transcript.jsonl';rows=[json.loads(l) for l in p.read_text().splitlines()]
  next(r for r in rows if r['direction']=='sent' and r['frame'].get('params',{}).get('name')=='universe_propose')['frame']['params']['arguments']['rationale']='tampered'
  p.write_text('\n'.join(json.dumps(r) for r in rows)+'\n')
  with self.assertRaisesRegex(RuntimeError,'report differs from wire'):audit(self.root)
 def test_missing_approval_is_rejected(self):
  def change(db):
   db.execute('DROP TRIGGER workflow_entries_no_delete');db.execute("DELETE FROM workflow_entries WHERE key LIKE 'approval:%'")
  self.mutate(change)
  with self.assertRaisesRegex(RuntimeError,'exact approval missing'):audit(self.root)
 def test_receipt_retarget_is_rejected(self):
  def change(db):
   db.execute('DROP TRIGGER immutable_operation_receipts_update')
   genesis=db.execute('SELECT id FROM commits WHERE sequence=0').fetchone()[0]
   db.execute("UPDATE operation_receipts SET revision_id=? WHERE idempotency_key='mechanism-a-commit'",(genesis,))
  self.mutate(change)
  with self.assertRaisesRegex(RuntimeError,'kernel receipt mismatch'):audit(self.root)
 def test_head_membership_is_rejected(self):
  self.mutate(lambda db:db.execute("DELETE FROM head_membership WHERE record_id='rec_000000000000000000030d46'")) # entity 6
  with self.assertRaisesRegex(RuntimeError,'head membership differs'):audit(self.root)
 def test_historical_version_is_rejected(self):
  historical=json.loads((self.root/'report.json').read_text())['historical_after_restart'][0]
  def change(db):
   db.execute('DROP TRIGGER immutable_record_versions_update')
   row=db.execute('SELECT payload FROM record_versions WHERE id=?',(historical['record_version_id'],)).fetchone()
   r=json.loads(row[0]);r['payload']['polarity']='support'
   db.execute('UPDATE record_versions SET payload=? WHERE id=?',(json.dumps(r),historical['record_version_id']))
  self.mutate(change)
  with self.assertRaisesRegex(RuntimeError,'committed payload differs|history differs'):audit(self.root)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a,extra=p.parse_known_args();EVIDENCE=a.evidence.resolve();unittest.main(argv=[__file__,*extra])
