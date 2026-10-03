# Assessment attachment and selection through MCP

October 2, 2026, America/Los_Angeles. Follows the approved
[D03/D08 lifecycle](decisions/d03-d08-source-assessments.md) after the
[Goal 8 storage proofs](assessment-persistence-verification.md) passed again.

Protocol 3's existing `universe_propose` now accepts closed `attach_assessment`
and `select_assessment` actions. Attach returns the immutable assessment
reference in its newly appended selection. Selection accepts an exact existing
reference or an explicitly present `null` for withdrawal. Both require the exact
frozen proposal reference, a matching owned context/frame, expected selection
generation and an idempotency key. The result is `AssessmentSelection`; semantic
proposal actions retain the existing Proposal wire shape. There are still
thirteen public tool names. The shared client contract and native draft response
handling compile with the new response union; no native assessment UI is added.

The routes call the existing storage service directly, separately from semantic
proposal edits. They use authenticated profile-to-principal identity, current
propose permission, owner/author access, full candidate/source/historical
visibility and existing grant boundaries. Exact authorized retries recover their
original immutable identities and generations after replacement, withdrawal or
restart. No-change selections, mismatched retry bodies/generations/references,
and stale generations reject. Publication remains one authority-locked,
generation/proposal-compared SQLite transaction. Proposal version, operations,
digest and canonical tables are preserved by assessment operations.

`source_assessment.v1` is advertised as partial, explicitly limited to attachment
and selection. Assessment retrieval, validation/approval/commit integration and
new public tool names are excluded. Current validation still reports its previous
scope/absence behavior; these declarations do not qualify assessed continuation
or arbitrary prose semantics.

## Proofs

Final service/store/protocol/client/MCP Rust suite: **132 passed, zero failed;
one standard workload deliberately ignored**. Shared native contract compilation,
schema freshness, independent contract checks and fixture MCP smoke also pass.
Exact results and test logs are retained in
[evidence/assessment-mcp/proof-results.json](evidence/assessment-mcp/proof-results.json).

- Three focused service tests pass: existing persistence/admission/restart tests
  plus public dispatcher lifecycle and frozen-proposal preservation.
- Ten assessment protocol tests pass, including closed action decoding, required
  explicit null, unchanged output shape and malformed-body rejection.
- Twenty-four actual stdio MCP assessment cases pass in a disposable owned
  installation: attachment, replacement, reselection, withdrawal, exact retries
  after later selections and restart, impersonation, stale generations,
  mismatched bodies/generations/references, no-change, malformed requests,
  proposal owner denial, current propose denial and source visibility denial.
- Every MCP case observes raw SQLite workflow bytes and all canonical tables
  before/after. Rejected requests and retries preserve every row. Successful
  requests append only their assessment/selection/receipt rows. Source scope has
  an accessible-proposal positive control under an otherwise allowed propose
  grant; retained source visibility separately denies attachment.
- The separately authored [independent audit](evidence/assessment-mcp/independent-audit.md)
  freezes its oracle before examining producer evidence, recalculates hashes,
  checks exact append sets and immutable history, verifies every canonical table
  and raw MCP text/structured response, and finds no implementation issue.

The [transcript](evidence/assessment-mcp/transcript.json) contains synthetic data,
raw tool responses, complete before/after observations and tools/list schemas.
Private profile credentials and the disposable installation are not retained.
A separate record-only setup commit establishes the source-visibility fixture;
no assessment call moves the canonical head. That setup is not assessment
validation integration qualification.

Reproduce from the repository root (use short temporary paths for macOS sockets):

```sh
cargo test -p universe-service -p universe-store -p universe-protocol
cargo test -p universe-client -p universe-mcp
cargo check -p universe-ui
cargo run -p xtask -- check-schemas
uv run --with jsonschema==4.25.1 python scripts/test_source_assessment_contracts.py
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
cargo build -p universe-cli -p universe-engine -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/assessment_mcp_pilot.py
python3 scripts/audit_assessment_mcp.py docs/evidence/assessment-mcp/transcript.json
TMPDIR=/tmp uv run --with jsonschema==4.25.1 python scripts/mcp_smoke.py
```
