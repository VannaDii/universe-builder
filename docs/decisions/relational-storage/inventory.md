# Persisted-family inventory and migration mapping

Scope: all persistence-writing paths in the current repository, including supported historical input schemas. This is a source inventory, not an inventory of Vanna's installed author packages. No live package or credential was opened. Source hashes and coverage counts are recorded by `audit_inventory.py`.

## Canonical records

Every `Payload` discriminator has a fixed branch row in `typed.sql`, linked from `r_payload` and the version header. The complete list is:

| Group | Persisted families | Typed destination |
|---|---|---|
| Identity/topology | entity, entity_type, world, realm, represented_context | One closed Payload route. Types have one nullable parent; instances have one nullable classification and explicit resolution state. Ambiguous source vectors become ordered classification evidence, not an alternate body. Names, labels, metadata and world associations retain typed child rows. |
| Definitions | property, relation, unit, calendar, value_definition, domain_pack | Closed branch plus shared ValueShape, Multiplicity, RoleDef, conversions/fields/dependencies/pack-record child rows. Preserve namespace/key, labels, dimensions, base references, scale, conversions and executable flags. |
| Facts/policy | proposition, assertion, completeness, boundary, rule, exception | Proposition roles/value/quantification/context; assertions' exact polarity/scope/time/basis; explicit Expr nodes and ordered operands; rule policies/capabilities, exceptions and accepted findings. New definition attributes add mode; provenance stays on assertions. |
| Occurrences/behavior | event, item_power, action_definition | Closed branch plus ordered participants/preconditions/effects, owner-bound AttributeRequirement, ConsequenceContract, EffectSlot/Target/Condition/Change/Lifetime rows. Preserve slots/order/presence, occurrence identity, sequence, expansion version and exact value changes. |
| Epistemic/intent | epistemic_attitude, observation, communication, memory, secret, goal, commitment | Closed branch; typed holder/content/context/time/acquisition and participant references, conditions/status/party child rows. No truth inference from archiving these bodies. |
| Narrative/review | work, work_version, scene_ref, passage_ref, saga, issue_decision | Closed branch; WorkBinding segments, positions, work/world associations, source refs, versions and saga membership rows. Retain all editorial evidence even when outside the primary factual flow. |
| Source/media | source, source_version, anchor, appearance, image_asset | Closed branch; origin/decoding/locator/target/image/link rows. Source and image bytes live in content rows, with exact digest/byte-size/UTF-8 boundaries retained. |

`field-mapping.md` specifies every scalar and child reference in these groups, all Value variants (including quantity, ranges, sequence, set, structured and reference values), all expression variants and all 50 DomainOperation variants. No rule node, requirement, effect slot, map or list remains an opaque document.

## Kernel/package tables

Source: `crates/universe-store/src/schema_v1.sql`, `schema_v2.sql`, `db.rs`, `kernel.rs`, `projections.rs`, `media.rs`, `archive.rs`.

| Legacy/current location | New representation / exact transformation |
|---|---|
| schema_meta | Retired source metadata; no schema-version table in the normative target. Source format identifies an input decoder only. |
| universes | Retain id/singleton/name. |
| record_identities | Retain universe/id/kind tuple and immutability. |
| record_versions.payload | Decode recognized source body and normalize to the single typed Payload branch. Preserve factual IDs/kind/history; original digest provenance is separate from the normalized digest. No old/new route or schema tag. |
| continuities | Retain head, pinned baseline and IDs. Circular commit/head references remain deferred in the same transaction. |
| commits | Retain continuity, parent, sequence, principal, decision, reason, digest. No reauthoring. |
| commit_changes | Retain record, prior and next version including tombstone nulls; replay per continuity and compare each head. |
| world_name_reservations | Retain nonrebindable name/record/first revision. |
| head_membership | Retain complete effective record-version map with same-universe/version-record foreign keys. |
| projection_heads, projection_state | Retain generation/head checksums or rebuild using existing policy; never treat a cache as canonical authority. |
| snapshot_membership.membership | Decode map into `snapshot_member` rows; retain original revision/checksum in snapshot header; replay and compare before using. |
| reference_index, typed_projection, world_projection, narrative_projection, search_index | Rebuild from typed authority; preserve reference/path/world/text lookup behavior. Existing scalar/path query indexes remain derived only. No stored JSON document becomes authority through these indexes. |
| operation_receipts | Retain exact principal/kind/key/input digest/revision; private current authentication still precedes use. Never infer approval from a digest. |
| workflow_entries.payload | Dispatch strictly by recognized key family below; replace with one typed family pointer/content row; retain original key and canonical workflow digest. Unknown prefixes block. |
| WAL/SHM, writer.lock, temporary backup/snapshot files | SQLite/OS coordination, not separate domain serialization; follow existing private path/locking/cleanup. Source snapshots stay consistent. |

## Workflow key families

Source: `workflow.rs`, `validation_binding.rs`, `assessments.rs`, `drafts.rs`, `runtime.rs`, `archive.rs`, `media.rs`.

| Exact key family | Typed rows and retained bindings |
|---|---|
| context:{id} | StoredContext(owner, scope hash, expires, Frame); reconstruct and recheck expiry/current visibility. |
| proposal:{id}:{version:020} | StoredProposal → Proposal (base Frame, world scope, version/digest/submission/operations/rationale/canonical/operation/withdrawn), owner/author_origin, ordered Assignment changes and Footprint. Frozen IDs/expected/next bodies and full generated effects remain unchanged. |
| reserved-record:{record} | ReservedRecord(proposal_id); retain reservation and key. |
| validation:{run} | Checked → Validation/findings/opposing chains/coverage/unsupported capabilities, admissible, optional report and capture. Capture binds selection, assessment state, submitted input, head, latest proposal key, authority digest/sequence. Preserve missing versus null legacy defaults. |
| operation:{id}, request:{principal}:{kind}:{hash(key)}, job:{id}:running, job:{id}:terminal | StoredOperation with **internal OperationStatus**, optional CommitInput, owner, request digest, footprint/capture. Public OperationStatusReport is a presentation wrapper and must not replace the persisted internal status. Preserve all queued/running/terminal/interrupted/cancelled states and embedded receipts. |
| cancel:{id} | Cancellation(owner if historically present, cancelled); retain cancellation boundary. |
| approval:{author}:{proposal_digest}:{run} | ApprovalEvidence(author, exact ProposalRef, Checked digest, evaluator). It remains historical package evidence; current installation authority and fresh binding checks are still required. |
| assessment:{assessment_id} | AssessmentEnvelope/id/digest/attached_by plus complete SourceAssessment assessor, material/source ranges, dependencies, inventory, claim mappings, candidates, unresolved dispositions and declarations. |
| assessment-selection:{proposal}:{version:020}:{generation:020} | AssessmentSelection with exact proposal, selected reference or explicit absence, generation, selector. Preserve every generation and CAS order. |
| assessment-receipt:{principal}:{request_hash} | AssessmentReceipt(request digest, exact selection, optional envelope); no reconstructed selection may point to a different proposal/body. |
| cursor:{id} | Cursor(binding hash, offset); persisted offset binds frame, principal/query and scope hash. Never reuse after current visibility fails. |
| draft:{owner}:{continuity}:{version:020} | SavedDraft/version → typed DraftContent/frame/proposal binding/rationale and ordered DomainOperation rows. Raw-editor conversion may block; see compatibility.md. Owner/continuity stay bound by original key. |
| source:{digest} | `source_content` stores actual UTF-8 bytes, length and byte digest; reconstruct the old workflow string transiently to compare its separate workflow digest. |
| source-version:{record} | `source_staging` key/workflow digest + typed SourceVersion branch (includes discriminator). |
| image-asset:{record} | `image_staging` key/workflow digest + typed ImageAsset branch. |
| image-bytes:{digest}:{index} | `media_chunk` ordered actual bytes, size and historical workflow digest; reconstruct the current base64 staging string transiently for its original workflow digest checks. |
| continuity-name:{id} | `continuity_name` with exact string/key/workflow digest. |
| logical-import-origin | ImportOrigin(source digest, source/target universe, completeness/omissions). |
| logical-import-admission | ImportAdmission(preview, digest, target/name/completeness/omissions/imported). It is import evidence, not imported installation permissions. |

Original key format remains a compatibility lookup and integrity binding. New code may also address explicit columns, but must compare the same latest proposal/version, selection generation, head and authority sequence atomically. A scalar source-content key cannot be treated as a generic workflow body. Append-only workflow rows and associated body trees are published in one transaction; published immutable bodies/children must reject update/delete as well as their envelope. The concrete DDL installs immutable update/delete triggers on every typed body/collection table and the existing envelope/history tables. Query projections remain rebuildable.

## Installation, profile and import files

Source: `registry.rs`, `imports.rs`, `installation.rs` in protocol/client, and runtime's registration/restore paths.

| Persisted family | Target |
|---|---|
| settings | Typed scalar settings; normalization version unchanged. Unknown settings require a mapping, not arbitrary structured TEXT. |
| profiles | Preserve id/credential hash/author/revoked. No automatic enrollment or authority reissue. |
| catalog | Preserve universe/name/path/device/inode uniqueness. Path ownership is checked again against real target files at later cutover. |
| aliases | Preserve normalized selector keys and universe reservation. |
| grants.worlds | Explicit all/listed state and ordered grant_worlds rows. Null and empty list stay distinct. |
| grant_limits | Fold boolean/expiry/limit-state columns into grants; ordered entities/predicates/continuities child rows. Missing limits use the source's exact defaults; retain current delegation/shared/protected semantics. |
| purge_pending | Preserve pending universe/path/device/inode; do not purge merely by opening a normative migration target. |
| audit | Preserve actor/action/target and original monotonic sequence; this fences current grant ABA. |
| profiles/{profile}.json | Separate 0600 per-profile credential.sqlite: profile_id TEXT PRIMARY KEY, credential TEXT NOT NULL. Credential/hash stay identical; private installation only. Both client and service profile readers change together at implementation cutover. Synthetic proof uses no real secrets. |
| imports/{operation}.preview | ImportPreview typed installation row retains owner/source checksum/target/source/name/completeness/omissions/count, plus derived exact preview digest and staged path. |
| imports/{operation}.jsonl | Read-only legacy input; decode to fresh typed archive staging. Store original checksum, not its bytes as application metadata. Unknown/inconsistent content blocks. |
| private sockets, engine lock/PID markers, runtime in-flight tasks | OS/in-memory transport coordination; not exported domain data. Recover durable operation/job rows rather than persisting a new task serializer. |

## Backups, exports, auxiliary storage and legacy v0

Physical backups copy the complete typed package, including content bytes and workflow/receipts. There is no separate current backup manifest file: kernel backup verifies the SQLite copy itself. Normative archive manifests use fixed ArchiveManifest fields, typed tables and an explicit whole-export checksum; imports retain the original checksum. Logical v1 JSONL families `manifest`, `record`, `continuity`, `commit`, `change`, `reservation`, `text`, `image_chunk`, `checksum` map respectively to typed manifest/header, canonical version rows, kernel history, source_content/media_chunk and export integrity metadata. Old v1 excludes workflow and receipts; never claim their reconstruction from it.

The generic `BlobStore` uses digest-named source/media files with filesystem bytes and no JSON metadata; the service kernel embeds its source/media staging in workflow storage today. Retain verified referenced content bytes; do not add a blob payload store for application metadata. Package maintenance/purge summaries are transient responses, not durable document families. Release manifests/contracts/fixtures/build logs are software artifacts and test evidence, not author application data; the decision package's JSON oracles are similarly test inputs/results and are not copied into prototype authority tables.

Schema v0 has these additional/older families. They must be inventoried even though the current converter rejects nonempty ambiguous side tables:

| v0 tables | Typed normative destination and compatibility gate |
|---|---|
| schema_meta, universes, record_identities, record_versions | Single-model kernel headers and canonical bodies; unsupported scaffold bodies block conversion. Retain needed original scalar evidence in explicitly mapped provenance fields; retired software format tags are input metadata only. |
| worlds, world_name_reservations | Typed world canonical rows plus original scalar selector/reservation headers; no unreviewed identity remap. |
| commits, commit_changes, continuities, head_membership | Original typed historical ledger, including scalar timestamps/actions/legacy IDs; preserve baselines or block if not reconstructable. Do not use the existing legacy converter's generated replacement revision IDs for an identity-preserving conversion. |
| assertion_index, participant_index, time_index, fts_universes, fts_entities, fts_worlds, fts_sources | Rebuildable indexes only after verifying that no unique authored facts live solely in an index. Otherwise report the missing authority and block. |
| source_versions, anchors, blob_refs | Source/SourceVersion/Anchor typed canonical structures and preserved scalar legacy row IDs/timestamps/reference/digests; provenance insufficient to identify a canonical source blocks rather than invents it. |
| changesets, changeset_versions | Recognized proposal headers in the single model (id, universe, continuity, base revision, author, rationale, status, timestamps) + ordered DomainOperation/Assignment bodies; unknown old payload schema blocks. |
| approvals | Typed historical approval (id, changeset, version, digest, author, scope, granted/expires/revoked) + recognized exact proposal binding; never activates installation authority. |
| validation_runs, findings, dependencies | Typed validation headers, Finding outcomes/coverage and typed evidence references/derivations; unknown evidence encoding blocks. Preserve original IDs, rule/affected IDs and dependency links. |
| operation_receipts, idempotency_keys | Recognized receipt header in the single model and recognized result union; preserve principal/kind/key/digest/status/timestamps, nullable result and explicit key tombstone. Unsupported result encoding blocks. No retry key reuse. |

There is no parallel scaffold-era retention schema. These are retired input families mapped into the single normative model when their meaning is known. Unknown bodies or unmatched scalar evidence block conversion; retain originals rather than infer provenance or silently drop data.

## Operator conversion provenance

`import_workflow_digest` binds each recognized original workflow key and digest to
its normalized workflow digest, including draft operation normalization. It stores
no serialized body. Ordinary package integrity verifies its target and digest.
Explicit conversion, supported input layouts, refusals and publication recovery are
documented in [the operator procedure](../../operator-conversion-procedure.md).
