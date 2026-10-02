# Additional D03/D08 completion-audit controls

October 2, 2026. These supplementary fixtures preserve the original frozen oracle and remain awaiting separate judgment. They specify proposed-contract outcomes, not implemented test passes.

| ID | Exact stimulus | Expected judgment / evidence |
|---|---|---|
| O39 | Hidden source dependency; client requests the assessment-aware validation wrapper | Exactly the `restricted_result` in examples.json: kind=restricted, execution_coverage=restricted, restricted input and assessment. No hidden IDs, digests, counts or stale reasons. `Validation`'s mandatory input_digest is not embedded. A null/redacted excerpt alone is inadequate. Covers O24/O29 concretely. |
| O40 | Query-mode engine validation at an exact known frame, complete execution, no frozen proposal or assessment | `query_result` has evaluated kind, query submitted_input, absent assessment, null final_binding_digest. Engine complete does not create proposal approval/commit authority. |
| O41 | Inventory item's byte range outside declared source ranges; or mapping refers to item but inventory item omits mapping; or source_key references an absent source | Reject attachment accounting. Independent decoder/range comparison and reciprocal ID lookup are the acceptance oracle; positive example ranges are [0,34), [11,34), [35,47) within [0,47). These are structural judgments, not semantic recall proof. |
| O42 | Only frame.readerScene or frame.personalSequence changes; or source/dependency VersionRef omits universe | Frame change requires new exact candidate/assessment; old final binding stale. Omitted universe rejects assessment input instead of inferring it; current domain optional reference remains unchanged elsewhere. |

All gold sources, canonical arithmetic preimages and unchanged-state references stay unchanged. The completion audit caught that the original normal result type required input_digest even for hidden sources; the explicit restricted response variant now implements the stated nondisclosure recommendation in the proposed contract. This is not a change to the current runtime or approval architecture.
