# Normalized foundation verification

October 3, 2026. Implementation in progress. The normative decision is
[the relational storage package](decisions/relational-storage/README.md).
Vanna's direction in **Define relational storage decisions** was: “rip it all
out and replace it with this model” and “Until we release a version everything
we decide is normative.”

## Typed body codec checkpoint

`crates/universe-store/src/relational.rs` implements the approved physical
catalog in Rust. It stores fixed scalar columns, explicit branch pointers,
ordered collections and named map children. The catalog is embedded software
metadata; it is not persisted application data. Numeric scalars use decimal
text; exact authored numeric digit strings remain unchanged. Missing fields
and explicit null have separate states. Inserts require an existing SQLite
transaction and never commit independently.

Executed checks:

- `cargo test -p universe-store --locked`: 54 tests passed, including four new
  relational codec tests.
- `cargo fmt --all -- --check` and `git diff --check`: passed.
- Rust writes 72 frozen body fixtures and 50 frozen Cedar/Pistol factual
  versions to a disposable database. After closing and reopening SQLite,
  Rust reconstructs every body and verifies canonical bytes and its frozen
  normative digest. The separately implemented Python reader reconstructs
  the same 122 roots directly from SQL and independently computes all hashes.
- Exact digit strings, uint64 magnitude, Unicode, collection order and
  duplicates, named structured values, and absent/null distinctions survive.
- Malformed reference shapes and unknown fields fail before insertion;
  physical child pointers obey foreign keys. Dropped transactions leave no
  body or child rows. Immutable-row mutations fail. Readback rejects ordinal
  gaps and cyclic collection pointers.

These are codec proofs. They do not establish kernel publication, continuity
resolution, domain reference admission, or process-interruption recovery for
the new format. Existing kernel regression tests still exercise the current
serialized storage. The private codec is not yet called by runtime storage;
the build consequently reports dead-code warnings until integration.

## Remaining goal gates

| Requirement | Current evidence |
|---|---|
| Normative definitions/instances/attribute domain contracts | Decision specified; runtime domain alignment pending. |
| Typed value/reference/scope/time and record body storage | Rust codec and independent disposable SQL reconstruction pass. |
| Existing kernel transactional reads/writes | Integration pending. |
| Names, classifications, attributes and evidence | Frozen bodies reconstruct; kernel-owned factual records pending. |
| Historical identities, selected revision and digests after restart | Frozen body digests pass; package-level history/restart pending. |
| Invalid references preserve integrity | Shape/physical pointer checks pass; snapshot-aware namespace/kind/version checks pending. |
| Interrupted publication preserves head, membership and receipts | New-format kernel fault and process-exit tests pending. |
| Conventional commits and actual working time | Report at checkpoints and completion; full objective remains active. |

Unsupported-family qualification, live migration, workflow/installation
conversion, and declaring the whole persistence conversion complete remain
outside this goal.
