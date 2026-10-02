# ADR-0005: durable packages and installation-owned engines

Date: 2026-09-24. Implemented under the user's authorization for milestones 3 and 4 (WP05/WP06). The fixture boundary in ADR-0004 remains available.

## Authority and storage

A schema-v1 SQLite file contains one universe. Immutable record identities/versions, commits, assignments, continuity descriptors, permanent world-name reservations, and operation receipts are authoritative. Foreign keys include universe, record identity/kind, and continuity where applicable. Genesis and changes publish in IMMEDIATE transactions; expected heads and prior versions prevent stale changes. Tombstones change membership without deleting retained versions. Branch genesis pins an exact source revision.

Historical reads replay immutable assignments, including branch baselines. Head membership, reference/typed/world/narrative projections, FTS5, and snapshot caches are disposable. Rebuilds create a new generation and publish it atomically. Readers never trust an incomplete cache. FTS candidate versions are intersected with the requested historical membership. Text indexing currently covers entity labels, world selectors/aliases, and work titles; it is not a complete WP09 research implementation.

Typed-value map keys are authored names and never suppress traversal of the values they contain. Snapshot reads and recovery validate effective dependencies, including payloads admitted by an older implementation. The kernel checks same-universe references, explicit namespaces on canonical RecordRef/VersionRef values, current dependencies, exact historical version identities, world kinds, and definition-family aliases. WorldId and RecordId share the same 24-hex identity body, following the existing definition-family remapping convention. Structural storage checks do not substitute for WP07 validation/approval or WP08 semantics.

Receipt keys bind principal, operation kind, idempotency key, canonical request digest, and committed revision in one transaction. Matching retries work after restart even when their old expected head is stale. Changed payloads cannot reuse a receipt key. This is an internal storage API; no client can call it to bypass approval. Persistent proposal/commit services remain unavailable until WP07.

Every database connection requires foreign keys, synchronous FULL, a two-second busy bound, patched SQLite >=3.51.3, and FTS5. Packages use WAL. Unsupported future versions are rejected before schema/journal changes. Empty legacy v0 scaffolds upgrade transactionally; populated or unversioned databases are preserved and require explicit conversion. There is no speculative migration of authored data.

Blob publication validates lowercase SHA-256 names, confines paths to a private directory, refuses symlinks/hardlinks, verifies bytes on read, fsyncs a unique staging file, publishes without replacing an existing digest, and syncs the directory. Concurrent duplicate publication is supported. Reachability-aware GC, backup, and logical import/export are WP10; no application GC command is exposed.

## Installation identity and ownership

Installation catalog, profile hashes, grants, aliases, and administrative audit records live outside universe packages. Versioned profile files contain random 256-bit credentials and are created with mode 0600 under mode-0700 directories. Secrets never appear in CLI output, Debug formatting, status, or doctor. A profile identifies a local principal, not a claimed client name. Author enrollment is a one-time local bootstrap; additional profiles are non-author. Peer UID checks and credential authentication both apply. A malicious process running as the same OS user remains outside the isolation guarantee: it can access that user's files.

Selector lookup trims surrounding whitespace, applies NFC/full default Unicode case folding/NFC, and preserves internal whitespace. The normalization policy is stored as `nfc-0.1.22-casefold-0.2.0-v1` with pinned crate versions; changing it requires an explicit catalog upgrade. Original display spelling is retained. Old aliases remain permanently bound to their original universe/world identity. No fuzzy or wildcard routing exists.

Bootstrap and service file locks coordinate cold starts. Each canonical package path has an OS-held sidecar writer lock. Symlinks and hardlinks are rejected, and the catalog records canonical path plus device/inode. The database itself is not flocked because that conflicts with SQLite locking on macOS. Locks explicitly unlock before descriptor close, preventing concurrent fork/exec inheritance from briefly retaining a released lock. PID metadata never grants ownership. A stale socket is removed only after acquiring the service lock and validating its type/owner.

Desktop, CLI, and MCP share the authenticated length-delimited protocol. Profiles and grants are checked for each call and before disclosure. World grants never expand to shared/global or protected writes. Revocation invalidates existing connections. Successful enrollment/grant/revocation/rename/catalog writes have durable installation audit entries; read failures are sanitized, without payload or credential logging.

The engine owns its lifetime. Closing the persistent desktop or adapter does not terminate it. Shutdown drains admitted work, joins universe threads, closes SQLite connections, and releases locks. An authenticated author may request maintenance shutdown; 15 minutes without clients also stops the engine. A later client safely starts it again. Caller timeout/drop abandons delivery, not an already admitted durable operation; clients mark interrupted connections unusable and never replay mutations automatically. Administrative creates are not idempotent APIs: after an uncertain outcome, inspect status before retrying.

## Bounds and later work

Limits: 32 connections overall, 8 connections/requests per principal, 24 non-author connections, 8 non-author blocking jobs plus 4 reserved author jobs, 16 queued reads per universe, and up to 32 opened universe workers. Recovery holds only the selected universe slot. Open/create/register admission reserves a capacity permit before touching a package; the worker retains it until shutdown. Failed opens remove unused slots after the last waiter. Catalog and worker publication remain under the same registry gate. Handshake/write deadlines are 5 seconds, client request deadline 15 seconds, idle connections 60 seconds. Frames retain the protocol's 1 MiB bound. Catalogs cap at 1,000 registered entries; a universe caps effective membership at 10,000, replay at 10,000 commits per branch and 64 ancestry levels, and rebuilds at 100,000 versions. Exceeding a bound fails explicitly; performance/scale acceptance is not claimed.

A failed create/catalog registration can leave an unregistered, complete genesis package in the installation packages directory; it cannot become visible canon through the catalog. Preserve it for inspection instead of deleting uncertain data. Doctor checks registered packages. Rich grant predicates/expiry, persisted long-running job cancellation, maintenance export/GC, and broader diagnostics belong with their corresponding WP07/WP09/WP10 workflows. Current grants cover universe/world scope and propose/edit/protected permissions.

The implementation and process-level tests cover rollback, SQLite FULL, abrupt process exit and restart, and atomic publication. They do not simulate physical power loss or prove filesystem/hardware durability. Clean-machine, offline, accessibility, distribution, and LM Studio acceptance remain separate.

## References

- [Rust file locking](https://doc.rust-lang.org/std/fs/struct.File.html#method.try_lock) documents the OS-backed lock interface used here.
- [Unicode case folding API](https://docs.rs/unicode-casefold/0.2.0/unicode_casefold/trait.UnicodeCaseFold.html) defines the pinned normalization component.
