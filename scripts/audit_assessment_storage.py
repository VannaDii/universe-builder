#!/usr/bin/env python3
"""Independent read-only SQLite audit; does not import service/store serializers."""
import hashlib
import json
import sqlite3
import sys
from relational_history import workflows


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def audit(path, phase):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    rows = []
    stored_payload_sha256 = {}
    db.row_factory = sqlite3.Row
    for row in workflows(db):
        key, raw, digest = row['key'], row['payload_utf8'].encode(), row['digest']
        value = json.loads(raw)
        stored_payload_sha256[key] = hashlib.sha256(raw).hexdigest()
        assert stored_payload_sha256[key] == digest, key
        rows.append([key, value])
    entries = dict(rows)
    attachments = {k: v for k, v in rows if k.startswith("assessment:")}
    selections = {k: v for k, v in rows if k.startswith("assessment-selection:")}
    for key, envelope in attachments.items():
        assert key == "assessment:" + envelope["assessment_id"]
        body = envelope["body"]
        assert hashlib.sha256(b"source-assessment:v1:" + canonical(body)).hexdigest() == envelope["digest"]
        ref = body["proposal"]
        proposal = entries[f"proposal:{ref['proposal_id']}:{ref['version']:020d}"]
        assert proposal["proposal"]["digest"] == ref["digest"]
        assert proposal["proposal"]["base_frame"] == body["base_frame"]
        candidate = {c["record_id"]: c["next"] for c in proposal["changes"] if c["next"]}
        for dependency in body["dependencies"]:
            record = candidate[dependency["record"]]
            assert record["record_version_id"] == dependency["version"]
            assert record["identity"]["universe_id"] == dependency["universe"]
            if record["payload"]["record_kind"] == "anchor":
                anchor = record["payload"]
                version = anchor["sourceVersion"]
                source = next(s for s in body["sources"] if s["source_version"] == version)
                text = entries["source:" + source["blob_digest"]].encode()
                start, end = anchor["locator"]["start"], anchor["locator"]["end"]
                assert any(r["start"] <= start < end <= r["end"] for r in source["ranges"])
                excerpt = text[start:end]
                assert excerpt.decode() == anchor["excerpt"]
                assert hashlib.sha256(excerpt).hexdigest() == anchor["excerptDigest"]
        for source in body["sources"]:
            version = source["source_version"]
            record = candidate[version["record"]]
            assert record["record_version_id"] == version["version"]
            assert record["identity"]["universe_id"] == version["universe"]
            payload = record["payload"]
            assert payload["record_kind"] == "source_version"
            raw = entries["source:" + source["blob_digest"]].encode()
            assert hashlib.sha256(raw).hexdigest() == source["blob_digest"] == payload["digest"]
            assert len(raw) == source["byte_size"] == payload["byteSize"]
            for span in source["ranges"]:
                raw[:span["start"]].decode()
                raw[:span["end"]].decode()
    for key, receipt in rows:
        if key.startswith("assessment-receipt:"):
            selection = receipt["selection"]
            ref = selection["proposal"]
            stored_selection = entries[f"assessment-selection:{ref['proposal_id']}:{ref['version']:020d}:{selection['generation']:020d}"]
            assert stored_selection == selection
            if receipt["envelope"]:
                assert receipt["envelope"] == attachments["assessment:" + receipt["envelope"]["assessment_id"]]
    generations = {}
    for key, selection in selections.items():
        prefix, generation = key.rsplit(":", 1)
        assert int(generation) == selection["generation"]
        generations.setdefault(prefix, []).append(int(generation))
        selected = selection["selected"]
        if selected:
            envelope = attachments["assessment:" + selected["assessment_id"]]
            assert envelope["digest"] == selected["digest"]
            assert envelope["body"]["proposal"] == selection["proposal"]
    for values in generations.values():
        assert sorted(values) == list(range(1, max(values) + 1))
    return {"phase": phase, "integrity": "ok", "attachment_count": len(attachments), "selection_count": len(selections), "payloads_and_bindings": "verified", "rows": rows, "stored_payload_sha256": stored_payload_sha256}


if __name__ == "__main__":
    print(json.dumps(audit(sys.argv[1], sys.argv[2]), ensure_ascii=False, sort_keys=True))
