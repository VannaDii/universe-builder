# Compatibility and migration decisions

These are proposed decisions for review. The goal delivers a mapping and proof package, not an operator cutover or certification that every unknown legacy package can convert.

## Historical identities and serialization

Preserve universe, record, version, continuity, revision, principal, proposal, operation, assessment and validation identities byte-for-byte for same-universe conversion. Preserve commit parents/sequences, pinned baselines, changes/prior versions/tombstones, reservations, receipts, idempotency keys, proposal versions, frozen generated assignments and selection generations. Store old schema tags and digests as given; a mismatching reconstruction blocks conversion. Do not build new historical versions or rehash a mismatch into success.

Each historical body routes to typed rows governed by its original contract. Fields retain absent / explicit null / value state, separate from empty collection headers. Arrays preserve ordinal order; named maps preserve exact Unicode keys and values. Set ordering follows the historical serializer, not SQL insertion order. Integer/decimal/rational digit strings remain TEXT with exact authored precision; units and clocks retain stable identities. No SQLite REAL conversion is permitted. Unsigned workflow counters use decimal text because u64 exceeds SQLite signed INTEGER; compare bounded parsed integers, never lexicographic text.

Current payload digests use **`kind:v1:v1:` + canonical payload bytes**, including when the payload header requires v2 (`NoOpposingEvidence`). The first v1 comes from `RecordKind::discriminator()` and the second from `payload_digest()`. Preserve that actual recipe; do not substitute the header schema. Workflow digests hash sorted canonical serde bytes without that prefix. Assessment/body/execution/binding digests retain their separate domain prefixes and existing recipes from assessment.rs. Commit and projection/snapshot checksums retain their current formulas. Source/media digests hash actual bytes; workflow digests of source strings and image hex strings remain reconstructable transiently from those bytes.

The proposed v3 payload recipe is explicitly `kind:v3:v3:` plus canonical v3 body (including record_kind). It is demonstrated only in the disposable prototype. Adopting it requires Vanna's decision; no current encoder or admission path was changed. The physical `storage_layout` is separate from semantic schema version. Preserve supported historical omitted defaults instead of letting a new serde derive silently add fields.

## Legacy classification matrix

| Existing data | Retention and proposed effective resolution |
|---|---|
| Zero type parents | Preserve omitted versus empty historical list; new effective root has null parent. |
| One parent | Preserve historical list and order; resolved one-parent projection names that identity. |
| Multiple parents | Preserve every ordered parent in historical body and legacy rows; classify lineage as ambiguous and block executable ancestry. Never select the first parent. |
| Zero instance memberships | Preserve empty historical list; effective instance remains unclassified. |
| One membership | Preserve historical list; resolved classification names that identity. |
| Multiple memberships on one chain | Preserve all; report potential most-specific candidate, but require an explicit author resolution rather than silently discarding memberships. |
| Multiple unrelated memberships | Preserve all; report ambiguity, require author correction or explicit relation-based modeling. No synthetic intersection subtype. |
| Cyclic/cross-universe/wrong-kind or unavailable ancestry | Preserve recoverable historical evidence; block executable resolution and report exact references. A valid historical read does not certify a new use. |
| classificationExecutable=false | Preserve flag; descriptive lineage can be shown with provenance, but do not expand executable ancestry through it. |
| Previously single parent changed on a branch | Resolve the branch's revision, never mutate historical definition/ancestry. |

An author's resolution creates a new immutable version, with protected authority and impact review. It changes neither old IDs/digests nor historical memberships. It does not introduce ammunition, change size or imply a transformation.

## Raw editor drafts and unsupported scaffold data

Current `DraftContent.operations` is a string containing potentially invalid/incomplete JSON. The proposed target stores ordered `DomainOperation` rows, with typed draft frame/proposal binding and rationale. This is an intentional contract change, not a claim that the string was already typed.

A draft can convert only if its operations decode under a supported closed contract **and** its old string/digest can be reconstructed exactly under a recognized old editor encoding recipe. The initial implementation should recognize only explicitly tested encoding recipes, such as the actual current editor's pretty serialization; add a recipe only after an exact independent byte comparison. The package does not implement or certify those recipes. Invalid, incomplete, custom-formatted or otherwise nonreconstructable drafts block whole-package conversion. Retain the original read-only package; present the specific affected draft to Vanna for repair, export as user source under an explicitly approved exception, or a separately authorized omission policy. No timeout, automatic repair, opaque text/binary payload or generic token tree is a substitute for that decision. Do not claim that a partial target is a complete backup.

Schema-v0 side-table source/workflow/evidence data currently has no supported modern lossless interpretation; the existing converter rejects it. The proposed mapping lists its typed destinations, but importing an unknown old body requires its actual declared format and exact reconstruction test. Unknown fields, duplicate keys, unsupported schemas, references or digest mismatches block conversion and preserve originals. No current authority is inferred from legacy approvals or old receipt results. Known record/commit IDs that use historical prefixes remain historical IDs; an explicit mapping table is needed if a future active contract rejects them, with author review, never an unreported ID replacement.

## Conversion and recovery sequence after approval

1. Inventory actual package/configuration formats under their owning installation. Open legacy inputs read-only, pin a consistent snapshot, verify integrity/digests and record immutable source checksums. No startup conversion.
2. Create a separate private target with foreign keys and deferred commit/continuity cycles. Populate identities, typed historical bodies, commits/changes, workflow children, source/media bytes and snapshot members in bounded transactions. Reject unknown families/keys and orphaned links; report classification/draft blockers before publication.
3. Reconstruct all canonical/workflow bodies transiently. Compare original identities, versions, digests, exact receipt results/bindings, branch membership, snapshots, selection history, retained content and installation authority. Verify current query projections against replayed history. Preserve original counters/audit sequences so authority ABA remains fenced.
4. Exercise interrupted writes, fault rollback, stale head/proposal/selection/authority checks, retry, backup/readback and restore. These are later implementation gates, not all proven by this prototype.
5. Publish only a completely verified target using the existing private-path ownership, sync and atomic switch discipline under operator authorization. Retain needed originals and a verified recovery path. Coordinate profile-reader changes; no credential regeneration or permission widening.

## Exports, backups and authority

A physical backup is a complete SQLite snapshot of the typed package, including workflows, receipts, drafts, sources and media. It does not contain the separate installation database or credentials. Restore verifies schema, content/digests, history and receipts; it binds the recovered package to the installation through current author registration and current grants.

The proposed logical format is a fresh schema-constrained SQLite archive, populated into a fresh trusted schema on import (never execute input SQL). A manifest stores format, source universe/name, completeness/omission count, history/workflow inclusion and export digest. Canonical/history tables are the same typed tables; source/media bytes are content. Canon-only exports exclude workflows and installation authority, as the current logical format does. Complete-history archives may retain workflow and receipt evidence as explicitly marked historical data; installation approvals/delegations are never activated by importing them. A clone maps the universe namespace explicitly, creates new content digests where references changed, retains original IDs/digests in an origin mapping and starts fresh active retry authority. A same-universe restore preserves original IDs/digests. A filtered export cannot restore as the original universe; reference closure, appearances, definitions and policies remain included.

Old JSONL archives and profile JSON files remain read-only migration inputs. Their checksums can be recorded in typed import-origin/preview rows; their bodies are not copied as new application metadata. Legacy receipts excluded by old logical export cannot be recreated from that archive: report them as unavailable. A physical backup is required when exact workflow/receipt recovery matters. New export checksums do not pretend to equal old byte-format checksums.
