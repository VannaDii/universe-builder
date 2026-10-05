"""Current public-MCP probes for knowledge, communication and global counts.

The classifications are independently authored challenge cases. The pilot
records whether current admission distinguishes them; clean admission of a
challenge is evidence of a missing declared contract, not a green result.
"""
import argparse
import json
from pathlib import Path
import sqlite3
import tempfile
import time

from canonical_families_pilot import FamilySession, authority_counts, restart
from continuity_gap_pilot import build_identity, save
from pilot_support import NAME


def run(output: Path, bin_dir: Path):
    output.mkdir(parents=True, exist_ok=False)
    report = {"status": "running", "cases": [], "build": build_identity(bin_dir, {})}
    began = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="ub-g34-", dir="/tmp") as root:
        with (output / "mcp-transcript.jsonl").open("w") as wire:
            s = FamilySession(root, bin_dir, report, wire=wire)
            try:
                s.start()
                report["installation"] = s.u
                world = s.rid(60).replace("rec_", "wld_")
                scope = {"context": {"universe": s.uid, "record": s.u["context_id"]},
                         "applicability": {"kind": "universe_wide"}}

                def instance(n, label):
                    return {"kind": "introduce_instance", "client_ref": s.rid(n),
                            "name": {"text": label, "validity": s.interval(0)},
                            "classification": None,
                            "world_associations": [{"world": world, "role": "setting",
                                "validity": s.interval(0), "qualifiers": {}}]}

                def prop(n, key, shape):
                    return {"kind": "define_property", "client_ref": s.rid(n),
                            "record": {"namespace": "g34", "key": key, "labels": {},
                                "subjectTypes": [], "value": shape, "multiplicity": "single",
                                "persistence": "explicit_interval", "exclusive": False,
                                "symmetric": False, "transitive": False}}

                def proposition(n, subject, predicate, value):
                    return {"kind": "define_proposition", "client_ref": s.rid(n),
                            "record": {"subject": s.rr(subject), "predicate": s.rr(predicate),
                                "value": value, "roles": [], "quantification": "particular",
                                "context": s.rr(s.u["context_id"])}}

                def assertion(n, proposition_id, polarity="support", validity=None, precision="exact"):
                    return {"kind": "assert_proposition", "client_ref": s.rid(proposition_id),
                            "proposition": {"subject": s.rr(1), "predicate": s.rr(10),
                                "value": {"kind": "boolean", "value": True}, "roles": [],
                                "quantification": "particular", "context": s.rr(s.u["context_id"])},
                            "assertion": {"attributeMode": "instance", "proposition": s.rr(proposition_id), "polarity": polarity,
                                "scope": scope, "validity": validity or s.interval(5),
                                "persistence": "explicit_interval", "precision": precision,
                                "basis": {"kind": "author_decision", "note": "Goal 34 probe"}}}

                def evaluate(case_id, family, classification, operations):
                    before = authority_counts(s)
                    head = s.open()["frame"]["revision"]
                    p = s.propose(operations, "g34-" + case_id)
                    v = s.validate(p)
                    row = {"id": case_id, "family": family, "oracle_class": classification,
                           "proposal": p, "validation": v, "before": before,
                           "head_before": head}
                    if v["coverage"] == "complete" and not v["findings"]:
                        approval = s.approval(p, v, check=False)
                        row["approval_returncode"] = approval.returncode
                        if approval.returncode == 0:
                            receipt = s.call("universe_commit", s.commit_args(p, v, "g34-commit-" + case_id))["result"]
                            row["receipt"] = receipt
                            row["admitted"] = True
                            s.open()
                        else:
                            row["admitted"] = False
                    else:
                        row["admitted"] = False
                    row["after"] = authority_counts(s)
                    row["head_after"] = s.open()["frame"]["revision"]
                    report["cases"].append(row)
                    return row

                setup = [
                    {"kind": "create_world", "client_ref": s.rid(60),
                     "record": {"selector": "Goal34", "labels": {}, "metadata": {}}},
                    instance(1, "Mara"), instance(2, "Iven"), instance(3, "Nera"),
                    prop(10, "fact", {"kind": "boolean"}),
                    prop(40, "counterpart", {"kind": "boolean"}),
                    {"kind": "define_relation", "client_ref": s.rid(41),
                     "record": {"namespace": "g34", "key": "exclusive_pair", "labels": {},
                         "roles": [{"name": "counterpart", "participantTypes": [],
                                    "multiplicity": "single", "ordered": False}]}},
                    assertion(20, 20, "refutation"),
                    proposition(22, 1, 10, {"kind": "boolean", "value": False}),
                ]
                seed = s.propose(setup, "g34-seed")
                s.publish(seed, "g34-seed-commit")

                def attitude(n, target, kind):
                    return {"kind": "add_belief", "client_ref": s.rid(n), "record": {
                        "holder": s.rr(2), "proposition": s.rr(target), "attitude": kind,
                        "certainty": None, "validity": s.interval(10),
                        "basis": {"kind": "author_decision", "note": "synthetic probe"}}}

                evaluate("knowledge-belief-legal", "knowledge", "legal",
                         [attitude(100, 20, "believes")])
                evaluate("knowledge-refuted-knows", "knowledge", "illegal-if-justified-policy",
                         [attitude(101, 20, "knows")])
                evaluate("knowledge-unknown-knows", "knowledge", "unresolved",
                         [attitude(102, 22, "knows")])

                def communication(n, sent, received, actual=True):
                    return {"kind": "record_communication", "client_ref": s.rid(n), "record": {
                        "sender": s.rr(1), "intendedRecipients": [s.rr(2)],
                        "actualRecipients": [s.rr(2)] if actual else [], "content": [s.rr(20)],
                        "channel": "ordinary letter", "sentAt": s.instant(sent),
                        "receivedAt": s.instant(received) if received is not None else None,
                        "distorted": False}}

                evaluate("communication-forward", "chronology", "legal", [communication(110, 5, 15)])
                evaluate("communication-reversed", "chronology", "illegal-if-forward-rule",
                         [communication(111, 15, 5)])
                evaluate("communication-unreceived", "chronology", "unresolved",
                         [communication(112, 5, None, actual=False)])

                def relation(n, target, start, end=None, precision="exact"):
                    valid = {"kind": "unknown"} if precision == "unresolved" else s.interval(start, end)
                    return {"kind": "record_relation", "client_ref": s.rid(n),
                        "proposition": {"subject": s.rr(1), "predicate": s.rr(41),
                            "value": None, "roles": [{"role": "counterpart", "participant": s.rr(target)}],
                            "quantification": "particular", "context": s.rr(s.u["context_id"])},
                        "assertion": {"attributeMode": "instance", "proposition": s.rr(n), "polarity": "support", "scope": scope,
                            "validity": valid, "persistence": "explicit_interval", "precision": precision,
                            "basis": {"kind": "author_decision", "note": "synthetic probe"}}}

                evaluate("cardinality-one-legal", "cardinality", "legal", [relation(120, 2, 0, 5)])
                evaluate("cardinality-overlap", "cardinality", "illegal-if-max-one",
                         [relation(121, 2, 5), relation(122, 3, 5)])
                evaluate("cardinality-unknown-validity", "cardinality", "unresolved",
                         [relation(123, 3, 5, precision="unresolved")])

                # Correct one admitted record in each family. Corrections use
                # explicit tombstones plus replacement records because the
                # public operation model does not expose family-specific edit
                # operations for attitudes and communications.
                def corrected_publish(key, operations):
                    before = authority_counts(s)
                    old_head = s.open()["frame"]["revision"]
                    p = s.propose(operations, "g34-correction-" + key)
                    v = s.validate(p)
                    assert v["coverage"] == "complete" and all(
                        finding["outcome"] == "supported" for finding in v["findings"]), v
                    approval = s.approval(p, v, check=False)
                    assert approval.returncode == 0, approval.stderr
                    receipt = s.call("universe_commit", s.commit_args(
                        p, v, "g34-correction-commit-" + key))["result"]
                    s.open()
                    row = {"key": key, "proposal": p, "validation": v,
                           "receipt": receipt, "head_before": old_head,
                           "head_after": s.open()["frame"]["revision"],
                           "counts_before": before, "counts_after": authority_counts(s)}
                    assert row["head_after"] != old_head and row["counts_after"] != before
                    report.setdefault("corrections", []).append(row)
                    return row

                def assertion_row(proposition_number):
                    package = s.root / "packages" / (s.uid + ".sqlite")
                    with sqlite3.connect(f"file:{package}?mode=ro", uri=True) as db:
                        ids = [row[0] for row in db.execute("SELECT record_id FROM head_membership")]
                    rows = [item for start in range(0, len(ids), 10)
                            for item in s.get(ids[start:start + 10])]
                    return next(item for item in rows
                                if item.get("payload", {}).get("record_kind") == "assertion"
                                and item["payload"]["proposition"]["record"] == s.rid(proposition_number))

                knowledge_old_revision = s.open()["frame"]["revision"]
                corrected_publish("knowledge", [
                    {"kind": "tombstone_record", "record": s.rr(101),
                     "expected_version": s.get([s.rid(101)])[0]["record_version_id"],
                     "rationale": "Correct attitude classification"},
                    attitude(103, 20, "believes")])
                communication_old_revision = s.open()["frame"]["revision"]
                corrected_publish("communication", [
                    {"kind": "tombstone_record", "record": s.rr(111),
                     "expected_version": s.get([s.rid(111)])[0]["record_version_id"],
                     "rationale": "Correct send and receipt chronology"},
                    communication(113, 5, 15)])
                cardinality_old_revision = s.open()["frame"]["revision"]
                extra_relation_assertion = assertion_row(122)
                corrected_publish("cardinality", [
                    {"kind": "tombstone_record",
                     "record": {"universe": s.uid,
                                "record": extra_relation_assertion["identity"]["record_id"]},
                     "expected_version": extra_relation_assertion["record_version_id"],
                     "rationale": "Remove the extra overlapping relation"}])
                report["correction_history"] = {
                    "knowledge_old_revision": knowledge_old_revision,
                    "communication_old_revision": communication_old_revision,
                    "cardinality_old_revision": cardinality_old_revision,
                    "historical_before_restart": {
                        "knowledge": s.get([s.rid(101)], s.open(knowledge_old_revision)["context_id"]),
                        "communication": s.get([s.rid(111)], s.open(communication_old_revision)["context_id"]),
                        "cardinality_first": s.get([assertion_row(121)["identity"]["record_id"]], s.open(cardinality_old_revision)["context_id"]),
                        "cardinality_second": s.get([extra_relation_assertion["identity"]["record_id"]], s.open(cardinality_old_revision)["context_id"]),
                    }}
                restart(s, report)
                report["correction_history"]["head_after_restart"] = s.open()["frame"]["revision"]
                report["correction_history"]["historical_after_restart"] = {
                    "knowledge": s.get([s.rid(101)], s.open(knowledge_old_revision)["context_id"]),
                    "communication": s.get([s.rid(111)], s.open(communication_old_revision)["context_id"]),
                    "cardinality_first": s.get([assertion_row(121)["identity"]["record_id"]], s.open(cardinality_old_revision)["context_id"]),
                    "cardinality_second": s.get([extra_relation_assertion["identity"]["record_id"]], s.open(cardinality_old_revision)["context_id"]),
                }
                s.open()
                package = s.root / "packages" / (s.uid + ".sqlite")
                with sqlite3.connect(f"file:{package}?mode=ro", uri=True) as db:
                    head_ids = {row[0] for row in db.execute("SELECT record_id FROM head_membership")}

                report["correction_history"]["current_after_restart"] = {
                    "knowledge_old_in_head": s.rid(101) in head_ids,
                    "knowledge_replacement": s.get([s.rid(103)]),
                    "communication_old_in_head": s.rid(111) in head_ids,
                    "communication_replacement": s.get([s.rid(113)]),
                    "cardinality_removed_assertion_in_head": extra_relation_assertion["identity"]["record_id"] in head_ids,
                    "cardinality_retained_assertion": s.get([assertion_row(121)["identity"]["record_id"]]),
                }
                report["status"] = "executed"
            finally:
                s.close()
                report["cleanup"] = {"engine_stopped": not (s.root / "engine.sock").exists()}
    report["cleanup"]["temporary_install_removed"] = not Path(root).exists()
    report["seconds"] = time.monotonic() - began
    save(output / "report.json", report)
    print(f"Goal 34 public MCP probes: {report['status']} ({len(report['cases'])} cases)")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--bin-dir", type=Path, default=Path("target/debug"))
    a = p.parse_args()
    run(a.output, a.bin_dir.resolve())
