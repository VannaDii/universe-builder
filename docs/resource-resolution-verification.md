# Resolution of unexplained resource changes

Revised Goal 33 implements the author's decision to require resolution of
unexplained stock changes on selected properties. The original Pistol proof and
its committed evidence remain unchanged. Its admitted non-event increase is an
explicit limit of the old, opt-out behavior; it is not the behavior of a property
with the new accounting rule enabled.

## Authoring and publication

An executable Rule opts in with capability `resources.accounting.v1`, named
`targetPredicates` such as `resolution:rounds`, and commit policy
`block_unless_exception`. Its ordinary expression is still evaluated. No record
schema, storage layout or migration was added.

The complete candidate timeline is checked for each applicable stock property.
A first observation establishes a baseline; a later direct observation of the
same balance corroborates it. A changed balance needs one of these resolutions:

- A declared delta event whose effects pass the existing accounting checks.
- A coherent correction of earlier factual evidence that removes the jump.
- An author-origin IssueDecision with mode `accept`, scope
  `resource:<proposition record ID>`, the exact resource finding fingerprint, and
  a nonempty rationale. The existing installation-author authority guard applies.

The fingerprint binds the exact claim, policy, property, world and predecessor
contents. It excludes incidental generated record-version IDs so recompiling the
same reviewed proposal preserves its meaning. A changed claim or predecessor
requires a new acceptance. Ordinary approval never creates that acceptance;
publication revalidates the candidate using the existing review/approval machinery.

Creative acceptance establishes the count as canon without establishing a cause.
Effective-object delivery retains `resource_arrival_unexplained:<fingerprint>` on
the factual row and delivers the acceptance as a dependency. The finding remains
`not_established` with its decision evidence even when publication is permitted.
History preserves the decision and claim rather than manufacturing an arrival event.

## Executed proof

`scripts/resource_resolution_pilot.py` uses the real stdio MCP server, private
author review/approval CLI, and an owned disposable installation. It retains a
credential-free typed database, exact JSON-RPC wire log and report under
`/tmp/resource-resolution-proof/actual.{sqlite,jsonl,json}`. The installation is
removed and its engine stopped. These are synthetic author decisions; live author
data is not modified.

The final run made 212 MCP calls, published eight revisions, delivered nine
snapshots and eleven state queries, and forced two engine restarts.

| Requirement | Executed evidence |
| --- | --- |
| Original unexplained increase rejects | Original reserve 2 is corrected to 1 before time 5, then asserted as 2 after time 5 without a supplying event. Complete validation reports the gap; ordinary approval, commit and retry reject with canon unchanged. |
| Accounted replenishment succeeds | A declared event increases one reserve from 1 to 2 while debiting supply from 3 to 2. |
| Earlier correction succeeds | A later 2 observation initially rejects against earlier 1 evidence. Correcting that earlier evidence to 2 removes the discontinuity and permits publication. |
| Exact creative acceptance succeeds | Author accepts the exact unexplained 2 claim. Changing it to 3 rejects until a fresh acceptance is recorded. Both decisions survive in history. |
| Authority and receipt controls | An enrolled agent cannot mint acceptance by copying the author principal. Reusing old validation or a successful commit key for changed content rejects. All eight publications reject before ordinary approval and return identical receipts on exact retry. |
| Restart cannot bypass | The unresolved candidate still rejects after restart. Current and historical delivery agree before and after the final restart. |
| Subsequent accounting | Reload consumes 2 from accepted reserve 3, leaving reserve 1 and pistol 2. Two shots leave pistol 0. Another shot and a reload overdrawing the reserve both reject with canon unchanged. |
| Historical fidelity | The historical revision still delivers count 2, its exact acceptance and unexplained-arrival marker after current history advances to count 3 and subsequent events. |

`scripts/audit_resource_resolution.py` independently reconstructs every captured
revision from typed SQLite history, compares exact MCP-delivered bytes and digests,
and checks the separately authored expected table. It independently recomputes
acceptance fingerprints from claim, policy and predecessor contents. It does not
call the Rust accounting evaluator or trust the driver's pass/fail labels.

Fourteen audit controls pass: authentic database/wire evidence and thirteen
coherent forgeries. They alter balances, acceptance scope/fingerprint/principal/
mode, policy, supply debit, reload residue, earlier correction, historical count,
unexplained markers, event provenance or restart denial. Forged delivered payload
digests are recomputed; the semantic audit still rejects them.

The original Pistol regression also passes on the final implementation: 436 MCP
calls, sixteen publications, twelve admission controls, fifteen queries, twelve
snapshots, five initialization receipts and eleven independent audit controls.
Its accounting policy remains opt-out, preserving the original proof's meaning.

Workspace checks pass formatting, strict Clippy and 395 Rust tests (one ignored).
Contract validation passes 26 schemas, 13 valid and 91 invalid fixtures. The new
MCP proof and audit controls are added to the existing CI workflow; hosted CI has
not been executed here. Machine-readable counts and artifact hashes are recorded
in `resource-resolution-proof-results.json`.

## Limits

Accounting is author opt-in. It covers single integer or exact-unit quantity
properties, exact named-calendar instance stock, supported world applicability,
and realm-free facts. Unresolved scope, precision or applicability fails closed
under the policy. The finite evaluator has a comparison work budget.

The gate does not infer causes, parse prose rationale, impose universal physics,
or distinguish intent behind a first baseline observation. Corrections operate on
the author's canonical evidence; explicit acceptance deliberately permits an
unexplained balance. Native UI, VoiceOver, hosted CI, distribution and deployment
qualification are outside this proof. No release is claimed.

## Goal 35 external-writer workflow — October 6, 2026

The same persistent author installation now runs the factual workflow from
incremental setup through continued canon. It creates a definition and instance
with `introduce_definition` and `introduce_instance`, adds a scoped initial-value
candidate with `add_named_attribute`, and retrieves the object before
initialization. A reviewed occurred start publishes its instance fact and durable
receipt. The writer deliberately reads the old pinned context after publication
and sees the earlier candidate-only state, then reads the new head and sees the
initialized value.

The run also reads through an actual world-limited agent grant. Its effective
object marks coverage `restricted` and carries the permissions-limit unknown;
the independent audit confirms that the hidden source remains in canonical
history. The resource rule is scoped to North so the two-world fixture preserves
one exact accounting finding. Ordinary approval and commit are rejected while
clarification remains unresolved. The author accepts the exact finding
fingerprint and `resource:<proposition record ID>` scope. A changed balance then
requires another decision, demonstrating that the first acceptance is content
specific.

For receipt recovery, the driver discards its local return value after the MCP
client receives the successful reviewed-start response, restarts the engine, and
queries `universe_get_operation` with the original commit idempotency key. The
recovered operation is `succeeded`; its receipt matches the delivered wire, the
canonical revision, and the typed SQLite initialization and commit receipt rows.
This simulates interruption at the writer's local response-processing boundary;
it does not simulate a network packet loss.

The current run made 268 MCP calls, published nine revisions, captured ten
canonical snapshots and 15 effective-state responses (11 accounting views plus
four initialization and access views), delivered 65 immutable versions, and
forced three engine restarts. The independent audit recomputes every resource
acceptance fingerprint from typed canonical content. All 18 audit controls
passed, including the authentic report and 17 coherent forgeries covering
resource decisions, history, restart recovery, initialization receipts, stale
context and restricted coverage. The report includes the exact initialization
instructions and verifies that the writer received the MCP guidance. The run is
scripted protocol evidence; it does not measure a model's prose interpretation.

Reproduce the integrated run and its independent controls with:

```sh
uv run --with jsonschema==4.25.1 python scripts/resource_resolution_pilot.py --output /tmp/goal35-resource-resolution.json
uv run --with jsonschema==4.25.1 python scripts/audit_resource_resolution.py /tmp/goal35-resource-resolution.json
uv run --with jsonschema==4.25.1 python scripts/test_resource_resolution_audit.py --evidence /tmp/goal35-resource-resolution.json -v
```

The driver is scripted protocol qualification. It does not score an external
model's prose interpretation or extract arbitrary facts from prose.
