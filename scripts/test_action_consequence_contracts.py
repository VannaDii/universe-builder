"""Independent schema and SHA-256 proofs; no production serializer is imported.

Schema covers closed shapes and scalar/collection bounds. Relational invariants,
UTF-8 byte limits and i128 numeric limits are checked by the owning Rust decoder.
"""
import copy
import hashlib
import json
import subprocess
import unittest
from pathlib import Path
from jsonschema import Draft202012Validator
ROOT = Path(__file__).resolve().parents[1]
class ActionConsequenceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = json.loads((ROOT/'fixtures/action-consequences/payload-digests.json').read_text())
        cls.normative = {row['name']:row for row in json.loads((ROOT/'fixtures/normalized-foundation/historical-digests.json').read_text())}
        cls.validators=[]
        for tool in json.loads((ROOT/'contracts/tools.json').read_text()):
            for direction in ['input_schema','output_schema']:
                schema=tool[direction]
                if 'ActionDefinition' in schema.get('$defs',{}):
                    selected={'$schema':schema['$schema'],'$defs':schema['$defs'],'$ref':'#/$defs/ActionDefinition'}
                    Draft202012Validator.check_schema(selected)
                    cls.validators.append(Draft202012Validator(selected))
        assert cls.validators
    def action(self,index=3):
        # Schema checks use the already frozen normative oracle. Original input
        # vectors remain unchanged and retain their separately verified recipe.
        payload=copy.deepcopy(self.normative[self.fixtures[index]['name']]['payload']);del payload['record_kind'];return payload
    def valid(self,payload):
        return all(v.is_valid(payload) for v in self.validators)
    def test_all_action_examples_match_every_generated_action_schema(self):
        for n in [0,2,3,4,5,6]:
            for validator in self.validators: validator.validate(self.action(n))
    def test_independent_canonical_bytes_and_two_digest_implementations(self):
        for fixture in self.fixtures:
            raw=json.dumps(fixture['payload'],ensure_ascii=False,sort_keys=True,separators=(',',':'))
            self.assertEqual(raw,fixture['canonical_utf8'])
            preimage=(fixture['payload']['record_kind']+':v1:v1:'+raw).encode()
            self.assertEqual(hashlib.sha256(preimage).hexdigest(),fixture['digest'])
            openssl=subprocess.run(['openssl','dgst','-sha256'],input=preimage,capture_output=True,check=True).stdout.decode().split()[-1]
            self.assertEqual(openssl,fixture['digest'])
            normative=self.normative[fixture['name']]
            self.assertEqual(normative['source_digest'],fixture['digest'])
            raw=json.dumps(normative['payload'],ensure_ascii=False,sort_keys=True,separators=(',',':'))
            self.assertEqual(raw,normative['canonical_utf8'])
            preimage=(normative['payload']['record_kind']+':'+raw).encode()
            self.assertEqual(hashlib.sha256(preimage).hexdigest(),normative['normative_digest'])
            openssl=subprocess.run(['openssl','dgst','-sha256'],input=preimage,capture_output=True,check=True).stdout.decode().split()[-1]
            self.assertEqual(openssl,normative['normative_digest'])
    def test_absent_empty_and_explicit_null(self):
        self.assertTrue(self.valid(self.action(0)))
        self.assertTrue(self.valid(self.action(2)))
        bad=self.action();bad['consequenceContract']=None;self.assertFalse(self.valid(bad))
    def test_closed_nested_shapes_and_required_fields(self):
        for index in [3,5]:
            for path in [(),('consequenceContract',),('consequenceContract','slots',0),('consequenceContract','slots',0,'target'),('consequenceContract','slots',0,'change'),('consequenceContract','slots',0,'condition'),('consequenceContract','slots',0,'lifetime')]:
                original=self.action(index); obj=original
                for key in path: obj=obj[key]
                keys=list(obj)
                for removed in [None]+keys:
                    bad=copy.deepcopy(original);parent=bad
                    for key in path:parent=parent[key]
                    if removed is None:parent['unsupported']=True
                    elif removed=='consequenceContract':continue # absent is historical
                    else:del parent[removed]
                    self.assertFalse(self.valid(bad),(path,removed))
    def test_bad_versions_variants_bounds_and_nullable_unit(self):
        bad=self.action();bad['consequenceContract']['kind']='action_consequences_v2';self.assertFalse(self.valid(bad))
        for path,value in [(('presence',),'permitted'),(('change','kind'),'expression'),(('condition','kind'),'guess'),(('lifetime','kind'),'forever'),(('order',),64),(('order',),-1),(('order',),1.5),(('slot',),''),(('slot',),'x'*121),(('target','role'),''),(('change','delta'),'+1'),(('change','delta'),'-0'),(('change','delta'),'01'),(('change','delta'),1),(('change','unit'),'bad')]:
            bad=self.action();parent=bad['consequenceContract']['slots'][0]
            for key in path[:-1]:parent=parent[key]
            parent[path[-1]]=value
            self.assertFalse(self.valid(bad),(path,value))
        bad=self.action();bad['consequenceContract']['slots']*=65;self.assertFalse(self.valid(bad))
        self.assertTrue(self.valid(self.action())) # explicit unit null is required and valid
if __name__=='__main__':unittest.main()
