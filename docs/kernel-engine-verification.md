# Milestones 3–4: kernel and engine verification

Date: 2026-09-24. Working-tree evidence on macOS arm64, Rust 1.92.0. This increment followed the completed implementation repair of milestones 1–2. Their blocked/pending verifications were retained rather than used to defer WP05/WP06.

## Delivered

Milestone 3 adds schema-v1 immutable universe packages, genesis, pinned continuities, expected-head/version admission, atomic assignments and receipts, current/historical membership, rebuildable reference/typed/world/narrative/FTS projections, snapshot publication, namespace/kind constraints, retained name reservations, atomic empty-v0 upgrades, future-version rejection, and confined content-addressed blobs.

Milestone 4 adds installation-only credentials/catalog/grants/audit, authenticated principals, normalized exact aliases, author enrollment, writer ownership, coordinated process startup, bounded connections/work queues with reserved author capacity, stale endpoint recovery, idle/maintenance shutdown, status/doctor, CLI administration, and a persistent desktop status screen. Desktop and MCP use the same client boundary. The disposable fixture remains explicit and separate.

See [ADR-0005](adr/ADR-0005-durable-kernel-and-ownership.md) for authority, limits, failure behavior, and deferred capabilities. In particular, the internal kernel commit API is not exposed to clients. Application approval/commit is WP07, executable semantic coverage is WP08, and store-backed research is WP09. Persistent summary/capability discovery is implemented; unfinished tool modes return typed unsupported errors.

## Automated evidence

| Check | Result and scope |
|---|---|
| `cargo run --locked -p xtask -- check` | Pass: formatting, strict workspace/all-target Clippy, 144 tests, generated schema drift. |
| `xtask validate-contracts` | Pass: 26 schemas, 13 valid examples, 91 invalid examples through independent Python JSON Schema validation. |
| `xtask mcp-smoke` | Pass: original fixture research/proposal/error/retry/adapter-restart behavior and both negotiated MCP versions remain intact. |
| `scripts/installation_smoke.py` | Pass: six independent cold-starting CLI processes share one engine; real stdio MCP validates persistent describe output; current grants, retained rename aliases, forged/incompatible hello rejection, revocation, adapter disconnect survival, and stale endpoint recovery after SIGKILL. |
| Store tests | Pass: history after edits/restart, tombstones, pinned branches, exact/conflicting receipt checks, cross-universe rejection, cross-world associations, duplicate/reserved world names, identity/kind constraints, projection reconstruction/failure, snapshot rollback, path/link ownership rejection, atomic migration failure and empty-v0 upgrade, populated legacy preservation, future-version rejection. |
| Commit fault/process tests | Pass: all six prepublication hooks roll back; abrupt child-process exit at each stage recovers no partial canon; exit after publication retains the revision and matching receipt. SQLite's real SQLITE_FULL error rolls back the whole test transaction. These are not physical power-loss tests. |
| Blob tests | Pass: eight concurrent duplicate publications, digest validation, traversal/symlink refusal, no replacement of corrupt existing data, size bounds. |
| Authenticated socket tests | Pass: author and agent share one service; a claimed author client name grants no authority; unauthorized catalog is empty; current grants/aliases apply; active sessions fail after revocation; world grants cannot edit shared/protected/out-of-world records; eight idle agent connections leave author status available; missing packages remain visible as doctor errors. |
| `xtask package-fixture` | Pass: optimized desktop, engine, MCP, and CLI bundle; ad-hoc signature verification. Packaged SQLite is **3.53.2**, with FTS5, foreign keys, WAL, synchronous FULL, and schema version 1. |
| Both Python smoke scripts against packaged helpers | Pass from the bundle path containing spaces, including persistent cold start and SIGKILL recovery. No development binary or shell PATH is used to discover the engine. |

Test count: 36 domain, 10 protocol, 32 rules, 10 schema, 36 store, 5 fixture-client transport, 12 service integration, 3 service ownership/admission. The new persistent-client behavior is exercised through the service integration/process tests.

Commands use `DEVELOPER_DIR=/Library/Developer/CommandLineTools` on this machine and `UNIVERSE_PYTHON=/tmp/universe-contract-validation/bin/python` with `jsonschema==4.25.1`. `xtask installation-smoke` reproduces the persistent-process check; the GitHub workflow now includes it. Hosted CI has not been run here.

## Readiness follow-up for the next conditional request

Two milestone 3–4 failures were demonstrated against the preceding implementation: `metadata_field_names_cannot_hide_foreign_or_dangling_references` admitted a dangling reference under `metadata.text`, and `failed_recovery_does_not_exhaust_worker_capacity` could not open a healthy package after 32 failed opens. Both now pass.

Typed metadata/qualifier/structured-value field names no longer control reference traversal. Valid references under those names remain indexed across rebuild, dangling/foreign references fail without advancing the head, and ordinary labels/text resembling IDs stay prose. Snapshot reads and recovery reject previously stored dangling references even when their serialized payload and digest agree.

Workers hold an atomic capacity permit for their lifetime. Loading, creating, and registering reserve capacity before package work. Failed recovery removes an unused slot after the last waiter; concurrent successful opens share one worker. Four concurrent creates with one remaining slot produce exactly one package and three typed capacity errors. Registry publication stays gated until the worker is installed, avoiding a visible catalog entry whose writer has not yet been published.

Six new regression tests pass; the complete workspace has 144 tests. Strict checks, independent contracts, rebuilt ad-hoc package, and both packaged smoke suites pass after repair. These are implementation corrections, so this increment completed the first-four-milestone branch; it did not begin milestones 5–6. The original milestone 6 also includes WP10 sources/backup/restore and WP11 native author workflow, not just WP09 queries.

## Native and external verification boundary

The previous fixture-native evidence remains in [fixture verification](fixture-verification.md). The packaged fixture was observed again through the native accessibility tree in this increment. The persistent screen is compiled and connected through the same authenticated client, but **an actual concurrent native desktop/MCP session and native-window-close lifecycle check remain unverified**. The UI-control API cannot pass launch arguments, and its attempt to access Terminal was denied. No substitute UI automation was used. The temporary prepared installation's engine was shut down; no user installation was changed.

Socket tests use a desktop client and an MCP client, then drop the desktop connection and verify the same service remains. Process tests close a real MCP adapter and verify survival. These establish service/client lifetime behavior without claiming native GUI acceptance.

LM Studio remains **blocked by user choice**: Bionic must stay open. Its host configuration was not changed. Full VoiceOver, clean-machine/offline, scale/security, real power-loss, signing/notarization, and distribution acceptance remain pending. No authoring-alpha or release completion is claimed.

## Secret scanning and quality boundary

Files were scanned before reading. Final commands:

```sh
rg --files crates apps xtask docs scripts .github -0 | xargs -0 sonar analyze secrets
sonar analyze secrets IMPLEMENTATION_STATUS.md Universe_Builder_Full_Implementation_Plan_v0.4.md docs/kernel-engine-verification.md
sonar analyze secrets crates/universe-store/src/kernel.rs crates/universe-store/tests/kernel.rs crates/universe-service/src/runtime.rs
sonar analyze secrets IMPLEMENTATION_STATUS.md docs/kernel-engine-verification.md docs/adr/ADR-0005-durable-kernel-and-ownership.md
sonar list projects --query universe-builder-mcp
```

Scans reported no findings. The project lookup returned no matching project, so full server-backed Sonar analysis could not run. Secret scanning is not a full quality/security audit. `codealike.json` remains unread and untouched. Existing working-tree changes were preserved; no commit, branch, PR, host configuration, or distribution release was created.
