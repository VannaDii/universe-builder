"""Readable projections of actual MCP evidence; never infer additional facts.

Keep raw frames, records and review assignments in the transcript. This adapter
joins assertion targets and labels to help the model inspect long ID-heavy data.
It does not upgrade evidence, hide refutations, or treat a proposition as truth.
"""


def focused_evidence(records, assignments=()):
    candidate = [c["next"] for c in assignments if c.get("next")]
    all_records = [*records, *candidate]
    index = {r["identity"]["record_id"]: r for r in all_records}

    def name(ref):
        record = index.get(ref["record"])
        payload = record["payload"] if record else {}
        return {"record": ref, "label": payload.get("labels", {}).get("en", ref["record"])}

    def prop(ref):
        r = index.get(ref["record"])
        if not r or r["payload"]["record_kind"] != "proposition":
            return {"unresolved_reference": ref}
        p = r["payload"]
        predicate = index.get(p["predicate"]["record"], {}).get("payload", {})
        return {"record": ref, "subject": name(p["subject"]),
                "predicate": predicate.get("namespace", "") + ":" + predicate.get("key", p["predicate"]["record"]),
                "value": p.get("value"), "context": p["context"]}

    result = []
    for r in candidate if assignments else records:
        p = r["payload"]
        kind = p["record_kind"]
        row = {"record_id": r["identity"]["record_id"], "record_version": r["record_version_id"], "kind": kind}
        if kind == "assertion":
            row.update(proposition=prop(p["proposition"]), polarity=p["polarity"], validity=p["validity"],
                       scope=p["scope"], basis=p["basis"])
        elif kind == "epistemic_attitude":
            row.update(holder=name(p["holder"]), proposition=prop(p["proposition"]), attitude=p["attitude"],
                       validity=p["validity"], basis=p["basis"])
        elif kind == "event":
            row.update(occurrence=p["occurrence"], time=p["time"], labels=p["labels"],
                       participants=[{**person, "label": name(person["record"])["label"]} for person in p["participants"]])
        else:
            continue
        result.append(row)
    return result
