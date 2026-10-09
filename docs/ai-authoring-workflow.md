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
and executed power evidence.

For G02, declare breathing, consciousness, mobility or other capabilities only
on the roles and actions that need them. Life, body and agency are separate
facts: an authored undead speaker can have speech capability, and a capable
actor can move an unconscious patient. Unknown capability evidence does not
authorize use. See the authoring requirements and applicability proofs
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
The canonical serving guidance is `crates/universe-mcp/src/instructions.rs`;
`crates/universe-protocol/src/request.rs` owns tool descriptions and schemas,
and `contracts/tools.json` is their generated snapshot. This operator guide
explains their use; it is not an additional system prompt. Approved decisions
control product meaning, and runtime code enforces authority and wire contracts.
Keep current user requests separate from attributed source text, tool results,
historical records and current time-scoped state when assembling model input.

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

The native state inspector presents these returned evidence lanes separately,
with the queried revision, represented context, world focus, time and coverage.
Shared definition attributes and initial-value candidates are not current stock.
Initialization history is shown with its own coverage; restricted receipts stay
concealed. Expand a row to inspect exact records, qualifications and references.

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

In native proposal review, validate and show the exact changes, then use
“Accept an unexplained resource count” to select the resource finding and enter
the author's rationale. Recording acceptance revises that proposal; it does not
approve or publish it. Validate and review the revision, approve it separately,
then commit. The count enters canon while its arrival remains unexplained.

After publication, recover a lost response with `universe_get_operation` and
the original commit idempotency key. Reopen context at the receipt's committed
revision and retrieve the affected object again before writing dependent prose.
Stale context or validation requires fresh retrieval, validation, and approval
as applicable.

## Prose and evidence

Source assessment attachments now participate in the complete publication path.
After freezing a submitted proposal, attach/select its exact assessment and review
all pinned pages. Completed validation binds that identity or explicit absence,
selection generation, submitted scope and assessment state. Author approval and
delegated commit require that exact final binding; replacement, withdrawal and
reselection require fresh validation and applicable approval. Private revalidation
and atomic publication check the same selection. Assessment conclusions remain
assessor declarations and do not add universal admission blockers. Fresh raw-source
and record publication remains available under the existing rules.

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

## Interactive local author writing checks

`scripts/author_session.py` checks author-entered writing against existing canon
using an installed MLX model and installation. Use a Python environment that
already contains `mlx`, `mlx-lm` and `jsonschema`; no models are downloaded.
Build current helpers and supply distinct existing author and agent profiles.
The agent needs read/propose permissions for the selected universe and grants
covering its proposed changes.

```sh
python scripts/author_session.py \
  --model /absolute/path/to/existing/MLX-model \
  --bin-dir /absolute/path/to/current/helpers \
  --installation /absolute/path/to/installation \
  --universe "Your universe" \
  --author-profile prf_EXISTING_AUTHOR_ID \
  --agent-profile prf_EXISTING_AGENT_ID
```

Enter multiline prose; a blank line submits it for automatic checking. `/quit`
between passages exits. The model uses the installed tokenizer's native tool calling
with canonical serving instructions and ordinary public MCP tools. It researches
pinned canon, then sends only plain factual deltas to `universe_check_changes`.
`universe_read_facts` returns named effective facts, exact property names, conflicts,
unknowns and authored clock metadata from the existing pinned state engine.
A successfully checked candidate ends the checking turn immediately; the session
returns the actual backend result without waiting for another model response.
The session renders actual checking results, including proposed additions, exclusions,
material questions and coverage; generated explanations cannot claim publication.
The engine resolves existing identities and property definitions, allocates new
records, and runs the existing proposal, validation and impact workflow. New
identities require explicit introduction intent. Existing facts reuse evidence.
Dialogue, beliefs, plans, hypotheticals and metaphor remain separate from objective
narration. Relevant ambiguity requires author clarification; unspecified scope or
time remains visible as an unknown without inventing defaults. Any unresolved
submitted or engine clarification holds the entire delta before creating a candidate;
held suggestions have no validation or impact result. Resubmit corrected changes
after the author answers.

Default MCP discovery includes this small change interface. Raw `universe_propose`
and `universe_validate`, plus raw `universe_get`, `universe_get_state` and
`universe_get_context` views, remain supported and are discoverable with the MCP server's
`--advanced-tools` flag. Ordinary callers do not construct internal domain records
or maintain proposal versions. They receive an opaque candidate handle and actual
engine findings. Changes remain incremental and uncommitted. A completed candidate
check requires evaluated validation and complete engine/impact coverage; restricted
or unsupported checks remain incomplete.

Structured tool results enter the conversation once. Author prose, tool decisions,
errors and retrieved evidence stay in memory; no transcript or report is saved.
Private author credentials stay outside model input. The adapter closes on exit;
the installation engine remains available to other clients.

The session reports concise additions, conflicts or material clarification. It
cannot approve, stage source bytes or publish canon; those author actions remain
unavailable. A candidate remains uncommitted, and the model's bounded interpretation
does not guarantee extraction of every implication in prose.

Local-model testing exception: the selected Qwen3.6 MLX model can guess ambiguous
owners, duplicate established identities, mishandle attribution and omit authored
knowledge dependencies even after canon retrieval. One bounded native reasoning-enabled
trial did not resolve these failures. These interpretation failures are accepted as
a testing exception for continued engine work; they are not passing model results,
product correctness claims or fictional resource/constraint exceptions. Full native
writing-loop qualification remains incomplete. Engine validation, permissions,
exact author approval and source provenance remain required.

Default limits are 20 model turns per passage, 3,000 generated tokens per turn
and 32,768 context tokens including the next generation. Configure them with
`--max-steps`, `--max-tokens` and `--max-context-tokens`. Two identical invalid
responses stop the passage check promptly. Limits and transport errors
leave checking incomplete; a context limit requires a fresh session.

Ordinary `universe_check_changes` also accepts `definitions` with an exact name,
explicit `introduce`, optional parent name, scope and `shared_attributes`. These
introduce reusable classifications; an omitted parent on a new type means a root.
`changes.classification` names the definition for a new instance or refines an
existing instance into an authored subtype, preserving its identity and state.
Existing ancestry cannot be rewritten through refinement. Unknown or ambiguous
names hold the delta for clarification. New scalar properties allow multiple
values; existing property definitions retain their authored semantics.

`universe_read_facts` accepts instance and definition names. It returns named
classification and ancestry, `inherited_attributes` separately from instance
`facts`, and initial-value candidates separately from both. Scope, time, restricted
visibility and unknown coverage still apply. Shared attributes do not create
instance-owned ammunition or other stock. Source preparation and exact approval
remain required before any definition/refinement becomes canon.

The local session also accepts private author commands. `/review` stages the exact
submitted passage (including any author clarification), binds its UTF-8 source
anchor to the factual candidate, and shows the actual compiled changes and fresh
engine findings, actual impact coverage and any validation limitations. Impact is
a conservative dependency closure; it does not identify every affected prose passage.
`/approve` explicitly approves and publishes only that exact
review. `/reject` withdraws the candidate without changing canon. Questions hold
the entire delta; answering in ordinary language triggers a fresh corrected check.

`/accept FINDING RESOURCE_SCOPE reason` records separate creative acceptance of an
exact current resource-accounting finding. The engine preserves its unexplained
arrival and reruns validation and review; acceptance does not waive structural
constraints or grant publication approval. Other unsupported issues remain blocked.

If publication is interrupted, `/retry` uses the same operation key. The printed
`/recover TOKEN` command also recovers that original operation after session
restart; it carries exact review bindings, not credentials. Successful publication
clears old pinned research, requiring fresh canon retrieval before continuation.
Author commands use `universe author-writing UNIVERSE` with a private JSON decision
on standard input. These actions are never exposed as model tools; author credentials
remain outside inference. No conversation transcript is saved.


## Local MLX verification

The opt-in evaluator uses an already installed model with MLX-LM on Metal. It
creates a temporary installation, a temporary author and agent, and a small
synthetic universe. It reads the actual initialization instructions; the model
fills a schema-checked requested research call, classifies prose candidates and
workflow scenarios, and returns supplied structured proposal operations. The
independent host executes the MCP calls. This uses application JSON dispatch, not native
function-call parsing or an LM Studio session.

The harness checks custody immediately before, at and after an exclusive interval
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
  --report /tmp/mlx-authoring-new-run.json
```

These commands are historical opt-in entry points, not evidence of a current
model run. Their operation shapes and protocol-3 validation, approval and commit
handling are covered by focused deterministic contract regressions against
disposable engines. Build the current engine, CLI and adapter, then run
`python -m unittest discover -s scripts -p 'test_pilot_contracts.py' -v`. These
tests retain source prose only as temporary application fixtures and write no
reports or transcripts. They do not establish model behavior. The scripts save
prompts, outputs and reports, so running them requires an explicit request for
those artifacts under AGENTS.md. Ordinary review uses the existing focused
harness tests without saving transcripts.

The system message now uses the actual MCP initialization instructions unchanged.
The user message supplies the task, response choices, schemas and retrieved
state. Expected verdicts stay in host-side scoring; model-visible case IDs are neutral
so identifiers do not disclose the expected answer. Verdicts measure
bounded classification under those supplied inputs, not open-ended writing or
native host behavior. No wrong verdict is repaired into a correct score. Earlier
descriptive case IDs and case-specific reminders supplied verdict cues; prior
scores therefore do not establish independent classification.

Exact operation and commit-call turns are directed execution: templates provide
the operation or arguments, and one feedback retry can provide the exact answer.
They are recorded as directed execution and excluded from independent-decision
scores, including successes after answer-supplying feedback. Their success
establishes response/call mechanics only. Earlier descriptions of
these turns as model selection, discovery or independent authoring are invalid.
Runtime rejection, persistence and receipt recovery remain separate observations.
No new model results are established by an editorial prompt change; previous runs
used their original prompts and cannot qualify the revised serving path.

## Chapter and retcon pilot

`scripts/chapter_retcon_pilot.py` exercises the real persistent engine with three
chapter scenes and a continuation. The local MLX model generates directed prose,
locates excerpts for a supplied material-change inventory, reviews provisional
continuity and returns supplied research, proposal, validation and commit calls.
The host compiles a declared story vocabulary into existing typed operations;
tool-call arguments are template-assisted. This is not an unrestricted prose importer. Private author source staging and exact
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
  --output /tmp/chapter-pilot-new
```

The model receives authored story beats and required extraction categories.
These are legitimate writing and excerpt-location tasks, but they cannot establish
independent selection of events, knowledge or material claims. Positive review
is checked by the host outside model input; it is not authority to publish. Earlier
review prompts also supplied case-specific remedies, limiting any independent
judgment claim. Those prompts have been simplified; no revised model run is
claimed. Existing deterministic checks exercise graph, source and recovery
mechanics, not conversational judgment. The pilot still uses a specialized
context transformation (`pilot_evidence.focused_evidence`) alongside raw MCP
results; its results cannot qualify an unmodified host context path.

The pilot saves reports and transcripts. Execute its report-producing commands
only on an explicit request for those artifacts. Pure extraction regressions
remain available without a model or saved substantiation.

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
assessed prose. See retrieval proofs.

## Declared knowledge acquisition: Goal 40

Use an explicit context `knowledgePolicy` on a blocking rule to choose
`author_established` or `justified`. A `knows` attitude then declares `acquisition`
with its truth context and exact authored time. Direct author establishment uses
its distinct typed basis and an attributable author decision. Justified receipt
names a communication and an explicit interpreted proposition; provide an actual
holder recipient, content, receipt and matching channel chronology rule. The
service checks supported truth at acquisition and acquisition before or at knowledge
onset. Receipt alone does not infer understanding, and false belief stays belief.

Unknown truth, interpretation, policy or comparable clocks stays unresolved;
refuted acquisition cannot be approved into publication. Correct earlier facts
with exact version bindings and resolve dependent knowledge in the same candidate.
Historical reads retain the old facts. See the contract and executed proofs
for supported shapes, legacy behavior and native editing limits.

## Repairing factual constraint proposals

Retrieve the applicable policies and evidence before proposing changes. Use
`universe_describe` for capabilities, `universe_search` for authored rule names,
and `universe_get_context` focused on the knowledge holder, proposition or relation
key. Follow all cursors. Authorized context includes relevant communication links
and the relation assertions needed to check an authored maximum across instances.
Rule applicability in `universe_get_state` includes typed policy context and scope;
applicability alone does not certify an action or establish complete knowledge.

An author-visible validation finding provides `message`, `records` and exact
version `evidence`. Retrieve committed records with `universe_get` at the same
frame. For records introduced by the proposal, inspect `universe_get_proposal`
compiled changes. Missing truth, interpretation, recipients, scope or comparable
time stays unresolved; the message identifies which authored dependency needs
attention. A receipt needs an explicit interpreted proposition to justify knowledge.

The native action editor declares consequence slots separately from attribute
requirements. Choose required or permitted presence, an owning role, target
property, an always or attribute-equality condition, and a fixed assignment or
bounded resource delta. Delta amounts and stock bounds use exact whole-number
strings; quantity units must match the property exactly. Declare both sides of a
transfer explicitly. Fixed assignments can last until changed or for positive
calendar ticks; deltas last until changed. Ordinary actions can explicitly permit
no effects. Definitions follow the protected draft, review and approval workflow.

The native event editor uses the selected action’s declared roles and slots.
Assign each participant and explicitly include or omit each effect. Supply a new
typed value or an existing proposition, the represented context and world scope,
an authored timestamp and exclusive end, polarity and declared order. Resource
effects require explicit post-event whole-number balances in the contract’s exact
unit. A reload with reserve consumption needs both declared effects; the editor
does not compute balances or invent a reserve. Review the resulting propositions
and event together before publication. Changing actions clears role assignments
and effect inputs.

To correct a consequence-bearing event, inspect it and load its authored
references at the pinned revision. The same event controls retain the original
action, participants, time and effects, and preserve additional labels, sequence,
occurrence identity and preconditions. The draft uses `revise_event` bound to the
loaded record version. Review the returned dependency context and add coherent
dependent-event corrections to the same proposal; an isolated earlier balance
change may invalidate later events. Generated assertions are rebuilt by event
recompilation and cannot be directly edited or restored in the inspector.
Earlier revisions remain readable. Unsupported clocks or effect validity block
loading for editing and retain the original event.

To require knowledge for an action occurrence, author the existing attitude
expression in the event's `preconditions`. The action definition's scalar attribute
requirements still apply separately. Acquisition must follow receipt, supported
truth must hold at acquisition, and knowledge must exist before the event. Correct
an earlier fact using exact version bindings, then repair dependent acquisition,
knowledge onset and event timing together. Use `universe_propose` with
`action:"revise"` and fresh context to repair a held proposal, revalidate it and
obtain approval for its exact revised reference. An earlier canon correction makes
old approved proposals stale; historical reads do not certify the current head.

For an authored maximum, simultaneous distinct participants can exceed the limit;
sequential participants and repeated evidence for the same participant do not.
Repair the participant, scope or validity evidence, or explicitly revise the authored
rule. Multiplicity within one relation remains separate. Minimum counts,
completeness inference and clock conversion remain deferred.

Restricted validation retains its redacted response and cannot authorize a commit.
Use authorized context and evidence retrieval, then request author validation of
the exact proposal reference. Restricted diagnostics do not reveal hidden findings
or promise that visible evidence is complete.

The native policy editor offers **Communication chronology**, **Knowledge basis**,
**Maximum relation participants**, and **Resource accounting** as explicit opt-in
choices alongside the existing rule, boundary and complete-set forms. Chronology takes a channel,
forward or signed-delay order, and optional inclusive integer-tick delay bounds.
Knowledge basis selects an existing truth context and author-established or
justified interpreted-receipt knowledge. Maximum cardinality selects a relation,
its declared grouping/counting roles (or subject grouping), an unsigned maximum,
world/context/optional realm scope, and unrestricted, instant or interval validity.
Resource accounting selects a single integer or exact-unit quantity property and
requires accounted transitions or exact author acceptance of unexplained changes.
It applies to that property across the universe and infers no arrival or cost.
Exact validity uses the selected context's authored clock. These forms keep the
supported blocking wrapper fixed; they do not offer minima, clock conversion,
automatic understanding or generic rule exceptions. Added policies remain drafts
until normal validation, exact author approval and publication. Activating a policy
rechecks existing facts and can require dependent evidence to be repaired first.

The native knowledge form requires an explicit acquisition path for **Knows**:
author establishment or interpreted communication receipt. Choose the truth
context, acquisition time and optional truth world; for a receipt, explicitly
choose the message and interpreted proposition. Acquisition and attitude onset
use that context's authored clock. Belief, suspicion, rejection and memory stay
separate and do not acquire knowledge automatically. Messages and propositions
in the current draft can be selected before publication.

The native **Communication and delivery** form records a sender, separate
intended and actual recipients, proposition content, channel, authored send and
receipt times, and distortion. Unchecked recipients stay absent; an unspecified
time stays unspecified. Review and publish messages through the ordinary draft
workflow. Published messages load into the knowledge-acquisition selector when
the current revision is opened. Delivery alone never adds knowledge. An active
channel chronology rule can block reversed or unresolved delivery.

Native review shows the existing finding guidance, policies, affected record
references and exact evidence versions. Authorized draft metadata identifies
related holders, messages, propositions and relations. Inspect those records,
remove and replace the affected draft operation, then revise and validate again.
A canon correction requires reopening the current context and rebasing the draft;
old approval does not carry over. Restricted validation shows only fixed guidance
for requesting authorized author review. Automated form and connected service
checks do not qualify manual native interaction, which remains pending.

The native type form introduces a reusable definition with an explicitly selected
parent (or no parent), applicability and executable classification setting.
Unspecified applicability stays unresolved; selecting no worlds applies nowhere.
Each ancestor's applicability still matters: a child does not widen its parent.
Pending definitions remain selectable in the same draft and survive draft recovery.

Attribute authoring now distinguishes current instance facts from definition-owned
shared attributes and initial-value attributes. Select an instance for the first
mode or a definition for the other two. All modes retain typed values, authored
scope, validity, precision, alternatives, polarity and basis. Shared attributes
remain reusable definition facts; initial values remain candidates for explicit
reviewed initialization. Neither mode creates or refills current instance stock.
Conflicting applicable values require correction before admission; a descendant
or newer assertion does not silently override an inherited value.

The native initialization control selects an instance, an approved initial-value
assertion and an exact occurred event containing that instance. The preview pins
the source assertion version and begins validity at the event's time; scope and
an exact exclusive or explicitly unbounded end are authored choices. Selected
worlds are inspected separately at the pinned revision. The preview separates the
proposed starting fact, shared attributes, existing instance facts, candidates,
conflicts and initialization receipts before adding the operation to the draft.
Publish the source and start event before selecting them in this control.

Initialization follows normal proposal validation, review, approval and
publication. Draft recovery retains the selected version, scope and validity.
Conflicting or unresolved candidates cannot initialize an instance. Existing
receipts prevent a second initialization of the same instance property across
retry, naming changes, classification refinement and restart. A starting fact
belongs to its instance; changing a reusable initial value does not refill stock.

A connected native stock workflow starts by publishing the reusable object,
stock property, action contracts and opted-in resource policy. Publish its
initial-value source and occurred start, then initialize each instance separately
with an authored validity interval. Record consumption and replenishment with
explicit post-event balances, including any declared reserve debit. Inspect the
fresh effective state before acting on it. An inventory count without an accounted
transition requires exact author acceptance and still carries unexplained arrival.
Correct earlier events and dependent balances in the same reviewed proposal;
initialization receipts, original revisions and separate instance stock remain
available. Draft save/recovery, review, validation, approval and publication use
the same workflow throughout.

The ordinary writing tools also accept occurred actions, attributed messages,
separate epistemic attitudes, and corrections to pinned authored fact handles.
`universe_read_contracts` presents visible action roles, requirements and effects,
knowledge policies, channel chronology and attributed communications. Event
balances use the existing consequence evaluator; callers supply factual intent,
not generated post-state records. Explicit fact/attitude lifetimes are supported;
missing lifetime is not an invented stock interval. An explicit `at_tick` supplies
authored scene time on the selected context's declared calendar, including when
the research frame is timeless; no missing tick defaults to the current time. Interpretation alone never
establishes knowledge. The ordinary path supports justified communication receipt;
author-established knowledge still needs its separate actual author decision.

Private source preparation admits these factual operation kinds, preserves
`source_anchor` evidence on assertions/attitudes/corrections and `event_effect`
evidence on generated event assertions. Events and messages share the exact staged
source and reviewed atomic editorial commit; their existing records have no direct
anchor field. This does not establish per-record citation or complete prose mapping.
A correction preserves original assertion scope/time and checks subsequent actions
and knowledge through existing validation and impact. Generated event facts cannot
be corrected directly.
