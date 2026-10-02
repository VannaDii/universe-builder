# G05 decision fixtures

October 2, 2026. Design corpus v1; proposed outcomes, not executed engine results or approval. Record aliases below are synthetic fixture identities, not production record IDs. Translation to valid typed IDs belongs to later implementation qualification. Each row resets an independent candidate unless it explicitly describes revisions. Expected outcomes are fixed before implementation; failed implementation must not rewrite them.

## Complete base stimulus

Universe U, continuity Main, candidate based on revision H0. Objective represented context C; belief context B with parent C. Worlds A, BWorld, CWorld; named integer-tick calendars K and L with no executable conversion. Realm absent. Entity Door has stable identity E; distinct E2 has the same name “Door.” Predicate D is a property allowing exact Boolean values, not an exclusive competing-value scenario. P1 is `(subject E, predicate D, value true, roles [], quantification particular, context C)`. P2 has exactly that payload with a different proposition identity. Unrelated proposition Q has predicate D, subject Other, value true and no assertions.

S1 is an Exact Support assertion of P1, scope `(UniverseWide,C,no realm)`, validity K:[10,20), persistence ExplicitInterval, no alternatives, basis AuthorDecision("synthetic support"). R1 is an Exact Refutation of P1 with the same scope/time/precision/persistence and a different AuthorDecision basis. Their immutable version aliases are VS and VR. All references resolve to active versions in U/Main. No consistency rule or unrelated blocking failure is installed unless stated. All records are visible to the author. Expected publication “eligible” always requires normal exact authority, current head, valid footprint and other checks; no fixture grants authority.

Outcome column describes the local proposition, not a metacondition. “Unresolved” modifies coverage; it is not a fifth truth value. In uncertain rows, Supported means the known S1 bit remains; uncertain R1 does not create an exact refutation bit. When a separate context/world/time has its own negative evidence, it is Refuted there.

## Frozen inputs and outcomes

| Fixture | Changes from base stimulus | Expected detection, evidence and boundary | Gold oracle |
|---|---|---|---|
| F01 | Include S1 and R1, no consuming rule | One conflict family, Conflicting on K:[10,20), support VS and refutation VR; report-only eligible. Mechanism A. | O01,O26 |
| F02 | R1 refers to P2 | Same overlap and bits as F01, both proposition IDs retained; report-only eligible. Mechanism B. | O02 |
| F03 | Replace property with valid asymmetric transfer relation; P1 roles donor E/recipient E2; P2 same bindings serialized in reverse vector order; no value | Equivalent, conflict [10,20); full named-role multiset retained. | O03 |
| F04 | As F03 but P2 donor E2/recipient E | Distinct propositions; no G05 conflict; Supported and Refuted belong to different keys. | O04 |
| F05 | P2 subject E2, same display name as E | No identity merge, no G05 conflict. | O05 |
| F06 | Use one Decimal-shaped predicate; P1 Decimal digits "1.0", P2 Decimal digits "1.00" | Supported exact equality makes one conflict family despite distinct encodings/IDs. | O06 |
| F07 | P2 quantification universal | Distinct from particular P1; no exact G05 pair. Existing generic Claim limitation is disclosed. | O07 |
| F08 | R1 uses P2 whose context is B; R1 scope context B, B parent C | C Supported, B Refuted; no objective or cross-context conflict. Legal nested disagreement. | O08 |
| F09 | Both propositions/assertions context B | Local B Conflicting [10,20); no C conflict and no automatic ban. | O09 |
| F10 | S1 worlds {A}; R1 worlds {BWorld} | No common world; no conflict. | O10 |
| F11 | S1 UniverseWide; R1 worlds {A,BWorld} | Conflict only in {A,BWorld}, not CWorld. | O11 |
| F12 | S1 worlds {A,BWorld}; R1 worlds {BWorld,CWorld} | Conflict only in BWorld. | O12 |
| F13 | S1 realm X; R1 realm Y | No cross-realm pair; distinct explicit realms isolated. | O13 |
| F14 | Both realm X | Direct conflict scoped to X; current realm rule inference remains unsupported. | O13 |
| F15 | R1 K:[20,30) | No overlap; Supported [10,20), Refuted [20,30); tick 20 negative only. | O14 |
| F16 | R1 K:[15,25) | Conflicting [15,20), Supported [10,15), Refuted [20,25). | O15 |
| F17 | R1 instant K:20 | No conflict: excluded endpoint. | O16 |
| F18 | R1 instant K:19 | Conflict exactly at instant 19; never claim whole [10,20) conflict. | O16 |
| F19 | R1 L:[10,20) | Temporal comparison unresolved; no inferred clock mapping; S1 Supported on K. | O17 |
| F20 | R1 K interval start bounded [18,22], end 30 | Possible overlap unresolved: start 18 overlaps, start 22 does not; no definite conflicting bit. | O18 |
| F21 | R1 validity Unknown | Unresolved time, no infinity assumption; S1 Supported. | O19 |
| F22 | R1 applicability Unspecified | Unresolved applicability; no universal-world assumption; S1 Supported. | O19 |
| F23 | R1 applicability Conditional, no executable condition | Unresolved applicability; S1 Supported. | O19 |
| F24 | R1 Precision Approximate | Unresolved exact refutation; retain VS and potential VR separately. | O19 |
| F25 | S1 and R1 validities Unspecified | Conflicting with unqualified no-temporal-claim label; no invented [10,20) cell. | O20 |
| F26 | S1 Unspecified; R1 K:[10,20) | Unresolved mixed time, no guessed universal lifetime. | O20 |
| F27 | Include S1,R1 and third negative assertion R2 with Unknown validity | Definite conflict VS/VR on [10,20) plus separate unresolved VR2; not erased by uncertainty. | O21 |
| F28a/b/c | Include only S1 / only R1 / neither (P1 still exists) | Supported / Refuted / NotEstablished; no G05 conflict. | O22 |
| F29 | H1 contains F16; reviewed H2 replaces VR with new VR2 ending support/refutation separation at 20 (R1 validity [20,25)) | H2 no overlap; H1 still conflict [15,20) with VR; no stale approval reuse. | O23 |
| F30 | Repeat VS in evaluator input and reverse insertion order for F02 | Same normalized conflict/evidence; repeated identity contributes once. Do not admit duplicate active versions as canonical records. | O24 |
| F31 | F02 requester can see VS but not VR or its world/source dependencies | Restricted public result with no hidden IDs, counts, cells or hashes; private author result remains F02. | O25 |
| F32 | F01 plus complete applicable NoOpposingEvidence rule, BlockUnlessException, context C, worlds UniverseWide, K:[10,20) | Underlying Conflicting; metacondition Refuted; inadmissible even for author approval. | O27 |
| F33 | F32 plus exact rule-version exception, author-accepted decision, C/UniverseWide/K:[10,20), rationale | Rule waiver permits admission if otherwise valid; underlying conflict and both chains stay visible. | O27 |
| F34a/b/c | F32 plus standalone Accept IssueDecision / stale rule-version exception / valid exception only K:[10,15) | First unwaived; second invalid; third leaves [15,20) unwaived. All inadmissible, head unchanged. | O28 |
| F35 | F32 blocking rule applicability Conditional, unresolved | Incomplete blocking evaluation; no approval/delegation or exception-induced completeness. | O29 |
| F36 | F01 plus Q without evidence | P1 Conflicting; Q NotEstablished, no explosion. | O30 |
| F37 | R1 K:[10,10) empty | No conflict and no refutation at tick 10. | Additional |
| F38 | R1 start bounded [12,14], end 18 | Definite overlap, uncertainty-qualified intersection; common guaranteed cell [14,18); possible earlier overlap cannot be rendered exact. | Additional |
| F39 | R1 start bounded [21,22], end 30 | All interpretations disjoint; no temporal conflict, complete comparison if other fields exact. | Additional |
| F40 | R1 proposition context C but assertion scope context B | Existing storage shape may be valid; comparison ineligible/unresolved, no automatic context rewrite or new structural rejection. | Review C3 |
| F41 | S1/R1 known disjoint worlds as F10, R1 time Unknown | No overlap proven by worlds; do not issue a spurious pair-specific time gap. | Additional |
| F42 | P2 predicate is a different definition ID with the same label/key | No identity equivalence; if namespace resolution is ambiguous, expose unresolved policy selection. | Additional |
| F43 | R1 explicit realm X; S1 realm absent | Mixed realm containment unresolved; never widen absent realm into X. | Additional |
| F44 | F01, report-only, unrelated rule with hard-coded scalar conflicting values for another subject | G05 remains diagnostic; existing scalar check still denies admission, cannot be waived by a G05 exception. | Review C7 |
| F45 | F01 plus rule AlwaysBlock; otherwise valid exception attempt | Inadmissible; AlwaysBlock accepts no waiver. | Review C5,C6 |
| F46 | F20 report-only, exact author approval versus delegated attempt | Partial scan: delegation ineligible; author approval can proceed only if all existing blockers pass. Uncertainty remains visible. | Review C6 |
| F47 | F01 exists at base; proposed change edits an unrelated visible label only | Full candidate scan still reports F01; do not limit comparison to changed assertions. | Additional |
| F48 | R1 K interval explicit unbounded start/end | Conflict exactly S1's [10,20); unbounded differs from Unknown. | Additional |

| F49 | VR exists only in a different continuity Branch or historical revision Hminus, while Main/H0 contains VS only | Main/H0 remains Supported; do not join opposite polarities across snapshots. | Additional |
| F50 | Opposite assertion refers to an entity in another universe with the same record suffix | References do not resolve to the same universe-qualified identity; reject invalid reference through existing checks, never manufacture a local G05 conflict. | Additional |
| F51 | R1 applicability Worlds with empty world set | No applicable world, no overlap, no G05 conflict. | Additional |
| F52 | R1 validity is legacy Interval [10,20) without calendar, or unsupported PersistentUntilChanged | Each variant unresolved, no inferred clock or persistence. | Additional |
| F53 | R1 has OneOf precision and alternatives [true,false] | No exact refutation bit; potential opposing evidence remains unresolved. | Additional |

## Judgment and proof boundary

The independent agent froze O01–O30 and C1–C9 in `g05-independent-review.md` before seeing this proposal/corpus. The mapping above compares separately derived set intersections, evidence bits and current policy behavior. Additional cases require the independent review addendum; they are not inferred engine results. No fixture outcome has been selected from a producer pass/fail label.

For future engine execution, preserve the symbolic-to-typed-ID mapping, exact active versions, both polarity chains, context/world/time descriptions, candidate/evaluator bindings, actual validation, private approval response and commit receipts. F29 needs old/new revision reads after restart. F31 needs both restricted and author outputs. F32–F35/F44–F46 need unchanged-head assertions on rejection and exact authority controls. Apply the proposal's ordering, budget, transport and alternate-admission acceptance criteria to the corpus rather than inflating rows with repeats.
