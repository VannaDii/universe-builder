# Goal 33: Pistol admission qualification

October 5, 2026. One owned disposable installation executes a sustained stdio MCP
workflow using the existing authenticated private author review and approval path.
The [driver](../scripts/pistol_workflow_pilot.py) constructs its operations without
using the [independent accounting table](../fixtures/pistol-workflow/expected.json).
The [auditor](../scripts/audit_pistol_workflow.py) reconstructs captured revisions
from typed SQLite rows and ordered commit changes and compares every record to MCP
wire delivery. These are synthetic author decisions, not changes to live author data.

| Requirement | Executed evidence |
| --- | --- |
| Inheritance and reviewed starts | Gun supplies initial rounds = 3. Pistol inherits Gun and supplies shared `can_fire = true` only in Range. Service pistol inherits Pistol. Reviewed start events materialize stock separately for A, B, C, a Revolver, and an Other-world pistol. Five receipts bind the exact initial definition, start, predicate, original assertion, source revision and committed revision. Definition candidates remain separate from actual stock. |
| Independent pistols and exhaustion | A and B each fire at 11, 13 and 15: their separately authored expected balances are 3 → 2 → 1 → 0. Both fourth shots at 16 reject for underflow. A's holder changes at 12 from Holder A to Holder B; the old holder's attempted shot rejects. B retains Holder A. The accounting owner remains the pistol. |
| Constrained replenishment | Reserve begins with 2. A's reload at 20 declares +2 on A and −2 on Reserve. Readback gives A = 2, Reserve = 0, B = 0. A fires at 21 and 22 to zero. A forged post-value at 19 rejects for unequal arithmetic; a further reload at 21 rejects for bounds/underflow. Rejected candidates change neither canonical counts nor head. |
| Another matching instance | C is independently initialized to 3, remains at 3 during all A/B activity, and uses the same inherited capability and shooting action at 50 to reach 2. No instance-specific firing action is introduced. |
| Subtype/world differences | Revolver inherits Gun stock but has a shared false capability and rejects firing with a complete Refuted finding. Other-world pistol inherits stock, but Range-only Pistol capability is absent in Other; firing rejects with complete NotEstablished evidence. World-focused queries exclude facts from the other world. |
| Historical correction | Moving A's first shot from 11 to 10 alone creates an overlapping unequal balance and rejects with a complete conflict. Correcting the original stock endpoint and event together succeeds. Current query at 10 gives A = 2; historical query gives A = 3. Event-generated assertions are recomputed, and initialization receipts retain their original exact versions. |
| Restart and receipts | Forced engine restart preserves current and historical state, all committed records and five initialization receipts. Retrying each of the sixteen commits returns its original receipt. A repeat initialization rejects at proposal compilation and cannot refill A. |
| Direct observation | A direct factual assertion of zero at 60 agrees with its last shot consequence. It passes propose/validate/review/approve/commit. Both pieces of evidence remain visible; the assertion has no fabricated event provenance. |
| Direct conflicting refill | A direct factual assertion of three at 60 conflicts with zero. Proposal creation succeeds, validation returns complete conflicting findings, author approval fails, and commit is denied without a canonical change. This is evidence of conflict enforcement, not generic resource-transition enforcement. |
| Non-event stock change | One factual candidate shortens the reserve's earlier interval to [0,5), corrects that earlier amount to 1, and asserts 2 on [5,20). No supplying event occurs at 5. The candidate passes validation, private review, approval and commit. Current queries at 4 and 6 give 1 and 2; its direct assertion has no event provenance. The reload at 20 still validates against 2, so checking every declared action does not close this path. |

## Historical semantic decision and subsequent resolution

**This decision was subsequently resolved by the author.** The opt-in implementation
and its independent proof are recorded in [resource resolution verification](resource-resolution-verification.md).
This original run characterizes opt-out behavior and remains a regression
control; it is not an outstanding decision. The executed workflow
qualifies existing behavior and exposes its enforcement limit; it does not prove
that all factual stock changes obey resource-transition rules.

Current action contracts enforce each declared event's owner, pre-stock, delta,
bounds, post-stock, scope and effects. Factual assertions remain author-controlled.
An author may legitimately establish an observed quantity or correct an earlier
quantity. At the time of this proof, the schema did not type the distinction
between an observation, a correction, and an in-world stock transition. Prose rationale is not interpreted
as a machine-enforceable intent. Therefore the last candidate can represent either
an unsupported replenishment or a legitimate historical factual account; admission
cannot distinguish those meanings from its current structured evidence.

Recommendation submitted for decision: add an opt-in resource policy and typed
observation/correction provenance, with resource transitions admitted through
declared events. Legitimate observations and historical corrections must retain
explicit admission rules and downstream revalidation. This is a proposed semantic
extension, not an implementation fix to the current approved action semantics.
The material tradeoff is additional schema, migration/compatibility decisions and
author obligations. This was the recommendation at the time of this proof.
The later approved implementation uses existing Rule and IssueDecision records, without a schema
change or typed observation/correction extension.
The alternative is to retain trusted-author factual edits and document that event
accounting is enforced only on declared transitions.

## Proof and reproduction

Sixteen publications, twelve admission controls, fifteen queries, twelve canonical
snapshots, 100 delivered versions and five initialization receipts are audited.
All successful approvals bind captured private command results to exact validation
runs and proposal identities; durable operation receipts are read independently
from SQLite. The accounting table fixes balances, holders, inheritance, world,
coordinate, revision and admission expectations separately from proposal inputs.
Independence means a separate expected table and reconstruction algorithm, not a
second human or model review. No subagents were used.

The eleven [audit controls](../scripts/test_pistol_workflow_audit.py) include an
actual database/wire control plus ten coherent wire/report forgeries with
recomputed payload digests: post-balance, wrong pistol owner, omitted reserve debit,
wrong transferred holder, shared-to-instance promotion, removed firing requirement, historical time loss,
fabricated event provenance for the gap, wrong receipt source, and a conflicting
refill mislabeled as admitted. Each forgery must fail even when database comparison
is disabled to isolate the factual oracle. Normal audits always reconstruct SQLite.

```sh
cargo build --locked -p universe-engine -p universe-cli -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/pistol_workflow_pilot.py --output /tmp/pistol-workflow-proof/actual.json
python3 scripts/audit_pistol_workflow.py /tmp/pistol-workflow-proof/actual.json
python3 scripts/test_pistol_workflow_audit.py --evidence /tmp/pistol-workflow-proof/actual.json -v
RUST_TEST_THREADS=1 cargo run --locked -p xtask -- check
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
```

CI includes the combined MCP driver, auditor and falsification controls.
[Proof metadata](pistol-workflow-proof-results.json) records executed gates,
artifact hashes and actual working time. Raw report, JSON-RPC transcript and a
credential-free synthetic package database remain at
`/tmp/pistol-workflow-proof/actual.{json,jsonl,sqlite}`. The owned engine is stopped;
the installation and its credentials are removed.

Repeat initialization currently returns `STORAGE_FAILURE` with a generic structural
message at proposal creation. The evidence proves denial, not a useful diagnostic.
The oracle explicitly retains this observed limitation. Holder preconditions are
evaluated before their event: transfer and the new holder's shot use distinct
coordinates. Earlier harness attempts incorrectly used the transfer coordinate
for that shot, then were corrected. Other harness corrections concerned property
applicability to the unclassified reserve, an actual receipt column name and a
forged reload coordinate that initially hit bounds before arithmetic.

No prose-to-intent interpretation, general physical simulation, native UI,
VoiceOver, hosted CI execution, deployment or release qualification is claimed.
This original proof changed no production semantics. Subsequent opt-in accounting
qualification is linked above; native, host, migration and release limits remain.
