# Milestone 7–8 implementation evidence

Updated 2026-09-24. The conditional audit proceeded beyond the first six milestones. All work in this increment was headless; no desktop or LM Studio windows were opened, and Bionic was left running.

## Implemented behavior

| Area | Evidence and deliberate limits |
|---|---|
| Fictional event Timeline | Native scrollable event list, pinned revision, independent-calendar ordering, declared world/region location filters and entity comparison immediately before/after an occurred event. Compilation and service tests cover its underlying operations; current native interaction is unverified. Region filters do not infer geographic membership. |
| Event compilation and powers | Stable effect-slot identities, exact integer coordinates, explicit half-open validity, pre-event prerequisites, generated assertion reconciliation and provenance. Only occurred events generate effects. Effects within one atomic event use explicit unique order; superseded intermediate effects are never visible as a post-state. Noncommuting effects from separate simultaneous events fail rather than invent ordering. Possession powers require positive exact evidence, are removed on loss, follow a later holder and expire at timer boundaries. A separate power-validity timer expires while the character retains possession and its other powers. Event edits preserve historical reads. Recompilation is permutation-tested and rejects altered/missing generated effects. |
| Knowledge and completeness | Explicit attitudes evaluate only in the proposition's represented context and active interval. Belief does not become knowledge; presence, reports and communications do not imply knowledge. Typed native attitude controls require an acquisition time and basis. Objective membership completeness catches additions outside an exact declared set; observer-known, other-context and other-realm declarations do not close that set. Broader completeness inference remains partial. |
| Exceptions and definitions | An author decision may waive an exact version of a block-unless-exception rule or creative boundary within matching context and contained scope/validity. Exact named-clock periods are partitioned at every evidence/exception boundary. A narrower exception cannot disable the rest of a rule; original findings remain visible. Boundaries follow transitive references through existing propositions and check the old interval when evidence is removed. Structural invariants cannot be waived; independent clocks and realm-dependent constraint inference fail closed. Revising a rule makes its existing exception stale. Same-kind definition revisions retain namespace/key and create fresh immutable versions; inspector edits never require raw JSON. |
| Impact and jobs | Impact deliberately includes the full visible universe rather than claiming a narrow incremental result is complete. Hidden dependencies yield restricted coverage. Jobs append immutable queued/running/terminal records; completed results survive restart. Cancellation before execution is durable; a persisted running job is reported interrupted and retried with the original key. Findings page in batches of 100 with bindings to the exact result, frame, request, principal and grant. Delivery completion is separate from evaluation coverage. |
| Access and decisions | World-scoped validation reports generic restricted coverage without hidden findings. Read visibility follows transitive references; propositions and attitudes cannot expose a hidden-world character indirectly. Source/anchor and editorial-decision records without enforceable world scope require a universe grant. The author can validate the exact proposal; a scoped client can commit only with exact author approval, unchanged head and current grants. Fingerprints include the semantic frame, proposal input, evaluator, outcome and evidence, so changed evidence does not inherit a stale decision. |
| Continuities and packs | Forks pin an exact historical baseline. Parent edits remain outside the child until an explicit adoption proposal is validated, reviewed and committed. Pinned historical comparisons remain unchanged afterward. Exact pack dependencies, duplicate keys, dependency cycles/depth and version mismatches are checked. Native pack controls select existing definitions and dependencies; packs are data, not code. |
| Source-domain representation | `crates/universe-rules/tests/domain_catalog.rs` exercises 19 minimal custom-definition graphs plus 19 adversarial no-invention queries. Each case is named separately. They round-trip, preserve distinct predicates/identities and keep an asserted account from becoming an objective claim. This is explicit representation and no-invention evidence, not general simulation of each domain. |
| Universal appearance | Optional descriptions, sensory atmosphere, captioned images and explicit visual relationships attach to any entry or the universe. Authored intervals filter writing context, related appearances follow explicit links, and revised references retain historical reads. Imported PNG/JPEG/WebP originals are embedded in the package; previews are separate. There is no automatic image-to-fact or visual-consistency inference. New native controls compile; interaction remains pending. |
| Release tooling | Packaging records 393 locked build components on the tested target, SHA256 digests for three helpers and the component inventory, Rust compiler, source revision, dirty-build status, architecture and build-host OS. The entire development bundle is ad-hoc signed. Packaged clients verify its seal before selecting the engine; a modified-helper fixture fails before engine startup. |

## Bounded Silver Gate scenarios

`silver_gate_s01_to_s10_use_pinned_candidates_and_explicit_story_time` executes S01–S10 in separate pinned continuities against the persistent engine. It rejects an opening without the actor's seal, early contradictory location knowledge, additions outside a declared exhaustive entrance set, and a transfer that leaves conflicting continuous custody. Reports and accidental arrival add no objective possession/knowledge. Explicitly ending prior custody makes an off-page transfer and opening admissible. A method effective at day 21 fails at day 16 and succeeds at day 22. Narration at day 80 in its own context leaves objective knowledge and the story clock at day 16 unchanged.

This fixture represents explicit known-location assertions as a single-valued Boolean property and event requirements as bounded preconditions. It does not claim general inference about a character's mind. The disposable fixture adapter still reports unsupported evaluation; it is distinct from this persistent-engine suite.

## Executed checks

- `DEVELOPER_DIR=/Library/Developer/CommandLineTools cargo run --locked -p xtask -- check`: formatting, strict Clippy, workspace tests and generated-schema drift. The current suite passes 250 tests; one opt-in standard workload is excluded from the routine run and executed separately in release mode.
- `cargo run --locked -p xtask -- schemas` regenerates the closed contracts after the typed operation/response changes.
- `/tmp/universe-contract-validation/bin/python scripts/validate_contracts.py`: 26 schemas, 13 valid examples and 91 invalid examples.
- `cargo run --locked -p xtask -- package-fixture`: rebuilds and verifies the ad-hoc sealed development bundle.
- Independent `scripts/mcp_smoke.py` and `scripts/installation_smoke.py` run against the bundled helpers with a restricted PATH. MCP mutations cover all 91 malformed contract cases, alongside Unicode, idempotency, adapter restart, output-schema and text/structured parity checks.
- `scripts/verify_release.py`: verifies manifest/component/helper digests and the bundle seal, then tampers with a disposable copy and confirms refusal before engine startup.
- `scripts/benchmark_workload.py`: commits 500 entities in five reviewed batches, runs 30 concurrent search samples per universe, restarts, and restores a backup into a separate installation. Both original and restored historical heads are checked.

## Measured development workload

Observed on Mac17,6, Apple M5 Max, 128 GiB RAM, macOS 27.0 / arm64. This is a local measurement, not an SLA or a clean-machine result.

| Operation | Samples | Median | Maximum |
|---|---:|---:|---:|
| Reviewed 100-entity batch | 5 | 131.284 ms | 144.782 ms |
| Warm search in 500-entity universe | 30 | 11.646 ms | 13.448 ms |
| Concurrent search in independent universe | 30 | 0.893 ms | 1.389 ms |

Cold engine start was 79.529 ms. Search results were validated against the generated output schema. The test uses disposable installations and stops their engines during cleanup. It does not establish event-heavy, source-heavy, sustained-contention or memory-pressure targets.

## Additional semantic and durability evidence

- `semantic_acceptance.rs` covers missing versus complete-empty membership, expiry of completeness, competing accounts, local conflicting evidence, false belief without objective promotion, n-ary treaty roles, uncertain/half-open/independent-clock intervals, finite quantification and numeric ranges with units/open endpoints.
- `rule_checks` partitions temporal rules into exact integer-clock cells. Generated cases vary endpoints and record order, comparing indexed and unindexed results, coverage and evidence. Each world is evaluated separately; a fact from another world cannot satisfy a local rule.
- `boundary_checks` verifies indirect subject protection, narrow temporal exceptions, removal of old evidence, independent-clock uncertainty and preserved findings after an authorized waiver.
- Persistent-engine completion fixtures cover worldless universes, duplicate names across universes, selector collisions, per-request world focus, shared content, cross-scope cursors, many-to-many work/saga references, live cross-universe reference refusal, advisory norms/tendencies and atomic cross-world travel with stable character/item identities.
- Appearance regressions cover universe/world/entity references, related appearance context, before/after appearance selection at a half-open endpoint, immutable revisions, author-only image import/preview, partial context for inaccessible visual references, forged import receipts, source-file removal, multi-chunk images, backup/restart, filtered export/clone and rejection of missing chunks even after an archive envelope checksum is recomputed. Invalid, oversized and non-regular image inputs fail.
- Store regressions cover backup interruption before verification/publication, existing-backup preservation, semantically corrupt workflow bytes despite a successful SQLite page check, branch admission at the actual recovery-depth boundary, and exact restart/restore of 10,050 entities. Existing abrupt-exit, transaction fault and disk-full tests remain passing.
- Supported schema upgrades retain a private `0600` verified pre-upgrade SQLite copy. Tests inspect its old schema and original record; failed snapshot verification prevents the upgrade and leaves the old data intact.
- Logical archives are bounded to 512 MiB, two million rows and one million record versions; canonical snapshots are bounded to 500,000 records. Physical backups and SQLite writer page growth share the 8 GiB restore limit. Repeated identical branch memberships are verified once per recovery operation; every branch chain and immutable payload still gets checked. Limit errors preserve the original; compaction never silently deletes canonical history, source bytes, drafts or receipts.

## Standard-sized storage and evaluator workload

`DEVELOPER_DIR=/Library/Developer/CommandLineTools cargo test --locked --release -p universe-service --test standard_workload -- --ignored --nocapture` constructs 10,000 entities, 200,000 propositions, 200,000 assertions and 2,000 executable rules: 412,002 records including context/property metadata. It imports a checksummed 367,542,915-byte archive, creates ten pinned continuities, evaluates all 2,000 rules through the candidate index, verifies a physical backup, restarts and restores into a separate package. It compares every record and all continuity heads after recovery. An unindexed scan exceeding its budget reports incomplete coverage.

The routine 247-test run and this opt-in workload are separate evidence. The workload measures kernel/evaluator behavior, not end-to-end standard-sized UI or MCP latency. Its fixture process retains generated/imported data; it is not an engine-idle or engine-only peak-memory measurement. Ten-world distributions, long/skewed provenance graphs, sustained contention and local-model coexistence still require acceptance profiling. Provisional latency/memory targets are not claimed achieved.

## Facilitated final testing

Implementation for the eight milestones is ready for testing within the declared capability limits. The release matrix is not yet signed off.

1. **Native author loop and accessibility:** in a coordinated session, create Gregorian and fictional-calendar universes; exercise keyboard/VoiceOver and rich selectors; author rules, boundaries, complete sets and exceptions; save/recover drafts; validate/review/commit exact changes. Confirm every edit uses typed controls and no raw JSON editor.
2. **Timeline and plot continuity:** transfer an item between characters, lose/reacquire its powers, expire a timer while retaining possession, filter declared world/region locations, compare before/after and older revisions, and confirm ordinary editing never moves story time. Check explicit elapsed time and backward time travel separately.
3. **Author-visible recovery:** back up a disposable multi-world universe containing source text and drafts, restore into a separate installation, compare history/source anchors/receipts, and rehearse recovery from an interrupted write. Preserve the original installation throughout.
4. **Host and platform:** LM Studio desktop remains blocked while Bionic stays open. Native testing remains paused until a coordinated session; being unlocked alone does not revoke that pause. Check a clean supported Mac, offline startup, helper updates, signing/notarization and hosted CI separately.
5. **Final acceptance review:** execute remaining S/T/U/E/V scenarios, domain-specific narrative variants, larger/skewed security/fuzz and performance profiles, and any released-version upgrade/downgrade routes before advertising those guarantees. Existing tests are evidence for their named cases, not a claim that the entire catalog ran.

`sonar list projects --query universe-builder-mcp` returned no project. Secret scans pass for scanned files; a full SonarQube code-quality result is unavailable. No commit, PR or distribution release was created. No desktop windows were opened; unrelated changes and Bionic were preserved.

## Standard storage/evaluator measurement

The final pre-appearance standard run passed in 183.71 seconds: 10,000 entities, 200,000 propositions, 200,000 assertions, 2,000 rules, ten continuities and a 367,542,915-byte logical fixture. Import took 34,625 ms, branch creation 46,113 ms, snapshot read 3,819 ms, index build 83 ms, rule evaluation 188 ms, backup 18,558 ms, restart 36,319 ms and restore 38,997 ms. Full records and heads were compared. New image durability changes are covered separately by the multi-chunk recovery and corruption regressions; this standard fixture contains no images. These are storage/evaluator measurements, not end-to-end interactive or memory SLAs.

Include the new appearance editor in the coordinated native test: attach multiple images to a world, an entity and an abstract definition; add universe atmosphere and complementary references; revise an appearance across a story-time boundary; navigate with keyboard/VoiceOver; save the draft, restart, and recover its captions and original image references. Verify image layout on the target display and use the documented file/size limits. Do not resume GUI testing until the user coordinates the session.

The final appearance-enabled bundle passed independent MCP and installation smoke checks, contract validation, seal/helper-tamper verification, and the 500-entity restart/restore benchmark above. No native window was opened.

## Eight-item completion audit

The subsequent remediation covers subject evidence closure, exact world guards, context/proposal pagination, explicit perspective views, typed history/evidence and compensating undo, research and delegated authority, detached cancellable jobs, and the starter-pack/administration/purge controls. [Implementation status](../IMPLEMENTATION_STATUS.md#eight-item-audit-remediation) records the precise boundaries.

Headless verification:

- `DEVELOPER_DIR=/Library/Developer/CommandLineTools cargo run --locked -p xtask -- check` passed formatting, strict Clippy, 253 tests and generated-schema drift; one opt-in standard workload remains excluded from this routine run. The earlier standard-workload measurement above is historical evidence, not a new measurement of this increment.
- `cargo test --locked -p universe-service --test workflow audit_eight -- --nocapture` passed the strengthened disposable integration scenario: supporting/refuting evidence, world lookup and guard failures, multi-page context larger than its page manifest budget, authored/compiled proposal pages, character/narrator isolation, earlier/later reader disclosure, typed history, research-only validation, delegated writes and rejected overflow, all 19 starter installations, grant withdrawal, stale purge rejection, and author-only package purge.
- `cargo test --locked -p universe-service --lib detached_validation -- --nocapture` held a queued evaluation at a deterministic barrier and verified that the same universe still served reads, reported running status and accepted cancellation before release.
- The final native perspective and complete-proposal-loading changes passed `cargo clippy --locked -p universe-ui --all-targets -- -D warnings` and `cargo test --locked -p universe-ui`.
- `/tmp/universe-contract-validation/bin/python scripts/validate_contracts.py` passed 26 schemas, 13 valid examples and 91 invalid examples.
- `sonar analyze secrets crates scripts contracts docs fixtures xtask apps .github IMPLEMENTATION_STATUS.md README.md` found no secrets. `sonar list projects --query universe-builder-mcp` returned no project, so full SonarQube code-quality analysis remains unavailable.

No native windows or LM Studio sessions were opened. Native interaction/VoiceOver, clean-machine/offline, distribution signing/notarization, hosted CI and the remaining performance/acceptance matrix still need their coordinated runs. The development bundle remains explicitly unaccepted for distribution.

The refreshed development bundle also passed:

- `DEVELOPER_DIR=/Library/Developer/CommandLineTools UNIVERSE_PYTHON=/tmp/universe-contract-validation/bin/python cargo run --locked -p xtask -- package-fixture`.
- `/tmp/universe-contract-validation/bin/python scripts/mcp_smoke.py --bin-dir 'target/fixture/Universe Builder Fixture.app/Contents/MacOS'`: 13 tools, 91 malformed mutations, output schemas, Unicode, retry/recovery and both supported negotiated protocol versions.
- `/tmp/universe-contract-validation/bin/python scripts/installation_smoke.py --bin-dir 'target/fixture/Universe Builder Fixture.app/Contents/MacOS'`: concurrent cold starts, authenticated proposal/approval/commit, grants/revocation, crash recovery and durable heads.
- `/tmp/universe-contract-validation/bin/python scripts/verify_release.py --bundle 'target/fixture/Universe Builder Fixture.app'`: bundle seal, 393 component records, three helper digests and tamper refusal. `release_accepted` remains false.
