# Pinned assessment review and retrieval

October 2, 2026, America/Los_Angeles. Implements the review slice of the approved
[D03/D08 design](decisions/d03-d08-source-assessments.md), following immutable
[attachment and selection](assessment-mcp-verification.md).

`universe_get_proposal` accepts `view_group:"assessment"`. Omit
`assessment_reference` to retrieve the current selected envelope; supply its exact
ID and digest to retrieve an authorized historical attachment for the same frozen
proposal version. The optional reference is rejected outside this view, in both
the owning request decoder and generated input schema. The thirteen public tool
names and ordinary proposal result shape are preserved.

An authorized result has exactly `selection`, `state`, `envelope` and `fragment`.
Selection and state describe the current selection, independently of the requested
historical envelope. A small envelope is returned whole. For larger envelopes,
`envelope` is null and `fragment` carries an exact assessment reference, UTF-8 byte
offset, total byte length and up to 32,768 bytes of `canonical_envelope_utf8`.
Chunks are UTF-8 aligned and contain the owning canonical envelope JSON. This
transport avoids turning a sliced inventory into an apparently valid assessment.
Concatenate fragments in byte-offset order, require complete delivery, decode
the envelope, and verify `SHA256("source-assessment:v1:" || J(body))` against its
digest. All authored array order, nulls, exact integers and Unicode are preserved,
including sources/ranges, dependencies, declared inventory, mappings, exclusions
and unresolved dispositions. Neither absence nor missing retention creates a
synthetic assessment body.

Cursors bind the request, exact proposal reference, selection identity/generation,
requested envelope identity/digest, frame, authenticated principal and grant scope,
permissions and limits. Each page resolves and authorizes the full candidate and
attachment dependencies before reading cursor metadata or creating another
cursor. Replacement, withdrawal and reselection invalidate obsolete pages, even
when an earlier identity is selected again. Missing or inaccessible references and
invalid cursors return the same generic denial without offsets or delivery data.
Current full authority is checked again at public response disclosure. Revoked
MCP sessions fail transport authentication and return only the adapter's generic
disconnection error, with no structured resource metadata.

Historical attachments remain immutable and readable after replacement,
withdrawal, restart and proposal revision. The unrestricted author can also read
an old retained body when a different currently selected body is missing; the
current state remains unavailable. This retention-loss case is deliberately
corrupted only inside the disposable service fixture, never through a production
storage operation.

The existing private author `Review` route returns `assessment_review` from the
same service resolver. The existing author screen displays selection generation,
state, exact attachment identity/digest, assessor, source ranges, dependencies,
inventory, declaration/exclusions, mappings and unresolved material. It labels
the assessor's declaration separately from byte verification and engine checks.
Refreshing review clears previously displayed review and local approval state.

## Proofs

- **134 Rust tests pass**, zero failures; one standard workload is deliberately
  ignored. The focused service test reconstructs a large Unicode envelope,
  verifies its body digest, compares author review, checks obsolete/restricted
  cursors, and preserves history across simulated selection retention loss.
- **88 actual stdio MCP review cases pass**, including seven complete nine-page
  deliveries, small-envelope/absence controls, wrong digest/identity/proposal,
  replacement, withdrawal, reselection, restart, read-only history, revised
  proposal history, wrong owner, an accessible-proposal/hidden-source contrast,
  restored access and revoked sessions.
- **Two actual private author reviews** equal the stored selected envelope,
  including its inventory, mappings, exclusions and unresolved items. One is
  current; the other is stale proposal history.
- The independent [reconstruction audit](../scripts/audit_assessment_review.py)
  imports no producer/service/hash code. It compares every reconstructed byte
  with raw SQLite workflow bytes, recomputes workflow/body/inventory hashes and
  compares a handwritten canonical encoder, Python sorted JSON and OpenSSL
  SHA-256. All seven reconstructions preserve the same 267,485-byte envelope.
  It checks every selection against the latest stored generation and verifies
  that reads preserve canonical tables and existing workflow rows. Only opaque
  cursor rows may be appended by non-final authorized pages.
- Four mutation controls reject a missing final page, a changed byte offset,
  changed envelope content and a private count in a restricted response.
- Native contract compilation, schema freshness, independent body/tool contract
  checks and the actual fixture MCP regression pass.

Final evidence is in [proof-results.json](evidence/assessment-review/proof-results.json).
The complete synthetic [transcript](evidence/assessment-review/transcript.json.gz)
is compressed to avoid repeating large envelopes in source control. It retains
raw MCP text/structured responses, tools/list, authenticated synthetic profile IDs,
raw before/after SQLite observations and author review responses. Disposable
credentials and installation files are not retained.

## Reproduce

```sh
cargo test -p universe-service -p universe-store -p universe-protocol -p universe-client -p universe-mcp
cargo check -p universe-ui
cargo run -p xtask -- check-schemas
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
uv run --with jsonschema==4.25.1 python scripts/test_source_assessment_contracts.py
cargo build -p universe-cli -p universe-engine -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/assessment_review_pilot.py
python3 scripts/audit_assessment_review.py docs/evidence/assessment-review/transcript.json.gz
python3 scripts/test_assessment_review_audit.py
TMPDIR=/tmp uv run --with jsonschema==4.25.1 python scripts/mcp_smoke.py
```

This increment does not implement assessment approval enforcement,
validation/commit binding integration, language interpretation, or native
interaction/accessibility qualification. Existing validation still reports its
previous record-scope/absence behavior. A retrieved assessor declaration does
not promote that result into assessed continuation or manuscript qualification.
