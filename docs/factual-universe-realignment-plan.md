# Factual universe realignment plan

October 3, 2026. Normative unreleased replacement roadmap, based on Vanna's clarification in **Design reusable object rules** and source review at `f3dbf05`.

This replaces the unstarted Goals 20–21 and the remaining execution sequence in the [continuity-gap remediation plan](continuity-gap-remediation-plan.md). Completed work and its evidence remain valid within their recorded scope. Vanna has directed replacement with one normative model and no parallel prerelease schema/contract versions. The concrete mapping is in [the relational package](decisions/relational-storage/README.md). Production migration remains a separate operator action; the earlier two-operand recommendation is superseded.

## Product boundary

Universe Builder owns the author-defined universe, its worlds, the identities and definitions within them, and the chronology of established facts and changes. The external writer's AI interprets prose, reasons about the story, asks the author relevant questions, and submits proposed factual changes. The MCP retrieves and correlates facts, exposes uncertainty, validates supported consequences, and publishes authorized changes.

It does not recommend prose, judge a storyline, extract every implication from arbitrary writing, or simulate unauthored behavior. Manuscript assessments are optional attributed evidence; they are not prerequisites for ordinary factual universe management. Keep their working bindings and historical records without making them the central authoring workflow.

Objects and types can be introduced incrementally. A name and identity are enough to begin a definition. Missing properties remain unknown. Request clarification when a missing fact matters to the proposed use, rather than demanding a complete specification of every object.

## Target semantics

| Concept | Required meaning |
|---|---|
| Type definition | Stable universe-owned identity, name and one nullable subtype parent; optional authored world applicability. |
| Instance | Stable identity and its known classification. Classification can become more specific without creating a new instance or implying physical transformation. Preserve unclassified objects where information is absent. |
| Attribute | Authored name and typed value or values, attached to a definition or instance with applicable world, context, time and basis. |
| Shared definition | Describes inherited capabilities or constraints. It never supplies an instance's current ammunition, height or other changing state. |
| Initial-value definition | Can establish a separate initial fact once at each instance's explicit authored start, through reviewed changes. It is not a continuing balance or a refill. |
| Relationship | Explicit relation between identities. Composition, location and custody are distinct from subtype ancestry. |
| Occurrence | An established event can change facts through its declared effects. Planned, reported and hypothetical events retain their existing nonexecution meanings. |
| Rule | Authored condition associated with relevant definitions or instances and explicit jurisdiction. Keep wording, versions, policy and authorized exceptions. |
| Unknown or conflict | Preserve its evidence and scope. Never select a convenient value, borrow another object's state or import unauthored physics. |

For example, Tree → Cedar → Western red cedar is a subtype chain. A particular tree can have `height: 30 feet` and `dangerous to climb: true`. Tree may have `grows: true`; a growth rate does not automatically advance height or establish an unconditional prediction. A world may define a different subtype without altering another world's trees.

Gun → Pistol and Gun → Revolver share authored definitions. Pistol A can have seven rounds while Pistol B has three. Firing A changes A's state only. Renaming, reclassification, holder transfer, another mention, another scene and restart do not reinitialize either instance.

Refining classification is new knowledge about an identity; an occurrence transforming an object is a different authored change. If relevant classifications or shared definitions conflict, report them for resolution instead of choosing silently.

## Findings that change the roadmap

The committed accounting, history and publication work should be retained. Goals 16–18 have implemented declared effects, exact transitions and cumulative resource use. The latest committed reusable-rule work is preparation evidence, not a delivered shared-definition layer.

Source inspection confirms these mismatches:

1. `EntityType.parents` is a vector rather than one nullable parent. Property subject-type checks use direct instance memberships, without ancestor resolution. Ordinary property propositions require entity subjects, preventing the same fact path from directly describing a type.
2. `record_versions.payload`, `workflow_entries.payload` and snapshot membership are serialized data. Canonical JSON is persisted even where the SQL column is BLOB. Installation grant worlds/limits and profile files also serialize JSON; logical export writes JSONL. Normalizing record projections alone cannot satisfy the no-JSON-data-storage requirement.
3. State/context retrieval exposes record families that callers must assemble. It does not yet provide one effective object description with separately attributed definition facts, instance facts, chronology and applicable rules.
4. The earlier rule recommendation used an isolated evaluator result as evidence of an admission gap. Full candidate validation separately rejects incompatible supported values of a single-valued property. Retain the probe as a characterization of the rule function; reassess the recommendation through the entire public workflow.

Implementation anchors: [types](../crates/universe-domain/src/records.rs), [structural/scalar validation](../crates/universe-service/src/validation.rs), [canonical storage](../crates/universe-store/src/kernel.rs), [stored workflow schema](../crates/universe-store/src/schema_v2.sql), [installation authority](../crates/universe-service/src/registry.rs), [logical archive](../crates/universe-store/src/archive.rs), and [cumulative proof](cumulative-resource-verification.md).

## Preserve the working foundation

Keep stable IDs, represented contexts, explicit worlds and clocks, proposition/evidence distinctions, historical revisions, branches, opposing-evidence reporting, owner-bound requirements, generated effects, exact resource accounting, protected rules, current grants, frozen proposals, validation bindings, author approval/delegation, atomic publication and idempotent receipts.

Keep sources, appearances and existing work/assessment records recoverable. Do not delete history because it is outside the primary writer-facing flow. Existing tests remain regression evidence; do not weaken them to accommodate a replacement design. An intentional semantic change needs independently specified expectations and preservation of authored factual evidence. Earlier prerelease design contracts are not compatibility obligations.

Do not replace the transactional kernel, introduce another AI inside the MCP, add a separate state ledger, or implement a background simulator. Prefer the existing thirteen public tools with simpler typed operations/views where sufficient.

## Execution order

### A. Specify the normative relational storage and definition-resolution model

First produce a concrete schema and complete mapping of persisted application data. Use a small semantic core, with additional rows only where existing requirements demand them:

- Preserve identity, version, commit, change, continuity and receipt tables.
- Represent type names/parents, instances/classifications, properties, propositions, assertions and relationships with typed columns and foreign keys.
- Store supported values in typed fields; use ordered child rows for collections and named rows for authored attributes. Preserve exact numeric representations, units, reference identity and absent/explicit-null distinctions where historical digests require them.
- Represent rule expressions, requirements and effect slots as explicit typed nodes/rows with ordered links, not JSON documents or opaque serialized payloads.
- Give proposals, compiled changes, validations, approvals, operations, assessment bodies and selection history typed workflow representation. Avoid creating a table per incidental field where a shared typed representation suffices.
- Audit installation authority, snapshots, caches, source/media staging, backup manifests and export/import. JSON transport may remain transient at the MCP boundary; it must not be copied into persistent application-data payloads. Required source/media bytes remain content rather than an escape hatch for application metadata.

Show the exact handling of every currently supported family before declaring the mapping complete. A compact illustration is not a complete migration schema. Do not hide remaining JSON in a generic document column, alternate binary serializer or relational projection backed by JSON authority.

The proposal must resolve legacy multiple-parent/multiple-membership data explicitly; never pick a parent or discard a classification silently. It must specify definition applicability, subtype refinement and conflicts without inventing override precedence. Existing authored packages and old backups are migration inputs to preserve, not files to delete under the no-JSON requirement.

The replacement policy is decided: revise the single normative schema in place until release. Do not retain old/new body routes, alternate active serializers or prerelease contract-version tags. Keep factual revisions and evidence. The concrete package demonstrates this policy; implementation and operator migration are separate work.

### B. Implement normalized canonical storage in bounded vertical slices

Deliver shared typed value/reference/scope/time storage and a complete Tree/instance/fact round trip first. Then move supported canonical record families in coherent groups, including rules, actions, events, source/appearance/work records and their references.

Each slice writes a disposable new-format package, reads it back into the normative domain types and verifies identities, values, provenance and historical digests independently. Do not advertise the new format as complete while unsupported families still require opaque payloads. Keep the working evaluator and generated-assertion identity recipe unless an explicitly reviewed change is necessary.

### C. Complete workflow and installation persistence

Normalize proposals and compiled assignments, validations, operation history, approvals, attachments/selections, grants and persisted installation configuration. Preserve authority separation and private credential protections. Store snapshot membership as rows or rebuild it; do not retain a JSON snapshot cache.

Prove exact retry and restart behavior, current permission checks, stale proposal/selection denial, private review and atomic selection/head comparison. Historical assessment declarations remain attributed declarations. Ordinary factual changes retain the explicit absence-assessment path.

### D. Migrate and cut over safely

Use read-only legacy inputs and a private target containing the single normative schema. Normalize recognized source data, preserve identities/factual revisions/receipts/authority, verify original digests before conversion, and retain original digest provenance separately when normalized bodies change bytes. Do not keep old active serialization contracts to reconstruct old layouts forever.

Do not rehash mismatches into success. If exact historical reconstruction is impossible for a family, bring that specific incompatibility and proposed handling to Vanna before conversion.

Inventory actual packages/configuration before operator migration. Test interruption and failure before publication; verify the complete target before a controlled atomic switch. Retain needed originals for recovery under the reviewed migration policy. Do not automatically convert active author data on startup.

Update backup/restore and logical export/import to the approved non-JSON persisted format. Prove full historical reads, integrity verification, source/media availability and exact receipts after restore and restart. Check actual target tables/files for residual serialized application data, not just the absence of `.json` filenames.

### E. Deliver effective definitions, instance facts and simple authoring

Implement the approved one-parent subtype model, definition-subject attributes and ancestor-aware property/rule applicability. Preserve instance-owned changing state and revalidate affected facts/events when definitions change. Unknown membership/applicability remains visible.

Offer atomic writer-facing operations that introduce a minimal type or instance and add named typed attributes without requiring the caller to manually construct every low-level record. Compile them into the established fact/evidence/proposal path. Preserve stable instance identity during classification refinement. No default physics or silent initialization.

Assemble an effective object description through existing state/context retrieval. Return identity, known classification/ancestry, applicable definition attributes, distinct instance facts, current state, behavioral requirements, applicable rules, conflicts, relevant unknowns and exact provenance. Keep world/context/time/revision and access restrictions explicit. Shared values must not appear as instance observations.

### F. Qualify the Cedar and Pistol workflows

Use actual MCP calls and independently authored state tables:

1. Define Tree with minimal information; establish one tree's existence/location/time; add a shared capability and an instance-specific climbing hazard; refine its classification to a cedar subtype while retaining identity.
2. Retrieve its effective description; demonstrate unknown height/unit or growth conditions; record a supported factual change; compare earlier/later facts; restart; correct an earlier fact and inspect the impact.
3. Define authored gun behavior; establish two independent instances/balances; exercise shots, exhaustion, holder change, replenishment with constrained supply, subtype/world differences, retcon and restart.
4. Introduce another matching instance and check applicable definitions/rules. Test a factual stock proposal outside a firing event through complete propose/validate/approve/commit admission.

Clarification belongs to the external authoring interaction. The MCP returns the exact missing or conflicting factual obligation; the external AI asks only what matters, preserves the author's answer, and proposes its agreed scoped interpretation through existing protected authority.

### G. Close demonstrated factual enforcement gaps

Use the complete workflows to decide whether targeting, retrieval, authoring compilation or an evaluator extension is needed. Reuse finite expressions where they satisfy the real requirement; do not impose an arbitrary enumeration when demonstrated author rules need a broader bound.

Reassess knowledge basis/truth/context, channel chronology and cross-instance cardinality as factual constraints. Establish author-controlled semantics before affected changes. Add only the supported bounded checks the workflows demonstrate, with legal and unresolved controls. General paradox solving, geometry or biological simulation remain outside the required service.

### H. Qualify the external writer integration and optimize measured paths

Verify the external AI can retrieve effective facts, identify relevant unknowns, obtain author clarification, submit a factual proposal, respect authority, recover receipts and continue from the committed revision. Score factual mappings separately from engine admission. Scripted MCP tests establish protocol behavior, not model interpretation quality.

Native interaction and the intended model host remain subject to their existing pauses/restrictions; this plan does not resume them. Qualify their factual workflow when resumed, without making a universal manuscript-analysis promise.

Measure ancestor resolution, temporal fact retrieval, applicable-rule lookup, impact analysis and context assembly. Add indexes or narrower evaluation only where observed cost warrants it. Prove any optimized path equivalent to the trustworthy complete path; do not invent performance thresholds or another coordination service.

## Reframe the original gaps without losing their evidence

| Original gap | Service responsibility under the corrected boundary |
|---|---|
| G01: wrong action classification | Return applicable capabilities/actions; validate the submitted declaration. Prose classification belongs to the external AI and author. |
| G02: incapable actor acts | Retain owner-bound factual requirements and pre-event checks. |
| G03: unlimited resources | Retain instance accounting; complete applicable shared definitions/rules and relevant clarification. |
| G04: unrelated grant | Retain required/permitted effect checks and authored causal basis. |
| G05: opposing evidence | Retain reporting and authored scoped admission policy. |
| G06: impossible knowledge | Keep knowledge, belief and acquisition as scoped facts; enforce the declared supported semantics. |
| G07: impossible communication | Check authored channel/time constraints; preserve unresolved clocks and lawful exceptions. |
| G08: global cardinality | Check an explicitly declared cross-instance constraint where needed; local role multiplicity is distinct. |
| G09: appearance mismatch | Correlate accepted factual appearance attributes with applicable state; external interpretation does not silently create facts. |
| G10: wrong citation interpretation | Preserve source bytes/basis and attributed judgments. Byte verification never proves entailment. |
| G11: source-only contradiction | Source archiving is legitimate. Only authorized factual changes alter canon; a source receipt is not a manuscript-continuity certificate. |

Use R01–R14 as factual boundary scenarios: separate story time from narration; isolate lies/dreams/reports; preserve aliases versus IDs; declare body/mind/clone ownership; record memory changes; expose unmapped clocks; check authored travel/process/artifact conditions; preserve completeness limits; revalidate retcons; restrict information by actual perspective; distinguish promises from fulfillment; let the external AI interpret metaphor and implied action. These scenarios do not mandate fourteen additional simulations or a storyline subsystem.

## Proof and completion discipline

For each semantic capability use independently specified legal, illegal and unresolved cases, actual MCP admission/state checks, and correction/history/restart proof where relevant. For persistence use an independent relational reconstruction audit plus migration/fault/backup/restore tests. Keep failed attempts and existing regression evidence; changing an oracle to fit an implementation is not qualification.

The corrected completion criteria are:

- Definitions/instances can be introduced and refined incrementally, with scoped attributes and useful deterministic factual retrieval.
- Authored applicable rules and declared effects are enforced on the correct identities and chronology; unsupported conditions stay explicit.
- New-format application persistence contains no JSON payload authority, workflow blobs or equivalent opaque document fallback; all supported families and installation data are mapped and verified.
- Migrated history, receipts, authority and source/media integrity remain recoverable, with controlled compatibility and no silent history rewrite.
- Cedar/Pistol and relevant factual risk scenarios pass independent/public/recovery proofs; host/native claims reflect actual executed evidence.
- The service owns factual continuity and makes no exhaustive prose or storyline claim.

Size execution goals around 45–75 minutes of observed working time, with meaningful implementation plus proofs in one goal. Keep a necessary design decision separate; split large storage/migration work by coherent supported families after the schema inventory establishes its size. Do not fill an hour with extra abstractions or duplicate tests. Every execution goal ends with all its work conventionally committed and reports commit hashes, evidence, limitations and actual working time. Do not claim a revised total goal count before this mapping is scoped.

The concrete package in A is complete with disposable proofs; it follows the normative replacement decision. Subsequent implementation work replaces the existing application paths with that single model. Production migration and evaluator extensions were excluded from the package goal.
