"""Coherent forged record/wire controls must fail the independent fact oracle."""
import argparse
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from audit_incremental_authoring import audit, encoded

EVIDENCE=None
RID=lambda n:f'rec_{200000+n:024x}'


def rewrite(value, mutation):
    if isinstance(value,dict):
        if 'payload' in value and 'payload_digest' in value and 'identity' in value:
            mutation(value)
            value['payload_digest']=hashlib.sha256((value['payload']['record_kind']+':').encode()+encoded(value['payload'])).hexdigest()
        for child in value.values():rewrite(child,mutation)
    elif isinstance(value,list):
        for child in value:rewrite(child,mutation)


class AuditControls(unittest.TestCase):
    def check_mutation(self,mutation):
        report=json.loads(EVIDENCE.read_text())
        wire=[json.loads(line) for line in EVIDENCE.with_suffix('.jsonl').read_text().splitlines()]
        rewrite(report,mutation);rewrite(wire,mutation)
        with tempfile.TemporaryDirectory(prefix='incremental-audit-') as directory:
            path=Path(directory)/'proof.json';path.write_text(json.dumps(report))
            path.with_suffix('.jsonl').write_text('\n'.join(json.dumps(line) for line in wire)+'\n')
            with self.assertRaises(AssertionError),redirect_stdout(io.StringIO()):audit(path)
    def test_original(self):
        with redirect_stdout(io.StringIO()):audit(EVIDENCE)
    def test_unrelated_classification(self):
        def mutate(r):
            if r['identity']['record_id']==RID(4) and r['payload'].get('classification')==RID(2):r['payload']['classification']=RID(3)
        self.check_mutation(mutate)
    def test_instance_hazard_promoted_to_shared(self):
        def mutate(r):
            if r['payload'].get('proposition',{}).get('record')==RID(11):r['payload']['attributeMode']='shared'
        self.check_mutation(mutate)
    def test_world_scope_erased(self):
        def mutate(r):
            if r['payload'].get('proposition',{}).get('record')==RID(10):r['payload']['scope']['applicability']={'kind':'universe_wide'}
        self.check_mutation(mutate)
    def test_explicit_unknown_promoted(self):
        def mutate(r):
            if r['payload'].get('proposition',{}).get('record')==RID(12):r['payload']['validity']={'kind':'unspecified'}
        self.check_mutation(mutate)
    def test_authored_provenance_replaced(self):
        def mutate(r):
            if r['payload'].get('proposition',{}).get('record')==RID(11):r['payload']['basis']={'kind':'imported_claim'}
        self.check_mutation(mutate)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);args,rest=p.parse_known_args();EVIDENCE=args.evidence;unittest.main(argv=[__file__,*rest])
