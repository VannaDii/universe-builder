"""Independent G02 oracle/wire/storage audit; imports no runner or rules engine."""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
        separators=(",", ":")).encode()).hexdigest()


def rid(n):
    return f"rec_{200000+n:024x}"


def wire_calls(path, expected_sessions=2):
    calls, pending, sessions = [], {}, 0
    for line, entry in enumerate(map(json.loads, path.read_text().splitlines()), 1):
        f = entry["frame"]
        if entry["direction"] == "sent":
            if f.get("method") == "initialize":
                check(not pending, "restart abandoned request")
                sessions += 1
            if "id" in f:
                check(f["id"] not in pending, "duplicate wire request")
                pending[f["id"]] = (f, line)
        elif "id" in f:
            check(f["id"] in pending, "unpaired wire response")
            q, start = pending.pop(f["id"])
            check("error" not in f, "JSON-RPC error")
            if q["method"] == "tools/call":
                result = f["result"]
                body = result["structuredContent"]
                check(json.loads("".join(c["text"] for c in result["content"] if c["type"] == "text")) == body,
                      "wire text/structured mismatch")
                calls.append({"tool": q["params"]["name"], "arguments": q["params"]["arguments"],
                    "expected_error": bool(result.get("isError")), "result": body, "lines": [start, line]})
    check(not pending and sessions == expected_sessions, "incomplete wire/restart sequence")
    return calls


def audit(directory):
    report = json.loads((directory / "report.json").read_text())
    oracle = json.loads((directory / "oracle.json").read_text())
    identity = json.loads((directory / "build-identity.json").read_text())
    check(report["status"] == "executed", "runner did not finish")
    check(hashlib.sha256((directory / "oracle.json").read_bytes()).hexdigest() == identity["g02_oracle_sha256"], "oracle changed")
    check(hashlib.sha256((directory / "package.sqlite").read_bytes()).hexdigest() == report["package_sha256"], "snapshot changed")
    calls = wire_calls(directory / "mcp-transcript.jsonl")
    check([{k: v for k, v in c.items() if k != "lines"} for c in calls] == report["mcp"], "report differs from wire")
    gold = {c["id"]: c for c in oracle["cases"]}
    cases = {c["id"]: c for c in report["cases"]}
    check(len(cases) == len(report["cases"]) == 20 and set(cases) == set(gold), "case inventory differs")
    with closing(sqlite3.connect(f"file:{directory / 'package.sqlite'}?mode=ro&immutable=1", uri=True)) as db:
        db.row_factory = sqlite3.Row
        check(db.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "SQLite integrity failure")
        check(not db.execute("PRAGMA foreign_key_check").fetchall(), "foreign key failure")
        workflow = {}
        for r in db.execute("SELECT key,payload,digest FROM workflow_entries"):
            value = json.loads(r["payload"])
            check(digest(value) == r["digest"], "workflow digest differs")
            workflow[r["key"]] = value
        versions = {r["id"]: json.loads(r["payload"]) for r in db.execute("SELECT id,payload FROM record_versions")}
        def snapshot(rev):
            path = []
            while rev:
                path.append(rev)
                row = db.execute("SELECT parent_id FROM commits WHERE id=?", (rev,)).fetchone()
                check(row is not None, "missing historical commit")
                rev = row[0]
            result = {}
            for rev in reversed(path):
                for row in db.execute("SELECT record_id,version_id FROM commit_changes WHERE revision_id=?", (rev,)):
                    if row["version_id"]:
                        result[row["record_id"]] = versions[row["version_id"]]
                    else:
                        result.pop(row["record_id"], None)
            return result
        def stored(p):
            value = workflow[f"proposal:{p['proposal_id']}:{p['version']:020}"]
            check(value["proposal"] == p, "persisted proposal differs")
            check(any(c["tool"] == "universe_propose" and c["result"].get("result") == p for c in calls), "proposal absent from wire")
            return value
        def active(v, day, before=False):
            if v["kind"] != "calendar_interval":
                return None
            start, end = v["start"], v["end"]
            left = start["kind"] == "unbounded" or (int(start["value"]) < day if before else int(start["value"]) <= day)
            right = end["kind"] == "unbounded" or (day <= int(end["value"]) if before else day < int(end["value"]))
            return left and right
        def attributes(records, owner, day, before=False):
            attrs, unknown = {}, set()
            for row in records.values():
                a = row["payload"]
                if a["record_kind"] != "assertion":
                    continue
                p = records[a["proposition"]["record"]]["payload"]
                if p["subject"]["record"] != owner:
                    continue
                key = records[p["predicate"]["record"]]["payload"]["key"]
                applies = active(a["validity"], day, before)
                if applies is None:
                    unknown.add(key)
                elif applies:
                    attrs.setdefault(key, []).append((p["value"], a["polarity"], row))
            return attrs, unknown
        pubs = report["publications"]
        check(len(pubs) == 9, "missing legal publications")
        for pub in pubs:
            p, v, receipt, args = pub["review"]["proposal"], pub["validation"], pub["receipt"], pub["commit_arguments"]
            stored_p = stored(p)
            checked = workflow[f"validation:{v['run_id']}"]
            check(checked["validation"] == v and checked["proposal_digest"] == p["digest"] and checked["admissible"], "validation binding differs")
            check(v["coverage"] == "complete" and not v["findings"], "publication not complete/passing")
            approvals = [a for k, a in workflow.items() if k.startswith("approval:") and k.endswith(f":{p['digest']}:{v['run_id']}")]
            check(len(approvals) == 1, "missing exact approval")
            check(approvals[0]["proposal"] == args["proposal_reference"] and approvals[0]["validation_digest"] == digest(checked)
                  and approvals[0]["evaluator"] == v["evaluator_version"] and approvals[0]["author"] == pub["author_selection"]["author_profile"], "approval binding differs")
            cli = report["author_cli"]
            for name, tail, body in (("review", [], pub["review"]), ("approve", [v["run_id"]], pub["author_selection"]["approval"])):
                check(any(r["arguments"] == [name, "The Cairn Archive Pilot", p["proposal_id"], str(p["version"]), p["digest"], *tail]
                          and r["returncode"] == 0 and json.loads(r["stdout"]) == body for r in cli), "private author record differs")
            operation = workflow[f"operation:{receipt['operation_id']}"]
            check(operation["status"]["proposal"] == p and operation["input"]["changes"] == stored_p["changes"] == pub["review"]["changes"], "review/operation assignments differ")
            kernel = db.execute("SELECT * FROM operation_receipts WHERE idempotency_key=?", (args["idempotency_key"],)).fetchone()
            check(kernel is not None and kernel["revision_id"] == receipt["revision"] and kernel["payload_digest"] == digest(operation["input"])
                  and kernel["principal"] == operation["input"]["principal"], "kernel receipt differs")
            commit = db.execute("SELECT * FROM commits WHERE id=?", (receipt["revision"],)).fetchone()
            check(commit["parent_id"] == args["expected_base_revision"] and commit["digest"] == digest(operation["input"])
                  and commit["decision"] == p["digest"], "canonical commit binding differs")
            sql_changes = {r["record_id"]: r for r in db.execute("SELECT * FROM commit_changes WHERE revision_id=?", (receipt["revision"],))}
            check(set(sql_changes) == {r["record_id"] for r in stored_p["changes"]}, "canonical assignments differ")
            for change in stored_p["changes"]:
                row = sql_changes[change["record_id"]]
                check(row["prior_version"] == change["expected"] and row["version_id"] == change["next"]["record_version_id"]
                      and versions[row["version_id"]] == change["next"], "canonical version differs")
            commits = [c for c in calls if c["tool"] == "universe_commit" and c["arguments"] == args]
            check(commits[0]["expected_error"] and all(c["result"]["result"] == receipt for c in commits[1:]), "authority/retry receipts differ")
        seed = snapshot(report["seed"]["revision"])
        for n, requirements in oracle["actions"].items():
            a = seed[rid(int(n))]["payload"]
            check(a["record_kind"] == "action_definition" and a["validity"] == {"kind": "unspecified"}
                  and a["scope"]["applicability"] == {"kind": "universe_wide"}, "action declaration differs")
            actual = {seed[r["predicate"]["record"]]["payload"]["key"]: r["value"]["value"] for r in a["requirements"]}
            check(actual == requirements and len(actual) == len(a["requirements"]) and all(r["role"] == "actor" for r in a["requirements"]), "owner action contract differs")
        # Check the actual authored premises, including the legal undead exception.
        expected_attrs = {1: {"alive": False, "breathing": False, "conscious": False},
                          2: {"alive": False, "breathing": False, "conscious": True, "speech": True},
                          4: {"alive": True, "breathing": True, "conscious": True, "mobile": True},
                          9: {"conscious": True, "mobile": False}}
        for owner, expected in expected_attrs.items():
            attrs, unknown = attributes(seed, rid(owner), 19)
            check(not unknown and {k: values[0][0]["value"] for k, values in attrs.items()} == expected, "authored capability premises differ")
        results = {}
        for key, g in gold.items():
            r, p = cases[key], cases[key]["proposal"]
            candidate = stored(p)
            e = r["operation"]["record"]
            normalized_op = json.loads(json.dumps(r["operation"]))
            normalized_op["record"].setdefault("worlds", [])
            check(any(c["tool"] == "universe_propose" and c["result"].get("result") == p and
                      c["arguments"]["operations"][-1] == r["operation"] for c in calls), "case operation differs from wire")
            check(p["operations"][-1] == normalized_op and r["operation"]["kind"] == "record_event"
                  and e["action"]["record"] == rid(g["action"]) and e["time"]["value"] == str(g["day"]) and e["occurrence"] == "occurred", "case stimulus differs")
            participants = [{"record": {"universe": report["installation"]["universe_id"], "record": rid(g["actor"])}, "role": "actor"}]
            for field, role in (("patient", "patient"), ("duplicate_actor", "actor")):
                if field in g:
                    participants.append({"record": {"universe": report["installation"]["universe_id"], "record": rid(g[field])}, "role": role})
            check(e["participants"] == participants, "participant owner differs")
            if "optional_owner" in g:
                check(len(e["preconditions"]) == 1 and e["preconditions"][0]["subject"]["ref"]["record"] == rid(g["optional_owner"]), "borrowed condition differs")
            else:
                check(not e["preconditions"], "unexpected optional condition")
            expected_effect = 63 if g.get("self_grant") else 66 if "patient" in g else None
            check(len(e["effects"]) == (1 if expected_effect else 0), "case effects differ")
            if expected_effect:
                check(e["effects"][0]["proposition"]["record"] == rid(expected_effect) and
                      e["effects"][0]["validity"]["start"]["value"] == str(g["day"]), "self grant/movement stimulus differs")
            # Calculate capability admission independently from saved candidate
            # assertions, with strict pre-event inequalities, including self effects.
            records = snapshot(p["base_frame"]["revision"])
            records.update({c["record_id"]: c["next"] for c in candidate["changes"] if c["next"]})
            attrs, unknown = attributes(records, rid(g["actor"]), g["day"], before=True)
            requirements = oracle["actions"][str(g["action"])]
            computed = "duplicate_actor" not in g and all(k not in unknown and
                any(value == {"kind": "boolean", "value": needed} and polarity == "support" for value, polarity, _ in attrs.get(k, [])) and
                not any(value == {"kind": "boolean", "value": needed} and polarity == "refutation" for value, polarity, _ in attrs.get(k, []))
                for k, needed in requirements.items())
            check(computed == g["allowed"], "independent capability calculation differs: " + key)
            validations = [c for c in calls if c["tool"] == "universe_validate" and c["arguments"]["proposal_reference"]["proposal_id"] == p["proposal_id"]]
            check(validations, "missing case validation")
            if g["allowed"]:
                check("receipt" in r and any(pub["receipt"] == r["receipt"] for pub in pubs), "legal case not committed")
                check(all(not c["expected_error"] for c in validations), "legal case rejected")
            else:
                check(len(validations) == 1 and validations[0]["expected_error"] and validations[0]["result"] == r["rejection"]
                      and r["rejection"]["code"] == "INVALID_ARGUMENT" and r["rejection"]["field"] == "event.action.requirements", "illegal action not rejected")
                check(not any(k.startswith("approval:") and p["digest"] in k for k in workflow), "illegal action approved")
                check(not any(pub["receipt"]["proposal_id"] == p["proposal_id"] for pub in pubs), "illegal action committed")
                check(not db.execute("SELECT 1 FROM commit_changes WHERE record_id=?", (r["operation"]["client_ref"],)).fetchone(), "illegal action entered canonical history")
                check(any(c["tool"] == "universe_commit" and c["expected_error"] and c["result"] == r["commit_rejection"] and
                          c["arguments"]["proposal_reference"]["proposal_id"] == p["proposal_id"] for c in calls), "illegal commit denial absent")
            results[key] = {"allowed": g["allowed"], "calculated": computed, "validation_lines": validations[0]["lines"]}
        def state_proof(response, revision, day, conscious):
            check(any(c["tool"] == "universe_get_state" and c["result"] == response for c in calls), "state absent from wire")
            check(response["frame"]["revision"] == revision and response["frame"]["time"]["time"]["value"] == str(day), "state query frame differs")
            records = snapshot(revision)
            attrs, unknown = attributes(records, rid(3), day)
            expected_rows = sorted([row for values in attrs.values() for _, _, row in values], key=lambda r: r["record_version_id"])
            actual_rows = sorted(response["result"]["assertions"], key=lambda r: r["record_version_id"])
            check(actual_rows == expected_rows, "queried state differs from canonical history")
            check(not unknown and len(attrs["conscious"]) == 1 and attrs["conscious"][0][0] == {"kind": "boolean", "value": conscious}, "consciousness history differs")
            return attrs
        original, final = report["original_revision"], report["corrected"]["revision"]
        for field in ("original_states", "historical_states"):
            for day, value in oracle["post_state"].items():
                state_proof(report[field][day], original, int(day), value)
        for day, value in oracle["corrected_post_state"].items():
            state_proof(report["corrected_states"][day], final, int(day), value)
        body = state_proof(report["body_state"], original, 21, False)
        check(body["location"][0][0] == {"kind": "text", "text": "shelter"} and body["location"][0][2]["payload"]["establishedBy"]["event"]["record"] == cases["carry_unconscious"]["operation"]["client_ref"], "body movement effect differs")
        state_proof(report["restarted_state"], final, 19, False)
        check(report["restart_receipt"] == report["corrected"], "restart receipt differs")
        for r in [report["retcon"], *report["retcon"]["isolated"]]:
            p = r["proposal"]
            candidate = stored(p)
            check(any(c["tool"] == "universe_validate" and c["expected_error"] and c["result"] == r["rejection"] and c["arguments"]["proposal_reference"]["proposal_id"] == p["proposal_id"] for c in calls), "retcon rejection absent")
            check(r["rejection"]["field"] == "event.action.requirements", "retcon did not reject dependent action")
            check(not any(k.startswith("approval:") and p["digest"] in k for k in workflow), "invalid retcon approved")
            check(p["base_frame"]["revision"] == original and p["operations"][0]["record"]["record"] == rid(71)
                  and p["operations"][0]["replacement"]["time"]["value"] == "18", "retcon stimulus differs")
            records = snapshot(original)
            for change in candidate["changes"]:
                if change["next"]:
                    records[change["record_id"]] = change["next"]
                else:
                    records.pop(change["record_id"], None)
            dependent_keys = [r["dependent"]] if "dependent" in r else oracle["retcon"]["invalidated"]
            for key in dependent_keys:
                event_id = cases[key]["operation"]["client_ref"]
                check(event_id in records and records[event_id]["payload"] == snapshot(original)[event_id]["payload"],
                      "isolated dependent changed or missing")
                attrs, unknown = attributes(records, rid(3), gold[key]["day"], before=True)
                check(not unknown and attrs["conscious"][0][0] == {"kind": "boolean", "value": False}, "retcon did not independently invalidate dependency")
        check({r["dependent"] for r in report["retcon"]["isolated"]} == set(oracle["retcon"]["invalidated"]), "retcon isolation incomplete")
        old, new = snapshot(original), snapshot(final)
        check(old[rid(71)]["payload"]["time"]["value"] == "20" and new[rid(71)]["payload"]["time"]["value"] == "18", "earlier incapacity history differs")
        for key in oracle["retcon"]["invalidated"]:
            record = cases[key]["operation"]["client_ref"]
            check(old[record]["payload"]["time"]["value"] == str(gold[key]["day"]) and new[record]["payload"]["time"]["value"] == "17", "corrected dependent action differs")
        head = db.execute("SELECT head_commit FROM continuities").fetchone()[0]
        check(head == final, "unexpected canonical head")
        membership = {r["record_id"]: versions[r["version_id"]] for r in db.execute("SELECT record_id,version_id FROM head_membership")}
        check(membership == new, "head membership differs from replayed history")
        check(all(new[r["identity"]["record_id"]] == r for r in report["restarted_records"]), "restart record differs")
        check(db.execute("SELECT count(*) FROM operation_receipts").fetchone()[0] == 10 and db.execute("SELECT count(*) FROM commits").fetchone()[0] == 11, "unexpected canonical history count")
    result = {"status": "passed", "cases": results, "illegal_rejected": 13, "legal_committed": 7,
              "publications": 9, "mcp_calls": len(calls), "retcon_dependents_invalidated": 2,
              "history_and_restart": "passed", "limit": "Independent program/storage audit, not an external human review or arbitrary prose qualification."}
    (directory / "audit.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    result = audit(Path(sys.argv[1]).resolve())
    print(json.dumps(result, indent=2))
