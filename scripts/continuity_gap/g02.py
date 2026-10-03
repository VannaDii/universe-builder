"""Small authored G02 vocabulary. Expected outcomes live in a separate oracle.

No source/prose classification, life inference or action consequence contract.
"""
from copy import deepcopy
from pilot_support import NAME
from mlx_authoring_smoke import require

# Stimuli are specified separately from the proof auditor's expected outcomes.
CASES = [
    ("dead_breath", 1, 20, 19, False, {}),
    ("dead_inspect", 1, 21, 19, False, {}),
    ("unconscious_inspect", 3, 21, 21, False, {}),
    ("borrowed_breath", 1, 20, 19, False, {"optional_owner": 4}),
    ("borrowed_conscious", 3, 21, 21, False, {"optional_owner": 4}),
    ("unknown_conscious", 5, 21, 19, False, {}),
    ("unknown_refutation", 7, 21, 19, False, {}),
    ("missing_conscious", 6, 21, 19, False, {}),
    ("same_event_grant", 8, 21, 19, False, {"self_grant": True}),
    ("carrier_missing_mobile", 9, 23, 21, False, {"patient": 3}),
    ("ambiguous_actor", 3, 21, 21, False, {"duplicate_actor": 4}),
    ("conscious_start", 3, 21, 10, False, {}),
    ("at_restoration", 3, 21, 30, False, {}),
    ("conscious_inspect", 4, 21, 19, True, {}),
    ("living_breath", 4, 20, 19, True, {}),
    ("undead_speech", 2, 22, 19, True, {}),
    ("carry_unconscious", 4, 23, 21, True, {"patient": 3}),
    ("before_loss", 3, 21, 19, True, {}),
    ("at_loss", 3, 21, 20, True, {}),
    ("after_restoration", 3, 21, 31, True, {}),
]


def exercise(s, report):
    boolean = lambda value: {"kind": "boolean", "value": value}
    def proposition(n, owner, predicate, value):
        return {"kind": "define_proposition", "client_ref": s.rid(n), "record": {
            "subject": s.rr(owner), "predicate": s.rr(predicate), "value": value,
            "context": s.scope["context"], "quantification": "particular"}}
    def premise(n, owner, predicate, value, validity=None, polarity="support"):
        return {"kind": "assert_proposition", "client_ref": s.rid(n),
            "proposition": proposition(n, owner, predicate, value)["record"], "assertion": {
                "proposition": s.rr(n), "polarity": polarity, "scope": s.scope,
                "validity": validity or s.interval(0), "persistence": "explicit_interval",
                "precision": "exact", "basis": {"kind": "author_decision", "note": "Synthetic G02 premise"}}}
    def effect(prop, day):
        return {"slot": "capability", "order": 0, "proposition": s.rr(prop),
                "polarity": "support", "scope": s.scope, "validity": s.interval(day)}
    def event(n, actor, action, day, options=None, effects=None):
        options = options or {}
        participants = [{"record": s.rr(actor), "role": "actor"}]
        if "patient" in options:
            participants.append({"record": s.rr(options["patient"]), "role": "patient"})
        if "duplicate_actor" in options:
            participants.append({"record": s.rr(options["duplicate_actor"]), "role": "actor"})
        conditions = []
        if "optional_owner" in options:
            conditions = [{"kind": "claim", "subject": {"kind": "record", "ref": s.rr(options["optional_owner"])},
                "predicate": "g02:" + ("breathing" if action == 20 else "conscious"),
                "value": {"kind": "value", "value": boolean(True)}, "polarity": "support"}]
        return {"kind": "record_event", "client_ref": s.rid(n), "record": {
            "occurrence": "occurred", "action": s.rr(action), "time": s.instant(day),
            "participants": participants, "preconditions": conditions,
            "effects": effects or [], "labels": {}}}
    entities = ("Dead human", "Undead speaker", "Recovering human", "Companion",
                "Unknown consciousness", "Missing evidence", "Uncertain refutation",
                "Self grant attempt", "Immobile carrier")
    ops = [{"kind": "create_entity", "client_ref": s.rid(n), "record": {
        "names": [], "types": [], "worldAssociations": [], "labels": {"en": label}, "metadata": {}}}
        for n, label in enumerate(entities, 1)]
    for n, key in ((10, "alive"), (11, "breathing"), (12, "conscious"), (13, "speech"), (14, "mobile"), (15, "location")):
        ops.append({"kind": "define_property", "client_ref": s.rid(n), "record": {
            "namespace": "g02", "key": key, "labels": {}, "subjectTypes": [],
            "value": {"kind": "text" if n == 15 else "boolean"}, "multiplicity": "single",
            "persistence": "explicit_interval", "exclusive": True, "symmetric": False, "transitive": False}})
    for n, key, predicates in ((20, "breathing_action", [11]), (21, "inspect", [12]),
                               (22, "undead_speech", [13]), (23, "carry_body", [12, 14]), (24, "author_transition", [])):
        ops.append({"kind": "define_action", "client_ref": s.rid(n), "record": {
            "namespace": "g02", "key": key, "labels": {}, "requirements": [
                {"role": "actor", "predicate": s.rr(p), "value": boolean(True)} for p in predicates],
            "scope": s.scope, "validity": {"kind": "unspecified"}}})
    facts = [(1, 10, False), (1, 11, False), (1, 12, False),
             (2, 10, False), (2, 11, False), (2, 12, True), (2, 13, True),
             (3, 10, True), (3, 11, True), (4, 10, True), (4, 11, True), (4, 12, True), (4, 14, True),
             (7, 12, True), (9, 12, True), (9, 14, False)]
    ops += [premise(40 + i, owner, p, boolean(value)) for i, (owner, p, value) in enumerate(facts)]
    ops += [premise(60, 5, 12, boolean(True), {"kind": "unknown"}),
            proposition(61, 6, 12, boolean(True)),
            proposition(63, 8, 12, boolean(True)),
            proposition(64, 3, 12, boolean(True)), proposition(65, 3, 12, boolean(False)),
            proposition(66, 3, 15, {"kind": "text", "text": "shelter"})]
    ops += [event(70, 3, 24, 10, effects=[effect(64, 10)]),
            event(71, 3, 24, 20, effects=[effect(65, 20)]),
            event(72, 3, 24, 30, effects=[effect(64, 30)])]
    report["seed"] = s.publish(s.propose(ops, "g02-seed"), "g02-seed-commit")
    report["cases"] = []
    for i, (key, actor, action, day, allowed, options) in enumerate(CASES):
        effects = [effect(63, day)] if options.get("self_grant") else []
        if options.get("patient"):
            effects = [effect(66, day)]
        op = event(100 + i, actor, action, day, options, effects)
        operations = [op]
        if key == "unknown_refutation":
            operations.insert(0, premise(62, 7, 12, boolean(True), {"kind": "unknown"}, "refutation"))
        p = s.propose(operations, key)
        row = {"id": key, "operation": op, "proposal": p}
        if allowed:
            row["receipt"] = s.publish(p, key + "-commit")
        else:
            row["rejection"] = s.validate(p, error=True)
            require(row["rejection"]["code"] == "INVALID_ARGUMENT" and
                    row["rejection"]["field"] == "event.action.requirements", key)
            row["commit_rejection"] = s.call("universe_commit", s.commit_args(
                p, report["publications"][0]["validation"], key + "-denied-commit"), error=True)
        report["cases"].append(row)
    original = report["publications"][-1]["receipt"]["revision"]
    report["original_revision"] = original
    report["original_states"] = {str(day): s.state([s.rid(3)], day, revision=original)
                                 for day in (10, 19, 20, 21, 30, 31)}
    report["body_state"] = s.state([s.rid(3)], 21)
    def revise(n, day):
        old = s.get([s.rid(n) if isinstance(n, int) else n])[0]
        replacement = deepcopy(old["payload"])
        replacement.pop("record_kind")
        replacement["time"] = s.instant(day)
        for e in replacement["effects"]:
            e["validity"] = s.interval(day)
        return {"kind": "revise_event", "record": s.rr(n), "expected_version": old["record_version_id"],
                "replacement": replacement}
    earlier = revise(71, 18)
    bad = s.propose([earlier], "earlier-incapacity")
    report["retcon"] = {"proposal": bad, "rejection": s.validate(bad, error=True), "impact": s.impact(bad)}
    require(report["retcon"]["rejection"]["field"] == "event.action.requirements", "retcon did not invalidate action")
    report["retcon"]["commit_rejection"] = s.call("universe_commit", s.commit_args(
        bad, report["publications"][-1]["validation"], "earlier-incapacity-denied-commit"), error=True)
    # Isolate each unchanged dependent event to prove both dependencies fail.
    for keep, remove in (("before_loss", "at_loss"), ("at_loss", "before_loss")):
        row = next(r for r in report["cases"] if r["id"] == remove)
        old = s.get([row["operation"]["client_ref"]])[0]
        tombstone = {"kind": "tombstone_record", "record": s.rr(old["identity"]["record_id"]),
                     "expected_version": old["record_version_id"], "rationale": "Isolate retcon dependency"}
        p = s.propose([earlier, tombstone], "isolate-" + keep)
        rejection = s.validate(p, error=True)
        require(rejection["field"] == "event.action.requirements", "dependent action escaped")
        report["retcon"].setdefault("isolated", []).append({"dependent": keep, "proposal": p, "rejection": rejection})
    corrections = [earlier] + [revise(row["operation"]["client_ref"], 17)
        for row in report["cases"] if row["id"] in ("before_loss", "at_loss")]
    report["corrected"] = s.publish(s.propose(corrections, "corrected-retcon"), "corrected-retcon-commit")
    current = report["corrected"]["revision"]
    report["corrected_states"] = {str(day): s.state([s.rid(3)], day, revision=current)
                                  for day in (17, 18, 19, 20, 30)}
    report["historical_states"] = {str(day): s.state([s.rid(3)], day, revision=original)
                                   for day in (10, 19, 20, 21, 30, 31)}
    s.restart()
    report["restarted_state"] = s.state([s.rid(3)], 19)
    pub = report["publications"][-1]
    report["restart_receipt"] = s.call("universe_commit", pub["commit_arguments"])["result"]
    require(report["restart_receipt"] == pub["receipt"], "restart receipt changed")
    report["restarted_records"] = s.get([s.rid(n) for n in (20, 21, 22, 23, 24, 70, 71, 72, 117, 118)])
