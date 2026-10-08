"""Delivery checks accept edited guidance and validate the actual public catalog."""
import copy
import json
import unittest
from mcp_smoke import check_server_contract
from validate_contracts import ROOT


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.initialization = {'instructions': 'Newly edited serving guidance.'}
        self.tools = [{'name': t['name'], 'description': t['description'],
                       'inputSchema': t['input_schema'], 'outputSchema': t['output_schema']}
                      for t in json.loads((ROOT / 'contracts/tools.json').read_text())]

    def test_guidance_wording_and_tool_order_can_change(self):
        check_server_contract(self.initialization, list(reversed(self.tools)))

    def test_missing_guidance_and_wrong_catalog_fail(self):
        for guidance in (None, '', '  ', []):
            with self.subTest(guidance=guidance), self.assertRaises(AssertionError):
                check_server_contract({'instructions': guidance}, self.tools)
        for tools in (self.tools[:-1], self.tools + self.tools[:1],
                      [*self.tools[:-1], self.tools[0]]):
            with self.assertRaises(AssertionError):
                check_server_contract(self.initialization, tools)

    def test_changed_or_invalid_delivered_schema_fails(self):
        for schema in ({'type': 'invalid-type'}, {'type': 'object'}):
            tools = copy.deepcopy(self.tools)
            tools[0]['inputSchema'] = schema
            with self.assertRaises(Exception):
                check_server_contract(self.initialization, tools)


if __name__ == '__main__':
    unittest.main()
