# Validation input scope

This document records the earlier reporting-only slice. Current selected-assessment
validation behavior and qualification are in [Selected assessment validation
bindings](validation-binding-verification.md). Historical proofs below retain
their original scope.

October 2, 2026. Implements the reporting slice of the [approved D03/D08 decision](decisions/d03-d08-source-assessments.md). Execution coverage, submitted input and assessment evidence are separate axes. This does not implement assessment attachment submission, language interpretation or native interaction qualification.

Protocol 3 validation returns `ValidationV3`. Evaluated results contain `execution`, `submitted_input`, `assessment` and an explicitly nullable `final_binding_digest`. Restricted results are exactly:

```json
{"kind":"restricted","execution_coverage":"restricted","submitted_input":{"kind":"restricted"},"assessment":{"kind":"restricted"}}
```

| Actual input/evidence | Submitted scope | Assessment |
|---|---|---|
| Structured writes without source records | `record_candidate`, `includes_sources=false` | `absent` |
| Source-only writes | `record_candidate`, `includes_sources=true` | `absent` |
| Mixed structured/source writes | `record_candidate`, `includes_sources=true` | `absent` |
| Inline check without frozen proposal authority | `query`, exact frame/check scope | `absent` |
| Stored protocol-2 validation | Scope reconstructed from its frozen compiled writes | `unavailable_legacy` |
| Restricted evaluation | Undisclosed | Restricted |

The service derives source inclusion from compiled source/source-version/anchor/work-edition writes. Sources merely present elsewhere in canon do not change the submitted scope. Caller rationale, claims of whole-manuscript assessment and caller scope hints cannot create assessment evidence. Complete engine execution still describes finite structured checks; a source-only canonical commit archives records without establishing manuscript continuity.

The typed output contract includes the approved source-assessed, bound, stale and unavailable representations, exact evidence references, source ranges and declared conclusions. Approved synthetic assessed fixtures exercise decoding/schema compatibility only. The current service has no attachment submission route and emits no bound assessment. Only a later implemented attachment workflow with recorded, validated evidence may promote an input to source-assessed scope. No `source_assessment.v1` implementation capability is advertised here.

Completed proposal validation binds the exact frozen proposal/frame, explicit absent selection at generation zero, submitted scope, absent assessment, fully serialized execution digest and evaluator using the approved `source-validation:v1:` hash domain. The existing candidate digest/domain operations are unchanged. Exact author approval binds the expanded Checked evidence. Approval and commit independently verify the scope/binding against the stored candidate; legacy, query, pending and restricted evidence has no usable final binding. Existing admissibility, partial-coverage author authority, delegation and head/version controls remain authoritative.

Historical workflow entries retain their original bytes/hashes. Public operation views wrap old execution as `unavailable_legacy` without authorizing fresh publication. A fresh protocol-3 run and applicable approval are required. Wire version mismatch fails explicitly; no live v2 bridge is supplied. Queued/polled/retried results retain the reporting axes and completed binding. Scoped operation reads suppress private findings, proposal details, failure reasons and pagination metadata.

Rust clients re-export the scope types; MCP schemas/guidance and native author result reads use the nested execution. Native author review exposes all axes and requires a final binding before approval. Native code compilation is checked; native UI interaction/accessibility qualification remains excluded.

## Proofs

[Expected responses](../fixtures/validation-scope/expected.json) are fixed from the approved decision, independent of runtime-produced responses. Protocol and Python schema checks also use the pre-existing approved query and assessed-result fixtures. Negative controls reject hidden metadata in restricted objects, unknown nested fields, missing explicit null bindings, malformed digests and omitted evidence universes. These establish DTO/schema behavior, not interpretation or attachment admission.

The [MCP proof runner](../scripts/validation_scope_pilot.py) uses actual persistent binaries and temporary installations, with source staging/exact approval through the existing author CLI. Its independently calculated canonical hash checks use Python rather than the service serializer or report builder. [Final actual responses and binary/fixture hashes](evidence/input-scope-2026-10-02/run6.json) retain all validation/commit calls and upgrade observations.

The final run checks structured, source-only, mixed, structured-after-source-history, inline query, restricted, queued/polled/completed retry and restart cases. It verifies source-only/mixed canonical commits, missing-approval denial, exact author approval, idempotent receipt recovery, protocol-2 handshake rejection, legacy approval/commit denial with unchanged head and successful fresh validation/approval/commit. All 11 existing v2 workflow entries remain byte-for-byte unchanged after upgrade and fresh publication.

Reproduction:

```sh
cargo test --locked -p universe-protocol -p universe-client -p universe-service
cargo check --locked -p universe-ui
cargo run -p xtask -- check-schemas
uv run --with jsonschema python scripts/validate_contracts.py
uv run --with jsonschema python scripts/test_validation_scope_contracts.py
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp
uv run --with jsonschema python scripts/validation_scope_pilot.py \
  --old-bin-dir /tmp/g05-old-bin \
  --output docs/evidence/input-scope-NEW/report.json
```

The old-binary directory must contain the actual protocol-2 binaries; hashes are recorded in the final report. This run reused the retained pre-G05 binary set. The reporting proofs use no model inference.

Final checks: 73 Rust tests passed, zero failed, one pre-existing release performance workload ignored; 3 independent scope schema tests passed; 26 generated schemas, 13 valid requests and 91 invalid requests passed, with schema freshness checked. Native client code compiled. Existing historical G05 and continuity audit tamper suites each passed 6 tests with their explicit saved-evidence arguments.

Earlier attempts are retained: the initial Python invocation lacked jsonschema; queue scheduling tests exposed consumers of the old flat result; restricted-object controls exposed permissive unit-variant decoding; and the nullable-binding schema control exposed an incorrectly nonnullable schema. These were implementation errors corrected without design changes. [Run 3](evidence/input-scope-2026-10-02/run3.json) retains the queued-schema failure. A broad test-discovery invocation also omitted the historical suites' mandatory evidence argument; both suites subsequently passed using their supported entrypoints. Run 2 passed the initial MCP cases; runs 4/5 passed after the fixes; run 6 is the final qualified build.

Evidence applies to the current working tree. The repository already contained substantial unrelated changes. The initial scope commit captured previously untracked shared files touched by this API change but left earlier dependencies uncommitted. At Vanna’s subsequent request, the follow-up implementation snapshot commits the remaining tracked changes and untracked source, tests, documentation and packaging files. The earlier checks ran against that full implementation; the initial scope commit alone did not capture it. This is reporting-contract qualification, not a release or wider continuity-gap completion claim.
