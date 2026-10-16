# Validation input scope

This document records the historical reporting-only slice. Statements below
about absent attachment routes apply to that slice, not the current service.
Current selected-assessment behavior is described in
[the operator workflow](ai-authoring-workflow.md) and governed by
[the approved D03/D08 contract](decisions/d03-d08-source-assessments.md).
Retained results describe their original scope.

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
| Restricted evaluation | Undisclosed | Restricted |

The service derives source inclusion from compiled source/source-version/anchor/work-edition writes. Sources merely present elsewhere in canon do not change the submitted scope. Caller rationale, claims of whole-manuscript assessment and caller scope hints cannot create assessment evidence. Complete engine execution still describes finite structured checks; a source-only canonical commit archives records without establishing manuscript continuity.

The typed output contract includes the approved source-assessed, bound, stale and unavailable representations, exact evidence references, source ranges and declared conclusions. Approved synthetic assessed fixtures exercise decoding/schema compatibility only. The current service has no attachment submission route and emits no bound assessment. Only a later implemented attachment workflow with recorded, validated evidence may promote an input to source-assessed scope. No `source_assessment.v1` implementation capability is advertised here.

Completed proposal validation binds the exact frozen proposal/frame, explicit absent selection at generation zero, submitted scope, absent assessment, fully serialized execution digest and evaluator using the approved `source-validation:v1:` hash domain. The existing candidate digest/domain operations are unchanged. Exact author approval binds the expanded Checked evidence. Approval and commit independently verify the scope/binding against the stored candidate; legacy, query, pending and restricted evidence has no usable final binding. Existing admissibility, partial-coverage author authority, delegation and head/version controls remain authoritative.


Rust clients re-export the scope types; MCP schemas/guidance and native author result reads use the nested execution. Native author review exposes all axes and requires a final binding before approval. Native code compilation is checked; native UI interaction/accessibility qualification remains excluded.
