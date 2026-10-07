# Milestones 5–6: implementation and verification

Baseline evidence from the first-six-milestone increment on 2026-09-24. The subsequent conditional audit proceeded to milestones 7–8; see [current semantic/release evidence](semantic-release-verification.md) for the Timeline, event effects, jobs, continuities, packs and new checks.

## Implemented behavior

- **Proposal authority:** immutable versions and reserved new-record IDs; exact revisions, digests, validation and author approval; full world/shared/protected footprints; fresh grants at atomic publication. Changed proposals and stale approvals cannot publish. Receipts recover successful commits without replaying them. A submitted desktop draft persists its proposal reference, so editing after restart revises the same proposal and reservations.
- **Basic evaluation:** four-valued evidence, explicit refutations, finite collections/cardinality/quantifiers, exact bounded arithmetic and scoped scalar/prerequisite/author-boundary checks. Half-open named-calendar intervals, bounded uncertainty and strict relative-order cycle checks retain independent calendars and evidence scopes. Unsupported operators and exhausted work budgets remain visible. Descriptive declarations are not executable rules.
- **Research:** universe-required immutable author frames, exact/name/contextual-name/FTS search, stable cursors, typed record/evidence reads, basic time-filtered state with unresolved assertion IDs, and budgeted dependency-closed briefs cached by principal/grant/revision. Time-sliced frames cannot narrow proposal admission checks. At this baseline, state reported partial coverage pending event, persistence and knowledge evaluators. Later event and declared-state support is implemented; broader inference remains bounded. See the [current completion matrix](completion-roadmap-goal37.md).
- **Author-controlled time:** creation requires a Gregorian or fictional starting timestamp. Canon stores both first interaction and current time. Explicit elapsed-time or time-travel proposal operations change current time while retaining the first timestamp and old revisions. Timers use authored starts and durations, not real elapsed time. Relative-month previews use a pinned current date; missing fictional month conversions and nonexistent Gregorian month-days fail explicitly.
- **Sources and recovery:** immutable exact UTF-8 text and byte anchors; checksummed logical archives, staged mapping/conflict previews and explicit restore/clone acceptance; dependency-closed filtered exports with declared omissions; bounded v0.3 conversion; no-clobber snapshot backups and historical/source restoration. The `retain-all-history-v1` policy preserves canonical history, workflow receipts and source assets; compaction cleans only rebuildable data. Broader legacy formats fail explicitly rather than inventing provenance.
- **Native controls:** pinned explorer and inspector; entity/world/work/saga creation and memberships; definitions; qualified values, alternatives, ranges, quantities, relationships and fictional time; typed name/type/world-alias and assertion-ending/retraction actions; exact readable proposal review. Dropdowns offer searchable choices with subtitles. Namespace typeahead suggests all pinned/draft namespaces and requires explicit selection of a new value. No native raw JSON manipulation is available.
- **Draft safety:** completed typed operations and rationale autosave without changing canon. Unfinished form fields enter durable storage only when added to the draft. Compare-and-set rejects competing-window overwrites; recovered stale drafts require explicit rebase. Source staging appends to the current draft. A malformed recovered draft is retained and cannot silently turn into an empty draft. Starting a new empty draft is an explicit action.

## Automated regression scope

Workspace tests cover transport, domain contracts, storage faults/recovery, current authorization and the real socket author/agent review/commit/re-query/restart loop. Specific regression coverage includes:

- adjacent temporal intervals and exact exclusive-end boundaries; unresolved/unknown boundaries, bounded uncertainty and mismatched clocks;
- positive ordering cycles, refutations, unasserted propositions and independent clock/context false-positive controls;
- an assertion ending in a later revision while old pinned state remains unchanged;
- explicit forward elapsed time and backward time travel with immutable first interaction;
- timer blank/zero/negative/overflow rejection and preservation of the story clock;
- submitted draft recovery, same-proposal identity reservation, changed approval invalidation and rejection of entity deletion through an assertion-only operation;
- current grants, stale approvals, world/shared isolation, source anchors, archive/history/source round trips, filtered export omissions, cache grant/revision separation and retention-safe maintenance;
- namespace reuse and typed values without absent-to-zero/false conversion.

## Reproduce

```sh
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
cargo run --locked -p xtask -- check
/tmp/universe-contract-validation/bin/python scripts/validate_contracts.py
cargo run --locked -p xtask -- package-fixture
/tmp/universe-contract-validation/bin/python scripts/mcp_smoke.py --bin-dir 'target/fixture/Universe Builder Fixture.app/Contents/MacOS'
/tmp/universe-contract-validation/bin/python scripts/installation_smoke.py --bin-dir 'target/fixture/Universe Builder Fixture.app/Contents/MacOS'
```

`check` runs formatting, warnings-denied Clippy, workspace tests and generated schema drift checks. The package command builds and ad-hoc signs the bundle without opening a window. Independent clients validate protocol/output schemas and exercise packaged helpers. Exact results for this increment are recorded below after execution.

## Native evidence and limits

Before testing was paused, native controls created/autosaved `Native Lantern`, submitted `prp_4fea5f14df3ca1bbdc02ada4`, displayed validation and the full shared/nonprotected footprint, obtained exact author approval, committed `rev_c8383086f957866ce6abc911`, and retrieved `rec_18c9c7d09e6f6f745ed82b43`. The accessibility tree exposed the form labels, messages and approval controls. This establishes an earlier native workflow, not verification of the newly added selectors/time/inspector controls or a full VoiceOver gate.

Current native interaction, full VoiceOver/lifecycle and simultaneous native/MCP checks are **paused by the user**. The Mac is unlocked. Test windows remain closed. LM Studio integration is **blocked by the user's instruction to keep Bionic open**. Clean-machine/offline, hosted CI, distribution signing/notarization and broader release-scale/security acceptance remain pending.

The subsequent milestone 7 increment implements bounded Timeline, possession-power, event, knowledge/exception, impact/job and continuity/pack behavior. State remains explicitly partial; see the newer evidence document for exact limits. Story-level silver-gate completion is not claimed.

## Sonar

`sonar analyze secrets` ran before reading relevant files and again over edited files, with no findings. `sonar list projects --query universe-builder-mcp` returned zero projects. A full SonarQube code-quality analysis is therefore blocked; clean secret scans are not a substitute.

## September 24 automated results

- `DEVELOPER_DIR=/Library/Developer/CommandLineTools cargo run --locked -p xtask -- check`: passed formatting, warnings-denied Clippy, **176 tests**, and generated-contract drift checks.
- `/tmp/universe-contract-validation/bin/python scripts/validate_contracts.py`: passed **26 schemas, 13 valid examples and 91 invalid examples**.
- Secrets scan command covering intended source/generated changes: `sonar analyze secrets crates scripts contracts docs README.md IMPLEMENTATION_STATUS.md Cargo.toml Cargo.lock xtask apps .github .gitignore rust-toolchain.toml`. No findings were reported; the unrelated `codealike.json` was not read or modified.
- `DEVELOPER_DIR=/Library/Developer/CommandLineTools cargo run --locked -p xtask -- package-fixture`: passed release build and local ad-hoc signing/verification. No app window was opened.
- Both packaged-helper commands under **Reproduce** passed: independent fixture MCP and persistent installation/MCP smoke checks. These include output-schema validation and the stored proposal/approval/commit/retry/research/restart path; they do not establish native UI or LM Studio acceptance.
