# Declared action effect enforcement

October 3, 2026. Implements the required/permitted **set effect** slice of approved
[D02](decisions/d02-action-consequences.md) using
[Goal 15's existing contracts](action-consequence-contract-verification.md).
Owning baseline: `d3396a2e6dc752b2bcfddeb8568746256d3eb606`.

## Behavior

The shared candidate validation path checks every event bound to a consequence
contract, including unchanged events after an evidence or definition retcon.
New, revised and adopted actions require an explicit contract; touched events
require a contract-bearing action. Untouched actionless/contractless history
remains readable with an explicit per-event consequence coverage exclusion.
Removing a contract cannot migrate an action back to undeclared effects.

Each supplied effect must match a unique declared slot, exactly one entity in
its owning participant role, predicate, particular role-free proposition, exact
value/polarity, explicit order and lifetime. Resolved slot targets cannot alias
one owner/property. Every effect's assertion scope and proposition context must
match the action context and the event's full world set, with no realm or
duplicate worlds. World order is immaterial. Existing action applicability,
validity, mandatory attributes and explicit preconditions still run unchanged.

For occurred events, required enabled slots must appear exactly once; optional
enabled slots may be absent. False conditions forbid an effect. Conditions use
complete unopposed evidence immediately before the event, through the existing
finite evaluator, including declared possession powers. Missing, uncertain,
expired, conflicting or alternative-valued evidence is unresolved and blocks
admission. Explicit refutation or a unique supported incompatible single-valued
attribute can establish falsity. Each event world is checked independently.
An omitted optional slot remains legal when established truth differs between
worlds; a present grant must be enabled in every target world. Non-occurred
events still check effect shapes/targets/scope but execute no consequences or
conditions and need not supply required effects.

No required assertion or post-value is silently generated as a repair. Existing
`events-v1` expansion remains frozen in the exact proposal before author review;
generated assertions can change only through their event. No canonical identity,
schema version, public tool or authority model changed. Evaluator binding is now
`finite-policy-v6-declared-effects`, so prior evaluator validations and approvals
cannot authorize publication under these semantics.

Resource arithmetic, simultaneous spending, author clarification/reusable object
rules, prose classification and native qualification are excluded. Enabled
resource delta execution fails closed as unresolved; omitted optional deltas do
not execute. This is scoped G04 effect enforcement, not completion of all D02 or
all continuity gaps.

## Proofs

The committed [independent expected-effect fixtures](../fixtures/action-effects/expected.json)
contain 41 authored expected outcomes. They cover required/optional/planned
behavior, unrelated grants, wrong recipients/worlds/context/predicates/values,
polarity/order/lifetime, duplicate slots/owners/worlds, aliased targets, second
effect scope, temporal/uncertain condition evidence, conditional falsity,
multiworld conditions and historical/touched compatibility. Expected outcomes
are not derived from the production matcher or assertion compiler.

The [actual MCP evidence bundle](evidence/declared-action-effects-final/result.json)
records 22 cases across 203 MCP calls: **15 rejected and seven committed**.
The missing mandatory effect, walking/unrelated power, wrong recipient and wrong
world cases all fail `universe_validate` with `event.action.effects`; attempted
commits fail and observed heads remain unchanged. Declared timed and conditional
grants commit through private author review and exact approval. Optional omission,
planned nonexecution and established false conditions also commit legitimately.

The [independent audit](evidence/declared-action-effects-final/audit.json) imports
neither the runner nor engine. It binds stimuli to the frozen fixture, calculates
assignment admission independently, pairs raw JSON-RPC requests/responses,
reconstructs historical SQLite snapshots and checks exact proposal, validation,
review, approval, operation, kernel receipt and commit assignments. It independently
calculates generated assertion identities, matches every generated assertion to
the reviewed effect, and compares state queries at ticks 11, 15 and expiry 16 to
canonical assertion versions. Restart queries and receipt replay also agree.
This is an independent program audit, not an external human review.

Additional audited unchanged-head controls reject direct mutation of a generated
assertion and an old validation/approval after the reviewed effects change.
A focused persistent workflow regression rejects both old evaluator validation
and old evaluator approval even when proposal/head/digest bindings otherwise
match. Existing owner-attribute, prerequisite, historical-query, permission,
retcon, approval/retry and recovery regressions remain passing.

The final workspace check passed 324 tests (one existing ignored workload),
formatting, warnings-as-errors Clippy and schema freshness. Independent contract
checks passed (26 schemas, 13 valid and 91 malformed examples; source-assessment,
action-contract suites). See [verification](evidence/declared-action-effects-final/verification.json)
and its complete gate logs.

All six [auditor tests](evidence/declared-action-effects-final/audit-negative-tests.json)
actually run: valid evidence passes; changed oracle, query, review, head and wire
owner fail. Prior attempts are retained locally and summarized in
[attempt history](evidence/declared-action-effects-final/attempt-history.json).
The final bundle records exact source/binary/oracle hashes and hashes every
artifact. Its package is a disposable synthetic universe and contains no profile
credentials.

## Reproduction

```sh
cargo run --locked -p xtask -- check
UNIVERSE_PYTHON=/path/to/jsonschema-4.25.1/python cargo run --locked -p xtask -- validate-contracts
cargo test --locked -p universe-service consequences::tests
cargo test --locked -p universe-service prior_evaluator_validation_and_approval
/path/to/jsonschema-4.25.1/python scripts/g04_pilot.py --output /tmp/fresh-effect-proof
```

The preexisting timeline fixtures now explicitly declare their effect contracts,
full event scope and timed expiry when event time changes. Their fixture-only
vocabulary helper is not used by the independent fixtures or MCP proof.
