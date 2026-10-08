"""Pure extraction regressions. Persistent graph checks run via --regression."""
import unittest
import json

from chapter_retcon_pilot import Writer, audit_known_pilot_prose, manuscript, validate_extraction, validate_scenes
from pilot_support import excerpt_locator
from pilot_evidence import focused_evidence


class PassageTests(unittest.TestCase):
    def test_review_uses_canonical_guidance_and_does_not_repair_a_negative_judgment(self):
        class Session:
            instructions = "Delivered canonical serving guidance"
        class Model:
            calls = []
            def ask(self, task, messages, **kwargs):
                self.calls.append((task, messages))
                return {"usable_after_commit": False, "issues": ["Missing support"]}
        model = Model()
        writer = Writer(model, Session(), {})
        canon = {"research_records": {"records": []}, "state": {"assertions": []}}
        with self.assertRaises(RuntimeError):
            writer.verify([], {}, canon)
        self.assertEqual(len(model.calls), 1)
        messages = model.calls[0][1]
        self.assertEqual(messages[0], {"role": "system", "content": Session.instructions})
        data = json.loads(messages[1]["content"])
        self.assertEqual(data["located_inventory_excerpts"], {})
        self.assertEqual(data["canon"], canon)
        self.assertNotIn("required_response", data)
        self.assertNotIn("expected", data)

    def test_supplied_call_execution_is_excluded_from_independent_scores(self):
        class Session:
            instructions = "Delivered canonical serving guidance"
        class Model:
            def ask(self, task, messages, **kwargs):
                self.messages = messages
                return json.loads(messages[1]["content"])["required_call"]
        report, model = {}, Model()
        args = {"universe": "synthetic", "context_id": "pinned"}
        result = Writer(model, Session(), report).decision("research", "universe_get_context", args)
        self.assertEqual(result, {"tool": "universe_get_context", "arguments": args})
        self.assertEqual(model.messages[0]["content"], Session.instructions)
        self.assertFalse(report["directed_execution"][0]["included_in_independent_scores"])

    def test_focused_evidence_keeps_polarity_and_exact_candidate_knowledge(self):
        ref = lambda n: {"record": n, "universe": "u"}
        record = lambda n, p: {"identity": {"record_id": n}, "record_version_id": "v-" + n, "payload": p}
        records = [record("mara", {"record_kind": "entity", "labels": {"en": "Mara"}}),
                   record("map", {"record_kind": "entity", "labels": {"en": "Map"}}),
                   record("route", {"record_kind": "property", "namespace": "pilot", "key": "route"}),
                   record("prop", {"record_kind": "proposition", "subject": ref("map"),
                       "predicate": ref("route"), "value": {"kind": "text", "text": "quarry tunnel"}, "context": ref("mara-context")})]
        claim = record("refutation", {"record_kind": "assertion", "proposition": ref("prop"),
            "polarity": "refute", "validity": {"end": "15"}, "scope": {}, "basis": {}})
        knowledge = record("knowledge", {"record_kind": "epistemic_attitude", "holder": ref("mara"),
            "proposition": ref("prop"), "attitude": "knows", "validity": {"start": "15"}, "basis": {}})
        rows = focused_evidence(records, [{"next": claim}, {"next": knowledge}, {"next": None}])
        self.assertEqual(rows[0]["polarity"], "refute")
        self.assertEqual(rows[1]["holder"]["label"], "Mara")
        self.assertEqual(rows[1]["proposition"]["predicate"], "pilot:route")
        self.assertEqual(rows[1]["record_version"], "v-knowledge")
        self.assertEqual(rows[1]["validity"], {"start": "15"})

    def test_known_continuity_misses_are_rejected_before_source_selection(self):
        with self.assertRaises(RuntimeError):
            audit_known_pilot_prose([{"id": 3, "text": "He folded the map carefully, tucking it into his pocket."}])
        for text in ("The heavy door groaned shut behind them. Mara now knew the route.",
                     "Iven closed the door. Mara understood the route.",
                     "The quarry tunnel was the only way forward. Mara knew it.",
                     "It is a route among others. Mara understood it.",
                     "Iven pointed toward the tunnel. Mara understood the route. They were ready.",
                     "Iven led Mara out. The floor drops off here; the edges are unstable. Mara understood.",
                     "Iven told her the route and gestured toward the tunnel."):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                audit_known_pilot_prose([{"id": 4, "text": text}])
        text = "The door stood open. Iven led Mara out toward the tunnel. Mara repeated the route; Mara now understood it."
        self.assertTrue(audit_known_pilot_prose([{"id": 4, "text": text}]))
        dialogue = 'Iven led Mara out. Mara studied the marked route. "I understand," she said. The door remained open.'
        self.assertTrue(audit_known_pilot_prose([{"id": 4, "text": dialogue}]))
        alternative = "Mara stepped forward and moved out through the doorway. Iven walked beside her and explained the route. She understood."
        self.assertTrue(audit_known_pilot_prose([{"id": 4, "text": alternative}]))

    def test_unicode_offsets_are_exact_utf8_without_normalization(self):
        text = "Préface 🌙 e\u0301\nIven’s clé opens.\nFin."
        excerpt = "Iven’s clé opens."
        loc = excerpt_locator(text, excerpt)
        self.assertEqual(text.encode()[loc["start"]:loc["end"]], excerpt.encode())
        self.assertNotEqual(loc["start"], text.index(excerpt))

    def test_duplicate_and_normalized_excerpt_rejected(self):
        for text, excerpt in (("same same", "same"), ("banana", "ana"), ("e\u0301", "é"), ("text", "")):
            with self.subTest(excerpt=excerpt), self.assertRaises(RuntimeError):
                excerpt_locator(text, excerpt)

    def test_extract_requires_every_material_change_once(self):
        scenes = [{"id": 1, "day": 12, "text": "A unique handoff. A distinct password."}]
        claims = [{"kind": "handoff", "scene": 1, "day": 12, "excerpt": "A unique handoff."},
                  {"kind": "password", "scene": 1, "day": 12, "excerpt": "A distinct password."}]
        self.assertEqual(set(validate_extraction({"claims": claims}, scenes)), {"handoff", "password"})
        for rows in (claims[:1], claims + claims[:1], claims + [{**claims[0], "kind": "injury"}]):
            with self.subTest(rows=rows), self.assertRaises(RuntimeError):
                validate_extraction({"claims": rows}, scenes)

    def test_wrong_time_scene_or_rewritten_quote_rejected(self):
        scenes = [{"id": 2, "day": 13, "text": "Iven opened the door."}]
        row = {"kind": "opening", "scene": 2, "day": 13, "excerpt": scenes[0]["text"]}
        for change in ({"day": 14}, {"scene": 1}, {"excerpt": "Iven opens the door."}):
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                validate_extraction({"claims": [{**row, **change}]}, scenes)

    def test_scene_chronology_and_ids_are_checked_before_staging(self):
        row = {"id": 2, "day": 13, "text": "word " * 35}
        self.assertEqual(validate_scenes({"scenes": [row]}, [13], [2]), [row])
        with self.assertRaises(RuntimeError):
            validate_scenes({"scenes": [row]}, [15], [2])
        with self.assertRaises(RuntimeError):
            validate_scenes({"scenes": [row, row]}, [13, 13], [2, 3])
        self.assertTrue(manuscript([row]).endswith("\n"))


if __name__ == "__main__":
    unittest.main()
