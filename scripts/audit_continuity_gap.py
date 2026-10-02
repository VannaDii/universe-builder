"""Independent, read-only proof audit; imports neither the runner nor pilot helpers.

Usage: python3 scripts/audit_continuity_gap.py EVIDENCE/run-a
Checks wire envelopes, persisted proposals/validations/approvals, commit inputs,
idempotent receipts, exact canonical changes, restart reads and source bytes.
"""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def normalize(value):
    """Only volatile identities, not story values, are erased in equivalence.

    Exact identity bindings are checked against SQLite before this projection.
    Fixed stimulus record IDs, polarity, time, participant and predicate roles,
    action IDs, effects, quotes and values remain present.
    """
    if isinstance(value, dict):
        return {k: "<import timestamp>" if k == "importTime" else normalize(v) for k, v in value.items()
                if k not in ("payload_digest", "record_version_id")}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, str) and re.fullmatch(r"(?:unv|cont|rev|ctx|cal|ver|prp|val|op|prn|rec)_[0-9a-f]+", value):
        if value.startswith("rec_00000000000000000003"):
            return value
        return value.split("_")[0] + "_<generated>"
    return value


def audit(directory):
    report = json.loads((directory / "report.json").read_text())
    oracle = json.loads((directory.parent / "oracle.json").read_text())
    baseline = json.loads((directory.parent / "baseline.json").read_text())
    identity = json.loads((directory.parent / "build-identity.json").read_text())
    check(report["status"] == "executed", "runner did not finish")
    check(hashlib.sha256((directory / "package.sqlite").read_bytes()).hexdigest() == report["package_sha256"],
          "package bytes differ from snapshot")
    check(identity["oracle_sha256"] == hashlib.sha256((directory.parent / "oracle.json").read_bytes()).hexdigest(),
          "oracle identity mismatch")
    check(identity["baseline_sha256"] == hashlib.sha256((directory.parent / "baseline.json").read_bytes()).hexdigest(),
          "baseline identity mismatch")
    expected = {r["id"]: r for r in oracle["cases"]}
    historical = {r["id"]: r for r in baseline["cases"]}
    cases = {r["id"]: r for r in report["probes"]}
    check(len(report["probes"]) == 13 and set(cases) == set(expected), "case set differs from frozen oracle")

    # Pair actual wire responses with sent requests across both MCP connections.
    frames = [json.loads(line) for line in (directory / "mcp-transcript.jsonl").read_text().splitlines()]
    calls, pending, sessions = [], {}, 0
    for line_number, entry in enumerate(frames, 1):
        frame = entry["frame"]
        if entry["direction"] == "sent":
            if frame.get("method") == "initialize":
                check(not pending, "restart abandoned a request")
                sessions += 1
            if "id" in frame:
                check(frame["id"] not in pending, "duplicate pending wire id")
                pending[frame["id"]] = (frame, line_number)
        elif "id" in frame:
            check(frame["id"] in pending, "wire response has no request")
            request, start = pending.pop(frame["id"])
            check("error" not in frame, "unexpected JSON-RPC error")
            if request["method"] == "tools/call":
                response = frame["result"]
                text = "".join(c["text"] for c in response["content"] if c["type"] == "text")
                check(json.loads(text) == response["structuredContent"], "text and structured wire result differ")
                calls.append({"tool": request["params"]["name"], "arguments": request["params"]["arguments"],
                              "expected_error": bool(response.get("isError", False)),
                              "result": response["structuredContent"],
                              "wire_lines": [start, line_number], "session": sessions})
    check(not pending and sessions == 2, "missing response or restart connection")
    check([{k:v for k,v in call.items() if k not in ("wire_lines", "session")} for call in calls] == report["mcp"],
          "runner evidence does not match actual wire transcript")
    check(report["baseline_mcp_calls"] == 42, "original baseline call sequence changed")

    with closing(sqlite3.connect(f"file:{directory / 'package.sqlite'}?mode=ro&immutable=1", uri=True)) as db:
        db.row_factory = sqlite3.Row
        check(db.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "SQLite integrity failure")
        check(not db.execute("PRAGMA foreign_key_check").fetchall(), "foreign-key failure")
        workflow = {}
        for row in db.execute("SELECT key,payload,digest FROM workflow_entries"):
            value = json.loads(row["payload"])
            check(digest(value) == row["digest"], "workflow digest mismatch: " + row["key"])
            workflow[row["key"]] = value
        universe_id = db.execute("SELECT id FROM universes").fetchone()[0]
        check(universe_id == report["installation"]["universe_id"], "package universe mismatch")
        versions = {r["id"]: json.loads(r["payload"]) for r in db.execute("SELECT id,payload FROM record_versions")}
        membership = {r["record_id"]: r["version_id"] for r in db.execute("SELECT record_id,version_id FROM head_membership")}

        def stored_proposal(p):
            value = workflow[f"proposal:{p['proposal_id']}:{p['version']:020}"]
            check(value["proposal"] == p, "proposal differs from durable workflow")
            check(any(c["tool"] == "universe_propose" and not c["expected_error"]
                      and c["result"]["result"] == p for c in calls), "proposal differs from wire result")
            return value

        def stored_validation(p, v):
            value = workflow[f"validation:{v['run_id']}"]
            check(value["proposal_digest"] == p["digest"] and value["validation"] == v,
                  "validation not pinned to exact proposal")
            check(any(c["tool"] == "universe_validate" and not c["expected_error"]
                      and c["result"]["result"].get("execution", c["result"]["result"]) == v for c in calls), "validation differs from wire result")
            return value

        def approvals(p, v):
            return [(k,a) for k,a in workflow.items() if k.startswith("approval:")
                    and k.endswith(f":{p['digest']}:{v['run_id']}")]

        # Publications are checked against kernel receipts and exact SQL changes.
        publication_by_revision, persisted_payloads = {}, {}
        for pub in report["publications"]:
            receipt, review, args = pub["receipt"], pub["review"], pub["commit_arguments"]
            p = review["proposal"]
            stored = stored_proposal(p)
            review_calls = [c for c in report["author_cli"] if c["arguments"] == [
                "review", "The Cairn Archive Pilot", p["proposal_id"], str(p["version"]), p["digest"]]]
            check(len(review_calls) == 1 and json.loads(review_calls[0]["stdout"]) == review,
                  "review differs from private author transcript")
            check(stored["changes"] == review["changes"], "review assignments differ from stored proposal")
            checked = stored_validation(p, pub["validation"])
            approved = approvals(p, pub["validation"])
            check(checked["admissible"] and len(approved) == 1, "publication lacks exact admissible approval")
            check(approved[0][1]["proposal"] == args["proposal_reference"]
                  and approved[0][1]["author"] == pub["author_selection"]["author_profile"]
                  and approved[0][1]["validation_digest"] == digest(checked)
                  and approved[0][1]["evaluator"] == pub["validation"]["evaluator_version"], "approval binding mismatch")
            check(pub["author_selection"]["approval"] == {"approved": args["proposal_reference"],
                                                          "validation_run": args["validation_run"]}, "CLI approval receipt mismatch")
            operation = workflow[f"operation:{receipt['operation_id']}"]
            # The append-only operation stores the commit input. The final receipt
            # is reconstructed from the immutable kernel row, not overwritten there.
            check(operation["status"]["operation_id"] == receipt["operation_id"]
                  and operation["status"]["proposal"] == p and receipt["proposal_id"] == p["proposal_id"]
                  and operation["input"]["changes"] == stored["changes"], "durable operation binding mismatch")
            kernel = db.execute("SELECT * FROM operation_receipts WHERE idempotency_key=?", (args["idempotency_key"],)).fetchall()
            check(len(kernel) == 1 and kernel[0]["revision_id"] == receipt["revision"]
                  and kernel[0]["principal"] == operation["input"]["principal"]
                  and kernel[0]["payload_digest"] == digest(operation["input"]), "kernel receipt/input mismatch")
            commit = db.execute("SELECT * FROM commits WHERE id=?", (receipt["revision"],)).fetchone()
            check(commit and commit["parent_id"] == args["expected_base_revision"]
                  and commit["digest"] == digest(operation["input"])
                  and commit["decision"] == p["digest"], "commit parent/digest/decision mismatch")
            changes = {r["record_id"]: r for r in db.execute("SELECT * FROM commit_changes WHERE revision_id=?", (receipt["revision"],))}
            check(set(changes) == {c["record_id"] for c in review["changes"]}, "SQL assignments differ from review")
            payloads = []
            for change in review["changes"]:
                row, next_record = changes[change["record_id"]], change["next"]
                check(next_record is not None, "unexpected removal in baseline pilot")
                check(row["version_id"] == next_record["record_version_id"] and row["prior_version"] == change["expected"],
                      "commit assignment/version binding mismatch")
                check(versions[row["version_id"]] == next_record, "canonical version differs from approved candidate")
                check(membership.get(change["record_id"]) == row["version_id"], "result absent from restarted head")
                payloads.append(normalize(next_record["payload"]))
            persisted_payloads[receipt["revision"]] = sorted(payloads, key=lambda v: canonical(v))
            publication_by_revision[receipt["revision"]] = pub
            successful = [c for c in calls if c["tool"] == "universe_commit" and c["arguments"] == args
                          and not c["expected_error"]]
            check(len(successful) == 2 and all(c["result"]["result"] == receipt for c in successful),
                  "commit/retry wire receipt mismatch")

        check(len(report["publications"]) == 12, "missing seed or gap publications")
        check(db.execute("SELECT count(*) FROM operation_receipts").fetchone()[0] == 13, "unexpected kernel receipt")
        check(db.execute("SELECT count(*) FROM commits").fetchone()[0] == 14, "unexpected canonical history")
        head = db.execute("SELECT head_commit FROM continuities").fetchone()[0]
        check(head == report["publications"][-1]["receipt"]["revision"], "final head mismatch")
        for record in report["restarted_records"]:
            check(versions[membership[record["identity"]["record_id"]]] == record,
                  "restart read differs from independently read SQLite")

        results, equivalent = {}, {}
        for case_id, row in cases.items():
            gold = expected[case_id]
            check(row["case"] == gold["case"], "case identifier changed")
            p, v = row["proposal"], row["validation"]
            stored = stored_proposal(p)
            probe_call = [c for c in calls[:42] if c["tool"] == "universe_propose"
                          and c["arguments"].get("idempotency_key") == row["case"]]
            validation_call = [c for c in calls[:42] if c["tool"] == "universe_validate"
                               and c["arguments"]["proposal_reference"]["proposal_id"] == p["proposal_id"]
                               and (c["result"] if case_id == "C01" else c["result"]["result"].get("execution", c["result"]["result"])) == v]
            check(len(probe_call) == len(validation_call) == 1, "missing baseline request")
            check(probe_call[0]["arguments"]["operations"] == row["operations"], "stimulus differs from wire request")
            check(normalize(row["operations"]) == historical[case_id]["operations"], "original probe stimulus changed")
            check((validation_call[0]["result"] if case_id == "C01" else validation_call[0]["result"]["result"].get("execution", validation_call[0]["result"]["result"])) == v,
                  "baseline validation not from recorded request")
            if case_id == "C01":
                observation = {"error_code": v["code"], "error_field": v["field"],
                               "approval": "not attempted: no validation run"}
                check(validation_call[0]["expected_error"] and not row["approval"]["attempted"], "phase control did not reject")
            else:
                checked = stored_validation(p, v)
                acceptance = row["approval"]["returncode"] == 0
                observation = {"coverage": v["coverage"], "findings": len(v["findings"]),
                               "approval": "accepted" if acceptance else "denied"}
                if case_id == "C02":
                    observation["finding_outcomes"] = [f["outcome"] for f in v["findings"]]
                    check(not checked["admissible"] and not approvals(p,v), "multiplicity control has approval")
                else:
                    check(checked["admissible"] and len(approvals(p,v)) == 1, "gap lacks durable baseline approval")
                cli = [c for c in report["author_cli"] if c["arguments"][:2] == ["approve", "The Cairn Archive Pilot"]
                       and c["arguments"][2:] == [p["proposal_id"], str(p["version"]), p["digest"], v["run_id"]]]
                check(cli and cli[0]["returncode"] == row["approval"]["returncode"], "baseline CLI approval mismatch")
            check(observation == historical[case_id]["observed_engine"], f"{case_id}: observed engine behavior drifted: {observation}")
            if case_id.startswith("G"):
                receipt = row["receipt"]
                pub = publication_by_revision[receipt["revision"]]
                check(pub["receipt"] == receipt, "gap receipt mismatch")
                check(pub["review"]["proposal"]["operations"] == p["operations"], "persistence stimulus changed")
                if case_id != "G11":
                    revisions = [c for c in calls if c["tool"] == "universe_propose"
                                 and c["arguments"].get("idempotency_key") == case_id + "-persistence"]
                    check(len(revisions) == 1 and revisions[0]["arguments"]["operations"] == row["operations"],
                          "persistence wire stimulus changed")
                payloads = persisted_payloads[receipt["revision"]]
            else:
                check(row["receipt"] is None, "rejected control has commit receipt")
                for change in stored["changes"]:
                    check(change["record_id"] not in membership, "rejected control became canonical")
                check(not any(pub["receipt"]["proposal_id"] == p["proposal_id"] for pub in report["publications"]),
                      "control proposal was committed")
                payloads = []
            results[case_id] = {"case": row["case"], "expected_continuity": gold["expected_continuity"],
                                "classification": gold["classification"], "observed_engine": observation,
                                "evidence": {"transcript": "mcp-transcript.jsonl", "propose_lines": probe_call[0]["wire_lines"],
                                             "validation_lines": validation_call[0]["wire_lines"], "report_case": case_id,
                                             "package": "package.sqlite", "proposal_id": p["proposal_id"],
                                             "receipt": row["receipt"]}, "audit": "passed"}
            equivalent[case_id] = {"observed_engine": observation,
                                  "operations": normalize(row["operations"]), "canonical_payloads": payloads,
                                  "receipt_verified": case_id.startswith("G")}

        # Verify the byte-level truth underlying the G10/G11 interpretation gaps.
        sources = [r for r in versions.values() if r["payload"]["record_kind"] == "source_version"]
        check(len(sources) == 1, "unexpected source inventory")
        source = sources[0]["payload"]
        text = workflow["source:" + source["digest"]]
        check(text == "Mara is alive. Iven has black hair." and hashlib.sha256(text.encode()).hexdigest() == source["digest"],
              "source text/digest mismatch")
        anchor = next(r["payload"] for r in versions.values() if r["payload"]["record_kind"] == "anchor")
        loc = anchor["locator"]
        check(text.encode()[loc["start"]:loc["end"]].decode() == anchor["excerpt"] == "Iven has black hair.",
              "anchor range differs from actual source bytes")
        check(hashlib.sha256(anchor["excerpt"].encode()).hexdigest() == anchor["excerptDigest"], "excerpt digest mismatch")
        result = {"status": "passed", "universe_id": universe_id, "mcp_calls": len(calls), "mcp_connections": sessions,
                  "baseline_mcp_calls": 42, "canonical_commits": 14, "commit_receipts": 12, "kernel_receipts": 13,
                  "cases": results, "equivalence": equivalent,
                  "limits": "Independent program and storage read, not an external human review. Interpretation expectations remain authored, not engine-derived."}
        (directory / "audit.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
        return result


if __name__ == "__main__":
    result = audit(Path(sys.argv[1]).resolve())
    print(f"PASS: {len(result['cases'])} cases, {result['commit_receipts']} MCP receipts, {result['kernel_receipts']} kernel receipts, independent SQLite/wire audit")
