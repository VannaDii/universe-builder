# Novel authoring readiness assessment

Assessment date: 2026-10-02, America/Los_Angeles. Scope: the existing working tree,
the persistent engine and MCP adapter, routine verification, and a local MLX
authoring evaluation. Existing unrelated working-tree changes were preserved.

## Assessment

The project has a substantial, appropriately separated foundation for maintaining
canon. Its practical authoring contract is: **research provisional prose, validate
its structured continuity consequences, commit the author's selected changes,
then write against the resulting canon revision.** Only a successful commit makes
the change canon. This does not require a manuscript editor or another model
inside the engine.

The most consequential issue found in the MCP adapter was stale initialization
guidance saying canon commit was unavailable “until approval integration.” That
contradicted the implemented persistent commit route. Tool descriptions also
provided little guidance about using research, validation and commit together.
Both are corrected. The server now explains the authoring workflow, the evidence
distinctions, exact commit authority, receipt recovery and fresh-context use.

These instructions improve the workflow available to an external AI. Engine
enforcement remains the authority: an AI saying prose passed is insufficient,
and text appearing in a source record does not make its implied facts executable.

## Structure and documentation

The crate boundaries are sensible: domain records and rules are separate from
storage; the service owns authorization, validation and publication; the protocol
owns contracts; desktop and MCP clients share the service. Generated JSON schemas,
independent protocol tests, ADRs and verification documents support those
boundaries. No architectural replacement is warranted by this assessment.

The main maintainability pressure is concentration in
`crates/universe-service/src/workflow.rs` (about 2,800 lines). It combines candidate
evaluation, sources, approvals, queries, pagination, proposals, operations and
publication. Future changes should stay inside those existing responsibilities
and retain integration tests around the shared author/agent path. A broad
reorganization is not needed to implement the requested instruction change.

Historical verification documents retain their original dated claims. The new
[AI authoring guide](ai-authoring-workflow.md) supplies the missing practical
research-to-commit instructions and explains how to reproduce local MLX testing.
The README links both documents.

An additional bounded defect was found in `RecordKind::all()`: it omitted
`ItemPower`. The list is corrected and its regression now compares the complete,
unique list with the generated enum schema, rather than only round-tripping the
entries already present. This does not change the canonical record format.

## Existing safeguards relevant to a novelist

| Concern | Current safeguard | Limit to keep visible |
|---|---|---|
| Facts versus claims | Separate propositions and positive/negative assertions; four-valued evidence | A proposition's existence is not truth; state propositions can outlive active assertions |
| Story time | Authored clocks, half-open intervals, event pre/post state, explicit time advancement | No automatic synchronization of independent calendars or inferred travel feasibility |
| Character knowledge | Represented contexts, explicit attitudes and acquisition time | Presence, receipt, reports and beliefs do not automatically establish knowledge |
| Reader spoilers | Exact bound work edition, pinned scene and explicit disclosure | Narrative position is not story time; inferred reader knowledge is unavailable |
| Possession and powers | Explicit custody, occurred-event effects, timers and possession-dependent powers | New/revised events enforce mandatory owner-bound action attributes; untouched actionless history and prose/action classification still need review |
| Identity and worlds | Stable IDs, aliases, contextual names and world/shared footprints | Cross-universe live references are rejected; universe/world scope must stay explicit |
| Retcons and alternatives | Immutable history, pinned forks and reviewed adoption | Parent edits do not enter a child automatically; earlier prose is not automatically revised |
| AI publication | Immutable proposal versions, validation, exact approval or bounded delegation, atomic commit and receipts | A proposal, validation result, approval or source import is not canon publication |
| Retrieval | Revision/grant-bound dependency briefs and explicit pagination/overflow | An agent must follow required pages and understand restricted/partial evidence |
| Recovery | Durable heads, sources, backups, restart recovery and idempotent receipts | Exported backups/transcripts have separate lifecycle and privacy boundaries |

## Wall traversal and declared powers: October 2 verification

The initial transport test established actual admission gaps: a traversal could
omit its power requirement or check another entity's power, and a possession
power could appear in state without satisfying a prerequisite. Vanna approved
mandatory owner-bound action definitions and extended the requirement to
attributes generally. [ADR-0006](adr/ADR-0006-declared-actions-and-owner-attributes.md)
records the approved change and compatibility boundary.

The implemented transport regression is
`wall_traversal_requires_owning_entity_attributes`. New and revised events must
name a declared action; its mandatory values are resolved on exactly one entity
per required role at the pre-event time. Direct and possession-derived attributes
share the same evaluator. General text attributes use this path too.

| Scenario | Current executed result |
|---|---|
| Character or object with its own active wall-phase power | Validation succeeds |
| Declared ring holder with a supported active item grant | Validation and selected canon commit succeed |
| Wrong owner; optional condition checks another character's power | Rejected at `event.action.requirements` |
| Power requirement omitted from optional conditions | Mandatory action requirement still checked |
| Entire action omitted from a new/revised event | Rejected at `event.action` |
| Undeclared or expired power | Rejected; missing evidence is not a default value |
| Explicitly muted recipient during the authored interval | Rejected; state query also withholds the indirect grant |
| Suppression interval ends while custody/grant remain valid | Authorized use restored |
| Conflicting, approximate or unknown custody | No derived grant, including when only one candidate holder is queried |
| Transfer or custody expiry | Prior owner loses the indirect grant at the authored boundary |
| Another entity's colour, or a previous colour after a canonical change | Cannot satisfy the current owning entity's value requirement |
| An event attempts to grant its own prerequisite | Rejected against the pre-event state |

Reproduce the owner-bound transport regression with:

```sh
cargo test --locked -p universe-service --test workflow wall_traversal_requires_owning_entity_attributes -- --nocapture
```

The persistent MCP power pilot exercises 11 cases, 70 public calls and two
selected commits in a disposable installation. The chapter/retcon regression
continues to pass with 332 public calls, 15 commits, provenance links, historical
state and restart recovery after its ordinary actions are explicitly declared.
The updated Rust gate passes 269 tests, strict Clippy, formatting and generated
contract drift, with one ignored workload; the 18 existing Python tests pass.

[MLX power attempt 1](evidence/power-pilot-2026-10-02-run1/report.json) retains a
failed model review: 8/11 exact verdicts match. The muted case incorrectly says
`usable`, although its explanation correctly concludes conflict. Custody-ending
and expiry cases are also mislabeled conflict instead of unknown. All 11 engine
admissions have the expected allowed/blocked outcome independently of those
model verdicts. The model cannot override a mandatory attribute check.

[MLX power attempt 2](evidence/power-pilot-2026-10-02-run2/report.json) uses the
final `finite-policy-v3-owner-attributes` evaluator and records explicit separate
engine/model assessments. Engine admission passes 11/11; model review fails with
9/11 exact verdicts. It incorrectly approves the muted recipient and the ring
itself, confusing a holder grant with an attribute of the item. Both candidates
are rejected by `event.action.requirements`; neither is committed. The report
preserves every prompt, raw response, model weight digest, runtime version,
validation and selected approval/commit receipt. No model-review retry or model
role substitution is used to turn those failures into a pass.

Reproduce the actual MCP engine pilot without a model:

```sh
python scripts/power_authoring_pilot.py --output /tmp/new-power-pilot
```

Add `--model /absolute/path/to/existing-mlx-model` for the scored MLX review.
Use a fresh output directory; failed reports remain evidence. These are synthetic
fixtures and direct MLX execution, not native host function-calling qualification.
The final chapter regression report is
`/tmp/universe-actions-chapter-regression-final/report.json`. Independent
contract, MCP protocol/restart and persistent installation smoke checks pass.

Historical actionless events stay readable without changing their immutable
bytes/digests. New or revised events require an action. Old evaluation bindings
are invalidated by `finite-policy-v3-owner-attributes`, and definitions remain
protected author-controlled changes. The small author form now requires action
selection and offers a typed ordinary/required-attribute declaration. Native UI
rendering and accessibility have not been newly qualified.

A prose model can still misclassify an extraordinary action as ordinary or fail
to extract a material attribute. The engine validates the structured declaration;
labels are not a physical simulation. Such interpretation errors remain part of
source/prose review, not an excuse to claim arbitrary manuscript continuity.

## What still matters before sustained novel use

The [October 2 G02 applicability qualification](g02-action-applicability-verification.md)
now proves authored breathing/consciousness requirements on exact owners,
unknown evidence rejection, legal undead speech, another actor moving an
unconscious body, pre-event incapacity/restoration boundaries and retcon
invalidation. All twenty structured outcomes and the persistent MCP/history
audit pass. Action classification and exhaustive prose extraction retain the
separate review limits described below.

1. **Prove the intended writing host passes the instructions through.** The local
   test reads MCP initialization directly and passes its instructions to the MLX
   model. It does not qualify LM Studio's native function calling or its complete
   chat workflow. Test the actual chosen host/model with generation, validation,
   selected-prose commit, receipt recovery and fresh context in one conversation.
2. **Apply the verified provenance loop to the actual book.** The chapter pilot
   now links its declared material facts, events and knowledge to exact immutable
   sources, byte anchors and bound edition passages. Citation targets are typed,
   and research follows source-linked observations and passages. The authoring
   client must consistently apply those links to the book's full vocabulary and
   inspect unrepresented implications; the bounded pilot does not qualify
   unrestricted extraction. Author source staging is currently
   outside the 13 public MCP tools. Preserve that boundary unless an explicit
   product decision authorizes another integration.
3. **Broaden the accepted chapter/retcon pilot to the book's needs.** The local
   MLX run now exercises a three-scene chapter, a fresh-canon continuation, a
   deliberately invalid earlier retcon, corrected commits, old editions and
   restart recovery. Next test pronouns, aliases, interrupted
   scenes, flashbacks, retrospective narration, lies, conflicting testimony,
   off-page events, possession transitions, injuries, elapsed time, and a changed
   earlier event that invalidates later passages. Track affected passage IDs and
   outstanding decisions. Current conservative impact analysis helps enumerate
   canon dependencies; it does not prove manuscript-wide extraction coverage or
   rewrite chapters automatically.
4. **Establish a usable author's loop in the native workspace.** Confirm typed
   operations, proposal review, approval/delegation, commits, restart/draft recovery,
   source staging and backups with the author. Headless tests do not replace the
   pending native interaction/accessibility evidence.
5. **Measure the actual book's working set.** Context pages have a 65,536-byte
   maximum and source staging has a 512,000-byte maximum per text. Chapter-sized
   sources and explicit pagination are practical existing paths. A whole-novel
   source may exceed the text limit. Large provenance closures, sustained model
   coexistence and native response time remain separate profiling work.

The disposable chapter/retcon/restart pilot is complete within the existing
design. See [its executed evidence and source audits](chapter-retcon-verification.md).
The next acceptance work concerns the actual writing host and book vocabulary.
No automatic prose-to-canon importer, extra inference service, new publication
authority or expanded tool surface was introduced here.

## Verification and interpretation

| Executed check | Result |
|---|---|
| Locked workspace formatting, strict Clippy, tests and generated-contract drift | Passed; 256 tests, 0 failures, 1 explicitly ignored scale test |
| Independent JSON Schema validation | Passed; 26 schemas, 13 valid examples, 91 invalid examples |
| Independent stdio MCP smoke | Passed; 13 tools, 91 malformed requests, isolation, Unicode, restart/recovery and both negotiated protocol versions |
| Persistent installation smoke | Passed; concurrent startup, authentication, proposal/approval/commit, idempotency, current grants, revocation, SIGKILL recovery and durable heads |
| New model-harness regressions | Passed; 11 tests, including closed dispatch, malformed output, case scoring, inactive propositions and bounded explicit feedback |
| MLX workflow decisions | 8/8 correct |
| MLX prose assessment | 11/12 correct; **not a passing model qualification** |
| Selected prose publication and future impact | Passed; model-authored commit call, successful receipt, fresh state containing age 30, conflicting age 31 denied approval |

The exact completed evidence is
[the local MLX transcript](evidence/mlx-authoring-2026-10-01-run8.json).
It is a local ignored verification artifact, not a published document. Its
`status` is deliberately `model_failure` because one prose verdict was wrong,
even though the engine and commit checks succeeded. The ordinary Rust/Python
verification logs remain under `/tmp/universe-review-*` for this session.

Model: the locally installed
`froggeric/Qwen3.6-35B-A3B-Uncensored-Heretic-MLX-4bit`, executed directly with
MLX-LM on Metal, seed 42 and greedy sampling. Runtime versions were MLX 0.32.3,
MLX-LM 0.31.3+leila.1, Transformers 5.18.0 and jsonschema 4.26.0. No project
dependency was changed for inference. Weight files total 20,402,204,301 bytes;
individual SHA-256 hashes are in the report. No publisher revision was inferred
from the directory name. Model loading took approximately two seconds, and seven
generation turns took approximately forty seconds in total.

The missed case was “Iven knew the password” at day 18. Authored evidence states
that Iven does **not** know the password only for the half-open interval ending
at day 18. At day 18 the correct result is unknown. The model called it a conflict
and described expired password knowledge, misreading the negative evidence.
An earlier incomplete harness run also misread inactive custody propositions.
These observations support caution about temporal evidence interpretation; they
do not establish a flaw in the engine's correctly filtered assertion results.

The selected-prose operation initially contained an invalid extra tool wrapper.
No mutation was executed from that output. One explicit feedback retry produced
the correct operation; the later model-authored `universe_commit` call was valid
on its first attempt. The report retains both initial and repaired output.

The evaluation uses synthetic material
and an application JSON dispatcher. The model authors calls/operations; the host
validates them and executes MCP. Fixture author approvals apply only to the
temporary test universe. Production installations are untouched.

MLX output is measured separately from engine behavior. Schema errors are not
silently corrected into executable calls. Selected operations/calls may receive
one explicit feedback retry, recorded in the report; a repeated error fails the
run. Correct classification on a small fixture does not demonstrate exhaustive
language understanding.

The contradictory-source check deliberately records that a source-only candidate
can have complete validation with zero findings. This verifies the design's
source/evidence boundary; the structured contradictory claim is separately
detected and denied admission. Future continuity depends on committed structured
changes, not solely on preserved prose bytes.

Native UI/VoiceOver, the intended LM Studio host, clean-machine/offline startup,
hosted Intel CI, signing/notarization and the complete release matrix remain
unverified by this work. The opt-in 412,002-record workload was not rerun here.
Passing routine tests does not constitute distribution or full novel acceptance.
