# G05 evidence detector qualification

October 2, 2026. Implements the comparison-kernel slice of the [approved recommendation](g05-opposing-evidence.md). This does not close all of G05: public reporting, visibility delivery, authored metaconditions, policy/admission integration, UI and publication qualification are separate work.

## Implemented behavior

`universe_rules::opposing::detect` takes the structurally checked, event-expanded active membership of one resolved candidate revision. The caller owns snapshot selection; record payloads do not carry continuity/revision membership. It never reads another snapshot or treats a UI world selection as applicability. Cross-universe references and ambiguous active membership are rejected. Repeated identical immutable witnesses are deduplicated.

The indexed path buckets by resolved subject, exact active predicate version, quantification, represented context and sorted named-role multiset. The reference path inspects all support/refutation pairs. Both prove value equality pairwise through canonical equality or the existing exact comparator, without transitive grouping. Different subjects, predicates, quantifications and contexts remain separate. Role multiplicity is retained; different role assignments do not become equivalent. Existing Claim matching semantics remain unchanged.

Results are internal opposing-pair witnesses, suitable for later aggregation/delivery. Each retains separate original assertion/proposition versions, both immutable payloads, exact reachable dependency versions and source/derivation metadata. Pinned historical dependencies that are unavailable in the supplied membership stay explicit provenance limitations; the active replacement is never substituted. Imported claims retain their direct evidence and expose their unsupported source chain. Source byte verification is retained metadata, not a truth judgment.

World-set intersections are normalized. Explicit realms remain isolated; mixed absent/present realms are unresolved. The existing temporal extremal comparator governs overlap. Exact intersections retain half-open boundaries, instants and explicit unbounded endpoints. Unspecified/Unspecified is labeled unqualified. Definite uncertain overlap retains both original uncertain validities and only the guaranteed exact intersection, while coverage remains incomplete. Unknown clocks, dates, applicability, mismatched assertion/proposition contexts, unsupported persistence and non-exact precision remain explicit gaps. Proven disjointness short-circuits irrelevant uncertainty. A definite pair survives additional unresolved evidence.

Membership and comparison work are each capped at 10,000. A smaller requested comparison budget is honored. Exhaustion cannot return a complete scan; it records the Budget gap and preserves already detected pairs. Chains are cached per immutable assertion, and dependency cycles terminate by version identity. Output ordering binds resolved meaning, scope/intersection and immutable witness versions.

This module is exported as an internal Rust API; no public wire schema, Validation field, rule expression, admission behavior, UI, canonical record or evaluator-policy binding was changed. No result is automatically serialized to a scoped client.

## Independent expected outcomes and executed checks

Expected outcomes come from the frozen [independent oracle](g05-independent-review.md) and [fixture table](g05-fixtures.md), which predate this implementation. They were not changed to match detector output.

Eight focused tests translate the detector portions of F01–F30, F36–F43 and F47–F53, including the F28 and F52 variants. They test identical/distinct proposition IDs, normalized exact decimals, named role order versus role swapping, same-name entity isolation, quantification, nested contexts, worlds and realms, temporal separation/overlap/empty intervals/instants/unbounded endpoints/bounded uncertainty, corrections via separate snapshots, duplicate witnesses, cross-universe rejection, precision alternatives and uncertainty coexistence. F29/F49 establish the kernel's independent snapshot behavior; they do not qualify persistence, restart, authority or receipts.

Each fixture checks indexed/full result and completeness parity, then reversed/rotated input order. An additional independent integer-set oracle checks all 231 valid interval pairs with endpoints from -10 through 10 against [-3,4), including empty and touching intervals. Additional tests inspect separate source-anchor/derivation chains, unresolved historical pins, namespace normalization, exact quantity comparison, undecidable equality, ambiguous membership and explicit budget exhaustion. The existing four-valued claim evaluator is exercised with and without its EvaluationIndex for Supported, Refuted, Conflicting and NotEstablished, plus unrelated absence and unchanged input records.

F31–F35/F44–F46's public visibility, policy, exception, authority and admission outcomes are excluded from this goal. Their detector inputs are covered where applicable; this qualification makes no claim about their future integration.

Verification on the final source:

- `cargo test -p universe-rules -p universe-domain -p universe-service`: **194 passed, 0 failed, 1 ignored**. This includes the eight focused detector tests and 186 existing tests. The existing ignored standard workload requests an explicit release-mode run; it was not executed here.
- Targeted `rustfmt --check` for the two new Rust files and staged whitespace verification passed.
- Initial compilation/fixture attempts exposed helper issues (record-kind changes and a principal-ID prefix), and an assertion that assumed diagnostic list positions before canonical sorting. These were corrected without changing the frozen semantic expectations.

## Checkout and commit boundary

The checkout already contained substantial modified/untracked implementation work when this goal began. Verification used that current implementation. The goal commit contains only the new detector, its tests, this note and the module declaration. It does not package the preexisting implementation and is not claimed to build independently from a clean historical HEAD.

Relevant existing dependency bytes used for qualification:

| Source | SHA-256 |
|---|---|
| `crates/universe-rules/src/basic.rs` | `5a3ef7c009f64860cca7cc84c71a803bddabe7c38ecffa15036fe231faca11d6` |
| `crates/universe-rules/src/time.rs` | `69dc0810b45684b99c31f21aebae8795b58eb9327af2c989385b783e99005059` |
| `crates/universe-rules/src/index.rs` | `44d04dc1ea7848bf4e90dc4388e1e4c552cc7d72e329170128daa339e9d38ddb` |
| `crates/universe-domain/src/records.rs` | `02a8de30b4d4bf59c1aee5bd715087ba131a6330ae11fd104cf2d7922a98bec4` |
| `crates/universe-domain/src/value.rs` | `fedbc0621f94f6b78bb239ebbaec215b5180ce5909381a48e0c35718b4afc370` |

The active goal began at 19:06:00 UTC (12:06:00 PDT). Actual working wall time through verified commit completion and the commit hash are reported in the final response; no later integration work is counted.
