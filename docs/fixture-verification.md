# Feasibility verification — 2026-09-24

Evidence applies to the local working tree on macOS arm64, Rust 1.92.0. It is not a release certificate. This increment implements the approved baseline/contracts/fixture work, preserving existing workspace changes.

## Automated checks

| Check | Result |
|---|---|
| `cargo run --locked -p xtask -- check` | Passed: format, workspace/all-target Clippy with `-D warnings`, 120 tests, generated-schema drift. |
| `cargo run --locked -p xtask -- validate-contracts` | Passed: 26 Draft 2020-12 schemas, 13 valid examples, 91 invalid examples. |
| `cargo run --locked -p xtask -- mcp-smoke` | Passed against independent Python stdio client with a restricted PATH. All 13 tools listed; missing universe rejected for all; known fixture read, omitted-world scope, cross-universe rejection, Unicode proposal, idempotency, receipt lookup, commit denial, text/structured parity, output-schema validation. |
| Replaced MCP adapter, retained fixture engine | Receipt recovered by idempotency key; same proposal returned when retried using a new context handle for the same frame. This does not prove durability across engine restart. |
| MCP lifecycle | Requested/negotiated `2025-11-25`; separate `2024-11-05` lifecycle and describe read passed. Host/model tool selection remains a separate test. |
| `cargo run --locked -p xtask -- package-fixture` | Built optimized desktop/engine/MCP bundle and verified ad-hoc signatures. Not notarized. |
| Packaged helpers relocated to a temporary path containing spaces and `café` | The full independent MCP smoke passed, including adapter replacement and both protocol lifecycles. |

Run Cargo with `DEVELOPER_DIR=/Library/Developer/CommandLineTools` on this machine. Independent scripts used `UNIVERSE_PYTHON=/tmp/universe-contract-validation/bin/python`, with `jsonschema==4.25.1`. Dependencies are pinned by Cargo.lock and the workflow's Python version/dependency command. The new GitHub workflow has not been executed remotely.

Transport tests exercise a stalled handshake, incompatible handshake without retry, out-of-order responses without EOF, timeout cancellation/pending cleanup, oversized inbound framing, and 32 concurrent calls through a 16-request bound. Contract tests reject unknown/duplicate keys, invalid IDs, explicit null selectors, forbidden world overrides, and deeply nested JSON. Rule tests include the complete pairwise four-valued Boolean truth table and unsupported/descriptive coverage regression checks.

The generated catalog is 2,028,673 bytes as checked-in formatted JSON; compact JSON is 997,344 bytes. This size is a feasibility cost to address before broad model use. LM Studio catalog token overhead and tool-template behavior have not been measured.

## Follow-up implementation audit

The next-milestone readiness audit identified and repaired substantive defects in the first two milestones. The four regression cases were run against the previous implementation and failed before repair:

- A second mutation based on stale proposal version 1 could overwrite version 2; old versions could also be used to revive a withdrawn proposal. Mutations now require the latest nonwithdrawn exact binding; old reads and exact retries remain valid.
- At 256 receipts, the admission limit ran before the retry lookup. Exact retries and receipt recovery now work at capacity, while new proposals remain bounded.
- A selected world did not constrain proposed writes. The fixture now checks explicit entity/work associations and supported existing-record footprints, rejects shared/out-of-world effects, and reports unsupported for footprints it cannot prove.
- Unqualified WorldIds could refer to another universe or an unknown world. Typed association/applicability references now resolve within the fixture universe.

The same audit found that receipt hashing used a parser preserving object insertion order. It now uses the canonical serializer, with world selection normalized to its resolved ID and consistency guards excluded. A matching optional ID guard no longer changes retry identity. The independent MCP client exercises this behavior and stale-version rejection.

The private and MCP wire decoder now accepts standard JSON Unicode escapes (including surrogate pairs), while still rejecting escaped duplicate keys, malformed JSON, invalid UTF-8, oversized frames, and excessive nesting. The independent client deliberately sends Python's default ASCII-escaped JSON. Payload digests no longer route through the restrictive canonical-input parser. Unsupported get/history/evidence view requests now return typed unsupported errors. Handshake and overload responses have bounded write deadlines.

The final follow-up checks passed: strict workspace check, independent schema validation, independent MCP smoke, optimized bundle/ad-hoc signature verification, and the MCP smoke against the rebuilt packaged helpers. Native UI behavior was not re-exercised in this follow-up; the earlier native evidence below remains separate.

The complete workspace has 120 tests (36 domain, 10 protocol, 32 rules, 10 schema, 17 store, 5 client, 10 service). Storage tests retain their limited scaffold scope; no WP05 or WP06 completion is implied by this audit.

## Native evidence

The local packaged app was launched from `target/fixture/Universe Builder Fixture.app`, using its bundled engine and embedded assets. Observed through the macOS accessibility tree and screenshot:

- Named universe and world selectors, labeled text fields, semantic table, disabled review before a context exists, and accessible modal controls.
- The Ashen Cycle loaded Aster, Nacre, Mara, a multiworld work, and an unassigned record. Explicit Nacre focus retained the shared records. Switching to The Glass Archive cleared the world focus and loaded its distinct Aster/Iven records.
- Unicode text `Lantern café — 雨` survived paste, review, and proposal creation. Status reported a noncanonical proposal ID with no approval or commit; canon records remained unchanged.
- Review moved focus into the modal; Escape returned focus to Review proposal. Keyboard Tab/Return saved the proposal.
- The native file chooser opened and was cancelled without importing data. A misleading cancel status and save-focus timing issue were found, corrected, and verified in the rebuilt package: cancellation reported no source selected, and saving returned focus to Review proposal. Filtering by Mara left only its record visible.
- Closing the app removed both desktop and fixture-engine processes; the helper is tied to the parent stdin pipe as well as orderly shutdown.

Accessibility-tree and keyboard evidence is **not** a completed VoiceOver audit. Full VoiceOver speech/navigation, clipboard round-trip, clean-machine installation, network-disabled operation, signing/notarization, and production-engine lifecycle remain unverified. No remote asset or development server is required by the fixture implementation, but this machine was not disconnected from the network during testing.

## LM Studio — blocked by user choice

The installed LM Studio startup screen reported that it cannot run while Bionic is open. The user explicitly instructed: “Keep Bionic open; record the LM Studio desktop check as blocked.” Bionic was left running. No LM Studio MCP configuration was modified, and no LM Studio desktop/model integration success is claimed. Independent stdio client success does not close this host gate.

To close it later, run the fixture engine, generate configuration with `xtask mcp-config`, configure the host, and demonstrate the same known read, typed error, and noncanonical proposal from that host. Record the actual negotiated protocol, model, host version, exposed tools, and structured/text behavior.

## Secret scanning and analysis boundaries

Workspace files were scanned before reading with `sonar analyze secrets <path>`. Bulk source scans used:

```sh
rg --files crates apps xtask scripts .github contracts fixtures -0 | xargs -0 sonar analyze secrets
sonar analyze secrets IMPLEMENTATION_STATUS.md README.md docs/adr/ADR-0004-fixture-contracts.md
sonar list projects --query universe-builder-mcp
```

Secret scans reported no findings in the scanned files. `codealike.json` was left untouched and unread. The project lookup returned no matching SonarQube project, so server-backed quality analysis is unavailable; secrets scanning is not evidence of a full quality/security review.

## Subsequent milestone work

Milestones 3–4 now add a durable kernel and persistent authenticated engine alongside this fixture. See [kernel/engine evidence](kernel-engine-verification.md) for current checks; the 120-test count and limited store scope above describe the preceding fixture audit. Persistent canonical proposal/approval/commit, store-backed research, full semantic evaluation, imports/exports, and broad authoring UI remain later work. Silver-gate S01–S10 remain explicitly unsupported acceptance targets.
