"""Independent response fixture checks; no producer result generator imported."""
import copy
import json
import unittest
from pathlib import Path
from jsonschema import Draft202012Validator
ROOT=Path(__file__).resolve().parents[1]
class ScopeContracts(unittest.TestCase):
    def test_restricted_exact_shape_and_negative_controls(self):
        tools=json.loads((ROOT/'contracts/tools.json').read_text())
        schema=next(t['output_schema'] for t in tools if t['name']=='universe_validate')
        # Validate the owned wrapper itself, independent of envelope/frame construction.
        wrapper=schema['$defs']['ValidationV3']
        validator=Draft202012Validator({**wrapper,'$defs':schema['$defs']})
        expected=json.loads((ROOT/'fixtures/validation-scope/expected.json').read_text())['restricted']
        validator.validate(expected)
        for key in ['execution','run_id','input_digest','proposal','assessment_reference','final_binding_digest','inventory_count','cursor','reason']:
            bad=copy.deepcopy(expected);bad[key]='private'
            self.assertFalse(validator.is_valid(bad),key)
        for field in ['assessment','submitted_input']:
            bad=copy.deepcopy(expected);bad[field]['digest']='private'
            self.assertFalse(validator.is_valid(bad),field)
    def test_approved_query_nullable_binding_and_bad_digest(self):
        schema=next(t['output_schema'] for t in json.loads((ROOT/'contracts/tools.json').read_text()) if t['name']=='universe_validate')
        validator=Draft202012Validator({**schema['$defs']['ValidationV3'],'$defs':schema['$defs']})
        query=json.loads((ROOT/'docs/decisions/d03-d08/examples.json').read_text())['query_result']
        validator.validate(query)
        missing=copy.deepcopy(query);del missing['final_binding_digest']
        self.assertFalse(validator.is_valid(missing))
        query['final_binding_digest']='a'*63
        self.assertFalse(validator.is_valid(query))
    def test_approved_assessed_reporting_fixture(self):
        schema=next(t['output_schema'] for t in json.loads((ROOT/'contracts/tools.json').read_text()) if t['name']=='universe_validate')
        validator=Draft202012Validator({**schema['$defs']['ValidationV3'],'$defs':schema['$defs']})
        fixture=json.loads((ROOT/'docs/decisions/d03-d08/examples.json').read_text())['validation_v3']
        validator.validate(fixture)
        del fixture['submitted_input']['sources'][0]['source_version']['universe']
        self.assertFalse(validator.is_valid(fixture))
if __name__=='__main__':unittest.main()
