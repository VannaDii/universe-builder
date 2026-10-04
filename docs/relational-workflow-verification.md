# Relational workflow verification

October 4, 2026. This records the scoped relational workflow implementation.
Complete no-JSON qualification and live-package cutover remain separate work.

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
the frozen proposal preimage (empty digest, ordered operations, full assignments
and footprint), proposal/frame, selection/absence/generation, assessment/source bodies, validation
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
new contention/interruption auditor and its seven adversarial mutation controls.
The updated disposable decision prototype also passes its independent body,
workflow, backup and semantic reconstruction controls. These prototype results
are not live-package or installation conversion qualification.

## Draft conversion and final workspace gate

The private draft DTO now carries ordered `Vec<DomainOperation>` values, matching
its approved relational schema. Autosave decodes the editor's transient operation
representation before sending the typed request; loading restores the ordered
array to the editor. The operation byte-size limit is retained. No raw operation
string is persisted as a fallback. Malformed strings and unknown operation kinds
reject at the private request boundary. This implements the already approved
[compatibility policy](decisions/relational-storage/compatibility.md); the earlier
claim that it required a new design decision was incorrect.

Both previously failing draft integration cases pass. They verify operation order
and values, author/continuity isolation, unchanged canon, optimistic concurrency,
exact lost-response retry, restart recovery and revision of a submitted draft
with invalidation of its prior approval. Historical invalid/incomplete inputs
remain subject to the approved read-only conversion policy; existing author
packages were not converted.

The required `cargo run --locked -p xtask -- check` passes: formatting, strict
workspace Clippy, 337 tests (zero failures; one existing release-only workload
test ignored), documentation tests and schema-drift checks. The final output is
retained in `workspace-gate.txt`. Fresh final-binary publication and race pilots
also pass their separate independent auditors; their retained transcripts and
checksums have been refreshed. The scoped workflow goal is complete.

Installation/configuration conversion, remaining canonical-family qualification,
export conversion and live-package cutover remain excluded from this goal.

Follow-up audit: all three frozen proposals in the retained publication transcript
also independently reproduce their candidate digests, rather than merely matching
the surrounding workflow-envelope hash. Three additional controls alter valid
operation, assignment or footprint fields and recompute the envelope hash; the
candidate preimage check still rejects them. No runtime/design change was needed.

Actual active working time to completion: approximately 40 minutes, including
the earlier 32 minutes 10 seconds and this final conversion/verification pass.
Time waiting between user turns is excluded.
