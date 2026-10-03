# Selected assessment validation bindings

October 2, 2026, America/Los_Angeles. Implements validation binding under the
[approved D03/D08 contract](decisions/d03-d08-source-assessments.md), using the
existing immutable assessment resolver. Assessment-aware approval/commit
integration, new semantic enforcement and manuscript certification are excluded.

Completed synchronous and queued proposal validation now use the typed
`SourceValidationBindingV1` serializer and digest. Before evaluation, validation
captures the exact proposal/frame, selection identity and generation, submitted
input, assessment state, current head, latest proposal key and authority. Queued
requests retain that snapshot at enqueue time, including explicit withdrawal
absence at its actual generation. Retries recover the original snapshot rather
than silently retargeting another assessment.

Selected evidence is resolved through the existing source/dependency checks:
immutable envelope/body hash, exact source/work versions, staged import metadata,
actual UTF-8 bytes and aligned ranges, source anchors, active dependency and
candidate-link versions, explicitly labeled historical evidence, inventory
accounting, unresolved dispositions and declared conclusion. A usable attachment
reports `bound` and `source_assessed_candidate`; its conclusion remains the
assessor's declaration. `absent`, `stale` and `unavailable` retain record scope.
Unresolved material cannot acquire a consistent conclusion. Stale evidence never
promotes scope. A fresh record-only run may bind an unusable selected state;
missing or corrupt source bytes still fail ordinary source verification. Missing
assessment bodies are disclosed only to the unrestricted author, following the
existing resolver's dependency visibility rule. Unassessed record validation
retains existing write boundaries without requiring an assessment visibility walk.

Completion checks the captured selection, proposal, head, assessment state and
current authority before appending completed evidence. The owning universe
worker and exclusive package writer lock serialize head changes. Selection and
latest-proposal comparisons plus validation/terminal evidence append share one
SQLite transaction while installation authority is locked. Existing authority
audit sequences additionally detect a grant change followed by restoration; a
scoped audit entry is added in the same grant transaction without changing the
installation schema. Unrelated profiles/universes do not invalidate the capture.
Failed, cancelled and interrupted operations have no final binding. Completed
reports retain their original assessment and digest across replacement/restart.
Execution hashes own the complete, unpaged typed core, including the final queued
operation ID; delivery pagination remains independent.

The existing generation-zero unassessed publication path remains usable. Any
selection transition revokes that path's earlier evidence, including approvals
recorded before an attachment was selected. Assessment-aware bindings and
withdrawal generations can be validated, but are not enabled for publication by
this slice. This is an invalidation guard, not assessment commit integration.

## Reproducible proofs

The [independent calculator](../scripts/audit_validation_binding.py) uses Python
JSON canonicalization and SHA-256, imports no service serializer/hash helper, and
recomputes body, inventory, execution and final digests from complete evidence.
It independently checks exact Unicode source bytes, lengths and UTF-8 range
boundaries. Recorded proofs are in
[evidence/validation-binding-2026-10-02](evidence/validation-binding-2026-10-02).

- Service proofs reproduce six synchronous/queued selection bindings and three
  dependency/retention bindings, including explicit absence, replacement,
  withdrawal, unresolved inventory, changed dependencies, missing bodies and
  restart recovery. False clean accounting and missing source bytes fail.
- Controlled service execution covers replacement, withdrawal, proposal revision,
  head advancement, changed authority, cancellation and selection changes before
  queued preparation. No completed validation row is persisted for these runs.
- Runtime requests decoded through the public MCP tool DTOs pause real detached
  workers during replacement, withdrawal, live grant change and grant restoration.
  Results are failed/interrupted, with unavailable check state and null binding.
- The actual stdio MCP pilot independently reproduces eight bindings and checks
  replacement, withdrawal, unresolved accounting, dependency revision, retention
  loss, queued/restart recovery, prior approval invalidation and source-integrity
  denial. Controlled concurrency is exercised in the service/runtime tests;
  the stdio pilot does not claim timing-based race coverage.

```sh
VALIDATION_BINDING_PROOF_DIR="$PWD/docs/evidence/validation-binding-2026-10-02" \
  cargo test -p universe-service --lib validation_binding
cargo test -p universe-service --lib queued_selected_tool_requests
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/validation_binding_pilot.py \
  --output docs/evidence/validation-binding-2026-10-02/mcp-bindings.json
python3 scripts/audit_validation_binding.py \
  docs/evidence/validation-binding-2026-10-02/mcp-bindings.json \
  --output docs/evidence/validation-binding-2026-10-02/mcp-independent.json
cargo test --workspace --locked
cargo run --locked -p xtask -- check-schemas
```

Qualification also runs the existing source-assessment and validation-scope Python
contract suites and the closed tool-schema oracle. Initial attempts exposed a
missing Python dependency and an overbroad visibility check for unassessed
records; both were corrected and rerun. The standard strict workspace lint gate
has existing `large_enum_variant` and `items_after_test_module` failures. The
untouched starting commit independently reproduces the latter failures; the
other flagged enum definitions are unchanged by this goal. These failures are
reported separately from the binding proof results.

Final workspace qualification: **302 tests passed, zero failed, one standard-workload
test intentionally ignored**. Source-assessment and validation-scope contract
suites passed (6 and 3 tests); the tool oracle passed 26 schemas, 13 valid and 91
invalid examples. Generated schemas, formatting and whitespace checks passed.
All-target workspace lint also passes when only the two existing lint classes
above are allowed; the normal strict gate remains blocked.
