"""Authentic control and coherent wire/report forgeries of the accounting oracle."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from audit_pistol_workflow import audit, RID
from test_cedar_workflow_audit import rewrite

EVIDENCE=None

class AuditControls(unittest.TestCase):
    def forge(self, mutation=None, tree_mutation=None):
        report=json.loads(EVIDENCE.read_text());wire=[json.loads(line) for line in EVIDENCE.with_suffix('.jsonl').read_text().splitlines()]
        if mutation:rewrite(report,mutation);rewrite(wire,mutation)
        if tree_mutation:tree_mutation(report,wire)
        with tempfile.TemporaryDirectory(prefix='pistol-oracle-') as directory:
            path=Path(directory)/'actual.json';path.write_text(json.dumps(report));path.with_suffix('.jsonl').write_text('\n'.join(json.dumps(row) for row in wire)+'\n')
            with self.assertRaises(AssertionError):audit(path,check_database=False)

    def test_authentic_database_and_wire(self):audit(EVIDENCE)

    def test_wrong_post_balance(self):
        def mutate(row):
            if row['identity']['record_id']==RID(204):row['payload']['value']['digits']='0'
        self.forge(mutate)

    def test_second_pistol_spends_first_stock(self):
        def mutate(row):
            if row['identity']['record_id']==RID(224):row['payload']['subject']['record']=RID(4)
        self.forge(mutate)

    def test_reserve_not_debited(self):
        def mutate(row):
            if row['identity']['record_id']==RID(251):row['payload']['value']['digits']='2'
        self.forge(mutate)

    def test_transfer_keeps_former_holder(self):
        def mutate(row):
            if row['identity']['record_id']==RID(240):row['payload']['value']['ref']['record']=RID(6)
        self.forge(mutate)

    def test_shared_capability_promoted(self):
        def mutate(row):
            if row['payload'].get('proposition',{}).get('record')==RID(12):row['payload']['attributeMode']='instance'
        self.forge(mutate)

    def test_firing_requirement_removed(self):
        def mutate(row):
            if row['identity']['record_id']==RID(31):row['payload']['requirements']=[]
        self.forge(mutate)

    def test_historical_time_lost(self):
        def mutate(row):
            if row['identity']['record_id']==RID(203):row['payload']['time']['value']='10'
        self.forge(mutate)

    def test_gap_disguised_as_event(self):
        def mutate(row):
            if row['payload'].get('proposition',{}).get('record')==RID(920):row['payload']['establishedBy']={'event':{'universe':row['identity']['universe_id'],'record':RID(252)},'slot':'reserve'}
        self.forge(mutate)

    def test_receipt_bound_to_wrong_source(self):
        def mutate(report,wire):report['initialization_receipts'][0]['initial_definition_version']='ver_'+'0'*24
        self.forge(tree_mutation=mutate)

    def test_conflicting_refill_marked_admitted(self):
        def mutate(report,wire):report['cases']['direct-unsupported-refill']['admitted']=True
        self.forge(tree_mutation=mutate)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a,rest=p.parse_known_args();EVIDENCE=a.evidence;unittest.main(argv=['test_pistol_workflow_audit.py',*rest])
