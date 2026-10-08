# Reusable object rules: capability evidence and decision

October 3, 2026. Baseline `7609ba2`. Status: **proposed; extension not authorized
or implemented**. This document resolves the design investigation, not delivery
of a new runtime feature. Proofs use synthetic examples and production rule
functions. Independent judgments are program checks, not independent human review.

## Recommendation and decision

Keep existing protected Rule records, named-clock assertions, declared action
contracts, full-candidate validation, exact approvals and scoped exceptions.
Add only two operand variants, **`entities_of_type`** and **`resource_value`**, to
make a protected rule apply to the current typed candidate set and compare its
unambiguous explicit stock with bounds. Use existing `Quantify`, `All`, and
`Compare`; do not add a template record, stock ledger, shot counter or simulation.

Decision requested from Vanna: approve these two operands and the semantics below,
or retain explicit finite object lists plus action accounting and accept the
coverage limits. The extension makes future matching objects subject to the rule
and checks stock outside declared actions; it changes wire schemas and evaluator
semantics, and needs fresh validation/approval. Finite lists need no runtime
extension but require explicit updates when membership changes and do not safely
resolve unique stock through `Claim` alone.

This is an evidenced expressiveness limitation, not a failing implementation of
an approved design. Work on the extension is paused pending the decision. Tests
here characterize existing behavior; they do not implement or endorse the gaps.

## What works now

The [capability payloads](../../fixtures/object-rules/capabilities.json) contain
complete JSON payloads per probe, synthetic IDs, frames, world footprints and
frozen expected outcomes. The [Rust probe](../../crates/universe-service/src/object_rule_capability_checks.rs)
builds immutable versions, verifies Rule protection, and calls the actual service
rule evaluator both with and without its production index.

| Requirement | Current executable behavior | Implication |
|---|---|---|
| A particular object | `Claim.subject` names its exact record | Names, holders and appearances do not change identity. |
| Several known objects | `Quantify` over a literal `sequence` of record references | `complete:true` describes this authored collection, not discovery of every typed object. |
| All objects of a type | `subjectTypes` does not select, filter or bind an expression variable | An additional same-type entity with missing stock is missed; an unbound variable is unsupported. |
| World A | `applicability:worlds` and assertion world scope | B's evidence cannot satisfy A; workflow skips unrelated world rules for local edits. |
| Universe scope | `universe_wide` checked in affected world cells; shared edits expand the workflow footprint | This is jurisdiction, not pooled stock, all-universe cross-world assertion synthesis, or cross-universe identity. |
| Conditional/unspecified jurisdiction | Unsupported in service rule checks | Ask for an explicit supported scope; do not guess. |
| Initial amount | Exact supported value at an authored start instant | The evaluator checks evidence; it never creates stock. A permanent equality to 12 rejects legitimate consumption. |
| Range 0–12 | `Any` of thirteen exact claims works for an isolated supported value | Not a safe stock bound: supported 12 plus supported 13 still passes. Missing matching evidence is not established, not proof of a numeric violation. |
| Numeric comparison | Exact `Compare` on value operands | A record operand is identity, not its property value. There is no state-value operand. |
| Between reloads | Declared delta effects with pre/post bounds and full-candidate cumulative accounting | Twelve from a full load; five from a partial load of five. No refill at scene, holder or engine changes. |
| Authorized waiver | `block_unless_exception`, exact rule version, accepted decision, contained world/context/time | Original refuted finding remains visible. Stale/missing acceptance, uncovered world or `always_block` reject. |

`targetPredicates` and `subjectTypes` are metadata, not executable lookup
instructions. A label such as “gun” is not a type predicate. Use explicit entity
IDs or an authored EntityType and `Entity.types`; no fuzzy name matching or implicit
subtyping. Property subject-type validation constrains property use separately;
it does not implement rule enumeration.

Current resource transitions already reject missing, opposed, uncertain, multiple
incompatible or out-of-bounds pre-stock; require authored post = pre + declared
delta; reject overlapping simultaneous dependent changes; and debit a constrained
reload reserve only when that debit is explicitly declared. A protected rule
exception does **not** waive these structural transition checks. A different
permitted transition needs an explicitly reviewed contract/canon revision.

## Concrete existing payloads

Read `exact_identity`, `finite_objects_both_supported`, `world_A_support_A`,
`initial_amount_at_start` and `authorized_exception_retains_finding` in the
capability fixture. These are **current** payloads, not the proposed operand
syntax. Wire keys are `subjectTypes`, `commitPolicy` and `targetPredicates`;
`Operand.Record` and `Value.RecordRef` both carry their reference under `ref`.

For a gun whose established start is tick 10, its stock proposition is:

```json
{"record_kind":"proposition","subject":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000050"},"predicate":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"value":{"kind":"integer","digits":"12"},"quantification":"particular","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000063"}}
```

Its initial assertion uses explicit scope, exact precision and a named-clock
interval `[10,11)` when the first declared shot is at 11. The initial-check Rule
uses an instant validity at 10; later stock may be 11 without violating that
initial condition. When the first shot is unknown, an explicitly authored open
endpoint is possible, but the initial assertion must be explicitly ended at the
first stock transition before admitting that candidate. Existing event expansion
ends generated effects, not arbitrary author assertions. Do not silently shorten
the author's evidence. Capability cases test an initial instant and stock starting
at 10; the prior transition fixtures test the explicit pre-event intervals.

The current shot effect slot can declare:

```json
{"slot":"shot","order":0,"presence":"required","target":{"role":"gun","predicate":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"}},"condition":{"kind":"always"},"change":{"kind":"delta","delta":"-1","minimum":"0","maximum":"12","unit":null},"lifetime":{"kind":"until_changed"}}
```

This slot goes in an ActionDefinition's existing `action_consequences_v1`
contract. The event binds exactly one gun participant and supplies the matching
post-proposition. A reload of three declares `+3` on gun stock and, if the reserve
is constrained, `-3` on reserve in the same contract/event. A full-reload operation
is not assumed from the word “reload”: topping up, replacing a magazine and adding
a fixed amount have different post-values and reserve debits. Required effects
remain explicit; no prose-generated execution is claimed.

## Preserve wording and clarify meaning

Store the author's original UTF-8 wording verbatim in the existing Rule
`labels.author_wording`, separate from namespaced keys and executable expressions.
Do not replace it with a normalized paraphrase. Existing immutable record versions
preserve earlier wording. For imported text, reuse SourceVersion/Anchor evidence
when available; no new source format is necessary. Synthetic fixture wording is
an example, not a quotation attributed to Vanna.

For “These guns start with twelve rounds and cannot fire more than twelve times
between reloads,” the review must make these choices explicit:

- Which entity IDs or exact type does “these guns” mean? Does a later same-type
  object join the set? Does the rule govern all typed identities in each rule
  world, or a named local subset?
- Is this world A, named worlds, or the universe's worlds? Which represented
  context, calendar and established start apply?
- Does “twelve” specify capacity, initial stock, or both? Is one shot one round?
  Are partial loads, replenishment without a reload, or other consumers permitted?
- Does “reload” add a stated amount or restore a full load? Is ammunition in the
  reserve constrained? Is the limit ammunition availability or literally twelve
  trigger pulls even if one firing event consumes another amount?

Keep incomplete answers unresolved and ask only the missing question; never turn
“yes,” “all,” “normal,” or “as before” into an unreviewed choice. Present the
original wording beside the interpreted matching set, jurisdiction, initial
condition, capacity and action effects before exact author approval.

Capacity is a maximum. Current stock is supported state on an object. An authored
capacity of 12 with no stock does not authorize firing. A partially loaded gun
with five rounds has five one-round shots; its capacity remains 12. If the author
intends an independent trigger-pull quota, that is a different design decision;
ammunition accounting cannot establish it. No counter is proposed here. Stock bounds also do not, by themselves, prohibit an
in-range stock increase from another declared action or a directly authored state
revision. The ammunition interpretation assumes the author permits replenishment
only through the reviewed reload contracts or explicit canon changes. If the
literal rule must mechanically reject every non-reload increase, that is an
additional temporal authorization policy, not solved by these two operands.
Clarify that interpretation before implementation; do not claim that capacity
bounds prove a strict count of shots between named reload events.

## Initialization once at an established start

Use the existing authored chronology's `first_interaction` only when the author
confirms it is this object's start. A later introduced object needs its own
explicit coordinate. Never derive a start from wall time, first observation,
scene order, current holder or process startup.

Proposed authoring procedure, using existing records and transactions:

1. Resolve exact object identity, context, world scope and named-clock start.
   Retrieve its prior initialization assertion and immutable history at the
   review's base revision. Unknown start or conflicting stock needs clarification.
2. Assign stable IDs to the initial proposition, assertion and per-object
   initial-check Rule in one reviewed proposal. The existing review changes and
   commit receipt identify those records; retrieve them and their immutable
   history on continuation. Reuse the exact reviewed assertion on retries.
   Do not add an initialization marker or derive a new start for each scene.
3. If the assertion/history already establishes initialization, retrieve current
   stock. Do not create another initial amount after scene change, transfer,
   reload, retcon, branch navigation or engine restart. Missing current evidence
   is unresolved, not a reason to bootstrap. Existing stock without an established
   initial record also needs clarification.
4. Validate against the exact base, approve the exact changes and use the existing
   stable commit idempotency key. Stale concurrent proposals must refresh.
   A deletion/correction of initialization is an explicit reviewed retcon, not a
   reset opportunity. Historical revisions retain their own authored stock.

There is currently no automatic once-only initializer. The independent start
examples judge this procedure, not a delivered runtime guard. Implementing the
procedure later requires authoring-side retrieval/history checks; no new ledger
or background task is warranted. Canonical edits still require the existing
approval or an explicit applicable delegation.

## Proposed smallest runtime extension

The following is **proposal syntax**; the current deserializer rejects its two
new operands. The capability proof explicitly verifies that rejection.

```json
{
  "record_kind":"rule", "namespace":"example", "key":"gun_stock_bounds",
  "labels":{"author_wording":"These guns start with twelve rounds and cannot fire more than twelve times between reloads."},
  "kind":"physical_constraint", "commitPolicy":"block_unless_exception",
  "applicability":{"kind":"worlds","world_ids":["wld_000000000000000000000014"]},
  "subjectTypes":["rec_000000000000000000000046"],
  "targetPredicates":["example:rounds"], "capabilities":["basic.v1","finite.v1","object_resources.v1"],
  "executable":true,
  "validity":{"kind":"calendar_interval","calendar":"cal_00000000000000000000000a","start":{"kind":"exact","value":"10"},"end":{"kind":"unbounded"}},
  "expression":{
    "kind":"quantify", "variable":"object", "complete":true, "quantifier":"for_all",
    "over":{"kind":"entities_of_type","entity_type":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000046"}},
    "body":{"kind":"all","exprs":[
      {"kind":"compare","left":{"kind":"resource_value","subject":{"kind":"variable","name":"object"},"predicate":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"unit":null},"op":"gt_eq","right":{"kind":"value","value":{"kind":"integer","digits":"0"}}},
      {"kind":"compare","left":{"kind":"resource_value","subject":{"kind":"variable","name":"object"},"predicate":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"unit":null},"op":"lt_eq","right":{"kind":"value","value":{"kind":"integer","digits":"12"}}}
    ]}
  }
}
```

`entities_of_type` resolves the exact EntityType in the same universe, enumerates
explicit direct `Entity.types` membership from the complete candidate (including
additions, type edits and deletions), and returns stable record references under
the existing finite work budget. No names, inferred subclass hierarchy,
associations, origin or physical location filter it. World scope filters the
**constraint/evidence**, not identity membership. Thus a world A class rule covers
all selected typed identities in A; if the author means only A-local objects, use
an explicit finite set or an explicitly authored local type. Unknown membership
semantics require clarification, not a guessed association role. Empty complete
sets are vacuous; this does not certify that an intended gun was actually typed.

`resource_value` resolves one supported exact bounded integer/declared-unit
quantity from explicit direct or generated assertions for the bound object,
predicate, frame context, time and current world cell. Reuse the selection,
precision, unit and uniqueness policy in resource transition checks. Agreeing
support corroborates; missing/opposed/uncertain/incompatible support returns
unsupported/not established, never a chosen value. Item powers, capacities,
unasserted propositions and other-world evidence do not supply stock.

Resolution has two explicit modes in the shared implementation: current frame for
this operand, existing pre-event frame for transitions. Do not change endpoint
semantics by reusing a pre-event instant for a current-stock check. Refactor shared
evidence logic without changing the established transition policy.

At existing rule validity partitions, bounds must cover all relevant stock
assertion boundaries. Ordinary claim operands already partition all assertions;
new resource operands must retain that behavior, including candidate generated
state and initial endpoints. Candidate membership changes must revalidate the
unchanged protected rule. Literal collections keep their existing semantics.

Existing exceptions waive a whole rule in a world/context/time cell; they have
**no subject selector**. An exception on the proposed class rule would waive its
bounds for every selected object in that cell. For a single exceptional object,
use explicit per-object rules and authorize its exception separately, with a
reviewed finite remainder rule. Do not silently turn a broad exception into an
object-specific one or introduce an exclusion list. A dynamic class that includes
future objects plus a single-object waiver would need a separate, undecided
exception-selector design; it is not included in this recommendation.

## Implementation and compatibility after approval

1. Add the two strictly validated Operand variants, canonical encoding, reference
   extraction and budget/depth accounting in `universe-domain`/rule compiler.
   Refactor exact stock evidence resolution into a shared domain-safe rules helper,
   called by both the service transition checker and `resource_value`.
2. Evaluate type enumeration against the complete candidate/index, not search or
   context-brief pages; preserve explicit universe identity and finite limits.
   Enable `object_resources.v1` only with complete implementation. Preserve
   original rule findings and scoped waiver behavior.
3. Extend protocol schemas, client/editor operand handling and capability
   description. Keep legacy payloads, digests and immutable histories unchanged.
   Old binaries reject the new variants; export/import must not drop them or
   downgrade executable coverage. No broad migration or rewriting old rules.
4. Change the evaluator binding from `finite-policy-v8-cumulative-resources` for
   new semantics, invalidating old validation/publication approvals. Revalidate
   unchanged dependent rules after type, stock, context, validity or contract edits.
5. Qualify through the current proposal/validation/review/commit path: new typed
   gun, deleted/changed member, untyped lookalike, world isolation, missing/ambiguous
   stock, period boundaries, initial start, consumption, partial reload, retcon,
   scoped exceptions and old-payload replay. Keep the current cumulative accounting
   suite as the regression baseline. No simulator, automatic execution, prose
   classifier or new authority model.

## Proof scope and results

Current results: **26 capability cases × two evaluation paths**, **30 independent
matching/scope/start/accounting judgments**, **44 existing independent resource
cases**, and **nine existing cumulative accounting fixtures** pass. The repository
check passes **327 tests**, zero failures and one pre-existing ignored workload,
formatting, warnings-as-errors Clippy and generated-schema freshness.

See verification and
independent judgments.
Capability fixtures assert actual current outcomes, including limitations; the
independent examples assert intended set/start/accounting judgments. They are
separate inputs with no production evaluator imports. Accounting examples of
multiple shots are arithmetic totals, not claims of multi-shot event admission.
Existing cumulative fixtures exercise actual individual events and ordering.

The capability probe operates at the production service rule function, not a
new live MCP session or full structural/authorization validation. Its fixtures
contain synthetic reference IDs, not a complete publishable installation.
Existing transition fixtures and independent Fraction replay establish executable
accounting support. This goal does not claim a shipped typed selector, a once-only
runtime initializer, accepted prose interpretation or author approval of the
proposal. No production behavior changes are made.

Reproduce the evidence with:

```sh
cargo test --locked -p universe-service object_rule_capability_checks --lib -- --nocapture
python3 scripts/judge_object_rule_examples.py
python3 scripts/resource_accounting.py
python3 scripts/test_cumulative_resources.py AccountingTests
cargo run --locked -p xtask -- check
```

The initial-check Rule is per object and per established start; the proposed
class stock-bounds Rule must not impose one historical start on future objects.
A class selector and stock-value query only read candidate evidence. They never
initialize, execute actions or change the author's chosen stock.
