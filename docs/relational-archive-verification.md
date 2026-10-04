# Goal 26 — Relational archive and trusted restoration verification

Executed October 4, 2026 (America/Los_Angeles), using disposable packages and authenticated local services. This replaces the application’s JSONL archive reader/writer and JSON preview files with the normative relational model. Existing author installations were not converted or restored.

## Implemented behavior

An archive is a standalone SQLite database created from the checked-in typed, kernel, semantic and workflow schemas, with `r_archive_manifest` and `archive_integrity`. Its format is `universe-relational`, without a prerelease version tag. Source and media BLOBs contain actual bytes; application metadata remains typed columns and child rows. Test oracle files and wire JSON are transient/reference data, not an alternate application archive format.

The approved `typed-row-stream` checksum binds ordered table names, columns and typed cells. A separate checksum binds the canonical manifest; the import/preview digest binds both checksums. Manifest inclusion and omission declarations therefore participate in exact preview acceptance. Schema comparison uses the locally installed trusted schema. Input DDL, triggers and views are never installed or executed for restoration. Validated rows copy into a fresh trusted database in a transaction with deferred foreign keys; projections rebuild from canonical records.

`export_logical` and the default CLI/UI export create canon-only archives. They retain all factual revisions, continuity baselines, changes/tombstones, world reservations, included record identities/versions, source anchors, exact required source/media content, continuity names and existing original-digest provenance. Workflows and operation receipts are omitted. Selected-record exports close over dependencies across every historical version and explicitly declare omitted canonical identities; restoration requires a named clone when omissions exist.

`export_relational(..., true)` and CLI `--complete-history` preserve workflows, drafts, assessments, original receipt tuples, original digest bindings, and staged/uncommitted source and media content as well as canonical history. Complete-history exports require all records. Clone imports remap canonical universe references and retain original workflow references/bindings as written. Changed canonical digests retain their original source digest in `import_record_digest`; its normalized digest must match the stored canonical body.

Imported workflow evidence remains independently readable. Imported approvals, operations, contexts and cursors are excluded from active lookups, and imported operation receipts cannot satisfy a current commit retry. Proposals remain reviewable under current installation authority. A fresh author approval is required where current delegation does not authorize publication; grants, revocation, credentials and current delegation always come from the owning installation. Reusing an imported approval key requires a fresh validation run rather than silently activating its historical entry.

Previews persist as typed `installation.sqlite.import_preview` rows, including owner, source digest, target identity, completeness, workflow inclusion, record count, exact preview digest and staged path. The staged archive remains a protected `.sqlite` file. Acceptance re-reads and validates the archive and checks its exact binding before publishing a no-clobber package. Failed registration removes only the package created by that failed attempt. Physical restoration follows the same trusted-schema copying and historical-authority boundary.

## Executed proofs

| Proof | Evidence |
|---|---|
| Independent archive inspection | `scripts/inspect_relational_archive.py` independently reconstructs all canonical bodies and workflow/content entries using direct SQLite reads and the independent decision-package decoder. It verifies both checksums, absence of installation authority, and exact comparison to a separately backed-up original package: identities, revisions, continuities, changes, reservations, receipts, digest provenance, continuity names and raw source/media bytes. Real-client workflow and media integration tests invoke it. |
| Canon-only export/import/restart | Authenticated service preview/accept/retry, exact UTF-8 source and anchor retrieval, historical reads, dependency-closed filtered clones, declared omissions and rejection of filtered original-identity restoration. Maintenance preserves the same deterministic canon-only archive. |
| Complete-history reconstruction | Same-universe trusted restoration and restart compare every original workflow/content entry. Authenticated complete-history clone preview/accept/retry and service restart retain content, permit historical proposal review, and reject publication using imported approval evidence. |
| Content preservation and omissions | Multi-chunk original images survive removal of their source files, historical appearance changes, canon-only clone, complete-history restore/clone and restart. Complete-history archives also preserve additional uncommitted UTF-8 text and a second staged image exactly; canon-only archives omit those staged assets. |
| Branches, tombstones and provenance | Both archive modes restore/clone/restart a pinned branch and its baseline while retaining the main continuity’s tombstone and original source-digest evidence. Remapped source/anchor bodies retain original digests separately from their current normalized digests. |
| Tampering and malformed references | Reject changed row checksums, changed manifest flags, foreign-key references to missing versions, a correctly rehashed canonical body containing a dangling semantic reference, missing source content, and missing image chunks even after independent checksum regeneration. |
| Hostile schema | Reject added hostile triggers and views before row copying. Damaged input bytes and existing destination bytes remain unchanged. |
| Interrupted restoration | Inject failure during row copying and after verification. Abruptly terminate a separate restoration process during copying; the original backup and existing destination remain byte-for-byte unchanged, and a subsequent restoration succeeds. Private incomplete staging never becomes a registered package. |
| Failed reviewed import | Corrupt the exact staged archive after preview, then inject registration failure after verified publication. Both failures leave the catalog unchanged and create no destination package; the registration failure also removes its owned lock file. Restoring the original staged archive permits the exact preview to succeed. |
| Scale recovery | The 10,050-record fixture passes relational input/admission, historical reconstruction, physical backup/restoration and restart comparisons. |

The independent inspector’s failure fixtures deliberately recompute checksums to separate envelope integrity from domain/reference/content validation. These fixtures use synthetic data only.

## Checks and scope

- `cargo test --locked --workspace -- --test-threads=2`: 345 passed; the opt-in standard workload remained ignored.
- `cargo clippy --locked --workspace --all-targets -- -D warnings`
- `cargo fmt --all -- --check`
- `UNIVERSE_PYTHON=/tmp/universe-goal26-contract-env/bin/python cargo run --locked -p xtask -- validate-contracts` (disposable environment with the repository-pinned `jsonschema==4.25.1`).
- `git diff --check`

The workspace run uses two test threads to avoid saturating the local service’s fixed request deadline with many simultaneous disposable-schema installations. Explicit concurrency and abrupt-exit tests still execute their own parallel/process scenarios. The Python consequence checker was repaired to select the existing frozen normative shape oracle while continuing to verify the unchanged original byte/hash vectors and both digest recipes independently. An earlier fully parallel run exposed deadline contention and recovery regressions; the recovery regressions were repaired without changing their missing-material or fresh-author-approval requirements.

Logical archives retain the existing 512 MiB and two-million-row bounds, now counted over typed SQLite rows; physical files retain the 8 GiB bound. Historical replay remains bounded to ten million memberships. Limit failures preserve originals and never publish partial archives. The opt-in 412,002-record standard workload was not run; this proof does not claim that scale or interactive latency. Native window interaction, physical-machine recovery, production/operator conversion and off-device backup acceptance remain outside this goal.
