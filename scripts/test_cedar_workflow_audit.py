"""Falsification controls for the independently authored Cedar oracle.

The baseline verifies the retained database too. Coherent report/wire forgeries
skip database comparison to exercise the factual oracle itself, rather than
failing solely because the forged report differs from the authentic database.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from audit_cedar_workflow import audit, encoded, RID

EVIDENCE=None


def rewrite(value, mutation):
    if isinstance(value,dict):
        if all(k in value for k in ('payload','payload_digest','identity')):
            mutation(value)
            value['payload_digest']=hashlib.sha256((value['payload']['record_kind']+':').encode()+encoded(value['payload'])).hexdigest()
        for child in value.values():rewrite(child,mutation)
    elif isinstance(value,list):
        for child in value:rewrite(child,mutation)


class AuditControls(unittest.TestCase):
    def forge(self, record_mutation=None, tree_mutation=None):
        report=json.loads(EVIDENCE.read_text())
        wire=[json.loads(line) for line in EVIDENCE.with_suffix('.jsonl').read_text().splitlines()]
        if record_mutation:
            rewrite(report,record_mutation);rewrite(wire,record_mutation)
        if tree_mutation:tree_mutation(report,wire)
        with tempfile.TemporaryDirectory(prefix='cedar-oracle-') as directory:
            path=Path(directory)/'actual.json';path.write_text(json.dumps(report))
            path.with_suffix('.jsonl').write_text('\n'.join(json.dumps(row) for row in wire)+'\n')
            with self.assertRaises(AssertionError):audit(path,check_database=False)

    def test_authentic_database_and_wire(self):
        audit(EVIDENCE)

    def test_authored_post_value_changed(self):
        def mutate(row):
            if row['identity']['record_id']==RID(52):row['payload']['value']['value']['digits']='32'
        self.forge(mutate)

    def test_refinement_identity_replaced(self):
        def mutate(row):
            if row['identity']['record_id']==RID(4) and row['payload']['classification']==RID(2):row['identity']['record_id']=RID(9)
        self.forge(mutate)

    def test_shared_capability_promoted_to_instance(self):
        def mutate(row):
            if row['payload'].get('proposition',{}).get('record')==RID(12):row['payload']['attributeMode']='instance'
        self.forge(mutate)

    def test_local_hazard_promoted_to_shared(self):
        def mutate(row):
            if row['payload'].get('proposition',{}).get('record')==RID(13):row['payload']['attributeMode']='shared'
        self.forge(mutate)

    def test_physical_location_erased(self):
        def mutate(row):
            if row['identity']['record_id']==RID(11):row['payload']['value']['text']='Grove'
        self.forge(mutate)

    def test_growth_conditions_removed(self):
        def mutate(row):
            if row['identity']['record_id']==RID(55):row['payload']['requirements']=row['payload']['requirements'][:1]
        self.forge(mutate)

    def test_unknown_water_promoted_to_exact(self):
        def mutate(row):
            if row['payload'].get('proposition',{}).get('record')==RID(15):row['payload']['precision']='exact'
        self.forge(mutate)

    def test_historical_fact_rewritten(self):
        def mutate(row):
            if row['identity']['record_id']==RID(14):row['payload']['value']['value']['digits']='29'
        self.forge(mutate)

    def test_correction_does_not_fix_downstream(self):
        def mutate(row):
            if row['identity']['record_id']==RID(81):row['payload']['value']['value']['digits']='31'
        self.forge(mutate)

    def test_height_event_provenance_erased(self):
        def mutate(row):
            if row['payload'].get('establishedBy',{}).get('event',{}).get('record')==RID(51):row['payload'].pop('establishedBy')
        self.forge(mutate)

    def test_retained_context_silently_moves_to_head(self):
        def mutate(report,wire):
            old=deepcopy(report['retained_state']);new=deepcopy(report['states']['corrected_before'])
            report['retained_state']=new
            for row in wire:
                if row['direction']=='received' and row['frame'].get('result',{}).get('structuredContent')==old:row['frame']['result']['structuredContent']=new
        self.forge(tree_mutation=mutate)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a,rest=p.parse_known_args();EVIDENCE=a.evidence;unittest.main(argv=[__file__,*rest])
