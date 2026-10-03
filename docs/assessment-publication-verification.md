# Exact assessment bindings at approval and atomic commit

October 2, 2026, America/Los_Angeles. Implements the approval/publication slice of
the approved [D03/D08 lifecycle](decisions/d03-d08-source-assessments.md).

Author approval and delegated commit now reconstruct the final binding from the
exact frozen proposal/frame, current selection identity or explicit absence,
selection generation, submitted scope, assessment state and stored execution.
They require equality with the complete persisted report and its final digest.
Approval continues to bind the full `Checked` hash and exact validation run.
Replacement, withdrawal and reselection of the same attachment invalidate prior
validation/approval because selection generation changes.

Commit performs the existing private engine admission check, compares its entire
execution after restoring only the approved run/operation identity, and resolves
the assessment again against the exact stored final binding. Read-only private
assessment resolution can inspect author-validated evidence beyond a committing
client's review visibility; the existing complete write footprint, current edit
permission and author approval or bounded delegation must authorize that route.
Public attachment, selection, retrieval and validation retain their dependency
visibility checks. No author identity or grant is substituted.

The initial publication capture also fences the installation authority audit
sequence. Current authentication, scope, permissions, delegation limits/expiry
and author identity are locked through publication. A grant changed and restored
while commit was preparing therefore fails as well as a revoked grant/profile.
The selection and latest proposal keys are compared in the same `BEGIN IMMEDIATE`
transaction as canonical versions, head, projections and the exact receipt.
Another writer either wins before that transaction and invalidates publication,
or cannot write between its selection comparison and head publication.

Existing engine admission policy is preserved. Generation-zero unassessed records,
fresh withdrawal absence, unresolved declarations and fresh record-only evidence
with an unavailable assessment can still publish when the existing record gates
and authority allow it. Missing or corrupt source bytes still fail source
verification. No positive assessment conclusion or new universal assessment
blocker is required. This does not qualify prose models or close the broader
continuity gaps. The capability remains partial because native interaction and
prose qualification are outside this work.

## Proofs

Evidence is retained in [evidence/assessment-publication](evidence/assessment-publication).

- Deterministic service controls pause after private revalidation and before
  publication: replacement, withdrawal, grant revocation, grant restoration and
  profile revocation all fail with unchanged head and canonical receipt count.
  Public requests are decoded with the actual MCP DTOs. Separate fixture writers
  exercise the final transaction comparison; normal selection requests already
  serialize on the owning universe worker.
- Store controls cover replacement, withdrawal, identity restoration, initial
  selection and proposal revision after preparation. All reject without canonical
  head or receipt movement. A separate writer receives `SQLITE_BUSY` after
  selection comparison and before head movement, proving that interval is locked.
- All six canonical fault points roll back versions, identities, changes, head,
  projections and receipt; the same compared commit succeeds afterward.
- Delegation controls publish a valid assessed, author-validated proposition
  without an author approval row. Withdrawal, replacement, revoked bounds and
  expiry fail. The bounded committer remains denied public source-assessment
  review. Raw-source/withdrawal and unresolved/unavailable record controls pass.
- The actual stdio MCP transcript records **33** validation, author CLI approval,
  selection, commit and recovery cases. Unapproved/stale/revoked controls preserve
  every observed row. A selected assessed proposal publishes successfully; exact
  commit retries and operation lookup recover the same receipt after a forced
  engine restart. Historical attachment, selection and validation bytes agree.
- The [separate standard-library auditor](../scripts/audit_assessment_publication.py)
  imports no producer or Rust helpers. It recomputes raw workflow/source/body
  hashes, final bindings and full approval hashes, checks canonical head/receipt
  deltas, text/structured MCP parity and restart/history equality. This is an
  independent calculation/process audit, not a second human or model review.

The proof producer initially used the wrong closed operation-lookup discriminator,
then assumed all authentication errors carry structured content. Both were
producer errors corrected to the existing contract. The second failed transcript
and attempt records are retained. The first locally rejected request is recorded
in the attempt ledger; no service call was sent for that lookup. Initial focused
tests also exposed the private dependency-read issue described above, which was
fixed without broadening public access or admission. The strict lint check found
one new redundant Boolean test expression; it was simplified without an allowance.

## Reproduction

```sh
cargo run --locked -p xtask -- check
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/assessment_publication_pilot.py \
  --output docs/evidence/assessment-publication/transcript.json
python3 scripts/audit_assessment_publication.py \
  docs/evidence/assessment-publication/transcript.json \
  --output docs/evidence/assessment-publication/independent-audit.json
cargo test --locked -p universe-service --lib assessment_publication
cargo test --locked -p universe-store --test kernel assessment_publication
uv run --with jsonschema==4.25.1 python scripts/test_source_assessment_contracts.py
uv run --with jsonschema==4.25.1 python scripts/test_validation_scope_contracts.py
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
```

The full workspace gate passes **309 tests, zero failures, one intentionally ignored
standard-workload test**, strict all-target linting, formatting and generated schemas.
The source-assessment and validation-scope contract suites pass 6 and 3 tests;
the tool oracle passes 26 schemas, 13 valid and 91 invalid examples. Four
independent-auditor tests reject misleading stale/head/restart/history evidence.
The existing stdio validation regression reproduces all eight final bindings.

Final qualification counts and commands are recorded in
[proof-results.json](evidence/assessment-publication/proof-results.json).
