# Replacement and preservation decisions

This unreleased application has one normative relational model. Replace the old persistence and definition contracts rather than keeping parallel old/new schemas, serializers or version-tagged body routes. Revisions to this model are normative immediately; do not introduce a compatibility layer for an earlier prerelease design. Any future release compatibility policy belongs to that release.

## History and integrity

Preserve universe, record, factual-version, continuity, revision, principal, proposal, operation, assessment and validation identities. Preserve commit ancestry/sequences, pinned baselines, change/tombstone history, reservations, receipt tuples, request keys, frozen assignments, proposal counters, selections and authority audit sequences. These describe authored events and concurrency, not software schema versions.

The single canonical payload digest recipe is SHA-256 of `kind:` plus canonical in-memory body bytes. There is no contract-version prefix. Workflow digests retain their defined canonical-byte recipe. Content digests bind actual source/media bytes. Exact numeric strings, units, references, Unicode keys, collection order and absent/null/empty distinctions remain represented by typed columns and child rows.

A historical input digest must never be passed off as a digest of a changed body. Verify the source under its declared input recipe before conversion; retain its original digest separately as import provenance (`import_record_digest`) alongside the normalized-body digest when normalization changes bytes. Keep exact receipts and their original input bindings as historical evidence. Do not mutate original evidence or regenerate authority. Conversion adapters may read known old inputs transiently; they are not alternate active body contracts. The prototype verifies the normative recipe, not all existing digest/conversion recipes.

## Classification conversion

| Existing source | Single-model result |
|---|---|
| No parents | Root, null parent. |
| One parent | Resolved parent identity. |
| Multiple parents | Ambiguous, null selected parent, ordered candidates retained in classification evidence. Block executable ancestry. |
| No memberships | Unclassified, null classification. |
| One membership | Resolved classification. |
| Multiple memberships, including a single chain | Ambiguous, null classification, all ordered candidates retained. Never silently choose the most specific. |
| Cyclic, cross-universe, wrong-kind or missing ancestry | Retain recoverable evidence; deny resolution with exact references. |
| Nonexecutable classification | Keep its flag and descriptive evidence; do not expand executable ancestry through it. |

An explicit authored resolution updates factual history through the existing protected-change path. It does not alter identity or initialize state. Old parent/membership vectors do not survive as an alternate canonical body model.

## Drafts and unknown inputs

Replace raw editor operation strings with ordered typed DomainOperation rows. Valid recognized source operations normalize into those rows. Preserve their original workflow digest as provenance if canonical representation changes. Invalid/incomplete drafts and unknown scaffold-era bodies cannot be converted by inventing facts, deleting them or hiding them in an opaque payload. Report the affected input and retain the original read-only source until the author chooses repair or omission. A partial target is not a complete backup.

The source inventory includes retired schemas and tables because actual author data must be accounted for. This does not require shipping those schemas indefinitely. Unsupported data blocks its conversion; it does not block revision of the unreleased normative model.

## Later operator conversion

Production migration remains excluded from this package. A later authorized conversion inventories actual files, verifies a consistent read-only source snapshot, populates a private target using the one normative schema, and independently checks identities, factual history, original digest provenance, normalized digests, exact receipts/bindings, content and authority. Unknown inputs or inconsistent evidence block publication. Test rollback/recovery and publish a completely verified target atomically. Keep needed originals for recovery; do not convert active author data automatically on startup.

## Exports and installation authority

Physical backups contain the complete typed package, including workflows, receipts, drafts and content. Installation authority and credentials remain separate. Logical archives use the same normative typed schema, populated into a fresh trusted target; never execute SQL supplied by an archive. Their manifest records completeness, omissions, history/workflow inclusion and checksum without a prerelease format-version tag.

Canon-only exports omit workflows; complete-history archives preserve their evidence without activating imported approvals or delegations. Registration, grants, revocation and current authority checks still come from the owning installation. Protected per-profile credentials retain their exact identity and secret, with coordinated client/service reader replacement; no regeneration or permission widening. The disposable proof uses synthetic installation data only.
