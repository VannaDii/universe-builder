# Relational workflow implementation checkpoint

October 3, 2026. The goal remains active; this is a verified implementation
checkpoint, not a complete no-JSON qualification or live-package cutover.

New disposable packages use the approved fixed workflow envelope pointers in
[workflow.sql](decisions/relational-storage/workflow.sql) and the existing typed
body codec. Frozen proposal operations and ordered assignments, checked
validations/captures, author approval evidence, internal operation states and
receipts, assessment envelopes, retry receipts and every selection generation
are reconstructed from scalar columns, variant pointers and child rows. There
is no opaque workflow-body fallback. Optional missing fields and explicit null
values retain their different states. Source/media content is stored as actual
bytes; its original transient workflow representation is reconstructed to check
the retained workflow digest. `workflow_index` joins these immutable namespaces
for the existing key lookup and latest-key comparisons.

Workflow append still owns one immediate transaction, including all body trees.
Retry reconstructs and verifies the prior body before accepting equality. Unknown
families and changed immutable keys reject. Selection/proposal comparisons still
occur in the same transaction as head movement and canonical receipts. Package
open and backup independently reconstruct every workflow hash. Canonical
membership and installation authentication/grant/authority boundaries are
unchanged. Old serialized workflow layouts are rejected without conversion or
repair. Logical export retains its existing format; adapting source/media access
is not export conversion.

The assessment discriminator now emits the approved `source_assessment` name,
with the existing `source-assessment:v1:` digest recipe. The public contracts and
current synthetic fixtures agree. The current protocol scenarios are separately
derived with Python, a handwritten encoder and OpenSSL; the original frozen
decision files remain unchanged. Previously published historical artifacts are
not rewritten. Existing author packages require the separately authorized
conversion/cutover and are outside this checkpoint.

## Evidence

The synthetic [evidence directory](evidence/relational-workflow) contains compressed
actual stdio MCP transcripts, separate audit results and SHA-256 checksums.
The independent Python relational reader uses the normative catalog but does not
import or execute the Rust codec. The publication auditor separately reconstructs
proposal/frame, selection/absence/generation, assessment/source bodies, validation
binding and complete approval hashes. The review auditor uses its handwritten
canonical encoder and OpenSSL digest checks.

| Requirement | Observed proof |
|---|---|
| Proposal → validation → private author approval → public commit | 33 publication/author cases; assessed commit and fresh withdrawn/absent commit pass. |
| Immutable frozen proposals and full assignments | Every observed workflow reconstructs to its retained digest; prior rows remain equal across attachment/selection and failed calls. |
| Explicit absence and selection generation | Generation-zero validation, replacement, withdrawal, same-identity reselection and fresh withdrawal approval/commit are independently checked. |
| Private access | 24 attachment/action cases and 88 paged private-review cases pass; restricted, revoked, wrong-owner and obsolete cursor controls retain generic denials. |
| Race safety | Two real MCP attachment requests sent before consuming either reply yield exactly one selection/receipt and one `APPROVAL_STALE` denial. Deterministic service and separate SQLite writer tests cover publication replacement, withdrawal, grant restoration/revocation and the final transaction lock interval. |
| Interrupted publication | A real MCP publication trigger failure leaves all observed workflow/canonical rows and every typed-table row count unchanged; six canonical fault points roll back head, versions, projections and receipt. |
| Exact historical recovery | Forced engine restart preserves attachment/selection/validation evidence and exact commit/attachment retry receipts. Independent auditors verify the recovered hashes and bindings. |
| Tamper/retry safety | A typed scalar changed after disabling its SQL trigger causes read, retry and restart rejection; body/envelope mutations and deletion normally reject. |

Executed checks: 43/43 service library tests, 27/27 kernel tests, 2/2 media tests,
11/11 protocol assessment tests, six standalone assessment schema tests,
strict workspace Clippy, formatting, schema-drift checks, three existing independent MCP audits,
new contention/interruption auditor and its four adversarial mutation controls.
The updated disposable decision prototype also passes its independent body,
workflow, backup and semantic reconstruction controls. These prototype results
are not live-package or installation conversion qualification.

## Remaining decision and gate

Two service integration tests still fail:
`drafts_survive_restart_without_canon_and_reject_cross_window_overwrites` and
`recovered_submitted_draft_revises_its_reserved_ids_and_invalidates_approval`.
The other 20 workflow integration cases pass. The required
`cargo run --locked -p xtask -- check` passes formatting and strict Clippy, then
stops at these two failures in workspace tests; it is not green.
The retained `workspace-gate.txt` records that result.

This is an existing contract mismatch exposed by the closed typed writer:
[DraftContent](../crates/universe-protocol/src/installation.rs) promises to preserve
invalid/incomplete editor text in `operations: String`; the approved
[relational contract](decisions/relational-storage/build_schema.py) stores
`DraftContent.operations` as ordered `DomainOperation` rows. Invalid raw text
cannot be converted into facts without inventing or dropping content. No raw-body
fallback or editor behavior change has been introduced to hide that conflict.
Affected draft conversion is paused pending Vanna's scope/design decision. The
requested core workflow proofs pass, but the full goal and workspace gate cannot
be declared complete while this regression remains. The pending scope question
asks whether to defer draft conversion or include the editor conversion here.

Installation/configuration conversion, remaining canonical-family qualification,
export conversion and live-package cutover remain excluded from this goal.

Working time for this checkpoint: 26 minutes 21 seconds, measured from
2026-10-04 04:32:03 UTC to 04:58:24 UTC. The goal is unfinished, so this is not a
claimed time to completion.
