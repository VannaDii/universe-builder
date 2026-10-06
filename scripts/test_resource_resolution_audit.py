"""Authentic typed-database control and coherent accounting/history forgeries."""
import argparse
import json
from pathlib import Path
import tempfile
import unittest
from audit_resource_resolution import audit, RID
from test_cedar_workflow_audit import rewrite

EVIDENCE=None
class AuditControls(unittest.TestCase):
    def forge(self,mutation=None,tree_mutation=None):
        report=json.loads(EVIDENCE.read_text());wire=[json.loads(line) for line in EVIDENCE.with_suffix('.jsonl').read_text().splitlines()]
        if mutation:rewrite(report,mutation);rewrite(wire,mutation)
        if tree_mutation:tree_mutation(report,wire)
        with tempfile.TemporaryDirectory(prefix='resource-resolution-oracle-') as directory:
            path=Path(directory)/'actual.json';path.write_text(json.dumps(report));path.with_suffix('.jsonl').write_text('\n'.join(json.dumps(row) for row in wire)+'\n')
            with self.assertRaises(AssertionError):audit(path,check_database=False)
    def test_authentic_database_and_wire(self):audit(EVIDENCE)
    def test_accepted_amount_changed(self):
        def mutate(row):
            if row['identity']['record_id']==RID(92):row['payload']['value']['digits']='4'
        self.forge(mutate)
    def test_acceptance_reused_for_changed_claim(self):
        def mutate(row):
            if row['identity']['record_id']==RID(101):row['payload']['scope']='resource:'+RID(91)
        self.forge(mutate)
    def test_acceptance_fingerprint_forged(self):
        def mutate(row):
            if row['identity']['record_id']==RID(100):row['payload']['fingerprints']=['0'*64]
        self.forge(mutate)
    def test_creative_authority_impersonated(self):
        def mutate(row):
            if row['identity']['record_id']==RID(101):row['payload']['principal']='prn_'+'0'*24
        self.forge(mutate)
    def test_acceptance_downgraded_to_ordinary_decision(self):
        def mutate(row):
            if row['identity']['record_id']==RID(100):row['payload']['mode']='resolve'
        self.forge(mutate)
    def test_resource_policy_disabled(self):
        def mutate(row):
            if row['identity']['record_id']==RID(20):row['payload']['capabilities']=['basic.v1']
        self.forge(mutate)
    def test_accounted_supply_not_debited(self):
        def mutate(row):
            if row['identity']['record_id']==RID(61):row['payload']['value']['digits']='3'
        self.forge(mutate)
    def test_reload_does_not_use_accepted_balance(self):
        def mutate(row):
            if row['identity']['record_id']==RID(93):row['payload']['value']['digits']='0'
        self.forge(mutate)
    def test_earlier_correction_is_not_coherent(self):
        def mutate(row):
            if row['identity']['record_id']==RID(82):row['payload']['value']['digits']='1'
        self.forge(mutate)
    def test_historical_count_silently_changes(self):
        def mutate(row):
            if row['identity']['record_id']==RID(91):row['payload']['value']['digits']='3'
        self.forge(mutate)
    def test_unexplained_arrival_erased_from_delivery(self):
        def mutate(report,wire):
            def walk(v):
                if isinstance(v,dict):
                    if 'unknowns' in v:v['unknowns']=[x for x in v['unknowns'] if not x.startswith('resource_arrival_unexplained')]
                    for child in v.values():walk(child)
                elif isinstance(v,list):
                    for child in v:walk(child)
            walk(report);walk(wire)
        self.forge(tree_mutation=mutate)
    def test_fabricated_arrival_event(self):
        def mutate(row):
            if row['payload'].get('proposition',{}).get('record')==RID(92):row['payload']['establishedBy']={'event':{'universe':row['identity']['universe_id'],'record':RID(72)},'slot':'arrive'}
        self.forge(mutate)
    def test_restart_denial_disguised_as_receipt(self):
        def mutate(report,wire):report['restart_denied']=report['publications'][1]['receipt']
        self.forge(tree_mutation=mutate)
    def test_recovered_operation_receipt_forged(self):
        def mutate(report,wire):report['recovered_operations'][0]['result']['receipt']['revision']='rev_'+'0'*24
        self.forge(tree_mutation=mutate)
    def test_stale_context_claimed_as_fresh(self):
        def mutate(report,wire):report['factual_workflow']['stale_context_state']['frame']['revision']=report['snapshots']['kit-initialized']['canonical']['revision']
        self.forge(tree_mutation=mutate)
    def test_restricted_evidence_claimed_complete(self):
        def mutate(report,wire):report['factual_workflow']['restricted_state']['result']['objects'][0]['coverage']='complete'
        self.forge(tree_mutation=mutate)
    def test_initialization_receipt_source_forged(self):
        def mutate(report,wire):report['factual_workflow']['after_initialization']['result']['objects'][0]['initialization_receipts'][0]['definition']='ver_'+'0'*24
        self.forge(tree_mutation=mutate)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a,rest=p.parse_known_args();EVIDENCE=a.evidence;unittest.main(argv=['test_resource_resolution_audit.py',*rest])
