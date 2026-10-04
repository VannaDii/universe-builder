# Relational storage and definition-resolution decision package

October 3, 2026. **Proposed; ready for Vanna's review, not approved.** Source baseline: `56f7b6b6e9a770c6c2dd1fc5f938f2b6e63f1b73`. This is step A of [the factual-universe realignment plan](../../factual-universe-realignment-plan.md). No application storage path, migration registration, public tool, evaluator or production data is changed.

## Recommendation and review surface

Keep the existing transaction kernel and installation/package separation. Replace serialized authority with closed typed rows. Keep old versions in their original semantic contracts; introduce explicit v3 definition/instance/attribute contracts for new authored facts. Resolve a single-parent ancestry at a pinned revision, keeping instance facts separate from shared definition facts. Preserve unresolved legacy classification as evidence and block its executable resolution until an author supplies an explicit new revision.

The proposed physical schema is executable SQLite DDL:

- [typed.sql](typed.sql): all current canonical families, values, expression trees, operation variants, workflow envelopes, assessment bodies, plus proposed v3 types, instances and attributes.
- [kernel.sql](kernel.sql): preserved identities, commits, changes, continuities, reservations, head membership, receipts; typed payload routing and snapshot rows.
- [workflow.sql](workflow.sql): closed workflow-envelope pointers, content rows and staging metadata. No generic document/payload fallback.
- [semantic.sql](semantic.sql): revision-bound semantic query projections, preserved legacy classifications and initialization receipts. Projections are rebuilt from typed canonical rows; they never replace those rows as authority.
- [installation.sql](installation.sql) and [credential.sql](credential.sql): grants, explicit limit states, audit, catalog/import previews and separately protected profile credentials.
- [export.sql](export.sql): typed archive manifest/checksum and explicit historical-evidence authority state.
- [field-mapping.md](field-mapping.md): every field, union branch and collection link, including named metadata values, rule nodes, requirements and effect slots. [catalog.json](catalog.json) is the machine-readable *schema specification*, not persisted application data.
- [inventory.md](inventory.md) and [compatibility.md](compatibility.md): complete source-family mapping, authority/export boundaries, historical reconstruction and explicit incompatibility decisions.
- [verification.md](verification.md), [proof-results.json](proof-results.json), [semantic-oracle.json](semantic-oracle.json): executed evidence and limits.

The full contract needs many explicit rows because supported rules, values, source assessments and operation bodies contain closed variants and ordered children. Scalars are columns, not individual tables. Common named domain structures such as `Value`, `Expr`, `RecordRef`, `Scope`, `Validity` and `Frame` are shared. Inline contract structures receive fixed tables; no path/value document store is authoritative. This conservative proposal favors auditable mappings over a compact but incomplete illustration. Collapsing physically identical collection tables later is optional, with equivalence proof; it is not needed to approve the semantics.

## Single-parent definitions and stable instances

A type has universe-owned identity, namespace/key, author-facing name/labels, one nullable parent, explicit applicability and the existing executable-classification flag. Its parent refers to a type identity, resolved through the requested continuity/revision membership, not the latest database version. The same type can have different historical revisions or branch definitions without changing its ID. A parent chain must be acyclic, entirely in the owning universe, and resolve to type records. SQL foreign keys preserve identity; admission checks kind, ancestry cycles and revision membership in the transaction before publishing. A definition with no parent is a root, not an inferred type of everything.

An instance has one nullable classification and stable identity. Null is unclassified. Refinement is allowed when the proposed type is a descendant of the established classification at the candidate revision; it records improved knowledge, not physical change. Sibling or unrelated reclassification requires an explicit author decision explaining the correction. A transformation requires an authored occurrence/factual change and remains distinct. Renaming, references, context changes, holder transfers and restarts never create identity or initialize state.

The v3 `TypeDefinitionV3`, `InstanceV3` and `AttributeAssertionV3` contracts in the generator are proposed additions. New records carry an explicit `v3` schema header and route to one corresponding typed body. Other existing families retain their existing contract and header. Legacy typed bodies reconstruct the old `parents`/`types` lists exactly, even when new resolution is blocked. New and historical views must not be confused.

## Attributes, applicability and effective descriptions

Named attributes use existing property identities and their typed shapes. A proposition identifies the property, subject identity, value, roles, quantification and represented context. An assertion retains polarity, basis, scope, precision, validity, alternatives and establishment evidence. V3 adds an explicit mode: `instance`, `shared`, or `initial_value`. A shared/initial attribute has a type subject; an instance attribute has an entity subject. Relation definitions and roles continue to express custody, containment, location and composition; none creates subtype ancestry.

An effective description at `(universe, continuity, revision, world, context, time, perspective)` follows these steps:

1. Resolve the stable instance and classification at that exact membership. Return unclassified or legacy ambiguity explicitly.
2. Walk its single ancestry through the same membership. Check each definition's applicability independently. A child does not widen its parent's jurisdiction. Unknown/conditional applicability stays unresolved; it does not become universal.
3. Collect applicable type attributes/rules along that chain with exact assertion/version/basis references. Collect instance evidence separately. Preserve positive, negative, uncertain and conflicting evidence. Never give a nearest subtype, instance fact or latest version automatic precedence.
4. Use the existing chronology and supported temporal/persistence semantics for instance state. A growth capability is not a height transition. An initial-value attribute is a candidate for an explicit reviewed start change, never current state or a refill. No rule/effect evaluation is added here.
5. Return separate definition attributes, instance facts/state, applicable rules/requirements, provenance, conflicts and relevant unknowns. Respect current grants and dependency visibility before revealing any row.

`universe_wide` is explicit author scope. `worlds` uses ordered world-ID rows; an empty list applies nowhere. `unspecified` and `conditional` return unresolved when their relevance matters. Represented context, realm, clock and temporal bounds remain explicit; an unknown end is not an unbounded end. World associations describe associations rather than implicitly authorizing all facts in that world. Existing descriptive rules and policies are retained; this proposal supplies targeting/resolution, not new evaluator semantics.

For single-valued attributes, opposing polarity or multiple supported incompatible values are conflicts. A shared capability and an instance observation remain separate claims. An instance-specific constraint does not silently cancel an inherited constraint. Author resolution uses existing protected changes or explicit exceptions; the resolver does not invent override precedence. Missing required facts remain unknown.

An initial value produces a separate instance assertion only in an explicitly authored start proposal, under normal reviewed changes and authority. Its receipt binds instance/start event/property, source definition version, created assertion and admitting revision. Retrying that start returns the same receipt; refinement, renaming and holder changes do not repeat it. Distinct restart of an object must be an explicit authored event, not service restart. Conflicting initial definitions block selection rather than choosing a winner.

Definition changes use normal expected-version checks and protected authority. Impact includes descendant classifications, affected attributes/rules and dependent facts/events at the candidate revision. Existing facts and prior verdicts remain historical evidence; unsupported revalidation is reported rather than certified. No separate state ledger or simulator is introduced.

## Material tradeoffs and decisions requested

This replaces convenient serialization with more mapping code, explicit ownership/link validation and a verified file-format transition. Historical semantic and serialization contracts must remain available indefinitely for retained versions. One-parent resolution deliberately exposes legacy ambiguity instead of preserving multiple-inheritance execution. Installation configuration and client profile loading need a coordinated later cutover.

The review decisions are the typed-row format and v3 contract additions; explicit ambiguity handling with no automatic choice; scope/conflict behavior with no override precedence; typed draft conversion/blocking policy; and the backup/export authority boundary. The draft blocker and unsupported scaffold-era payloads are explicit compatibility outcomes, not silent deletion. Production migration, evaluator extensions, implementation acceptance and approval of this proposal are excluded.
