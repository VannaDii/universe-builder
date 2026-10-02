# Chapter provenance and retcon verification

Execution began October 1 and continued October 2, 2026. All story records,
author profiles, agent grants and installations are disposable synthetic test
data. Existing project work and production universe packages were preserved.

The persistent deterministic regression and the scoped generated-prose MLX pilot
pass. The accepted run also passes a separate source audit; earlier producer
passes that failed that audit remain explicitly rejected below. This qualifies
the declared pilot workflow, not arbitrary manuscript extraction or model reliability.

## Accepted MLX evidence

[Run 11 transcript](evidence/chapter-pilot-2026-10-02-run11/report.json) and
[source audit](evidence/chapter-pilot-2026-10-02-run11/source-audit.json) contain
332 public MCP calls, 15 successful canonical commits and 12 persisted passage
references across the original chapter, continuation and revised edition.
The model generated a 420-word three-scene chapter, a 152-word continuation and
the 572-word corrected edition. Its 24 generation turns took approximately
295 seconds, excluding setup and independent checks. Four prose reviews passed.

The first continuation draft asserted unsupported route-count information. The
fixture rejected it before source staging or semantic publication. One explicit
feedback retry produced the accepted continuation; both outputs remain in the
transcript. No tool-call repair was needed in this accepted run.

The independent audit checks persisted source versions, UTF-8 ranges, excerpt
digests, exact edition references, source-linked knowledge/witness records,
author approval receipts, temporal/perspective queries, historical source
identity, stale rejection and the recovered current head. Reading the actual
prose confirms the key transfer, password acquisition, performed opening and
departure, map remaining in place, and Mara's explicit route acquisition.
The retcon changes the story dates while preserving those actions and their
source text. All previous source versions and bound editions remain available.

## What the pilot exercises

The original chapter has three scenes: Mara transfers a copper key and tells
Iven the password on day 12; Iven opens the archive on day 13; Iven reads the map
and learns the quarry-tunnel route on day 14. A continuation on day 15 uses
freshly retrieved committed canon: Iven leads Mara toward the tunnel and tells
her the route. An author-selected retcon delays the handoff until day 14, requiring
the opening, reading and continuation to move to days 15, 16 and 17.

The test preserves these distinct relationships:

- Immutable exact source text -> versioned UTF-8 anchor -> edition passage.
- State assertion or explicit knowledge -> source-anchor evidence.
- Generated state assertion -> generating event -> legitimate sourced observation.
- Scene -> depicted event; scene presence does not establish character knowledge.
- Work edition -> exact semantic continuity/revision, even after the current head changes.

Source evidence, semantic changes, bound editions and passage references use
separate ordinary proposals in this pilot. Each canonical publication has exact
author approval, a validation run, an atomic commit and an idempotent receipt.
Intermediate source commits preserve evidence and do not establish its prose's
material claims. Used prose is accepted only after its semantic commit succeeds.

## Executed regression evidence

Run:

```sh
python scripts/chapter_retcon_pilot.py --regression --output /tmp/chapter-regression-new
```

The latest completed regression report is
`/tmp/universe-chapter-regression-14/report.json`. It contains 332 actual public MCP
calls and 15 successful canonical publications, with author reviews, exact
proposal references, validation results and receipts. No public tool was added.

| Requirement | Authoritative evidence in the report |
|---|---|
| Exact immutable source and passage links | `original_source_graph`, `continuation_source_graph`, `revised_source_graph`: persisted records independently checked against exact UTF-8 bytes, source versions and bound editions |
| Canonical changes and current authority | `publications`: every unapproved commit first denied, then exact author-approved commit succeeds; receipt retry matches |
| Continuation from fresh canon | `research`, `continuation_scenes`, `original_timeline`: reopened revision, custody, door state, route and explicit knowledge |
| Perspective and story-time boundaries | `character_view` and timeline `knowledge_states`: only each holder's authored knowledge in the correct represented context |
| Partial retcon rejected | `retcon_conflicts`: `INVALID_ARGUMENT` at `event.preconditions`; the day-13 opening lacks day-14 custody |
| Affected passages remain discoverable | `provenance_research`, `retcon_impact`: source-linked passages in the conservative impact closure |
| Corrected retcon committed | `revised_timeline`: custody, opening, route and knowledge on the revised boundaries |
| Original history retained | `historical_timeline`, `original_source_preserved`: original revision still returns original state and unchanged exact source version |
| Stale approved changes denied | `stale_rejection`: `BASE_REVISION_CONFLICT` |
| Restart and receipt recovery | `restart_receipt`, `restarted_timeline`: owned engine terminated, fresh adapter recovers identical receipt and retries without republishing; current head still equals the revised passage publication |
| Invalid citations denied | `invalid_citation`, `tampered_excerpt`: non-anchor target and modified excerpt digest rejected |

The closed extraction regressions also cover exact UTF-8 offsets with combining
characters, punctuation and emoji; normalized or duplicated excerpts; missing,
duplicate or invented changes; altered quotes; and wrong scene dates/IDs.
Seven new Python tests and the earlier 11 model-harness tests pass. The Rust gate
passes formatting, strict Clippy, 258 tests and generated-schema drift, with one
explicitly ignored workload. Independent checks pass 26 schemas, 13 valid and
91 invalid examples; stdio MCP and persistent installation smoke checks pass.
Logs are under `/tmp/universe-chapter-*` for this session.

## MLX attempts and retained errors

The existing local Qwen3.6 35B A3B 4-bit MLX model runs directly on Metal with
seed 42 and greedy sampling. Each report records exact model-file SHA-256 hashes,
runtime versions, prompts, raw outputs, timing and explicit feedback. The model
generates prose and exact excerpts. The host compiles the declared story
vocabulary; research/proposal/validation/commit calls are template-assisted JSON
dispatch through the persistent MCP. This does not qualify native host function
calling or unrestricted extraction from arbitrary manuscript text.

- [Attempt 1](evidence/chapter-pilot-2026-10-01-run1/report.json): extra scene
  generated twice. The rejected text never reached a semantic commit. The prompt
  listed beats outside the requested scenes; later prompts were scoped precisely.
- [Attempt 2](evidence/chapter-pilot-2026-10-01-run2/report.json): the model
  duplicated the opening change, including after feedback. Later extraction
  prompts/errors specify exact cardinality and duplicate kinds.
- [Attempt 3](evidence/chapter-pilot-2026-10-01-run3/report.json): the model
  confused the stored `chronology.current` cursor with the pinned query time and
  rejected pending changes because they were not already asserted in base canon.
  This is retained as a failed prose review. Subsequent reviews receive actual
  validated candidate assignments and distinguish stored clock from query time.
- [Attempt 4](evidence/chapter-pilot-2026-10-01-run4/report.json): a long proposal
  response hit its token limit; an explicit retry produced the exact valid call.
  Execution then stopped on a harness error: public proposals contain operations,
  whereas compiled assignments come from the existing private author review.
  The corrected boundary is exercised in deterministic mode too; subsequent
  calls have a size-based response budget.
- [Attempt 5 transcript](evidence/chapter-pilot-2026-10-02-run5/report.json) and
  [independent source audit](evidence/chapter-pilot-2026-10-02-run5/source-audit.json):
  all transport/domain checks passed, and all four model prose reviews accepted
  the text. **The source audit rejected it.** The continuation closes the door
  while canon leaves it open, fails to state Mara's new knowledge, and asserts
  unsupported route exclusivity. The unchanged producer report retains its
  narrow `pass`; the separate audit records why this is not accepted completion.
  The pilot now checks these declared constraints before source selection and
  gives explicit corrective feedback. Those lexical guards are narrow fixture
  checks, not an arbitrary prose validator. Model self-review alone missed
  real implications and cannot certify exhaustive continuity.
- [Attempt 6](evidence/chapter-pilot-2026-10-02-run6/report.json): the continuation
  asserts other routes exist, which is also outside the declared canon. The
  feedback retry still introduces that claim. A pilot guard additionally fails
  to recognize Mara's explicit first-person acknowledgment across sentences;
  that overly narrow check is corrected and covered by a dialogue regression.
  Later prompts make no assertion about whether alternate routes exist.
- [Attempt 7](evidence/chapter-pilot-2026-10-02-run7/report.json) and
  [source audit](evidence/chapter-pilot-2026-10-02-run7/source-audit.json): transport,
  domain checks and model reviews pass, but the continuation only prepares for
  departure. Its typed journey is marked `occurred`. The audit rejects this
  mismatch. The pilot now requires an actual departure, and MCP instructions
  explicitly distinguish performed events from intentions/preparations. Neither
  an exact excerpt nor a valid event record proves that the prose depicts that
  event; the author must inspect the connection.
- [Attempt 8](evidence/chapter-pilot-2026-10-02-run8/report.json): the new action
  guard rejects a performed departure expressed as “Mara stepped forward” and
  “Iven walked beside her,” because it initially required only “led” or
  “followed.” That false positive is retained. The fixture check now recognizes
  those past movement verbs and has a regression for the actual phrasing. It
  remains a narrow guard against the known planning-only miss, not a semantic
  proof for arbitrary travel prose.
- [Attempt 9](evidence/chapter-pilot-2026-10-02-run9/report.json): review rejects
  the continuation, claiming its compiled Mara knowledge record is absent and
  that retained key custody needs a new assertion. Both claims misread the actual
  evidence. Separately, the generated chapter pockets the map despite the author
  constraint that it remain in place. The pilot now rejects that known custody
  violation and displays transparent, readable projections of actual active
  assertions and compiled candidate knowledge alongside the unchanged raw
  evidence. The projection preserves polarity, validity, contexts, source bases
  and exact record versions; it does not infer truth from a proposition catalogue.
- [Attempt 10](evidence/chapter-pilot-2026-10-02-run10/report.json) and
  [source audit](evidence/chapter-pilot-2026-10-02-run10/source-audit.json): the
  readable evidence resolves the missing-record/persistence review errors and the
  full workflow passes. The source audit rejects new unrepresented route hazards
  (a floor drop and unstable edges). The declared pilot vocabulary permits the
  route's name, not new geometry. Later drafts are constrained accordingly. In a
  real novel those details would need their own sourced semantic proposals if
  the author wanted to use them; a valid core proposal does not commit them.

No failed attempt is silently rewritten into a successful result. The earlier
12-case sentence assessment remains an independent 11/12 **model failure**, as
documented in the [readiness assessment](novel-authoring-readiness.md).

## Practical limits

Exact citations prove byte identity, not semantic truth. The pilot's material
vocabulary is declared by the synthetic author; model review can miss an extra
implication or misinterpret evidence. It does not prove exhaustive extraction
from arbitrary novel prose, subtle lies, flashbacks or every descriptive detail.
Unknown and unsupported evidence remain visible rather than becoming truth.

Impact is a conservative full-universe closure. The pilot identifies passages
through existing evidence links and its known causal chain; the engine does not
automatically produce a minimal affected-passage list or rewrite a manuscript.
Event attitude prerequisites are limited to their represented context. The pilot
checks character knowledge timelines separately rather than inventing a new
cross-context expression or changing the model's role.

Source staging and exact author approval remain private author operations. A real
host needs that author handoff or an existing appropriately bounded delegation.
Native workspace, accessibility, actual-host integration and book-scale context
performance remain separate acceptance work. No publication, distribution,
manuscript editor or architecture change is included.
