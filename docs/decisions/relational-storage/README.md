# Normative relational storage and definition resolution

October 3, 2026. Vanna's direction: replace the existing model; decisions revise the single normative model until release. Do not add parallel schemas, contract versions, old body routes or prerelease compatibility layers. This package specifies that replacement. Runtime cutover and production migration remain outside the original goal.

## Concrete storage

- [typed.sql](typed.sql): one closed model for all 38 canonical families, typed values, expressions, operations, workflow envelopes and assessment bodies.
- [kernel.sql](kernel.sql): stable identities, factual record revisions, commits, changes, continuities, reservations, receipts and row-based snapshots. Every canonical body uses one Payload route, with no schema-version or storage-layout discriminator.
- [semantic.sql](semantic.sql): definition, classification and attribute projections tied to canonical facts, explicit ambiguity evidence and initialization receipts.
- [workflow.sql](workflow.sql): typed envelope pointers, staging and actual source/media content; no opaque application payload fallback.
- [installation.sql](installation.sql), [credential.sql](credential.sql): separate installation authority and private credentials.
- [export.sql](export.sql): the same relational model in a trusted-schema archive, with content integrity and historical-evidence boundaries.
- [field-mapping.md](field-mapping.md), [catalog.json](catalog.json): concrete scalar columns, ordered children, references and closed branches.
- [inventory.md](inventory.md), [compatibility.md](compatibility.md): every source family, replacement mapping and preservation policy.

The generator consumes a snapshot of the existing source contracts solely as inventory, then replaces their type/classification/assertion shapes and removes contract-version tags. That snapshot is not an alternate active schema. Named values, references, scopes and expression nodes share fixed tables; scalar fields remain columns. Application data is never stored as a generic document, field-path/value store or serialized body. JSON fixtures support functional storage tests; the mapping catalog defines the codec.

## Definitions and instances

A type has stable universe-owned identity, namespace/key, name/labels, one nullable parent, explicit parent resolution and applicability. Root means no parent. Resolved means one parent. Ambiguous means unresolved candidates retained separately as evidence, with executable ancestry blocked. Resolve a parent identity through the requested continuity and factual revision, never the latest database row. Ancestry must be acyclic, same-universe and type-only. Admission checks these properties before publication; foreign keys alone do not establish them.

An instance has stable identity, one nullable classification and explicit resolved/unclassified/ambiguous status. Refinement to a descendant improves knowledge without creating identity or implying transformation. An unrelated correction requires an explicit authored factual change; physical transformation is a separately authored occurrence. Rename, holder transfer, context change and restart do not initialize state.

## Attributes and applicability

Assertions have an explicit `instance`, `shared` or `initial_value` attribute mode, retaining proposition, polarity, basis, scope, precision, validity and establishment evidence. Shared/initial attributes describe a type; instance attributes describe an entity. Composition, custody and location remain explicit relationships, never extra subtype parents.

At the requested universe, continuity, revision, world, context, time and perspective, resolve the instance and its single ancestry. Check applicability independently at every ancestor. Collect applicable definition facts/rules and instance facts separately, with exact evidence references. Preserve conflicts and unknowns; neither nearest subtype, newest fact nor instance specificity silently wins. Current permissions still restrict every result.

`universe_wide` is explicit. An empty world list applies nowhere. Unspecified or conditional applicability remains unresolved when relevant. Context, realm, clock and temporal bounds remain authored; an unknown end is not an unbounded end. A growth capability does not advance height. No evaluator extension or unauthored physics is introduced.

An initial-value definition is a candidate for an explicitly authored start, creating a separate instance assertion under the established reviewed-change authority. Its receipt binds the instance/start/property, source factual revision, assertion and admitting revision. Retry returns the same receipt. Rename/refinement/restart never refill a balance. Conflicting initial values block selection.

Definition edits use the existing factual-change and authority mechanisms, preserving past facts, evidence and prior verdicts. Historical record revisions are domain history, distinct from software contract versions. Before release, revising this design edits the normative schema and fixtures in place; Git records design history.
