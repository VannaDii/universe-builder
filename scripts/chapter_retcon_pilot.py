"""Reproducible chapter/retcon pilot against the actual persistent MCP.

The MLX run writes directed prose and locates exact excerpts for a supplied
material-change inventory. The host compiles that bounded inventory into domain
operations; the model returns supplied public research/propose/validate/commit calls. This is an
application tool-dispatch test, not unrestricted native function calling.
Author staging and exact approval apply ONLY to the disposable synthetic novel.
Use --regression for deterministic transport/domain regressions without MLX.
"""
import argparse
import importlib.metadata
import json
from pathlib import Path
import platform
import re
import tempfile
import traceback

from mlx_authoring_smoke import (LocalModel, artifact_manifest, exact_model_decision,
                                 fixture_supported_values, require)
from pilot_support import NAME, PilotSession, excerpt_locator, source_anchor
from pilot_evidence import focused_evidence

ORIGINAL_DAYS = [12, 13, 14, 15]
REVISED_DAYS = [14, 15, 16, 17]
KINDS = {"handoff": 1, "password": 1, "opening": 2, "route": 3,
         "journey": 4, "disclosure": 4}
SYNTHETIC = {
    1: 'Mara held the copper key against her palm. On day {day}, she put it in Iven’s hand. '
       '“Cairn,” she said. “That is the archive password.” Iven repeated “cairn”; now he knew it. '
       'He closed his fingers around the key. Mara watched him take it.',
    2: 'On day {day}, Iven stood before the archive door. He had the copper key and knew the '
       'password, “cairn.” He spoke it, turned the key, and opened the door. He watched it swing open.',
    3: 'On day {day}, inside the open archive, Iven read the map. It showed the route through '
       'the quarry tunnel. After reading it, Iven knew that route. He folded the map.',
    4: 'On day {day}, Iven led Mara from the open archive toward the quarry tunnel. '
       '“The route goes through the quarry tunnel,” he told her. Mara repeated the route back '
       'to him; Mara now knew it. Iven watched her turn toward the tunnel.'}


def manuscript(scenes):
    return "\n\n".join(f"Scene {s['id']} — day {s['day']}\n{s['text']}" for s in scenes) + "\n"


def audit_known_pilot_prose(scenes):
    """Narrow synthetic-author constraints, not a general prose validator.

    The model reviewer missed a door closure and missing explicit learning.
    These guards reject those known violations; source interpretation still
    requires an author. They neither infer arbitrary semantics nor add facts.
    """
    for scene in scenes:
        text = scene["text"]
        if scene["id"] >= 2:
            require(not re.search(r"\bdoor\b[^.!?]{0,100}\b(?:closed|closing|shut|shutting)\b|"
                                  r"\b(?:closed|closing|shut|shutting)\b[^.!?]{0,100}\bdoor\b", text, re.I),
                    "Unrepresented door closure: the archive must remain open through scene4")
        require(not re.search(r"\bonly (?:way|route|path|exit)\b|\broute\b[^.!?]{0,40}\bamong others\b", text, re.I),
                "Unrepresented route count: describe the marked route without asserting whether other routes exist")
        if scene["id"] == 3:
            require(not re.search(r"\bmap\b[^.!?]{0,100}\b(?:pocket|bag|coat)\b", text, re.I),
                    "Unrepresented map custody change: leave the map in place, do not put it in a pocket or bag")
        if scene["id"] == 4:
            require(not re.search(r"\b(?:unstable|hazard|hazardous|dangerous)\b|"
                                  r"\bfloor\b[^.!?]{0,50}\b(?:drops?|dropped)\b|"
                                  r"\btunnel\b[^.!?]{0,50}\b(?:widens?|narrows?|twists?)\b", text, re.I),
                    "Unrepresented route geometry/hazard: tell Mara the named route without adding conditions or terrain facts")
            require("Iven" in text and "Mara" in text
                    and re.search(r"\b(?:led|walked|moved|stepped|followed)\b", text, re.I)
                    and re.search(r"\b(?:out|through|toward|leaving|left)\b", text, re.I),
                    "Unperformed journey: show Iven leading Mara out toward the tunnel, not just preparing or pointing")
            require("Mara" in text and re.search(r"\b(?:learned|understood|knew|knows|memorized|understanding|understand)\b",
                                                 text, re.I) is not None,
                    "Missing explicit Mara route knowledge: name Mara and show her acquiring or acknowledging it")
    return scenes


def validate_scenes(value, days, scene_ids):
    require(set(value) == {"scenes"} and isinstance(value["scenes"], list), "invalid scene object")
    rows = value["scenes"]
    require([r.get("id") for r in rows] == scene_ids, "missing, reordered or invented scene IDs")
    for row, day in zip(rows, days):
        require(set(row) == {"id", "day", "text"} and row["day"] == day, "incorrect scene chronology")
        require(isinstance(row["text"], str) and len(row["text"].split()) >= 30, "scene is not prose")
    return audit_known_pilot_prose(rows)


def validate_extraction(value, scenes):
    require(set(value) == {"claims"} and isinstance(value["claims"], list), "invalid extraction object")
    expected = {k for k, s in KINDS.items() if s in {r["id"] for r in scenes}}
    rows = value["claims"]
    require(len(rows) == len(expected) and {r.get("kind") for r in rows} == expected,
            f"Return exactly {len(expected)} changes, one each of {sorted(expected)}; "
            f"actual kinds were {[r.get('kind') for r in rows]}. Remove duplicates; no change may repeat.")
    by_scene = {r["id"]: r for r in scenes}
    text = manuscript(scenes)
    for row in rows:
        require(set(row) == {"kind", "scene", "day", "excerpt"}, "invalid extracted fields")
        require(row["scene"] == KINDS[row["kind"]], "change attached to wrong scene")
        scene = by_scene[row["scene"]]
        require(row["day"] == scene["day"], "extracted time differs from depicted time")
        require(row["excerpt"] in scene["text"], "excerpt is not exact scene text")
        excerpt_locator(text, row["excerpt"])
    return {r["kind"]: r for r in rows}


class Writer:
    def __init__(self, model, session, report):
        self.model, self.s, self.report = model, session, report
        self.system = session.instructions

    def ask(self, task, data, checker, tokens=2600):
        messages = [{"role": "system", "content": self.system},
                    {"role": "user", "content": json.dumps(data, ensure_ascii=False)}]
        for attempt in range(2):
            try:
                value = self.model.ask(task + ("_repair" if attempt else ""), messages, max_tokens=tokens)
                return checker(value)
            except (ValueError, TypeError, KeyError, RuntimeError) as error:
                self.report.setdefault("model_errors", []).append({"task": task, "attempt": attempt + 1,
                                                                   "error": str(error)})
                if attempt:
                    raise
                messages += [{"role": "assistant", "content": self.model.metrics["turns"][-1]["output"]},
                             {"role": "user", "content": f"Response check rejected the response: {error}. "
                              "Return a corrected JSON response. Nothing from this response has been used."}]

    def decision(self, task, tool, args):
        expected = {"tool": tool, "arguments": args}
        if not self.model:
            return expected
        return exact_model_decision(self.model, task,
            [{"role": "system", "content": self.system}, {"role": "user", "content": json.dumps({
                "task": "Return this supplied public MCP call as one JSON object. The arguments were prepared from "
                        "the host-compiled supplied inventory or the exact proposal and validation receipt. "
                        "No author approval can be fabricated. Return only tool and arguments.",
                "required_call": expected})}], expected, self.report,
            max_tokens=max(1600, min(18000, len(json.dumps(args)) // 2 + 2000)))

    def commit(self, args):
        return self.decision("commit_selected_prose", "universe_commit", args)

    def research(self, label, day, revision=None):
        frame = self.s.open(revision, day)
        args = {"universe": NAME, "context_id": frame["context_id"],
                "focus_ids": [self.s.rid(n) for n in (1, 2, 3, 4, 5)],
                "purpose": f"Verify chapter continuity at day {day}: {label}", "byte_budget": 65536}
        decision = self.decision("research_" + label, "universe_get_context", args)
        research = self.s.call(decision["tool"], decision["arguments"])
        require(research["delivery"]["complete"] and research["result"]["coverage"] == "complete",
                "research omitted required evidence")
        state = self.s.state(args["focus_ids"], day, revision=revision)
        self.report.setdefault("research", []).append({"label": label, "research": research, "state": state})
        return {"pinned_frame": state["frame"], "state": state["result"],
                "research_records": research["result"]}

    def draft(self, days, scene_ids, canon, previous=None, retcon=False):
        if not self.model:
            return audit_known_pilot_prose([{"id": i, "day": day, "text": SYNTHETIC[i].format(day=day)}
                    for i, day in zip(scene_ids, days)])
        beats = {1: "Mara hands the copper key to Iven and explicitly tells him the password cairn; "
                      "Iven learns it. Mara sees the handoff.", 2: "Iven, holding the key and knowing cairn, "
                      "speaks cairn and opens the archive door with the key. He sees it open.",
                 3: "Inside the open archive, Iven reads the map: its route is through the quarry tunnel. "
                    "He learns the route.", 4: "Iven leads Mara from the open archive toward the quarry tunnel "
                    "and tells her the route. She learns it explicitly; Iven sees her respond."}
        return self.ask("rewrite_retcon" if retcon else "draft_" + str(scene_ids), {
            "task": "Write vivid connected novel prose, 100-160 words per scene. Return {scenes:[{id,day,text}]}. "
                    "Return ONLY the requested scene IDs, no additional scene. Use these exact days. "
                    "Each event happens in its own scene/day. "
                    "No extra characters, powers, injuries, possessions or historical revelations. "
                    "The map stays where it is: nobody takes, pockets or carries it. Do not invent the "
                    "tunnel's destination, size, exits or connection to the surface. Descriptions may convey "
                    "temporary sensations, not new durable world facts or changes beyond the supplied beats. "
                    "CRITICAL: the archive door remains OPEN through scene4; never describe it shutting or closing. "
                    "Describe the marked quarry-tunnel route only. Make NO claim about how many routes exist, "
                    "whether there are other routes, or that this route is the only way/path/exit. "
                    "In scene4 name Mara and explicitly show that Mara learned or understood the route; "
                    "dialogue directed toward her alone does not establish her knowledge. "
                    "Scene4 MUST perform departure on the page: Iven led Mara out of the archive toward the tunnel. "
                    "Pointing, planning, agreeing or being ready does not perform the journey. "
                    "Only Iven knows the route before scene4's explanation. Mara learns it during that conversation; "
                    "do not describe her already knowing or having memorized it before he tells her. "
                    "Do not invent hazards, unstable edges, floor drops, tunnel width, bends, turns or left/right "
                    "instructions. The only new route information communicated is its name: quarry tunnel. "
                    "Keep dialogue and dramatic hesitation, but explicitly perform every required action.",
            "scenes": [{"id": i, "day": d} for i, d in zip(scene_ids, days)],
            "beats": {str(i): beats[i] for i in scene_ids},
            "canon": canon, "previous_prose": previous, "retcon": retcon,
            "retcon_constraint": "For the revised edition the handoff/password move from day12 to day14; "
                                 "opening to15, reading to16, journey/disclosure to17. Preserve participants "
                                 "and causal chain. All prose is provisional pending exact approval and commit."},
            lambda v: validate_scenes(v, days, scene_ids), tokens=4500)

    def extract(self, scenes):
        if not self.model:
            rows = [{"kind": k, "scene": i, "day": next(s["day"] for s in scenes if s["id"] == i),
                     "excerpt": next(s["text"] for s in scenes if s["id"] == i)}
                    for k, i in KINDS.items() if i in {s["id"] for s in scenes}]
            return validate_extraction({"claims": rows}, scenes)
        required = {k: s for k, s in KINDS.items() if s in {r["id"] for r in scenes}}
        meanings = {"handoff": "key passes Mara->Iven", "password": "Mara tells Iven cairn and he learns it",
                    "opening": "Iven opens archive door", "route": "map route quarry tunnel and Iven learns it",
                    "journey": "Iven leads Mara toward quarry tunnel", "disclosure": "Iven tells Mara route, she learns it"}
        return self.ask("extract_exact_passages", {
            "task": "Locate exact contiguous verbatim excerpts for the supplied material-change inventory. "
                    "Return {claims:[{kind,scene,day,excerpt}]}. Excerpts must include the action/knowledge "
                    "acquisition, not merely anticipation. Each excerpt must occur exactly once. "
                    f"Return exactly {len(required)} rows. Each required kind appears exactly ONCE, "
                    "even if several sentences describe that change; choose one contiguous excerpt. No extra keys.",
            "required_kinds": required, "meanings": {k: meanings[k] for k in required},
            "scenes": scenes}, lambda v: validate_extraction(v, scenes), tokens=3200)

    def verify(self, scenes, claims, canon, candidate=None):
        # Build this boundary in regression mode too: public proposals contain
        # operations; compiled assignments come from the existing author review.
        candidate_evidence = {"proposal_reference": self.s.reference(candidate),
                              "compiled_changes": self.last_review["changes"],
                              "validation": self.last_validation} if candidate else None
        readable_candidate = focused_evidence(canon["research_records"]["records"],
            self.last_review["changes"]) if candidate else None
        readable_active_base = focused_evidence(canon["research_records"]["records"],
            [{"next": r} for r in canon["state"]["assertions"]])
        if not self.model:
            return
        result = self.ask("verify_provisional_prose", {
            "task": "Review this provisional prose against the pinned canon, exact proposed changes and "
                    "source excerpts. The candidate is pending publication; engine findings concern structured "
                    "checks. Identify conflicts, missing support and material claims absent from the supplied "
                    "inventory. Return only {usable_after_commit:boolean,issues:[string]}; usable_after_commit "
                    "means no unresolved material continuity issue was found in this review, conditional on "
                    "publication of the supplied candidate. Explain each issue. A positive engine result alone "
                    "does not establish that prose supports its proposed interpretation.",
            "scenes": scenes, "located_inventory_excerpts": claims, "canon": canon,
            "active_base_evidence": readable_active_base, "focused_candidate_evidence": readable_candidate,
            "candidate": candidate_evidence}, lambda v: v, tokens=2300)
        self.report.setdefault("prose_verification", []).append(result)
        require(result.get("usable_after_commit") is True and result.get("issues") == [],
                "model continuity review rejected prose")

    def propose(self, operations, key):
        args = {"action": "create", "universe": NAME, "context_id": self.s.ctx,
                "operations": operations, "submission": "submitted", "rationale": key,
                "idempotency_key": key}
        decision = self.decision("propose_" + key, "universe_propose", args)
        p = self.s.call(decision["tool"], decision["arguments"])["result"]
        args = {"mode": "proposal", "universe": NAME, "context_id": self.s.ctx,
                "proposal_reference": self.s.reference(p), "check_scope": "universe"}
        decision = self.decision("validate_" + key, "universe_validate", args)
        v = self.s.call(decision["tool"], decision["arguments"])["result"]
        require(v["coverage"] == "complete" and not v["findings"], f"continuity rejected {key}: {v}")
        self.last_validation = v
        self.last_review = self.s.admin("review", NAME, p["proposal_id"], p["version"], p["digest"])
        return p


def proposition(s, subject, predicate, value, context=None):
    return {"subject": s.rr(subject), "predicate": s.rr(predicate), "value": value,
            "context": s.rr(context or s.u["context_id"]), "quantification": "particular"}


def text_value(text):
    return {"kind": "text", "text": text}


def claim(s, n, subject, predicate, value, start, end=None, basis=None):
    return {"kind": "assert_proposition", "client_ref": s.rid(n),
            "proposition": proposition(s, subject, predicate, value), "assertion": {
                "proposition": s.rr(n), "polarity": "support", "scope": s.scope,
                "validity": s.interval(start, end), "persistence": "explicit_interval", "precision": "exact",
                "basis": basis or {"kind": "author_decision", "note": "Synthetic pilot premise"}}}


def narrative(s, n, kind, payload):
    return {"kind": "record_narrative_reference", "client_ref": s.rid(n), "record": kind,
            "payload": {"record_kind": kind, **payload}}


def seed(s):
    ops = [{"kind": "create_entity", "client_ref": s.rid(n), "record": {
        "names": [], "types": [], "worldAssociations": [], "labels": {"en": label}, "metadata": {}}}
        for n, label in ((1, "Mara"), (2, "Iven"), (3, "Copper key"), (4, "Archive door"), (5, "Map"))]
    ops.append({"kind": "define_action", "client_ref": s.rid(31), "record": {
        "namespace": "pilot", "key": "ordinary_story_action", "labels": {},
        "requirements": [], "scope": s.scope, "validity": {"kind": "unspecified"}}})
    for n, key, shape in ((10, "holder", {"kind": "entity_ref", "subject_types": []}),
                          (11, "open", {"kind": "boolean"}), (12, "route", {"kind": "text"}),
                          (13, "password", {"kind": "text"})):
        ops.append({"kind": "define_property", "client_ref": s.rid(n), "record": {
            "namespace": "pilot", "key": key, "labels": {}, "subjectTypes": [], "value": shape,
            "multiplicity": "single", "persistence": "explicit_interval", "exclusive": True,
            "symmetric": False, "transitive": False}})
    for n, holder in ((40, 1), (41, 2)):
        ops.append(narrative(s, n, "represented_context", {"universe": s.uid,
            "kind": {"kind": "character", "holder": s.rr(holder)}, "parent": s.scope["context"],
            "labels": {"en": "Mara viewpoint" if holder == 1 else "Iven viewpoint"}}))
    ops += [claim(s, 20, 3, 10, {"kind": "entity_ref", "ref": s.rr(1)}, 10, 12),
            claim(s, 21, 4, 11, {"kind": "boolean", "value": False}, 10, 13),
            claim(s, 22, 4, 13, text_value("cairn"), 10),
            {"kind": "define_proposition", "client_ref": s.rid(25),
             "record": proposition(s, 3, 10, {"kind": "entity_ref", "ref": s.rr(2)})},
            {"kind": "define_proposition", "client_ref": s.rid(26),
             "record": proposition(s, 4, 11, {"kind": "boolean", "value": True})},
            {"kind": "create_work", "client_ref": s.rid(30), "record": {"kind": "novel",
             "title": "The Cairn Archive", "labels": {}, "sourceRefs": [], "versions": [], "worldAssociations": []}}]
    receipt = s.publish(s.propose(ops, "seed-premises"), "seed-premises-commit")
    # Context-bearing proposition changes must be submitted in that context.
    # Mentioning these propositions does not yet establish character knowledge.
    for context, values in ((41, ((27, 4, 13, "cairn"), (28, 5, 12, "quarry tunnel"))),
                            (40, ((29, 5, 12, "quarry tunnel"),))):
        s.ctx = s.open(represented=s.rid(context))["context_id"]
        ops = [{"kind": "define_proposition", "client_ref": s.rid(n),
                "record": proposition(s, subject, predicate, text_value(value), context)}
               for n, subject, predicate, value in values]
        s.publish(s.propose(ops, f"seed-context-{context}"), f"seed-context-{context}-commit")
    return receipt


def precondition(s, subject, predicate, value):
    return {"kind": "claim", "subject": {"kind": "record", "ref": s.rr(subject)},
            "predicate": predicate, "value": {"kind": "value", "value": value}, "polarity": "support"}


def event(s, day, participants, label, preconditions=None, effect=None):
    return {"occurrence": "occurred", "action": s.rr(31), "time": s.instant(day), "participants": [
        {"record": s.rr(n), "role": role} for n, role in participants],
        "labels": {"en": label}, "preconditions": preconditions or [], "effects": [] if effect is None else [{
            "slot": "state", "proposition": s.rr(effect), "polarity": "support",
            "validity": s.interval(day), "scope": s.scope, "order": 0}]}


def anchors(s, source, scenes, extracted, offset):
    text = manuscript(scenes)
    return [{"kind": "add_source_anchor", "client_ref": s.rid(offset + i),
             "record": source_anchor(s.uid, source, text, row["excerpt"], s.scope["context"])}
            for i, row in enumerate(extracted.values())], {k: s.rr(offset + i) for i, k in enumerate(extracted)}


def knowledge(s, n, holder, prop, day, anchor):
    return {"kind": "add_belief", "client_ref": s.rid(n), "record": {"holder": s.rr(holder),
            "proposition": s.rr(prop), "attitude": "knows", "validity": s.interval(day),
            "basis": {"kind": "source_anchor", "anchor": anchor, "verified": True}}}


def observation(s, n, observer, observed, day, anchor):
    return {"kind": "record_observation", "client_ref": s.rid(n), "record": {
        "observer": s.rr(observer), "observed": s.rr(observed), "sensoryAccess": True,
        "time": s.instant(day), "basis": {"kind": "source_anchor", "anchor": anchor, "verified": True}}}


def original_changes(s, a, days, continuation=False):
    d1, d2, d3, d4 = days
    if continuation:
        return [{"kind": "record_event", "client_ref": s.rid(63), "record": event(s, d4,
            [(2, "guide"), (1, "traveller")], "Journey toward quarry tunnel", [
                precondition(s, 4, "pilot:open", {"kind": "boolean", "value": True})])},
            knowledge(s, 72, 1, 29, d4, a["disclosure"]),
            observation(s, 83, 2, 63, d4, a["journey"])]
    return [
        {"kind": "record_event", "client_ref": s.rid(60), "record": event(s, d1,
         [(1, "giver"), (2, "receiver"), (3, "object")], "Key handoff", [
            precondition(s, 3, "pilot:holder", {"kind": "entity_ref", "ref": s.rr(1)})], 25)},
        {"kind": "record_event", "client_ref": s.rid(61), "record": event(s, d2,
         [(2, "opener"), (4, "door")], "Archive opened", [
            precondition(s, 3, "pilot:holder", {"kind": "entity_ref", "ref": s.rr(2)})], 26)},
        {"kind": "record_event", "client_ref": s.rid(62), "record": event(s, d3,
         [(2, "reader"), (5, "map")], "Route read", [
            precondition(s, 4, "pilot:open", {"kind": "boolean", "value": True})])},
        knowledge(s, 70, 2, 27, d1, a["password"]), knowledge(s, 71, 2, 28, d3, a["route"]),
        claim(s, 23, 5, 12, text_value("quarry tunnel"), d3,
              basis={"kind": "source_anchor", "anchor": a["route"], "verified": True}),
        observation(s, 80, 1, 60, d1, a["handoff"]), observation(s, 81, 2, 61, d2, a["opening"]),
        observation(s, 82, 2, 62, d3, a["route"])]


def bind_passages(s, scenes, a, facts_revision, offset, label):
    edition = offset + 20
    p = s.propose([narrative(s, edition, "work_version", {"work": s.rr(30), "versionLabel": label,
        "binding": {"kind": "bound", "continuity": s.u["continuity_id"], "revision": facts_revision}})], label + "-edition")
    s.publish(p, label + "-edition-commit")
    version = s.get([s.rid(edition)])[0]
    vr = {"universe": s.uid, "record": s.rid(edition), "version": version["record_version_id"]}
    ops = [narrative(s, offset + 30 + i, "passage_ref", {"workVersion": vr,
           "passageId": f"{label}:scene-{KINDS[k]}:{k}", "anchor": anchor}) for i, (k, anchor) in enumerate(a.items())]
    ops += [narrative(s, offset + 40 + scene["id"], "scene_ref", {"workVersion": vr,
            "sceneId": f"{label}:scene-{scene['id']}", "viewpoint": s.rr(1 if scene["id"] == 1 else 2),
            "narrativePosition": scene["id"], "depictedEvents": [s.rr(59 + scene["id"])],
            "narrationFrame": s.scope["context"], "worldAssociations": []}) for scene in scenes]
    receipt = s.publish(s.propose(ops, label + "-passages"), label + "-passages-commit")
    return {"edition": version, "passage_ids": [op["client_ref"] for op in ops if op["record"] == "passage_ref"],
            "revision": receipt["revision"]}


def current_values(s, day, revision=None):
    state = s.state([s.rid(n) for n in (1, 2, 3, 4, 5)], day, revision=revision)
    require(not state["result"]["unresolved_assertion_ids"], "unresolved story times")
    knowledge_states = [s.state([s.rid(holder)], day, revision=revision,
                        context=s.rid(context), perspective={"character": s.rid(holder)}) for holder, context in ((1, 40), (2, 41))]
    return {"holder": fixture_supported_values(state, s.rid(10)),
            "open": fixture_supported_values(state, s.rid(11)),
            "route": fixture_supported_values(state, s.rid(12)), "state": state,
            "knowledge_states": knowledge_states}


def audit_provenance(s, source, scenes, extracted, citations, references, knowledge_ids, observation_ids):
    """Independently check the persisted graph, not just operation construction."""
    text = manuscript(scenes).encode("utf-8")
    passage_records = s.get(references["passage_ids"])
    actual_anchors = s.get([r["record"] for r in citations.values()])
    anchor_map = {r["identity"]["record_id"]: r for r in actual_anchors}
    require(len(passage_records) == len(extracted), "missing committed passages")
    for k, citation in citations.items():
        anchor = anchor_map[citation["record"]]["payload"]
        expected = source_anchor(s.uid, source, manuscript(scenes), extracted[k]["excerpt"], s.scope["context"])
        require({key: anchor[key] for key in expected} == expected, "persisted anchor differs from immutable source")
        loc = anchor["locator"]
        require(text[loc["start"]:loc["end"]].decode("utf-8") == anchor["excerpt"], "byte range differs from excerpt")
        passage = [p for p in passage_records if p["payload"]["passageId"].endswith(":" + k)]
        require(len(passage) == 1 and passage[0]["payload"]["anchor"] == citation, "passage points to wrong anchor")
        edition = references["edition"]
        require(passage[0]["payload"]["workVersion"] == {"universe": s.uid,
                "record": edition["identity"]["record_id"], "version": edition["record_version_id"]},
                "passage edition is not exact")
    evidence = s.get([s.rid(n) for n in [*knowledge_ids, *observation_ids]])
    for r in evidence:
        basis = r["payload"]["basis"]
        require(basis["kind"] == "source_anchor" and basis["anchor"]["record"] in anchor_map,
                "material knowledge/event witness has no exact source citation")
    # Event effects remain linked through their generating event, rather than
    # inventing a second assertion source or changing their sealed expansion.
    effects = s.state([s.rid(3), s.rid(4)], max(row["day"] for row in scenes))["result"]["assertions"]
    event_bases = [r["payload"]["basis"] for r in effects if r["payload"]["basis"]["kind"] == "event_effect"]
    witnesses = {r["payload"]["observed"]["record"] for r in evidence
                 if r["payload"]["record_kind"] == "observation"}
    if len(scenes) > 1:
        require(all(b["event"]["record"] in witnesses for b in event_bases), "event effect lost source witness")
    return {"source_version": source, "anchors": actual_anchors, "passages": passage_records,
            "material_evidence": evidence, "event_effect_bases": event_bases}


def check_timeline(s, days, revision=None):
    d1, d2, d3, d4 = days
    rows = {}
    for day in sorted({10, d1 - 1, d1, d2 - 1, d2, d3 - 1, d3, d4 - 1, d4}):
        row = current_values(s, day, revision)
        require(row["holder"] == [{"kind": "entity_ref", "ref": s.rr(1 if day < d1 else 2)}], "wrong custody")
        require(row["open"] == [{"kind": "boolean", "value": day >= d2}], "wrong door state")
        require(row["route"] == ([] if day < d3 else [text_value("quarry tunnel")]), "wrong route validity")
        attitudes = [r for st in row["knowledge_states"] for r in st["result"]["epistemic"]]
        expected = {s.rid(n) for n, when in ((70, d1), (71, d3), (72, d4)) if day >= when}
        actual = {r["identity"]["record_id"] for r in attitudes}
        # Retcon replaces authored attitudes with different immutable identities.
        if revision is None and min(days) == 14:
            expected = {s.rid(n + 300) for n, when in ((70, d1), (71, d3), (72, d4)) if day >= when}
        require(actual == expected, f"knowledge boundary failed day {day}: {actual} != {expected}")
        rows[str(day)] = row
    return rows


def revise_event(s, n, day):
    old = s.get([s.rid(n)])[0]
    replacement = {k: v for k, v in old["payload"].items() if k != "record_kind"}
    replacement["time"] = s.instant(day)
    for effect in replacement["effects"]:
        effect["validity"] = s.interval(day)
    return {"kind": "revise_event", "record": s.rr(n), "expected_version": old["record_version_id"],
            "replacement": replacement}


def replace_assertion(s, proposition_id, start, end, basis=None):
    state = s.state([s.rid(n) for n in (3, 4, 5)], 10 if proposition_id != 23 else 16)
    matches = [r for r in state["result"]["assertions"] if r["payload"]["proposition"]["record"] == s.rid(proposition_id)]
    require(len(matches) == 1, "assertion identity not unique")
    old = matches[0]
    replacement = {k: v for k, v in old["payload"].items() if k != "record_kind"}
    replacement["validity"] = s.interval(start, end)
    if basis:
        replacement["basis"] = basis
    return {"kind": "supersede_assertion", "record": s.rr(old["identity"]["record_id"]),
            "expected_version": old["record_version_id"], "replacement": replacement,
            "rationale": "Author selected delayed handoff retcon; repair dependent chronology"}


def run(args, report):
    model = None if args.regression else LocalModel(args.model, args.seed)
    report["mode"] = "deterministic_regression" if args.regression else "MLX_generated_prose"
    if model:
        report["model"] = {"path": str(args.model), "seed": args.seed, "temperature": 0.0,
            "files": artifact_manifest(args.model), "metrics": model.metrics,
            "environment": {p: importlib.metadata.version(p) for p in ("mlx", "mlx-lm", "transformers", "jsonschema")},
            "platform": platform.platform()}
    with tempfile.TemporaryDirectory(prefix="ub-chapter-", dir="/tmp") as directory:
        s = PilotSession(directory, args.bin_dir, report)
        try:
            s.start()
            report["server_instructions"] = s.instructions
            report["seed"] = seed(s)
            writer = Writer(model, s, report)
            canon = writer.research("before_chapter", 11)
            scenes = writer.draft(ORIGINAL_DAYS[:3], [1, 2, 3], canon)
            claims = writer.extract(scenes)
            report["original_scenes"], report["original_extraction"] = scenes, claims
            (args.output / "original-chapter.txt").write_text(manuscript(scenes), encoding="utf-8")
            source, _ = s.stage(manuscript(scenes), "Original chapter", "original")
            ops, a = anchors(s, source, scenes, claims, 100)
            p = writer.propose(ops + original_changes(s, a, ORIGINAL_DAYS), "chapter-material")
            writer.verify(scenes, claims, canon, p)
            receipt = s.publish(p, "chapter-material-commit", writer)
            original = bind_passages(s, scenes, a, receipt["revision"], 100, "original")
            report["original_provenance"] = original
            report["original_source_graph"] = audit_provenance(s, source, scenes, claims, a, original, (70, 71), (80, 81, 82))
            canon = writer.research("fresh_after_chapter", 15)
            continuation = writer.draft([15], [4], canon, scenes)
            extracted = writer.extract(continuation)
            report["continuation_scenes"], report["continuation_extraction"] = continuation, extracted
            (args.output / "continuation.txt").write_text(manuscript(continuation), encoding="utf-8")
            continuation_source, _ = s.stage(manuscript(continuation), "Continuation", "continuation")
            ops, ca = anchors(s, continuation_source, continuation, extracted, 200)
            p = writer.propose(ops + original_changes(s, ca, ORIGINAL_DAYS, True), "continuation-material")
            writer.verify(continuation, extracted, canon, p)
            receipt = s.publish(p, "continuation-material-commit", writer)
            continuation_refs = bind_passages(s, continuation, ca, receipt["revision"], 200, "continuation")
            report["continuation_source_graph"] = audit_provenance(s, continuation_source, continuation,
                extracted, ca, continuation_refs, (72,), (83,))
            old_revision = continuation_refs["revision"]
            report["original_timeline"] = check_timeline(s, ORIGINAL_DAYS)
            # Reader knowledge/presence remain separate; character view has explicit knowledge only.
            character = s.state([s.rid(2)], 14, context=s.rid(41), perspective={"character": s.rid(2)})
            require({r["identity"]["record_id"] for r in character["result"]["epistemic"]} == {s.rid(70), s.rid(71)},
                    "character view omitted authored knowledge or leaked another holder")
            report["character_view"] = character
            all_passages = original["passage_ids"] + continuation_refs["passage_ids"]
            # Research must connect an event -> observation -> exact anchor -> passage.
            research = s.call("universe_get_context", {"universe": NAME, "context_id": s.ctx,
                "focus_ids": [s.rid(60)], "purpose": "Trace handoff to source passage", "byte_budget": 65536})
            require(research["delivery"]["complete"], "provenance research truncated")
            serialized = json.dumps(research["result"])
            require(original["passage_ids"][list(claims).index("handoff")] in serialized,
                    "research did not include passage behind handoff evidence")
            report["provenance_research"] = research
            # An existing entity cannot masquerade as a source anchor.
            bad = s.propose([knowledge(s, 900, 2, 27, 12, s.rr(1))], "invalid-citation")
            report["invalid_citation"] = s.validate(bad, error=True)
            require(report["invalid_citation"]["code"] == "INVALID_ARGUMENT", "citation was not structurally rejected")
            altered = source_anchor(s.uid, source, manuscript(scenes), claims["handoff"]["excerpt"], s.scope["context"])
            altered["excerptDigest"] = "0" * 64
            bad = s.propose([{"kind": "add_source_anchor", "client_ref": s.rid(902), "record": altered}], "tampered-excerpt")
            report["tampered_excerpt"] = s.validate(bad, error=True)
            require(report["tampered_excerpt"]["code"] == "INVALID_ARGUMENT", "tampered excerpt digest was accepted")
            # Keep a fully validated, approved proposal stale across the retcon.
            stale = s.propose([{"kind": "create_entity", "client_ref": s.rid(901), "record": {
                "names": [], "types": [], "worldAssociations": [], "labels": {"en": "Stale marker"}, "metadata": {}}}], "stale-marker")
            sv = s.validate(stale)
            s.approval(stale, sv)
            # Partial retcon: opening day13 must fail without day12 custody and knowledge.
            naive = s.propose([revise_event(s, 60, 14), replace_assertion(s, 20, 10, 14)], "incomplete-retcon")
            invalid = s.validate(naive, error=True)
            require(invalid["code"] == "INVALID_ARGUMENT" and invalid.get("field") == "event.preconditions",
                    "partial retcon was not rejected by the causal prerequisite check")
            report["retcon_conflicts"] = invalid
            impact = s.impact(naive)
            require(impact["delivery"]["complete"], "retcon impact incomplete")
            impact_text = json.dumps(impact["result"])
            require(all(r in impact_text for r in all_passages), "retcon impact lost affected original passages")
            report["retcon_impact"] = {"response": impact, "affected_passages": s.get(all_passages),
                                      "scope": "conservative full-universe closure; passages selected by explicit evidence links"}
            revised_canon = writer.research("before_retcon", 13)
            revised = writer.draft(REVISED_DAYS, [1, 2, 3, 4], revised_canon, scenes + continuation, True)
            revised_claims = writer.extract(revised)
            # Validation below checks the fully resolved candidate; old canon is deliberately contradicted.
            report["revised_scenes"], report["revised_extraction"] = revised, revised_claims
            (args.output / "revised-chapter.txt").write_text(manuscript(revised), encoding="utf-8")
            revised_source, _ = s.stage(manuscript(revised), "Delayed handoff edition", "revised")
            ops, ra = anchors(s, revised_source, revised, revised_claims, 400)
            ops += [revise_event(s, n, day) for n, day in zip((60, 61, 62, 63), REVISED_DAYS)]
            ops += [replace_assertion(s, 20, 10, 14), replace_assertion(s, 21, 10, 15),
                    replace_assertion(s, 23, 16, None, {"kind": "source_anchor", "anchor": ra["route"], "verified": True})]
            for n in (70, 71, 72, 80, 81, 82, 83):
                old = s.get([s.rid(n)])[0]
                ops.append({"kind": "tombstone_record", "record": s.rr(n), "expected_version": old["record_version_id"],
                            "rationale": "Replace retconned evidence in this edition; retain immutable prior revision"})
            ops += [knowledge(s, 370, 2, 27, 14, ra["password"]), knowledge(s, 371, 2, 28, 16, ra["route"]),
                    knowledge(s, 372, 1, 29, 17, ra["disclosure"])]
            ops += [observation(s, 380 + i, 1 if i == 0 else 2, 60 + i, day,
                    ra[k]) for i, (day, k) in enumerate(zip(REVISED_DAYS, ("handoff", "opening", "route", "journey")))]
            p = writer.propose(ops, "resolved-retcon")
            writer.verify(revised, revised_claims, revised_canon, p)
            receipt = s.publish(p, "resolved-retcon-commit", writer)
            report["revised_provenance"] = bind_passages(s, revised, ra, receipt["revision"], 400, "revised")
            report["revised_source_graph"] = audit_provenance(s, revised_source, revised, revised_claims,
                ra, report["revised_provenance"], (370, 371, 372), (380, 381, 382, 383))
            report["revised_timeline"] = check_timeline(s, REVISED_DAYS)
            report["historical_timeline"] = check_timeline(s, ORIGINAL_DAYS, old_revision)
            stale_error = s.call("universe_commit", s.commit_args(stale, sv, "stale-commit"), error=True)
            require(stale_error["code"] in {"BASE_REVISION_CONFLICT", "APPROVAL_STALE"}, "stale commit was not rejected")
            report["stale_rejection"] = stale_error
            historical = s.get([source["identity"]["record_id"]], context=s.open(old_revision)["context_id"])[0]
            require(historical == source, "original immutable source version changed")
            report["original_source_preserved"] = historical
            final_canon = writer.research("fresh_after_retcon", 17)
            if model:
                writer.verify(revised, revised_claims, final_canon)
            # Durable engine restart, exact receipt recovery, no new publication.
            s.restart()
            operation = s.call("universe_get_operation", {"lookup": "key", "universe": NAME,
                "operation_kind": "commit", "idempotency_key": "resolved-retcon-commit"})
            require(operation["result"]["receipt"] == receipt, "durable receipt recovery differed")
            publication = next(r for r in report["publications"] if r["key"] == "resolved-retcon-commit")
            require(s.call("universe_commit", publication["commit_arguments"])["result"] == receipt,
                    "restart retry republished or changed receipt")
            report["restart_receipt"] = operation
            report["restarted_timeline"] = check_timeline(s, REVISED_DAYS)
            report["continuation_provenance"] = continuation_refs
            report["checks"] = {key: True for key in ("exact_source_links", "canonical_commits", "fresh_context",
                "character_knowledge", "retcon_conflict_detected", "affected_passages", "resolved_retcon",
                "historical_revision", "stale_commit_denied", "restart_receipt_recovery")}
            report["status"] = "pass"
        finally:
            s.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, default=Path("target/debug"))
    parser.add_argument("--model", type=Path)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--regression", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(args.regression or args.model and args.model.is_dir(), "supply an existing MLX model or --regression")
    args.bin_dir = args.bin_dir.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    report = {"status": "running", "limitations": ["Directed writing and excerpt location for a supplied inventory; not independent claim discovery",
        "Impact is conservative full-universe coverage, not minimal causal passage selection",
        "Exact citations verify bytes, not semantic truth; model review remains fallible",
        "Application JSON dispatch, not a native host function-calling qualification",
        "Event knowledge prerequisites cannot span represented contexts; pilot checks explicit knowledge timelines separately"]}
    try:
        run(args, report)
    except Exception as error:
        report["status"], report["error"] = "failure", f"{type(error).__name__}: {error}"
        report["traceback"] = traceback.format_exc()
        raise
    finally:
        (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"status": report["status"], "report": str(args.output / "report.json")}))


if __name__ == "__main__":
    main()
