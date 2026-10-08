"""Fast harness regressions; no model, Metal, subprocess, or universe required."""
import copy
import unittest

from mlx_authoring_smoke import NAME, dispatch, exact_model_decision, fixture_supported_values, parse_object, require, score_verdicts
from validate_contracts import validators


class Client:
    def __init__(self):
        self.schemas = validators()
        self.calls = []

    def call(self, name, args):
        self.calls.append((name, args))
        return {"complete": True}


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.client = Client()
        self.context = "ctx_000000000000000000000001"
        self.focus = ["rec_000000000000000000000001"]
        self.decision = {"tool": "universe_get_context", "arguments": {
            "universe": NAME, "context_id": self.context, "focus_ids": self.focus,
            "purpose": "Retrieve explicit canon", "byte_budget": 65536}}

    def test_exact_json_and_no_code_execution(self):
        self.assertEqual(parse_object('{"tool":"research"}'), {"tool": "research"})
        for value in ('[]', 'null', '```json\n{}\n```', '{} trailing', '__import__("os")'):
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                parse_object(value)

    def test_checks_survive_python_optimization(self):
        with self.assertRaises(RuntimeError):
            require(False, "failed")

    def test_valid_research_dispatches_once(self):
        result = dispatch(self.client, self.decision, self.context, self.focus)
        self.assertTrue(result["complete"])
        self.assertEqual(len(self.client.calls), 1)

    def test_unsafe_or_unpinned_calls_never_dispatch(self):
        changes = [
            ("tool", "universe_commit"),
            ("universe", "A different universe"),
            ("context_id", "ctx_000000000000000000000002"),
            ("focus_ids", []),
            ("cursor", "forged-page"),
            ("byte_budget", 65537),
            ("approved", True),
        ]
        for field, value in changes:
            decision = copy.deepcopy(self.decision)
            target = decision if field == "tool" else decision["arguments"]
            target[field] = value
            with self.subTest(field=field), self.assertRaises(Exception):
                dispatch(self.client, decision, self.context, self.focus)
            self.assertEqual(self.client.calls, [])

    def test_partial_subject_research_never_dispatches(self):
        with self.assertRaises(ValueError):
            dispatch(self.client, self.decision, self.context,
                     self.focus + ["rec_000000000000000000000002"])
        self.assertEqual(self.client.calls, [])

    def test_extra_top_level_fields_never_dispatch(self):
        self.decision["approval"] = True
        with self.assertRaises(ValueError):
            dispatch(self.client, self.decision, self.context, self.focus)
        self.assertEqual(self.client.calls, [])

    def test_wrong_verdict_is_a_failure(self):
        cases = [{"id": "a", "sentence": "Blue eyes", "expected": "conflict"}]
        rows = score_verdicts({"verdicts": [{"id": "a", "verdict": "consistent"}]}, cases)
        self.assertFalse(rows[0]["correct"])

    def test_case_identity_is_total_and_unique(self):
        cases = [{"id": "a", "sentence": "Green eyes", "expected": "consistent"}]
        invalid = [[], [{"id": "a"}, {"id": "a"}], [{"id": "invented"}], ["a"]]
        for rows in invalid:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                score_verdicts({"verdicts": rows}, cases)

    def test_scoring_uses_case_identity_not_model_order(self):
        cases = [{"id": "a", "sentence": "Green eyes", "expected": "consistent"},
                 {"id": "b", "sentence": "Blue eyes", "expected": "conflict"}]
        result = {"verdicts": [{"id": "b", "verdict": "conflict"},
                               {"id": "a", "verdict": "consistent"}]}
        self.assertTrue(all(row["correct"] for row in score_verdicts(result, cases)))

    def test_proposition_existence_does_not_establish_active_truth(self):
        state = {"result": {"propositions": [
            {"identity": {"record_id": "old"}, "payload": {"predicate": {"record": "holder"}, "value": "Mara"}},
            {"identity": {"record_id": "new"}, "payload": {"predicate": {"record": "holder"}, "value": "Iven"}}],
            "assertions": [{"payload": {"proposition": {"record": "new"}, "polarity": "support"}}]}}
        self.assertEqual(fixture_supported_values(state, "holder"), ["Iven"])
        state["result"]["assertions"][0]["payload"]["polarity"] = "refute"
        self.assertEqual(fixture_supported_values(state, "holder"), [])

    def test_explicit_model_repair_is_bounded_and_recorded(self):
        class Model:
            def __init__(self, responses):
                self.responses = iter(responses)
                self.calls = 0

            def ask(self, *args, **kwargs):
                self.calls += 1
                return next(self.responses)

        expected = {"operations": [{"kind": "assert_proposition"}]}
        model = Model([{"operations": [{"kind": "universe_propose"}]}, expected])
        report = {}
        self.assertEqual(exact_model_decision(model, "claim", [], expected, report), expected)
        self.assertEqual(model.calls, 2)
        self.assertEqual(len(report["model_repairs"]), 1)
        self.assertEqual(report["directed_execution"], [{"task": "claim", "attempts": 2,
            "answer_supplied": True, "included_in_independent_scores": False}])
        self.assertNotIn("model_score", report)
        self.assertNotIn("workflow_score", report)
        model = Model([{}, {}])
        with self.assertRaises(RuntimeError):
            exact_model_decision(model, "claim", [], expected, {})
        self.assertEqual(model.calls, 2)


if __name__ == "__main__":
    unittest.main()
