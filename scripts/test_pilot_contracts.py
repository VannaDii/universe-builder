"""Current pilot operations and publication handling against disposable engines."""
import unittest
import json

class CurrentContractWorkflowTests(unittest.TestCase):
    def test_chapter_and_retcon_current_contracts_without_reports(self):
        import tempfile
        from pathlib import Path
        from types import SimpleNamespace
        from chapter_retcon_pilot import run
        with tempfile.TemporaryDirectory(prefix="ub-chapter-contract-") as directory:
            result = {}
            run(SimpleNamespace(regression=True, model=None, seed=42,
                                bin_dir=Path(__file__).resolve().parents[1] / "target/headless/local/bin",
                                output=Path(directory)), result)
            self.assertEqual(result["status"], "pass")
            self.assertTrue(all(result["checks"].values()))
            self.assertFalse((Path(directory) / "report.json").exists())

    def test_power_current_contracts_preserve_all_expected_outcomes(self):
        from pathlib import Path
        from types import SimpleNamespace
        from power_authoring_pilot import run
        result = {}
        run(SimpleNamespace(model=None, seed=42,
                            bin_dir=Path(__file__).resolve().parents[1] / "target/headless/local/bin"), result)
        self.assertEqual(result["engine_assessment"]["passed"], 11)
        self.assertEqual([r["expected"] for r in result["admissions"]],
                         ["usable", "usable", "conflict", "usable", "unknown", "usable",
                          "unknown", "unknown", "unknown", "usable", "conflict"])
        self.assertNotIn("model_assessment", result)

    def test_mlx_operations_validation_and_exact_publication_bindings(self):
        import tempfile
        from pathlib import Path
        from pilot_support import PilotSession, NAME
        from mlx_authoring_smoke import (setup_operations, claim_operation, commit_arguments,
                                         fixture_supported_values, validation_execution)
        with tempfile.TemporaryDirectory(prefix="ub-mlx-contract-", dir="/tmp") as directory:
            session = PilotSession(directory, Path(__file__).resolve().parents[1] / "target/headless/local/bin", {})
            try:
                session.start()
                claim = lambda n, subject, predicate, value, start=0, end=None: claim_operation(
                    session.rid, session.rr, session.scope, session.interval,
                    n, subject, predicate, value, start, end)
                setup = setup_operations(session.rid, session.rr, session.scope, claim)
                p = session.propose(setup, "mlx-setup")
                v = session.validate(p)
                self.assertEqual(v["coverage"], "complete")
                self.assertEqual(v["findings"], [])
                args = commit_arguments(NAME, p, v, "mlx-setup-commit")
                session.client.schemas["universe_commit"][0].validate(args)
                self.assertEqual(args["proposal_reference"], session.reference(p))
                session.call("universe_commit", args, error=True)
                self.assertEqual(json.loads(session.approval(p, v).stdout),
                                 {"approved": session.reference(p), "validation_run": v["run_id"]})
                receipt = session.call("universe_commit", args)["result"]
                self.assertEqual(session.call("universe_commit", args)["result"], receipt)
                session.open()
                for day in (16, 17, 18):
                    state = session.state([session.rid(n) for n in (1, 2, 3)], day)
                    self.assertEqual(fixture_supported_values(state, session.rid(11)),
                                     [{"kind": "entity_ref", "ref": session.rr(1 if day < 17 else 2)}])
                bad = session.propose([claim(30, 1, 10, {"kind": "text", "text": "blue"})], "mlx-conflict")
                checked = session.validate(bad)
                self.assertTrue(any(f["outcome"] == "conflicting" for f in checked["findings"]))
                self.assertNotEqual(session.approval(bad, checked, check=False).returncode, 0)
                session.call("universe_commit", session.commit_args(bad, checked, "mlx-conflict-commit"), error=True)
                source = Path(directory) / "selected-source.txt"
                source.write_text("Mara's blue eyes narrowed as Iven carried the seal on day sixteen.\n", encoding="utf-8")
                staged = session.admin("stage-source", NAME, "Contradictory test passage", source)
                self.assertFalse(staged["canonical"])
                source_only = session.propose(staged["operations"], "mlx-source")
                source_validation = session.call("universe_validate", {"mode": "proposal", "universe": NAME,
                    "context_id": session.ctx, "proposal_reference": session.reference(source_only),
                    "check_scope": "universe"})
                self.assertEqual(validation_execution(source_validation)["coverage"], "complete")
                self.assertEqual(validation_execution(source_validation)["findings"], [])
                self.assertTrue(source_validation["result"]["submitted_input"]["includes_sources"])
                self.assertEqual(source_validation["result"]["assessment"]["kind"], "absent")
                source.write_text("Mara was thirty years old.\n", encoding="utf-8")
                staged = session.admin("stage-source", NAME, "Selected test passage", source)
                other = session.propose([*staged["operations"], claim(40, 1, 13, {"kind": "integer", "digits": "30"})], "mlx-selected")
                self.assertNotEqual(session.approval(other, checked, check=False).returncode, 0)
                session.publish(other, "mlx-selected-commit")
                self.assertEqual(fixture_supported_values(session.state([session.rid(1)], 18), session.rid(13)),
                                 [{"kind": "integer", "digits": "30"}])
            finally:
                session.close()
        for result in ({"kind": "restricted"}, {"kind": "evaluated", "execution": {}}):
            with self.assertRaises(RuntimeError):
                validation_execution({"result": result})
        v = {"run_id": "unchanged", "coverage": "partial"}
        self.assertIs(validation_execution({"result": {"kind": "evaluated", "execution": v,
                                                      "final_binding_digest": None}}), v)


if __name__ == "__main__":
    unittest.main()
