"""Tamper controls against the independent family qualification oracle."""
import argparse
from contextlib import closing
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest
from audit_canonical_families import audit

EVIDENCE = Path('docs/evidence/canonical-families-complete')


class FamilyOracleControls(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='universe-family-audit-',dir='/tmp')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in ('package.sqlite','report.json','fixture.json','mcp-transcript.jsonl'):
            shutil.copyfile(EVIDENCE/name,self.root/name)
        self.report = json.loads((self.root/'report.json').read_text())

    def reject_report(self):
        (self.root/'report.json').write_text(json.dumps(self.report))
        with self.assertRaises(AssertionError):audit(self.root)

    def test_untouched_evidence_passes(self):
        self.assertEqual(audit(self.root)['families'],38)

    def test_reordered_duplicate_communication_content_rejects(self):
        actor=self.report['bindings']['actor']
        body=next(r['payload'] for r in self.report['snapshots'][0]['records'] if r['payload']['record_kind']=='communication')
        body['content'][0]={'universe':self.report['bindings']['universe'],'record':actor}
        self.reject_report()

    def test_changed_historical_revision_rejects(self):
        self.report['snapshots'][0]['revision']=self.report['snapshots'][1]['revision']
        self.reject_report()

    def test_retargeted_editorial_pin_rejects(self):
        corrected=next(s for s in self.report['snapshots'] if s['label']=='corrected')
        edition=next(r for r in corrected['records'] if r['payload']['record_kind']=='work_version')
        scene=next(r for r in corrected['records'] if r['payload']['record_kind']=='scene_ref')
        scene['payload']['workVersion']['version']=edition['record_version_id']
        self.reject_report()

    def test_false_unchanged_authority_claim_rejects(self):
        self.report['controls'][0]['after']['record_versions']+=1
        self.reject_report()

    def test_permission_leak_rejects(self):
        self.report['restricted_read']['records']=self.report['snapshots'][0]['records']
        self.reject_report()

    def test_unrecorded_public_readbacks_reject(self):
        wire=[json.loads(l) for l in (self.root/'mcp-transcript.jsonl').read_text().splitlines()]
        for row in wire:
            result=row['frame'].get('result',{}).get('structuredContent',{}).get('result',{})
            if isinstance(result,dict):result.pop('records',None)
        (self.root/'mcp-transcript.jsonl').write_text(''.join(json.dumps(l)+'\n' for l in wire))
        with self.assertRaises(AssertionError):audit(self.root)

    def test_source_scalar_tamper_rejects(self):
        with closing(sqlite3.connect(self.root/'package.sqlite')) as db, db:
            db.execute('DROP TRIGGER source_content_no_update')
            db.execute("UPDATE source_content SET utf8_content=?",(b'forged',))
        with self.assertRaises(AssertionError):audit(self.root)

    def test_missing_original_media_chunk_rejects(self):
        with closing(sqlite3.connect(self.root/'package.sqlite')) as db, db:
            db.execute('DROP TRIGGER media_chunk_no_delete')
            db.execute('DELETE FROM media_chunk WHERE ordinal=0')
        with self.assertRaises(AssertionError):audit(self.root)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,default=EVIDENCE)
    a,tail=p.parse_known_args();EVIDENCE=a.evidence.resolve()
    unittest.main(argv=['test_canonical_families_audit',*tail])
