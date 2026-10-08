"""Opt-in MLX review of real MCP owning-entity/time evidence and action admission.

Synthetic canon only. Batch prose interpretation is scored independently against
the engine; no model verdict supplies authority. Retains raw outputs and failures.
"""
import argparse
import importlib.metadata
import json
from pathlib import Path
import tempfile
import traceback

from mlx_authoring_smoke import LocalModel, artifact_manifest, require
from pilot_support import NAME, PilotSession
from pilot_evidence import focused_evidence


def run(args, report):
    with tempfile.TemporaryDirectory(prefix="ub-powers-", dir="/tmp") as directory:
        s = PilotSession(directory, args.bin_dir, report).start()
        try:
            report["instructions"] = s.instructions
            ops = [{"kind": "create_entity", "client_ref": s.rid(n), "record": {
                "names": [], "classification": None, "classificationResolution": "unclassified", "worldAssociations": [], "labels": {"en": label}, "metadata": {}}}
                for n, label in ((1, "Mara"), (2, "Iven"), (3, "Nera"), (4, "Phase ring"), (5, "Probe"), (6, "Solid wall"))]
            for n, key, shape in ((10, "wall_phase", {"kind": "boolean"}),
                                  (11, "holder", {"kind": "entity_ref", "subject_types": []}),
                                  (12, "eye_colour", {"kind": "text"})):
                ops.append({"kind": "define_property", "client_ref": s.rid(n), "record": {
                    "namespace": "phase", "key": key, "labels": {}, "subjectTypes": [], "value": shape,
                    "multiplicity": "single", "persistence": "explicit_interval", "exclusive": True,
                    "symmetric": False, "transitive": False}})
            def premise(n, owner, predicate, value, start, end=None, polarity="support"):
                return {"kind": "assert_proposition", "client_ref": s.rid(n), "proposition": {
                    "subject": s.rr(owner), "predicate": s.rr(predicate), "value": value,
                    "context": s.scope["context"], "quantification": "particular"}, "assertion": {
                    "attributeMode": "instance", "proposition": s.rr(n), "polarity": polarity, "scope": s.scope,
                    "validity": s.interval(start, end), "persistence": "explicit_interval", "precision": "exact",
                    "basis": {"kind": "author_decision", "note": "Synthetic sci-fi pilot premise"}}}
            boolean = {"kind": "boolean", "value": True}
            ops += [premise(21, 1, 10, boolean, 10), premise(22, 5, 10, boolean, 10),
                    premise(23, 4, 11, {"kind": "entity_ref", "ref": s.rr(2)}, 10, 18),
                    premise(25, 2, 10, boolean, 13, 15, "refutation"),
                    premise(26, 1, 12, {"kind": "text", "text": "blue"}, 10, 16),
                    premise(27, 1, 12, {"kind": "text", "text": "red"}, 16),
                    {"kind": "define_proposition", "client_ref": s.rid(28), "record": {
                        "subject": s.rr(3), "predicate": s.rr(10), "value": boolean,
                        "context": s.scope["context"], "quantification": "particular"}},
                    {"kind": "define_item_power", "client_ref": s.rid(24), "record": {
                        "item": s.rr(4), "holderPredicate": s.rr(11), "powerPredicate": s.rr(10),
                        "value": boolean, "scope": s.scope, "validity": s.interval(10, 20)}}]
            for n, key, predicate, value in ((30, "wall_traversal", 10, boolean),
                                             (31, "blue_eyes_action", 12, {"kind": "text", "text": "blue"})):
                ops.append({"kind": "define_action", "client_ref": s.rid(n), "record": {
                    "namespace": "phase", "key": key, "labels": {}, "requirements": [
                        {"role": "actor", "predicate": s.rr(predicate), "value": value}],
                    "consequenceContract": {"kind": "action_consequences", "slots": []},
                    "scope": s.scope, "validity": {"kind": "unspecified"}}})
            s.publish(s.propose(ops, "power-premises"), "power-premises-commit")
            cases = [
                ("mara", 1, 12, 30, "Mara walks through the solid wall.", "usable"),
                ("ring_holder", 2, 12, 30, "Iven walks through the solid wall while holding the ring.", "usable"),
                ("muted", 2, 14, 30, "Iven walks through the solid wall during his power suppression.", "conflict"),
                ("restored", 2, 16, 30, "Iven walks through the solid wall after suppression ends.", "usable"),
                ("undeclared", 3, 12, 30, "Nera walks through the solid wall.", "unknown"),
                ("object", 5, 12, 30, "The probe passes through the solid wall.", "usable"),
                ("item_itself", 4, 12, 30, "The ring passes through the solid wall using its holder's power.", "unknown"),
                ("custody_ended", 2, 19, 30, "Iven walks through the wall after his ring custody ends.", "unknown"),
                ("expired", 2, 21, 30, "Iven walks through the wall after the ring grant expires.", "unknown"),
                ("blue_before", 1, 15, 31, "Mara's eyes are blue.", "usable"),
                ("red_after", 1, 17, 31, "Mara's eyes are blue after their canonical change to red.", "conflict"),
            ]
            evidence = []
            for key, owner, day, action, prose, expected in cases:
                ctx = s.open(day=day)["context_id"]
                state = s.call("universe_get_state", {"universe": NAME, "context_id": ctx,
                    "entity_ids": list(dict.fromkeys([s.rid(owner), s.rid(4)])), "predicate_filters": []})["result"]
                records = s.get([s.rid(n) for n in (1, 2, 3, 4, 5, 6, 10, 11, 12, 24, 30, 31)])
                evidence.append({"id": f"case_{len(evidence) + 1:02d}", "day": day, "owner": s.rr(owner), "prose": prose,
                    "active_attributes": focused_evidence(records + state["propositions"], [{"next": r} for r in state["assertions"]]),
                    "definitions_and_entities": records, "derived": state["derived"], "state": state})
                # Mandatory action requirement is tested without optional preconditions.
                p = s.propose([{"kind": "record_event", "client_ref": s.rid(100 + len(evidence)), "record": {
                    "occurrence": "occurred", "action": s.rr(action), "time": s.instant(day),
                    "participants": [{"record": s.rr(owner), "role": "actor"}], "preconditions": [],
                    "effects": [], "labels": {"en": prose}}}], "admission-" + key)
                if expected == "usable":
                    v = s.validate(p)
                    require(v["coverage"] == "complete" and not v["findings"], key)
                    if key == "restored":
                        s.publish(p, "restored-use-commit")
                else:
                    v = s.validate(p, error=True)
                    require("event.action.requirements" in json.dumps(v), key)
                report.setdefault("admissions", []).append({"id": key, "expected": expected, "validation": v})
            report["cases"] = evidence
            report["engine_assessment"] = {"status": "pass", "passed": len(cases), "total": len(cases)}
            if args.model:
                report["model_manifest"] = artifact_manifest(args.model)
                report["runtime"] = {name: importlib.metadata.version(name) for name in ("mlx", "mlx-lm", "transformers")}
                model = LocalModel(args.model, args.seed)
                messages = [{"role": "system", "content": s.instructions},
                    {"role": "user", "content": json.dumps({"task": "Review each prose case against its actual owning-entity evidence at the stated day. Return only one JSON object {verdicts:[{id,verdict,reason}]} in case order. verdict is usable (supported by active evidence), conflict (explicitly contradictory), or unknown (insufficient active evidence). Use the supplied records and time-scoped state as evidence.", "cases": evidence}, ensure_ascii=False)}]
                try:
                    result = model.ask("owner_attribute_review", messages, max_tokens=3200)
                    report["model_review"] = result
                    require(set(result) == {"verdicts"} and len(result["verdicts"]) == len(cases), "wrong verdict shape")
                    failures = []
                    for row, case, stimulus in zip(result["verdicts"], cases, evidence):
                        if row.get("id") != stimulus["id"] or row.get("verdict") != case[5]:
                            failures.append({"id": case[0], "expected": case[5], "actual": row})
                    report["model_assessment"] = {"passed": len(cases) - len(failures), "total": len(cases), "failures": failures}
                    require(not failures, f"model review failed {len(failures)}/{len(cases)} cases")
                finally:
                    report["model_metrics"] = model.metrics
            report["status"] = "pass"
        finally:
            s.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, default=Path("target/debug"))
    parser.add_argument("--model", type=Path)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.bin_dir = args.bin_dir.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    report = {"status": "running", "scope": "Synthetic declared vocabulary; actual MCP evidence/admission and batch MLX prose review, not arbitrary extraction or native host qualification"}
    try:
        run(args, report)
    except Exception as error:
        report.update(status="failure", error=f"{type(error).__name__}: {error}", traceback=traceback.format_exc())
        raise
    finally:
        (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps({"status": report["status"], "report": str(args.output / "report.json")}))


if __name__ == "__main__":
    main()
