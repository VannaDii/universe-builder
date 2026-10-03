# G02: authored action applicability

The October 2, 2026 qualification uses the accepted
[ADR-0006](adr/ADR-0006-declared-actions-and-owner-attributes.md) contract. Authors
declare the capabilities an action needs; the engine checks those requirements
on the named owner immediately before the event. Life, bodily capability and
agency are separate attributes. This does not add a universal life requirement,
classify prose automatically or constrain an action's consequences.

## Authoring requirements

Define a typed property for each relevant capability, then use `define_action`
with mandatory `{role, predicate, value}` requirements. Each required role must
identify exactly one entity. Keep the action's represented context and world
scope explicit. Empty requirements declare an ordinary action, so authors must
review whether that classification matches the intended passage.

This synthetic vocabulary has five definitions:

| Action | Mandatory owner requirements |
|---|---|
| Breathing-dependent action | `actor.breathing = true` |
| Conscious inspection | `actor.conscious = true` |
| Undead speech | `actor.speech = true` |
| Carry an unconscious body | `actor.conscious = true`, `actor.mobile = true` |
| Author-selected capability transition | Explicit empty requirements |

For example, conscious inspection declares:

```json
{"requirements":[{"role":"actor","predicate":{"universe":"<universe ID>","record":"<conscious property ID>"},"value":{"kind":"boolean","value":true}}]}
```

The last definition allows synthetic authored incapacity and restoration events;
it does not certify a general healing/resurrection mechanism. The author supplies
their effects explicitly through the existing event contract. Carrying the body
has an actual location effect on the patient, whose consciousness is not a
requirement. Undead speech uses explicit speech evidence despite life and
breathing being explicitly false.

Assertions must establish the required value on that owner in the intended
context/world, with usable validity and persistence. A proposition alone is not
evidence. Missing, expired, conflicting or unknown evidence cannot authorize an
action. A companion's attributes and optional prerequisites cannot replace
mandatory owner requirements. An action's own effects cannot satisfy its
preconditions retroactively.

When canon changes, end or supersede old positive evidence explicitly. The
fixture uses generated event assertions so the existing compiler reconciles
their intervals: consciousness begins at 10, ends at incapacity 20 and returns
at restoration 30. Immediately before 10 it is unavailable; immediately before
20 it still holds; immediately before 30 the actor remains unconscious. Ordinary
state queries at those coordinates see the post-state. Another event at the same
coordinate does not receive an invented sequence order.

## Proof method

The separately authored [outcome oracle](../scripts/continuity_gap/g02-oracle.json)
specifies twenty stimuli, expected admissions and the original/corrected state
timelines. The producer does not import it. The
[independent auditor](../scripts/audit_g02.py) imports neither the runner nor the
rules engine. It calculates capabilities from saved candidate assertions using
strict pre-event interval comparisons and compares those calculations with the
oracle and actual MCP responses.

The auditor pairs actual JSON-RPC requests and responses, verifies exact
persisted proposals, validation bindings, private synthetic author reviews and
approvals, canonical assignments, kernel receipts and idempotent retries. It
reconstructs original and corrected revisions from SQLite history, checks
queried state against those records and verifies head membership and recovery
after terminating only the disposable engine. Negative audit tests alter a wire
owner, oracle, approval, receipt and head membership; each must fail verification.
This is an independent program and storage audit, not an external human review.

The earlier incapacity retcon moves 20 to 18 while retaining actions at 19 and
20. It must fail. Separate candidates remove one dependent action at a time to
prove each remaining action is invalidated. The corrected proposal moves both
actions to 17 and commits. Original history remains unchanged.

Reproduce with an interpreter containing the project's pinned `jsonschema`:

```sh
python scripts/g02_pilot.py --output /tmp/g02-new
cargo test --locked -p universe-service g02_ -- --nocapture
python scripts/audit_g02.py /tmp/g02-new
python scripts/test_g02_pilot.py --evidence /tmp/g02-new -v
```

Use a fresh output directory. The pilot retains failures and records source and
binary hashes; it touches no production universe. CI runs the deterministic
pilot, including its independent audit and adversarial audit checks. Structured
action qualification does not establish unrestricted prose extraction, automatic
genre inference, native UI acceptance or broader G03/G04 consequence contracts.

## Execution results

[Accepted run 5](evidence/g02-2026-10-02-run5/result.json) passes all twenty
independently specified outcomes: thirteen constrained illegal actions fail
validation and commit attempts; seven legal controls commit. The sequence has
158 public MCP calls and nine approved publications (seed, seven controls and
corrected retcon), with exact receipts, history and restart recovery. Both
unchanged dependent actions are independently invalidated by the earlier retcon.
The [audit](evidence/g02-2026-10-02-run5/audit.json),
[wire transcript](evidence/g02-2026-10-02-run5/mcp-transcript.jsonl),
[producer report](evidence/g02-2026-10-02-run5/report.json) and
[saved package](evidence/g02-2026-10-02-run5/package.sqlite) are committed proof
artifacts. Source/binary identities and artifact hashes accompany them.

All three focused Rust regressions pass. The full workspace gate passes
formatting, strict Clippy, 312 Rust tests and generated schema drift, with one
explicitly ignored workload. Seven audit tests pass: the intact evidence plus
six corruptions, including a forged allowed outcome with a rebound oracle hash.
That forgery still fails the auditor's independent capability calculation.

No engine implementation defect was demonstrated in this scope. Existing
ADR-0006 enforcement supplies the required behavior; changes add the authored
synthetic vocabulary, regressions, audited qualification, documentation and CI
coverage. No evaluator or canonical format change is necessary.

The first four fixture attempts are excluded from qualification. Their
[retained errors](evidence/g02-2026-10-02-run5/attempts.json) distinguish setup and
audit failures: (1) an unknown refutation in seed canon made validation partial;
it now belongs solely to its rejected candidate, (2) a tombstone probe used
`reason` instead of the existing `rationale` field, (3) the correction helper
treated an existing record ID as an integer, and (4) the auditor initially failed
to account for the documented empty `worlds` default when comparing submitted
operations with their normalized stored form. Run 5 uses the final unchanged
source/binary hashes and passes the producer, independent audit and negative tests.
