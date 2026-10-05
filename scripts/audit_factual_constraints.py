"""Independent structural audit for retained Goal 34 public-MCP evidence."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

EXPECTED = {
    "knowledge-belief-legal": ("knowledge", "legal"),
    "knowledge-refuted-knows": ("knowledge", "illegal-if-justified-policy"),
    "knowledge-unknown-knows": ("knowledge", "unresolved"),
    "communication-forward": ("chronology", "legal"),
    "communication-reversed": ("chronology", "illegal-if-forward-rule"),
    "communication-unreceived": ("chronology", "unresolved"),
    "cardinality-one-legal": ("cardinality", "legal"),
    "cardinality-overlap": ("cardinality", "illegal-if-max-one"),
    "cardinality-unknown-validity": ("cardinality", "unresolved"),
}


def audit(report, transcript):
    assert report["status"] == "executed"
    cases = report["cases"]
    assert [c["id"] for c in cases] == list(EXPECTED)
    for c in cases:
        assert (c["family"], c["oracle_class"]) == EXPECTED[c["id"]]
        assert c["admitted"] is True and c["approval_returncode"] == 0
        assert c["validation"]["coverage"] == "complete"
        assert not c["validation"]["findings"]
        assert c["head_before"] != c["head_after"]
        assert c["after"] != c["before"]
    calls = [json.loads(line) for line in transcript.splitlines()]
    sent = [x["frame"] for x in calls if x.get("direction") == "sent"]
    commits = [x for x in sent if x.get("method") == "tools/call" and
               x.get("params", {}).get("name") == "universe_commit"]
    validations = [x for x in sent if x.get("method") == "tools/call" and
                   x.get("params", {}).get("name") == "universe_validate"]
    assert len(commits) >= len(EXPECTED) and len(validations) >= len(EXPECTED)
    return {"cases": len(cases), "public_validations": len(validations),
            "public_commits": len(commits), "all_admitted_without_findings": True}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("evidence", type=Path)
    p.add_argument("--output", type=Path)
    a = p.parse_args()
    raw = (a.evidence / "report.json").read_bytes()
    transcript = (a.evidence / "mcp-transcript.jsonl").read_text()
    report = json.loads(raw)
    result = audit(report, transcript)
    forged = copy.deepcopy(report)
    forged["cases"][0]["admitted"] = False
    try:
        audit(forged, transcript)
    except AssertionError:
        result["forged_admission_rejected"] = True
    else:
        raise AssertionError("auditor accepted forged admission status")
    result["report_sha256"] = hashlib.sha256(raw).hexdigest()
    result["transcript_sha256"] = hashlib.sha256(transcript.encode()).hexdigest()
    result["status"] = "passed"
    encoded = json.dumps(result, indent=2) + "\n"
    if a.output:
        a.output.write_text(encoded)
    print(encoded, end="")


if __name__ == "__main__":
    main()
