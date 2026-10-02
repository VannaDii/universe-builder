"""Independent JSON Schema checks of standalone assessment contracts.

Accounting, UTF-8 and retained-material checks are exercised by Rust tests;
JSON Schema only validates closed structural shapes and supported variants.
"""
import copy
import json
import hashlib
import subprocess
import unittest
from pathlib import Path
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]

class SourceAssessmentContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.examples = json.loads((ROOT / 'docs/decisions/d03-d08/examples.json').read_text())
        cls.schemas = json.loads((ROOT / 'contracts/source-assessments.json').read_text())
        cls.validators = {}
        for name, schema in cls.schemas.items():
            Draft202012Validator.check_schema(schema)
            cls.validators[name] = Draft202012Validator(schema)

    def test_approved_complete_shapes(self):
        for example in [self.examples, self.examples['production_bound_example']]:
            for name, value in [('body', example['assessment']['body']), ('envelope', example['assessment']), ('selection', example['selection']), ('binding', example['final_binding'])]:
                with self.subTest(name=name):
                    self.validators[name].validate(value)
        self.validators['body'].validate(self.examples['unresolved_body_example'])
        self.validators['binding'].validate(self.examples['fresh_record_only_binding'])

    def test_independent_edge_fixture(self):
        fixture = json.loads((ROOT / 'fixtures/source-assessments/edge.json').read_text())
        self.validators['body'].validate(fixture['body'])
        raw = json.dumps(fixture['body'], sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
        self.assertEqual(raw.decode(), fixture['canonical_utf8'])
        preimage = b'source-assessment:v1:' + raw
        self.assertEqual(hashlib.sha256(preimage).hexdigest(), fixture['digest'])
        openssl = subprocess.run(['openssl', 'dgst', '-sha256'], input=preimage, capture_output=True, check=True).stdout.decode().split()[-1]
        self.assertEqual(openssl, fixture['digest'])

    def test_nullable_is_required_and_accepts_explicit_null(self):
        cases = [('body', self.examples['assessment']['body'], [('assessor', 'tool'), ('sources', 0, 'work_edition'), ('sources', 0, 'passage_id'), ('claim_mappings', 0, 'world'), ('claim_mappings', 0, 'realm')]), ('selection', self.examples['selection'], [('selected',)])]
        for name, example, paths in cases:
            for path in paths:
                valid = copy.deepcopy(example)
                parent = valid
                for key in path[:-1]: parent = parent[key]
                parent[path[-1]] = None
                self.validators[name].validate(valid)
                del parent[path[-1]]
                self.assertFalse(self.validators[name].is_valid(valid), path)

    def test_closed_shapes_and_self_reference(self):
        for name, example in [('body', self.examples['assessment']['body']), ('envelope', self.examples['assessment']), ('selection', self.examples['selection']), ('binding', self.examples['final_binding'])]:
            for key in ['unsupported', 'own_digest', 'final_binding_digest']:
                bad = copy.deepcopy(example)
                bad[key] = 'unapproved'
                self.assertFalse(self.validators[name].is_valid(bad))
        for path in [('assessor',), ('sources', 0), ('claim_mappings', 0), ('claim_mappings', 0, 'semantic')]:
            bad = copy.deepcopy(self.examples['assessment']['body'])
            parent = bad
            for key in path: parent = parent[key]
            parent['unsupported'] = True
            self.assertFalse(self.validators['body'].is_valid(bad))

    def test_bad_discriminators_digests_and_versions(self):
        cases = [(('kind',), 'source_assessment_v2'), (('proposal', 'digest'), 'A'*64), (('proposal', 'version'), 0), (('proposal', 'version'), 1.5), (('sources', 0, 'representation'), 'url'), (('sources', 0, 'source_version', 'version'), 'head'), (('claim_mappings', 0, 'semantic', 'kind'), 'compiled_prose')]
        for path, value in cases:
            bad = copy.deepcopy(self.examples['assessment']['body'])
            parent = bad
            for key in path[:-1]: parent = parent[key]
            parent[path[-1]] = value
            self.assertFalse(self.validators['body'].is_valid(bad), path)

    def test_limits(self):
        for key, limit in [('sources', 64), ('dependencies', 16384), ('declared_inventory', 4096), ('claim_mappings', 4096), ('unresolved', 4096)]:
            bad = copy.deepcopy(self.examples['assessment']['body'])
            bad[key] = [bad[key][0] if bad[key] else {}] * (limit+1)
            self.assertFalse(self.validators['body'].is_valid(bad), key)
        bad = copy.deepcopy(self.examples['assessment']['body'])
        bad['inventory_declaration']['rationale'] = 'a'*16385
        self.assertFalse(self.validators['body'].is_valid(bad))

if __name__ == '__main__':
    unittest.main()
