# Goal 34: factual constraint decisions

Status: decision package prepared. No semantic change is approved by this
document. Product boundary follows the [factual universe realignment plan](../factual-universe-realignment-plan.md): the author defines the universe and its rules; the external writer interprets prose; MCP validates submitted facts and declared constraints without inferring unauthored laws.

## Current implementation and authored-expression fit

| Question | Current behavior | Do existing authored expressions suffice? |
|---|---|---|
| Knowledge acquisition (G06) | `EpistemicAttitude` stores holder, proposition, attitude, validity and evidence basis. Validation checks holder and proposition kinds. `Expr::Attitude` matches an exact authored attitude. The service explicitly says receipt/presence does not infer knowledge and automatic perception, interpretation, nested attitudes and memory decay are unsupported. It does not bind `Knows` to a justified acquisition path or test the target proposition in the declared truth context. | No, for a declared policy that distinguishes justified knowledge from belief. Exact authored attitudes remain sufficient when the author is directly establishing an attitude; arbitrary acquisition-chain inference is outside scope. |
| Communication chronology (G07) | A communication stores sender, intended and actual recipients, content, channel, sent time, optional received time and distortion. Admission requires a receipt time when actual recipients are named. It does not compare sent and received times, apply channel rules, or correlate a receipt with an attitude. Temporal expressions compare explicit operands, but current records do not expose communication events as a general constraint binding. Independent calendars have no inferred synchronization. | Partly. Exact authored time comparisons suffice for a finite, explicitly authored check on comparable clocks. They do not express a reusable per-channel transmission policy or safely infer acquisition from delivery. |
| Cross-instance cardinality (G08) | A relation role has per-relation-instance multiplicity. Validation can reject competing values for a single/exclusive property on one subject. `Expr::Cardinality` counts a finite expression collection; it does not aggregate matching relation instances from the candidate universe by role, scope and overlapping validity. | No, for a reusable max/min count over distinct participants across relation instances. A fixed explicitly enumerated collection can be counted, but it is not a dynamic relationship constraint. |

The historical public-workflow stimuli are maintained in
`scripts/continuity_gap/cases.py`: G06
submits `Knows` for a refuted proposition without an acquisition chain; G07
submits an ordinary letter received before it was sent; G08 submits two
simultaneous counterparts despite a single role declaration. The historical
baseline classifies these as gaps, not established product defects. The
corrected boundary means each is a gap only if the author declares a relevant
constraint.

## Smallest contract proposals if approved

These are recommendations for decision, not implementation instructions.

### K1 — Authored knowledge basis policy

- **Author-controlled meaning:** per applicable world/context, author chooses
  whether `Knows` means directly author-established, or requires a declared
  justified basis. Belief, suspicion, rejection and memory remain distinct.
- **Required facts:** holder, proposition, validity, represented truth context,
  acquisition time, and one explicit basis: author-established; interpreted
  observation with sensory access; or actual communication receipt plus
  authored interpretation. Distorted content alone does not establish
  interpretation.
- **Admission:** enforce only when the authored policy applies. Under justified
  mode, require basis before the attitude's validity begins and compatible
  supported evidence for the proposition at acquisition. Do not infer that a
  false belief is knowledge. Do not require an acquisition chain in
  author-established mode.
- **Uncertainty:** unknown truth, sensory access, interpretation, receipt,
  clock relation or policy applicability yields unresolved/partial coverage;
  it does not promote a belief or silently fail open under a blocking policy.
- **Correction impact:** corrections to proposition evidence, observation,
  communication, recipient, interpretation, context or time invalidate the
  dependent knowledge validation and downstream event validations. Historical
  revisions remain queryable against their old bindings.
- **Independent acceptance examples:** (1) justified knowledge after an
  interpreted received message is admitted; (2) the same knowledge before
  receipt is blocked; (3) explicit false belief is retained and admitted as
  belief; (4) unknown truth or uninterpreted/distorted content stays unresolved;
  (5) author-established omniscience is admitted only where that policy is
  authored.
- **Authoring tradeoff:** authors choose direct establishment or justified
  acquisition and provide interpretation/receipt evidence where required.
  This adds work for inferential knowledge while retaining direct assertions
  where the author intends them.

### K2 — Channel chronology policy

Goal 39 authorizes the bounded implementation and proof in communication chronology verification. The original probes and decision wording below retain their historical scope.


- **Author-controlled meaning:** named channel rules declare whether sender to
  recipient order must be forward, a minimum/maximum delay, or an explicit
  exception such as reverse-time transmission. No universal ordinary-world
  physics is assumed.
- **Required facts:** channel identity and rule version, sent time, actual
  recipient and receipt time, clock identity, and an explicit clock mapping
  when the times use different calendars. Intended recipient, actual recipient
  and sender remain separate.
- **Admission:** check comparable exact times against the applicable authored
  rule. A message without a receipt remains sent/unreceived; it cannot support
  acquired knowledge. A reverse-time message is legal only under an applicable
  authored rule.
- **Uncertainty:** missing channel rule, unresolved time, or unmapped clocks
  gives unresolved coverage where the policy matters. Do not synthesize a
  conversion or delivery time.
- **Correction impact:** changing channel rule, send/receipt time, recipient or
  clock mapping invalidates chronology findings and linked knowledge and
  actions. Preserve old revision results.
- **Independent acceptance examples:** (1) forward send then receipt on one
  clock passes; (2) reversed order under a forward-only rule blocks; (3) the
  same reversed order under an explicit reverse-time rule passes; (4) an
  unreceived message cannot establish knowledge; (5) two unmapped calendars
  remain unresolved.
- **Authoring tradeoff:** authors define rules only for channels where order
  matters and record clock mappings for cross-calendar comparisons. This keeps
  exceptions genre-controlled while requiring more explicit timeline data.

### K3 — Scoped relation cardinality

- **Author-controlled meaning:** a named rule selects a relation definition,
  counted role or participant key, minimum/maximum, world/context scope,
  validity window and any authored exceptions. It does not change local
  multiplicity on one relation instance.
- **Required facts:** supported relation instances, role participants,
  validity, world/context, rule applicability and completeness where a
  negative/minimum conclusion depends on absence.
- **Admission:** aggregate distinct participants for the key over applicable
  overlapping relation instances. Deduplicate repeated evidence for the same
  participant. Reject only a definite bound violation under the rule.
- **Uncertainty:** unresolved validity, conflicting participant identity,
  incomplete relevant membership or unresolved rule applicability yields
  unresolved coverage, never a guessed count. Sequential non-overlapping
  assignments do not violate a simultaneous bound.
- **Correction impact:** changes to any applicable relation, participant,
  validity, context/world or rule revalidate all affected counts. Historical
  counts remain bound to prior revisions.
- **Independent acceptance examples:** (1) two distinct simultaneous
  successors violate max-one; (2) sequential successors pass; (3) repeated
  evidence for one participant counts once; (4) multiple spouses pass under an
  authored max-two rule; (5) unknown overlap remains unresolved.
- **Authoring tradeoff:** authors choose participant key, scope, validity and
  completeness where minimum counts depend on absence. This is more setup than
  local role multiplicity, in exchange for defensible global bounds.

## Original continuity scenarios

| Scenario family | Supported behavior or remaining gap |
|---|---|
| G06 impossible knowledge; R01 retrospective narration | Explicit attitudes and represented contexts are supported; automatic knowledge inference and chronology linking are not. Reader and acting-character contexts must stay distinct. |
| R02 lies, dreams, visions and embedded stories | Represented contexts, belief and memory families exist. Objective truth promotion across contexts is not inferred; author records or an accepted external interpretation remain necessary. |
| R04 body swaps, possession, clones; R05 amnesia and false memories | Identity, memory and attitude records are explicit, but ownership transfer, memory accessibility transitions and clone copying are not generic inferred rules. Author-authored facts can be recorded; otherwise unresolved. |
| G07 communication; R06 time loops; R07 travel and simultaneous scenes | Exact same-calendar event times and declared event effects are supported. Communication-channel ordering, cross-clock causality, loop carryover and travel feasibility are not generally enforced. |
| G08 cross-instance cardinality; R10 quantifiers; R13 succession | Local relation roles and finite-set expressions are supported. Dynamic cross-instance counting, open-world completeness and promise fulfillment policies remain unsupported. |
| R11 retcons and delayed consequences | Proposal dependency impact and immutable historical revisions are supported for represented record links. Natural-language dependencies not represented in the fact graph remain outside deterministic validation. |

## Decision required before semantic implementation

Please decide whether the three proposed author-controlled contracts K1, K2 and
K3 should be adopted. The current task is to finish reproducible current-build
probes and this decision package; it does not authorize implementing K1–K3.
