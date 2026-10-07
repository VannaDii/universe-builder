# Writing with Universe Builder through MCP

## Owning entities, attributes and declared actions

Research attributes on the exact owning entity, at the passage's story time and
in its represented context/world. Keep their authored validity and persistence;
do not borrow a companion's value, infer a default from missing evidence, or
forget a continuing attribute merely because it was not mentioned in the last
scene. A canonical change must explicitly end, replace or refute the old value.
Expired or unknown evidence is unresolved, rather than proof of suppression.

Every new or revised event names an `action_definition`. Use `define_action`
to declare mandatory `requirements`: each contains a participant `role`, typed
property `predicate` reference and required `value`. Definitions require existing
protected authority. Each required role must resolve to exactly one individual
or object; optional event prerequisites cannot replace that owner's requirement.
Ordinary actions explicitly have an empty requirement list. Never classify wall
traversal as ordinary just to avoid its declared phase-power requirement.

The engine checks the pre-event state before applying effects. Direct attribute
assertions and explicit possession-dependent grants use the same evaluator.
An item grants only its declared recipient the defined value while custody and
grant validity hold. Explicit owner-specific refutation suppresses an indirect
grant; a supported Boolean false suppresses a granted Boolean true. Suppression
on another entity does not apply. Ending a suppression interval restores only a
grant that is still supported, not a lost or expired power.

Existing actionless history remains readable; new/adopted/revised events need an
action declaration. Existing validations/approvals from an older evaluator must
be refreshed. See [the approved decision](adr/ADR-0006-declared-actions-and-owner-attributes.md)
and [executed power evidence](novel-authoring-readiness.md#wall-traversal-and-declared-powers-october-2-verification).

For G02, declare breathing, consciousness, mobility or other capabilities only
on the roles and actions that need them. Life, body and agency are separate
facts: an authored undead speaker can have speech capability, and a capable
actor can move an unconscious patient. Unknown capability evidence does not
authorize use. See the [authoring requirements and applicability proofs](g02-action-applicability-verification.md)
for exact incapacity/restoration boundaries and retcon invalidation.

## Prose verification and canon commits

Draft prose remains provisional until its material continuity claims have been
checked. When the author chooses to use that prose, commit its universe changes.
**Only a successful `universe_commit` makes those changes canon.** Research,
source staging, proposals, validation, impact analysis and approval do not.

The persistent MCP server advertises this workflow during initialization and in
the relevant tool descriptions. Those instructions guide an external AI; the
engine independently enforces its supported validation and commit rules. An MCP
host must pass initialization instructions to its model for them to have effect.

## The authoring loop

1. **Research before accepting prose.** Name the universe on every call. Open a
   context pinned to the intended continuity and revision. Retrieve relevant
   entities, rules, boundaries, negative evidence, appearances and dependencies
   with `universe_search`, `universe_get` and `universe_get_context`. Follow every
   required page. Read `universe_get_state` at the scene's authored story time.
   Choose the correct represented context and author, character, narrator or
   reader perspective; author knowledge is not automatically character knowledge.
2. **Express the continuity consequences.** Draft externally, then create
   structured operations for the material facts and changes in the prose. This
   can include identity, attributes, relationships, possession, occurred events,
   event prerequisites/effects, time, knowledge acquisition, narrative references
   and reader disclosure. An unchanged established fact can simply be checked
   against its evidence; it does not need a duplicate assertion. Unestablished
   material facts need an explicit proposal or author decision, not invention
   presented as existing canon. Dialogue, reports, lies, beliefs and hypotheticals
   keep their represented context and do not automatically become objective facts.
3. **Validate the candidate.** Submit the exact operations with
   `universe_propose`, then use `universe_validate`. Proposal admission uses an
   author-perspective, timeless/all-validities frame; this prevents a scene-time
   filter from hiding contradictions elsewhere. Scene research still uses the
   intended story time. Inspect findings, coverage and unsupported capabilities.
   A complete evaluation can contain a blocking conflict. Correct contradictions
   or use the existing explicit, scoped author-decision/exception mechanism.
   Do not call a candidate continuity-verified while a material gap is unresolved.
4. **Check impact.** Use `universe_get_impact` for the same proposal. Consider its
   dependency footprint before using it. Current impact is conservative across
   the universe; it is not a manuscript editor that automatically rewrites earlier
   chapters. Keep affected passages and changes visible to the author.
5. **Commit selected prose's changes.** Once the author chooses to use the
   verified prose, call `universe_commit` with its exact proposal reference,
   expected base revision, validation run and a stable idempotency key. The engine
   requires current edit authority and either exact author approval or an existing
   bounded delegated-commit grant. An ordinary edit grant is not delegation.
   The AI cannot manufacture approval. This is the existing engine boundary,
   not a new review requirement added by these instructions.
6. **Confirm and continue from canon.** Keep the successful receipt, reopen
   context at the committed revision, and re-query the affected state. Future
   writing must use that revision so the committed changes carry forward.
   If a commit response is lost, use `universe_get_operation` and the original
   idempotency key; do not invent a receipt or blindly submit a new mutation.
   A changed proposal or canon head requires fresh validation and the applicable
   approval. A candidate awaiting approval is still a candidate.

## Retrieve and record factual state

For an object-level question, use `universe_get_state` at the scene's intended
time and represented context. Inspect the returned object evidence, including
ancestry, shared attributes, instance facts, initial-value candidates, behavior
requirements, dependencies, conflicts, unknowns, and coverage. Follow every
page. A proposition is claimable vocabulary, not proof that its value is true;
check the supporting assertions, polarity, scope, validity, provenance, and
unresolved evidence. Restricted or incomplete coverage does not establish
absence. Request authorized access or ask the author before relying on missing
evidence.

For genuinely new facts, `universe_propose` supports `introduce_definition`,
`introduce_instance`, `add_named_attribute`, and `refine_classification`.
Supply only known identity, names, scope, time, precision, and evidence basis;
unknown values remain unknown. Shared definition attributes and instance facts
are distinct. Classification refinement retains identity and is not a physical
transformation. Existing advanced record operations remain available for
explicit corrections and event-linked changes.

An initial-value definition is only a candidate. To establish starting state,
use `initialize_instance` with its exact assertion version, an occurred start,
and the requested scope and interval. Review, validate, approve, and commit it
through the same publication path. The resulting instance assertion and durable
receipt are separate from the definition candidate. Mentions, renames, holder
changes, definition edits, and process restarts do not initialize again. A
conflicting or unresolved applicable candidate requires an author resolution.

When an opted-in `resources.accounting.v1` rule finds a stock change without a
declared event or a coherent correction, keep the clarification unresolved and
ask the author. Do not invent an event or infer a cause. If the author explicitly
accepts the unexplained count, record an `IssueDecision` for the exact finding
fingerprint and `resource:<proposition record ID>` scope. This scoped creative
decision permits the count while retaining its unexplained marker; ordinary
proposal approval does not answer the factual question. If the claim or its
predecessor evidence changes, retrieve and validate again and obtain a fresh
decision.

After publication, recover a lost response with `universe_get_operation` and
the original commit idempotency key. Reopen context at the receipt's committed
revision and retrieve the affected object again before writing dependent prose.
Stale context or validation requires fresh retrieval, validation, and approval
as applicable.

The [Goal 35 resource-resolution verification](resource-resolution-verification.md#goal-35-external-writer-workflow--october-6-2026)
records one real-MCP run from incremental facts and reviewed initialization
through restricted retrieval, unresolved clarification, exact scoped acceptance,
restart recovery, and fresh canon. The existing
[effective-object](effective-object-verification.md) and
[instance-initialization](instance-initialization-verification.md) proofs remain
additional focused audits. All are scripted protocol evidence; they do not
establish that a model will correctly interpret arbitrary prose or follow the
advertised instructions.

## Prose and evidence

Source assessment attachments now participate in the complete publication path.
After freezing a submitted proposal, attach/select its exact assessment and review
all pinned pages. Completed validation binds that identity or explicit absence,
selection generation, submitted scope and assessment state. Author approval and
delegated commit require that exact final binding; replacement, withdrawal and
reselection require fresh validation and applicable approval. Private revalidation
and atomic publication check the same selection. Assessment conclusions remain
assessor declarations and do not add universal admission blockers. Fresh raw-source
and record publication remains available under the existing rules. See
[executed publication proofs](assessment-publication-verification.md).

Preserve exact used text through author source staging in the desktop or CLI.
Link each material change to its exact immutable source version and supporting
passage anchor before using it to continue the story. Source staging
returns operations; it does not publish those records. Commit the source evidence
and the material semantic changes together when practical.

An anchor names the exact source record version, a UTF-8 **byte** range, the
verbatim excerpt and its SHA-256 digest. Do not normalize punctuation, Unicode or
line endings after choosing the source. Assertion and explicit knowledge records
use `source_anchor` evidence. Occurred events can be cited through legitimate
sourced observations and scenes' `depictedEvents`; generated event assertions
retain their sealed `event_effect` basis. Do not invent an observer to attach a
citation. A `PassageRef` links the anchor to an exact `WorkVersion`; that edition's
binding pins the continuity and committed semantic revision it depicts.

The engine checks that source citations and passage anchors target actual anchor
records, and checks their excerpts against the exact source bytes. Research
follows observations, depicted-event scenes and anchored passages alongside facts
and knowledge. Exact citations establish identity and traceability; they do not
establish that the excerpt supports the claimed interpretation.

For an earlier-story retcon, inspect impact and follow facts/events/knowledge to
their source anchors and passage references. The current impact result is a
conservative universe-wide set; determine the affected passages from the explicit
evidence links rather than claiming every returned passage must change. Correct
dependent event times, effect intervals, state assertions and knowledge evidence
as one validated semantic candidate. Preserve the old source and bound edition,
stage a new source and create a new bound edition. Historical revisions retain
the old state and evidence. Never overwrite the original text to disguise a
contradiction or carry an earlier approval across a changed canon head.

Source bytes alone cannot constrain future story facts. For example, importing
“Mara was thirty years old” preserves text, but a structured age assertion is what
lets a later age claim produce a conflict. Conversely, committing a lie as source
evidence must not establish the lie as objective truth.

`universe_get_state.propositions` is a catalogue of claimable statements, not a
list of true facts. Evidence comes from the returned assertions, their polarity,
scope, validity, unresolved IDs and supported derivations. The catalogue can
include propositions whose assertions are inactive at the requested time.

Delivery completeness, research coverage, semantic validation and publication
are distinct. Never treat `delivery.complete`, a complete context brief, zero
reported findings under restricted coverage, or an imported source as a canon
commit or as an unrestricted continuity certificate.

## Local MLX verification

The opt-in evaluator uses an already installed model with MLX-LM on Metal. It
creates a temporary installation, a temporary author and agent, and a small
synthetic universe. It reads the actual initialization instructions; the model
authors a schema-checked research call, classifies prose candidates, chooses
workflow actions and authors structured proposal operations. The independent
host executes the MCP calls. This uses application JSON dispatch, not native
function-call parsing or an LM Studio session.

The test checks custody immediately before, at and after an exclusive interval
end; correct and conflicting appearance; unknown facts; expired ignorance;
negation; dialogue and hypotheticals; unapproved commit rejection; typed conflict
rejection; and the distinction between source validation and semantic claims.
It then commits a selected passage and its age assertion, retrieves the new canon
and verifies that a later contradictory age claim is blocked.

Build the current helpers and use an interpreter containing compatible `mlx`,
`mlx-lm`, `transformers` and `jsonschema` installations:

```sh
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp
python -m unittest discover -s scripts -p 'test_mlx_authoring_smoke.py' -v
python scripts/mlx_authoring_smoke.py \
  --model /absolute/path/to/existing/MLX-model \
  --report docs/evidence/mlx-authoring-new-run.json
```

Use a fresh report path for each run. The test refuses to overwrite evidence and
does not download models, edit host settings or touch production packages.
Reports include model weight digests, runtime versions, prompts and model outputs,
timing, MCP responses, commit receipts, scores and errors. `pass` means the named
synthetic checks passed; `model_failure` means at least one model verdict/action
was wrong; `error` means execution did not complete. A failure never counts as
successful qualification. Temporary engines are shut down before cleanup.

Operation and commit-call checks use supplied fixture templates to measure exact
tool use. They allow one explicit feedback retry, retaining both outputs. This
does not qualify automatic extraction of arbitrary prose. Sentence verdicts and
workflow decisions are scored separately, with no correction of wrong answers.

Fast harness tests run in CI without a model. MLX inference is opt-in so ordinary
CI does not require Metal or download model weights. See the
[readiness assessment](novel-authoring-readiness.md) for executed evidence and
remaining limits.

## Chapter and retcon pilot

`scripts/chapter_retcon_pilot.py` exercises the real persistent engine with three
chapter scenes and a continuation. The local MLX model generates prose, extracts
exact excerpts, reviews provisional continuity and selects research, proposal,
validation and commit calls. The host compiles a declared story vocabulary into
existing typed operations; tool-call arguments are template-assisted. This is
not an unrestricted prose importer. Private author source staging and exact
approval apply solely to the disposable synthetic novel.

The story changes custody of a key, opens a door, establishes a map route and
records who learns the password and route. The continuation uses fresh committed
context. A deliberate delayed handoff invalidates a later opening; the pilot
checks its rejection, traces affected passages, moves the dependent chronology,
commits a corrected edition and checks original and revised timelines separately.
Character knowledge is queried in each holder's represented context. Cross-context
knowledge is checked by explicit timeline regressions: current event prerequisites
cannot directly evaluate an attitude in another represented context.

The reproducible deterministic regression runs in CI without MLX. It checks
persisted source/anchor/passage/evidence links independently, malformed citation
targets, altered excerpt digests, stale approved commits and durable receipt
recovery after terminating only its owned engine.

```sh
python -m unittest discover -s scripts -p 'test_chapter_retcon_pilot.py' -v
python scripts/chapter_retcon_pilot.py --regression --output /tmp/chapter-regression-new
python scripts/chapter_retcon_pilot.py \
  --model /absolute/path/to/existing/MLX-model \
  --output docs/evidence/chapter-pilot-new
```

Use a new output directory each time. Reports retain the complete prompts, raw
outputs, explicit feedback, calls, actual validation failures, author reviews,
approvals' exact references and successful receipts. The output text files remain
external writing artifacts; only the committed structured records become canon.
See [chapter pilot evidence](chapter-retcon-verification.md) for executed results.

## Exact source assessment review

After attaching or selecting an assessment, retrieve `universe_get_proposal`
with the frozen proposal ID/version and `view_group:"assessment"`. Selection and
state describe the current attachment; an optional exact `assessment_reference`
retrieves authorized history without changing selection. Follow all cursors. For
fragmented delivery concatenate `canonical_envelope_utf8` by UTF-8 byte offset,
require complete delivery, decode the envelope and independently verify its
body digest. Review the declared source ranges, inventory, mapping links,
exclusions and unresolved material. A fragment alone is not an assessment body.

Replacement, withdrawal, reselection or changed authority invalidates old cursors.
Restart retrieval under current access instead of combining obsolete pages.
Historical attachments remain exact history; their declared conclusion does not
certify current canon or promote the existing record-only validation result into
assessed prose. See [retrieval proofs](assessment-review-verification.md).
