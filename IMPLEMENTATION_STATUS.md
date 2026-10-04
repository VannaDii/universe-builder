# Universe Builder — Implementation Status

Updated 2026-09-24 against the working tree. Design source: [v0.4 implementation plan](Universe_Builder_Full_Implementation_Plan_v0.4.md).

## Delivery boundary

Milestones **1–8 have an implementation candidate for facilitated final testing**. This is the bounded feature set described below, with executable/partial/descriptive/unsupported capabilities reported explicitly. It is not a declaration that every v0.4 acceptance scenario or provisional performance target has passed.

Current native interaction/VoiceOver verification remains paused by the user. LM Studio remains blocked while Bionic stays open. Clean-machine/offline, hosted CI, supported-OS and distribution verification remain pending. The sealed development bundle declares `release_accepted: false`.

## Implemented scope

October 2 G02 qualification: the existing ADR-0006 path passes twenty authored
action-applicability outcomes, including thirteen illegal rejections, seven
committed legal controls and earlier incapacity retcon invalidation of two
dependent actions. Nine publications and 158 MCP calls pass the independent
wire/state/history audit and restart recovery. No engine defect or design change
was needed. Focused regressions, documentation and CI now cover this scope;
see [G02 proof results](docs/g02-action-applicability-verification.md).

October 3 normalized foundation: definitions, instances and temporal facts now
use the approved fixed typed relational model through the existing transactional
kernel. Independent Cedar/Pistol SQL reconstruction, frozen digests, history,
restart, invalid-reference rollback and process-interruption proofs are covered
in [normalized foundation verification](docs/normalized-foundation-verification.md).
Old serialized packages require explicit conversion; none were migrated.
Workflow/installation conversion and unrelated-family qualification remain open.

October 3 rules/actions/events: the existing typed expression, requirement,
consequence, participant and generated-assertion rows are now qualified through
independent SQL reconstruction and actual disposable MCP histories. Cedar
capabilities retain original digests and legal/illegal/unresolved outcomes;
Pistol consumption, reload, temporal endpoints, generated identities and
retcon/restart histories pass exact accounting checks. Evaluator behavior remains
unchanged. See [normalized rules/events verification](docs/normalized-rules-events-verification.md).

| Milestone | Implementation and limits |
|---|---|
| 1 · WP01–03 baseline | Build/lint/test automation; typed domain and all 13 closed public tool contracts; generated schemas and valid/invalid fixtures. Unsupported evaluation cannot claim complete coverage. |
| 2 · WP01/03/04 integration | Bounded IPC framing/handshakes, correlation, cancellation/recovery, real MCP stdio adapter and independent client checks. Ad-hoc signed native fixture and prior native author-loop evidence; full accessibility/host acceptance remains open. |
| 3 · WP05 storage | Typed relational record bodies and membership; append-only workflow history; atomic revisions/receipts; durable source and image bytes; reconstruction, migration, fault/crash/full-disk tests. Typed reference validation also runs during historical reads and recovery. Backups verify canonical/workflow digests and reconstruct heads before publication; old serialized packages are refused unchanged for explicit conversion. Admission enforces recovery limits before publishing new history. |
| 4 · WP06 ownership | Authenticated installation profiles, current scoped grants, single package writer, coordinated startup and bounded worker capacity. Recovery failures release slots; publication has a short fresh-authority gate. |
| 5 · WP07–10 authoring/research/recovery | Immutable proposal versions, reserved identities, explicit rebase, exact author approvals, atomic publication/retry; bounded basic rules, temporal validity and finite ordering; revision/grant-bound research and cached dependency briefs; UTF-8 anchors, logical archives/import previews/clones, bounded legacy conversion, verified backups and retention-safe compaction. |
| 6 · WP11 native author workflow | Typed creation, definitions, qualified claims/relationships, narrative bindings, inspector edits, durable scoped drafts, readable exact review/approval/commit, source/recovery controls, rich searchable selectors and namespace reuse suggestions. Universal optional appearance descriptions, image references, visual relationships and time-bound appearance edits. No raw JSON editor. Current controls are compiled and exercised through pure/UI and engine tests; current packaged native interaction remains pending. |
| 7 · WP12–14 continuity semantics | Exact occurred-event effects and explicit within-event order; time/context-bound knowledge, complete sets, temporal rules and scoped author exceptions; conservative impact, durable validation jobs, pinned forks/adoption and exact pack upgrades. Typed rule, boundary, complete-set and exception controls supplement the event/knowledge/pack forms. Custom-domain minimal/adversarial pairs retain authored distinctions. Advanced inference remains explicitly unsupported. |
| 8 · WP15 hardening | Sealed component/helper manifest and tamper refusal; malformed MCP, isolation, revocation, fault/recovery and schema-upgrade regressions; headless packaged integration; standard-sized storage/evaluator/recovery workload and a separate multi-universe MCP benchmark; update/rollback runbook. External release acceptance remains open. |

## Eight-item audit remediation

The eight findings from the completion audit are implemented in order. This is a headless implementation result; the native and release gates above remain open.

1. Subject research follows incoming propositions, positive/negative assertions, relationships, completeness, boundaries and issue decisions as well as outgoing dependencies. Traversal has an explicit work bound and preserves unresolved/restricted coverage.
2. Definition discovery, inline validation and inline impact resolve exact world selectors and guards at the pinned revision. Inline writes must fit a named world's envelope.
3. Context records and dependency manifests paginate together without skipping mandatory records. Proposal pages include authored operations and their compiled expansion. Cursors bind the frame, request, principal and current grant. Native proposal loading assembles all pages before review. A single record that cannot fit the requested budget produces an explicit limit error.
4. Character/narrator research requires a matching authored context. Reader research requires a pinned scene, an exact bound work edition and explicit `disclosedRecords`; later scenes and mere event depiction do not imply earlier knowledge. Native state queries expose these perspective choices. This does not implement automatic perception or belief inference.
5. Get returns typed summary, evidence and history groups. History follows the selected revision and fork ancestry, with at most 100 changes per requested record; restricted views report restricted history. Native history restoration creates a compensating draft for validation and approval. Issue decisions have typed accept/defer/resolve controls.
6. Research profiles may run bounded inline checks without proposal permission. Restricted inline checks return generic coverage before compiling against hidden definitions. Explicit entity/predicate/continuity write limits, expiry and separate shared-write authorization support delegated commits after complete validation. Existing grants retain the approval requirement. Installation schema 2 prevents older engines from ignoring the new limits.
7. At most two queued evaluations run on detached immutable candidates. Same-universe reads, polling and cancellation continue during evaluation; publication rechecks current authority and cancellation. Shutdown cancels and drains active evaluations, leaving interrupted jobs retryable.
8. Nineteen optional starter vocabularies ship with their minimal/adversarial examples and install through ordinary proposals. They do not install executable domain simulations. Native administration lists/enrolls/revokes profiles and edits/withdraws grants. Author-only purge previews and confirms deletion of the **entire registered universe package**; selective canon purge is not offered. Changed previews fail, removal is recoverable after interruption, and backups/exports/client transcripts remain outside its scope.

See [verification evidence](docs/semantic-release-verification.md#eight-item-completion-audit) for commands and remaining acceptance limits.

## Appearance references

Every entry kind, including worlds and abstract definitions, can have optional companion appearance records. The universe itself also has a reference target. Authors can supply detailed physical descriptions, sensory atmosphere, multiple captioned images, and explicit matches/complements/contrasts/detail relationships to other entries. There is no item-kind allowlist. References can remain temporally unspecified or use a named-calendar half-open interval; revisions preserve earlier descriptions.

PNG/JPEG/WebP originals are copied into immutable, checksummed chunks inside the SQLite universe package. Previews are generated separately; moving or deleting the original external file does not remove the reference. Full physical backups retain drafts and image bytes. Logical exports include original bytes for included canonical image assets, and filtered entry exports follow companion appearances and their dependencies. Imports validate image bytes, dimensions, format, digest and chunk completeness before publication. Current limits are 10 MiB per image, 8192 pixels per edge, 32 megapixels and 16 images per appearance reference.

The native editor uses text fields, rich entry/relationship selectors, a file picker and captioned previews. Authors can find, load and revise saved references. Writing context includes applicable appearance text, captions, metadata and explicit relationships, within its declared byte budget. Image pixels and descriptive prose do not become executable facts, and visual consistency is not automatically judged. Appearance changes are explicitly authored phases; continuous corrosion, dimming or other gradual simulation does not automatically generate prose or images. Native interaction of these new controls remains part of facilitated final testing.

## Fictional chronology

Every newly created universe requires an author-provided first interaction timestamp. Authors choose Gregorian dates with an explicit offset, or a named fictional clock with a tick label and optional fixed month length. No clock is initialized from the computer's current date.

The first timestamp and current story time are canonical, revision-bound data. Reading, editing, waiting, autosave and ordinary commits never advance them. A reviewed time-change operation supplies a destination and reason: elapsed time must move forward; backward changes require explicit time travel. This changes the authored clock only; it does not yet simulate time-travel effects or branches.

Named-calendar assertion intervals are half-open. Timers have an explicit start and positive duration in that calendar's ticks (seconds for Gregorian). State queries at a time exclude definitely inactive assertions and identify unresolved assertions, preserving explicit negatives. Unknown endpoints and independent clocks are not converted into guesses. Legacy clockless intervals remain unresolved in time-specific queries.

“N months ago” is resolved from a pinned fictional date, never wall time. Gregorian uses the authored fixed offset and rejects nonexistent target month-days instead of silently rounding. Fictional months require a declared tick count. Seasonal calendars, DST rules, calendar conversion and arbitrary calendar formulas remain outside this increment.

## Milestones 7–8

Milestone 7 now includes a scrollable Timeline with declared world/region location filters, before/after state at exact occurred events, deterministic effect recompilation, explicit preconditions, possession-dependent powers and timers. Explicit knowledge is time/context bound. Objective membership completeness and exact-version author exceptions have conservative scope checks. Impact includes the full visible universe, including negative dependencies. Validation jobs append durable running/terminal records, recover by operation ID, support queued cancellation and page findings with bound cursors. Pinned forks, selected adoption, same-kind definition revisions and exact dependency pack upgrades are reviewable operations with typed native controls.

Milestone 8 includes a sealed helper/component manifest, tamper rejection, malformed-contract mutations through MCP, headless package checks, two-universe interactive measurements, a 10,000-entity / 200,000-assertion / 2,000-rule / ten-continuity storage and recovery fixture, and an update/rollback runbook.

**Acceptance remains open:** the 38 custom-domain fixtures establish representation and account/no-invention behavior; they do not establish general domain simulation. S01–S10 persistent-engine fixtures, additional S11–S21/S25–S35/S45 finite semantic checks, exact temporal boundary regressions and cross-world scope/travel tests now supplement that coverage. Independent-calendar conversion, automatic epistemic/causal inference and realm-dependent constraint evaluation remain explicit capability limits. Region filtering uses declared event locations. Native interaction/VoiceOver, LM Studio, clean-machine/offline, hosted CI, signing/notarization and the remaining full release matrix still need evidence. See [semantic and release evidence](docs/semantic-release-verification.md) and its final-testing checklist.

## Evidence and pending verification

See [authoring verification](docs/authoring-verification.md) for current commands, regression scope and verification limits; [fixture evidence](docs/fixture-verification.md) and [kernel/engine evidence](docs/kernel-engine-verification.md) retain earlier evidence.

Native testing is paused at the user's request because test windows interfered with their work. The Mac is unlocked; a locked screen is no longer the blocker. Both fixture windows were closed when testing was paused. This increment does not reopen them or quit Bionic.

Pre-read secret scans reported no findings. `sonar list projects --query universe-builder-mcp` returned no project, so full SonarQube code-quality analysis remains unavailable. Secret scans do not substitute for that analysis. No commit or PR was created; unrelated workspace changes were preserved.

## 2026-10-01 local AI authoring evaluation

Persistent MCP initialization and research/validation/proposal/impact/commit tool
descriptions now instruct external agents to verify provisional prose's material
continuity changes, commit selected changes to canon, confirm the receipt, and
continue from fresh committed context. The obsolete instruction claiming commit
was unavailable is removed. Existing approval/delegation and admission rules are
preserved. Only successful `universe_commit` makes changes canon.

The current locked workspace check passed 256 tests with 1 ignored workload;
independent contract/MCP/installation checks and 11 new harness regressions passed.
Direct local MLX testing scored 8/8 workflow decisions and 11/12 prose assessments.
The model-authored selected-prose commit succeeded; its age fact appeared in fresh
context and a subsequent conflicting age change was blocked. The model's expired
ignorance mistake remains a recorded qualification failure. This is direct
application-JSON/MLX evidence, not LM Studio native-host acceptance.

See the [authoring workflow](docs/ai-authoring-workflow.md) and
[readiness assessment](docs/novel-authoring-readiness.md) for reproducible commands,
the exact transcript and remaining author-host/native acceptance work.

## 2026-10-02 passage provenance and chapter/retcon pilot

Source evidence and passage references now require actual anchor targets.
Research includes sourced observations, depicted-event scenes and anchored
passages. MCP instructions require exact source/passage links, distinguish
performed events from preparations, and preserve old sources/editions on retcon.
The public 13-tool contracts and approval/delegation boundaries are unchanged.

The accepted local MLX pilot generates a three-scene chapter and continuation,
commits their declared material changes, rejects an incomplete delayed-handoff
retcon, commits the corrected chronology, retains old state/source versions,
rejects a stale approved change and recovers the exact receipt/current head
after terminating its owned engine. Evidence includes 332 public calls, 15 canon
commits, 12 passage references, exact author approvals and a separate source audit.
Locked verification passes 258 tests with 1 ignored workload; 18 Python harness
tests and independent contract/MCP/installation checks pass.

Earlier producer passes missed actual source implications; those are retained
and rejected explicitly. Model self-review is not a full continuity certificate.
The accepted pilot uses declared material vocabulary and narrow fixture checks;
unrestricted extraction, actual-host/native acceptance and book-scale profiling
remain open. See [chapter verification](docs/chapter-retcon-verification.md) and
the [authoring workflow](docs/ai-authoring-workflow.md).

## October 2: Approved owning-entity action attributes

Vanna approved the design change documented in
[ADR-0006](docs/adr/ADR-0006-declared-actions-and-owner-attributes.md). New/revised
events must name an author-controlled action definition. Its mandatory values
are evaluated on exactly one individual/object per required role in the exact
pre-event state and applicable context/world. Optional conditions cannot bypass
these requirements. Direct and possession-derived attributes share an evaluator;
explicit muting, expiry, transfer and unresolved/conflicting custody cannot leak
an ability to another owner. General scalar attributes use the same check.
Historical actionless events remain readable; older evaluator validation/approval
bindings require refresh. Existing ordinary fixtures declare their actions
explicitly. The author form requires action selection and offers typed action
declarations; native rendering/accessibility are still unqualified.

Final locked verification passes 269 Rust tests (one ignored workload), strict
Clippy, formatting and generated-contract drift. The 18 Python tests,
independent 26-schema/13-valid/91-invalid corpus, MCP protocol/restart and
persistent installation checks pass. The chapter/retcon regression still passes
332 public calls and 15 commits. The power MCP pilot passes all 11 admission
cases, with 70 calls and two selected commits. CI includes its deterministic path.

The final local MLX review is **model failure**, 9/11 exact verdicts. It falsely
approves an explicitly muted recipient and the item itself; mandatory engine
validation rejects both and neither becomes canon. Earlier failed MLX evidence
is retained. Prose extraction/action classification still requires source review;
passing structured constraints does not certify arbitrary manuscript semantics.
See [execution evidence](docs/novel-authoring-readiness.md#wall-traversal-and-declared-powers-october-2-verification).

## Internal assessment persistence (October 2, 2026)

Immutable proposal-bound assessment attachments, append-only selection history,
atomic generation/proposal comparisons, exact source/anchor checks and internal
readback states are implemented. Service/store/protocol checks passed (125 tests;
one standard workload intentionally ignored), with independent read-only SQLite
audits before and after restart, source text revision and proposal replacement.
See [assessment persistence verification](docs/assessment-persistence-verification.md).
Public attachment and selection are implemented in the next slice below. Final
validation/approval/commit integration and prose qualification remain subsequent goals.


## Assessment MCP submission (October 2, 2026)

The existing `universe_propose` exposes closed `attach_assessment` and
`select_assessment` actions with replacement and explicit-null withdrawal.
Authenticated assessor admission, proposal/source permissions, generation checks
and exact retry recovery reuse Goal 8's immutable atomic storage service.
Twenty-four actual MCP cases pass with an independent transcript/SQLite-state
and hash audit; three focused service tests and ten assessment protocol tests pass.
Frozen proposal and canonical state remain unchanged by assessment requests.
See [public assessment verification](docs/assessment-mcp-verification.md).
Assessment retrieval is implemented in the next slice below. This submission
slice does not qualify validation/approval/commit integration, native assessment
interaction or assessed prose.

## Pinned assessment review (October 2, 2026)

`universe_get_proposal` now provides a permission-checked assessment view with
exact historical references and pagination pinned to proposal, assessment digest
and selection generation. The existing author review uses the same service data
and displays declared source ranges, inventory, mappings, exclusions and unresolved
items. Independent reconstruction/digest checks, 88 real MCP review cases and two
private author reviews pass; the Rust suite passes 134 tests. Restricted or revoked
access exposes no assessment identifiers, excerpts, counts, hashes or cursors.
See [assessment review verification](docs/assessment-review-verification.md).
Assessment validation/approval/commit enforcement, language interpretation and
native interaction/accessibility qualification remain outside this increment.

## Declared action effects (October 3, 2026)

The shared action/event validation path now enforces Goal 15's required/permitted
set effects: exact slots, role owners, predicates, values/polarities, full scope,
order, conditions and lifetime. Missing obligations, unrelated power grants and
wrong recipient/world effects reject through actual MCP validation without head
movement. Generated assertions remain frozen in reviewed proposals; prior
evaluator approvals are stale under `finite-policy-v6-declared-effects`.
Forty-one independent effect fixtures and 22 audited MCP cases (15 rejected,
seven committed) pass, including exact queried assertions and expiry/restart.
Resource arithmetic, simultaneous spending and prose/native qualification remain
excluded. See [effect enforcement verification](docs/declared-action-effects-verification.md).

## Exact resource transitions (October 3, 2026)

Occurred delta effects now resolve exact pre-event stock on the declared object
and verify authored post-values using checked integer arithmetic, declared bounds
and exact units. Missing/uncertain/conflicting evidence, forged balances,
underflow/overflow and invalid atomic debit/credit effects reject without canon
movement or silent repair. Forty-four independent accounting fixtures, 39 audited
MCP transition cases (12 committed, 27 rejected), two evidence-retcon controls and
seven auditor tests pass. Generated assertions, queried balances and restart
receipts agree with independently audited SQLite history. Prior evaluator
validations/approvals are stale under `finite-policy-v7-resource-transitions`.
Multi-event ordering, reusable world-rule enforcement and prose qualification
remain excluded. See [resource verification](docs/resource-transition-verification.md).

## Cumulative resource continuity (October 3, 2026)

Overlapping uses of a resource require distinct exact story times, including
universe-wide/world-specific overlap and simultaneous set/delta changes. The
accounting target remains the gun across holder changes, scenes and restart.
Nine focused cumulative fixtures and independent Fraction replay pass. The audited
MCP sequence passes 282 calls, 23 commits, eight unchanged-canon rejections,
20 state queries, three scene editions and two engine restarts. Twelve established
rounds reach zero; a thirteenth shot rejects; a declared three-round reload debits
a four-round reserve; an overdraw rejects atomically. An earlier retcon with a
valid first use rejects on an unchanged invalid successor. A valid earlier-time
retcon preserves old editions and all retry receipts through restart. The prior
39-case MCP regression also passes under `finite-policy-v8-cumulative-resources`.
Reusable world-rule enforcement and prose qualification remain excluded.
See [cumulative verification](docs/cumulative-resource-verification.md).
