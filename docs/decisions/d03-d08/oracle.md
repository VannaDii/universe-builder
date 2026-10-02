# D03/D08 requirement-derived acceptance oracle

Prepared October 2, 2026. Frozen before the proposed payload and lifecycle were written. These judgments derive from the task, the remediation plan and current owning sources, rather than any implementation output. The oracle author is the same primary agent as the proposal author; independence here means a separately frozen requirement derivation and independent calculation methods, **not a second person or reviewing agent**. No production implementation is exercised. Future external host qualification requires a separate assessor and held-out corpus; this package grants no such qualification.

Gold passage A (exact UTF-8, no final newline): `Mara said, “The door is open.” Iven waited.` Gold B: `Mara said, “The door is closed.” Iven waited.`

Gold inventory: (1) Mara utters a quoted statement; (2) the statement attributes open/closed to the door in Mara's reported context, not objective reality; (3) Iven waits. The prose establishes neither objective door state nor Iven's knowledge acquisition. Waiting is an unchanged state if the candidate already represents it. A source archive with no semantic changes remains legitimate. The gold inventory is an independent expected answer for this synthetic example, not a universal materiality definition.

| ID | Stimulus | Gold judgment |
|---|---|---|
| O01 | Archive A with no attachment, structurally admissible records, complete engine run | Complete execution; source-only submitted input; absent assessment; no prose certificate. |
| O02 | A mapped to Mara's speech/context and Iven's waiting, both represented with exact references | Declared inventory covered; externally asserted consistent within submitted passage only. |
| O03 | A mapped to objective door-open truth | Interpretation mismatch, regardless of byte verification or engine success. |
| O04 | B mapped to door-open in Mara's context | Contradiction/mismatch, not clean. |
| O05 | Waiting omitted from declared inventory although in gold | Gold material recall fails; runtime binding may still be valid. Never claim runtime proves arbitrary inventory completeness. |
| O06 | Waiting included, linked to an unchanged base assertion | Covered without duplicate assertion or canonical operation. |
| O07 | Waiting included but no mapping or unresolved entry | Incomplete inventory representation; no consistent result. |
| O08 | “Iven could have waited.” mapped as an occurred waiting event | Modality mismatch. |
| O09 | “She said it was open.” with no resolved speaker | Unresolved referent; cannot become consistent merely by hashing. |
| O10 | Claim speaker replaced with a different same-name entity | Wrong owner; gold mismatch. |
| O11 | Claim context, world, story time or occurrence changed | Exact attachment changes; old review binding cannot apply. |
| O12 | Old source A superseded by B in a new work edition | Old attachment remains valid historical evidence for A; cannot apply to B/current continuation. |
| O13 | Source bytes changed while source/version identity retained | Integrity rejection, not just uncertain interpretation. |
| O14 | UTF-8 anchor starts inside a curly quote | Reject boundary, even if a byte hash is supplied. |
| O15 | Anchor bytes match, assessor claims semantic entailment | Bytes verified separately; entailment remains assessor's assertion. |
| O16 | Candidate, base revision, definitions or proposal submission version changed | Stale applicability; new exact assessment/validation and applicable approval required. |
| O17 | Attachment first added after approval | Approval for prior attachment selection cannot authorize the new selection. |
| O18 | Attachment replaced with equally positive verdict | New identity/digest/selection generation; fresh validation and applicable approval. |
| O19 | Selected attachment withdrawn | Historical body retained; live selected assessment absent/withdrawn; prior validation stale. |
| O20 | Two writers replace attachment from the same selection generation | Exactly one transition; second gets concurrency conflict. |
| O21 | Identical idempotency key retried with identical request | Exact response recovered; no new assessment/selection generation. |
| O22 | Same key, altered body or expected generation | Reject mismatched retry. |
| O23 | Assessor asserts an author identity absent from authenticated caller | Reject impersonation; model/organization labels alone confer no authority. |
| O24 | Assessment contains out-of-scope source/dependency/world | Generic restricted/unavailable response; no IDs, digests, counts, excerpt or status leak. |
| O25 | Grant revoked after assessment or approval | Commit denied under current authority; stored history does not restore access. |
| O26 | Positive assessment with inadmissible engine result | Canon admission remains blocked; assessment never waives rules/boundaries. |
| O27 | Partial engine execution but admissible candidate, exact author approval | Existing author path remains possible; no complete execution claim. Delegation's Complete gate still fails. |
| O28 | Complete engine run, unresolved assessment, valid delegation | Ordinary bounded record commit may proceed if existing authority permits; host cannot select passage as assessed consistent. No new universal canon blocker. |
| O29 | Restricted engine run | No usable approval/admission evidence; do not manufacture Complete from assessor's verdict. |
| O30 | Legacy closed DTO client receives added assessment fields | Rejects/unsupported version, not silent backward compatibility; never strip fields then issue assessment-aware approval. |
| O31 | Historical legacy receipt opened by new client | Preserve bytes/meaning; assessment status unavailable in legacy evidence, never retrospectively assessed. |
| O32 | Assessor body contains its own digest, or frozen candidate includes assessment's candidate digest | Cyclic binding; reject contract shape. A hash fixed point is not the design. |
| O33 | Reordered JSON object keys | Same canonical bytes/hash. Ordered inventory/claim arrays changed | Different hash; ordering is retained. |
| O34 | Attachment selection changes during final validation/private commit check | Cancel/stale result or fail atomic comparison; no receipt/head movement. |
| O35 | Earlier retcon affects later waiting evidence or definitions | Current reuse stale even if later source bytes unchanged; old historical edition keeps exact binding. |
| O36 | Final result paged/incomplete delivery | Delivery completeness distinct from execution and assessment; no approval from uninspected omitted review data. |
| O37 | Complete engine run and empty declared inventory for nonempty gold passage | Binding cannot prove completeness; material recall gold fails. A declared no-material-claims assertion is visible, never universal clean assessment. |
| O38 | Failed/cancelled attachment validation, interrupted response/restart | No usable final validation; recover immutable IDs/selection via idempotency, then revalidate. |

## Authority and compatibility evidence

Current `workflow.rs::approve` checks exact proposal, submitted/latest/not-withdrawn state, evaluator, admissibility and current head; it does not universally require Complete coverage. Commit separately requires Complete for delegation, checks protected/shared limits, exact approval evidence and current head, and privately rechecks the candidate under current authority. `canonical.rs` explicitly states matching digests are not authorship. `verify_sources` checks imported source metadata/blob bytes and UTF-8 anchor excerpts, not prose entailment. `response.rs::Validation.coverage` and `Envelope.delivery` are already distinct. `SourceVersion`, `Anchor`, `WorkVersion` and `VersionRef` supply exact source/edition/record binding without a new canonical assessment record. Public requests/results are closed (`deny_unknown_fields`), protocol version is currently 2. Generic workflow storage permits updates, so immutability needs a service insertion rule and atomic selection comparison, not an assumption that workflow_put is append-only.

These are source-based judgments and future acceptance expectations. No new schema, permission, canonical record kind, universal admission gate or implementation is approved by the oracle.
