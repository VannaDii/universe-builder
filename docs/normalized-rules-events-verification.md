# Normalized rules, actions and events verification

October 3, 2026. Scoped continuation of the
[normalized foundation](normalized-foundation-verification.md) and approved
[relational model](decisions/relational-storage/README.md).

## Storage and preservation

The foundation's closed catalog already contains the requested domain types.
This slice qualifies their existing transactional runtime route instead of
introducing duplicate models or changing evaluation:

| Canonical family | Typed relational body and children | Preserved authority |
|---|---|---|
| Rule | `r_payload_v22`, `r_expr` and its closed branches | Expression tree, operands, policy, scope, validity, capabilities and author wording |
| Action | `r_payload_v26`, ordered requirements, `r_attribute_requirement`, `ConsequenceContract`, `r_effect_slot` | Owner role, predicate and exact required value; declared slot, target, condition, change, order and lifetime |
| Event | `r_payload_v24`, `r_event_participant`, `r_entity_effect`, expression children | Occurrence, action, participants, preconditions, effects, authored order and temporal boundaries |
| Generated assertion | `r_payload_v18`, `r_event_effect_ref`, typed scope/value/time | Stable generated identity, establishing event and slot, exact proposition, polarity and lifetime |

The MCP auditors now reconstruct record versions directly from typed rows using
`relational_history.py` and the separately implemented decision-package reader.
Every reconstructed payload must reproduce the stored canonical SHA-256 digest.
Commit changes independently reconstruct historical memberships, which must
match the exact reviewed original versions. The readers import neither the Rust
writer nor evaluator. Workflow envelopes retain their existing storage and are
checked separately; they are not the source of canonical readback.

Pilot inputs use the current explicit classification and attribute modes and
consequence declaration. Frozen historical fixtures and original digest files
remain unchanged. The owner pilot declares its existing consciousness and
movement effects, with separate restoration/incapacity action definitions so
each declaration preserves an exact value and the original event/slot identities.
The accounting history uses an actual Gun → Pistol classification.

## Focused semantic proof

`object_rule_capability_checks.rs` publishes all 26 existing frozen capability
specimens through the kernel, closes the database, runs independent SQL/hash
reconstruction, reopens it and evaluates with both indexed and direct paths.
The frozen legal, illegal, unresolved, exception, world-scope, finite-domain and
known-limitation outcomes remain unchanged. Stored rules retain protected status.

`cedar-capabilities.json` adds ten independently frozen versions to the 32-record
Cedar foundation. Eight queries run before and after storage, with both evaluator
paths. They retain nested expression structure, shared growth, explicit instance
growth, a protected owner-bound climbing requirement, instance hazard scope and
height boundaries. Explicit instance growth is supported; its negation is
refuted. Shared growth with unspecified validity, unbound subjects, empty-world
hazard evidence and unverified height remain unresolved. Growth does not invent
or extend a height assertion. All original payload digests survive readback.

The existing typed-codec proofs also exercise every existing expression branch,
exact values, absent/null distinctions, ordinal corruption, cyclic pointers,
immutability and transactional rollback. No rule operator or inference behavior
was added.

## Disposable MCP proof

Final runs and their hashes are recorded in
[proof results](normalized-rules-events-proof-results.json). Raw transcripts,
private reviews, approvals, SQLite snapshots and manifests are retained locally
under `docs/evidence/`; each installation was temporary and closed by its runner.

- Single-event resources: 39 actual MCP cases, 12 committed and 27 rejected,
  339 calls. Includes exact integers/quantities, stock uncertainty/refutation,
  owner isolation, same-time boundaries, forged balances, overflow/underflow,
  multi-resource transfer, worlds, retcon invalidation and restart/retry.
  Seven adversarial audit tests pass.
- Owner requirements: 20 cases, seven legal and thirteen illegal, nine
  publications and 158 calls. Borrowed attributes, missing/unknown evidence,
  ambiguous actors and self-grants cannot authorize use. Earlier incapacity
  invalidates two dependent actions; corrected and historical results survive
  restart. The independent audit retains the original expected outcomes.
- Pistol continuation/history: twelve shots to zero, holder transfer, constrained
  three-round reload, another shot, eight rejected controls, valid/invalid
  earlier-time corrections, three pinned scene editions, two process restarts,
  twenty state queries, 23 publications and 282 calls. Independent Fraction
  arithmetic and generated-identity/lifetime reconstruction pass for every
  committed snapshot. Nine adversarial audit tests pass.

The full workspace gate covers formatting, Clippy with warnings denied, tests and
contract freshness. Passed with 336 tests, zero failures and current generated contracts; the executed result is recorded with the proof summaries.
One pre-existing workload test remains ignored.

## Scope

These proofs qualify the existing semantics of rules, actions, events and their
generated assertions on relational storage. They do not implement simulation,
implicit subtype rule binding, automatic shared-attribute initialization,
prose entailment, new operators, live migration, installation/workflow conversion
or unrelated record-family qualification. Existing evaluator limitations remain
explicitly tested rather than being repaired as part of storage normalization.
