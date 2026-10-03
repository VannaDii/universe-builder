# Cumulative resource accounting and scene continuity

October 3, 2026. Extends Goal 17's exact transition baseline `1ba4e6f`.

Occurred, enabled effects on the same owner, property and represented context
cannot share an exact story time when at least one is a resource delta and their
world scopes overlap. Universe-wide effects overlap every world; disjoint worlds
remain independent. A set effect cannot reset a resource simultaneously with a
delta. Uses must have distinct coordinates on the same named calendar; record
identities, scene order and holder identity supply no temporal ordering. Optional
omitted, disabled and non-occurred effects retain their previous behavior. Checks
use the existing work budget and exact contract/owner bindings, without a new
ledger, schema or authority path. The evaluator binding is now
`finite-policy-v8-cumulative-resources`, invalidating earlier publication approvals.

Balances remain attached to the declared gun entity. Existing event expansion
ends prior generated values at subsequent changes, recompiles the complete
candidate after a retcon, and retains immutable earlier revisions. Explicit
initial assertions are not silently shortened: the proof supplies their endpoints
and revises the first endpoint explicitly when moving the first shot earlier.
Reload contracts declare both the amount added to the gun and the matching debit
from the constrained reserve. No conservation rule is inferred from action names.
Reusable world-rule enforcement and prose qualification are excluded.

## Proof results

The [nine focused fixtures](../fixtures/resource-transitions/cumulative.json)
cover twelve shots to zero, a thirteenth underflow, stale successors after an
earlier retcon, dependent same-time uses, simultaneous multiple-value and
cross-scope spending, disjoint-world independence, planned nonexecution and a
simultaneous delta/set reset. All pass in Rust, alongside the previous 44 resource
and 41 set-effect fixtures. A separate Fraction replay checks the same nine
expected admission outcomes without importing production arithmetic or expansion.

The [audited real MCP sequence](evidence/cumulative-resources-final/audit.json)
passes **282 calls, 23 commits, eight rejected attempts, 20 state queries, three
scene editions and two engine restarts**. Its [frozen independent oracle](../fixtures/resource-transitions/continuation.json)
agrees with actual state responses:

| Stage | Gun rounds | Constrained reserve |
|---|---:|---:|
| Established stock | 12 | 4 |
| Shots 1–12, across scenes and a holder handoff | 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 | 4 |
| Declared reload of three | 3 | 1 |
| Continuation shot | 2 | 1 |
| Final engine restart | 2 | 1 |

A thirteenth shot, a forged reload amount and a reload exceeding the remaining
reserve reject without canonical movement. Same-time spending is rejected during
proposal expansion when scopes match; the new consequence check rejects the
universe-wide/world-specific overlap at validation. A new holder's shot at the
handoff's time fails its pre-event prerequisite; a later shot succeeds.

The incomplete earlier retcon changes established stock from twelve to eleven
and revises the first shot to ten. Independent replay confirms that first use is
valid (11 − 1 = 10) and the unchanged second shot is invalid (10 − 1 = 9, authored
post-value 10). Actual validation rejects the candidate and preserves canon. A
separate retcon moving the first shot onto its successor's time also rejects.
The valid retcon moves the first shot from tick 11 to tick 10 and explicitly moves
its premise endpoint. All later events revalidate with the same balances. The
original scene edition still reports twelve rounds at tick 10 and its original
first-shot time, while current canon reports eleven rounds there.

The [independent auditor](../scripts/audit_cumulative_resources.py) checks raw
JSON-RPC/report agreement, stored proposal and review changes, exact validation
and private author approval, kernel receipt and commit bindings, complete SQLite
history, generated assertion identities and endpoints, and all queried assertions.
It independently replays declared arithmetic and compares queried gun/reserve and
holder state with the frozen expectations. Each rejected candidate preserves the
entire canonical snapshot and has no canonical commit. Three distinct engine
service instances and three wire initialization sessions substantiate two restarts.
Exact old edition/scene records and the historical event survive; all 23 commit
receipts replay unchanged after the final restart. This is a program audit, not a
human review.

All [nine independent/auditor tests](evidence/cumulative-resources-final/audit-negative-tests.json)
pass with no skips: focused replay, the saved proof, and seven tampering controls
for head, review, wire owner, historical event, query, retry receipt and a rehashed
false accounting oracle. Source, binary and oracle hashes stay unchanged during
the final run. The saved synthetic package contains no installation credentials.
The manifest hashes every final proof artifact.

The [legacy MCP regression](evidence/cumulative-resources-legacy-regression/result.json)
also passes: all 39 prior transition cases (12 committed, 27 rejected), two rejected
evidence retcons, 339 MCP calls and seven saved-proof/tampering tests under the new
evaluator. Earlier cumulative harness attempts remain locally unqualified: one
used the wrong work operation, two expected a later rejection stage, and one used
a wire auditor's default single-restart count. These were proof-harness errors.
Final workspace and contract checks are recorded in
[verification](evidence/cumulative-resources-final/verification.json).

## Reproduction

```sh
cargo test --locked -p universe-service consequences::tests --lib
cargo run --locked -p xtask -- check
UNIVERSE_PYTHON=/path/to/jsonschema-4.25.1/python cargo run --locked -p xtask -- validate-contracts
/path/to/jsonschema-4.25.1/python scripts/cumulative_resources_pilot.py --output /tmp/fresh-cumulative-proof
/path/to/jsonschema-4.25.1/python scripts/resource_transitions_pilot.py --output /tmp/fresh-single-event-proof
```
