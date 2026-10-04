# Goal 28: ancestor-aware definition applicability

October 4, 2026. Scoped implementation against the approved [definition model](decisions/relational-storage/README.md#attributes-and-applicability).

## Delivered behavior

The resolver reads only the supplied factual snapshot. It resolves the instance's one classification and the type's one-parent chain, rejecting executable traversal through missing, foreign-universe, cyclic, ambiguous or nonexecutable definitions. It never fetches a latest database row. Ordinary structural admission and scoped assertion admission both use this ancestry for property subjects and relation participants, including definition subjects.

Each ancestor retains its own world jurisdiction. A child's disjoint world does not hide an otherwise applicable parent. Explicit empty world sets apply nowhere. Unspecified/conditional applicability and unknown ancestry remain unresolved; an applicable known ancestor does not override a relevant ancestor with unknown applicability. An assertion's complete authored world scope must be covered: an explicitly universe-wide fact cannot widen a world-restricted definition.

The claim evaluator collects applicable shared definition witnesses alongside distinct instance witnesses. It retains exact source assertion/proposition, instance and ancestor versions for inherited evidence. Authored represented context, realm, precision and validity still govern each witness. Known disjointness short-circuits irrelevant uncertainty. Different single-valued shared/instance values remain conflicts; nearest subtype and instance specificity supply no override. Initial-value definitions do not become inherited continuing capabilities, stock or implicit event effects.

Rule type hints now enumerate relevant rules over the complete candidate through ancestor membership and each evaluated world cell. They do not bind variables, discover a quantifier collection, replace an explicit subject or filter an authored expression. A known matching instance establishes relevance; without one, unknown membership prevents a convenient rule-skipping verdict. The existing finite expression evaluator remains responsible for the actual condition.

Full-candidate validation rechecks retained facts, relation participants, occurred-event owner requirements and authored preconditions when definitions change. Scalar comparison includes inherited shared witnesses without writing synthetic instance assertions. The evaluator binding is `finite-policy-v9-ancestor-definitions`; old validation/approval bindings cannot authorize new publication. Existing immutable history and receipts remain unchanged. No persisted schema change is required.

## Independently specified and executed proofs

The [admission oracle](../fixtures/ancestor-applicability/oracle.json) is separate from the driver and implementation. The actual MCP driver uses a disposable installation, authenticated private author review/approval, the closed public schemas and the existing transactional commit path. The [wire auditor](../scripts/audit_ancestor_applicability.py) determines results from captured MCP responses, checks denied commits, exact retry receipts and delivered historical records, and does not trust the driver's status labels.

The final run covers 28 cases, 147 captured MCP calls and six authorized publications with exact retries:

| Area | Legal controls | Illegal controls | Unresolved controls |
|---|---|---|---|
| Classification | Cedar property and Tree-typed relation participant | Stone property/participant | Unclassified/ambiguous instance; ambiguous parent |
| Definitions | Exact inherited Tree capability | Conflicting Tree/Cedar values; property/relation changes invalidate retained facts | Unknown world applicability |
| World jurisdiction | Explicit allowed world; parent A applicability survives child B restriction | Other world; universe-wide fact cannot widen a bounded definition | Unspecified world applicability |
| Rules | Ancestor targeting with unchanged authored operands | Explicit unrelated subject remains a failed condition | Unknown subject classification |
| Events | Cedar uses inherited Tree capability | Expired capability, unrelated actor, conflicting definitions, initial-value-only capability, other context | Missing/unknown capabilities remain nonauthorizing |
| Correction/restart | Atomic correction removes invalidated facts/event and retains instance identity | Parent correction invalidates an unchanged event; subsequent event still fails after restart | Historical evidence is retained, never silently rewritten |

Nine focused Rust tests additionally specify half-open endpoints, context/realm separation, unknown validity alongside exact instance evidence, shared/instance conflict, absence of initial-value inheritance, independent world checks, rule targeting, direct definition jurisdiction, possession-grant/shared conflict and historical snapshot isolation. Indexed and unindexed claim paths agree on the exercised cases.

The original Cedar characterization records and their digest fields remain frozen. Two current expectations are separately specified in [historical expectations](../fixtures/ancestor-applicability/historical-expectations.json): an inherited Tree assertion with unspecified validity adds an unresolved obligation at a dated frame even when exact instance support exists. Support remains Supported (or Refuted after negation), but coverage cannot remain complete. This is deliberate preservation of unknown inherited applicability, not removal of the original evidence or relaxation of admission.

The broader serial regression run passed 313 test executions, with one existing ignored workload benchmark. After the final claim refinements, current library tests passed 106 cases (46 rules and 60 service), including the nine focused ancestor cases. The full 22-case workflow suite also passed serially; final possession/shared conflict coverage comes from the current library and MCP proofs. Formatting checks passed.

The independent audit's five corruption controls pass: real wire evidence passes, while rewritten restart history, false denial envelopes, a relabelled unresolved proposal and a forged publication receipt fail.

## Reproduction

Use the repository's existing `jsonschema==4.25.1` Python test dependency.

```sh
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp
python scripts/ancestor_applicability_pilot.py --output /tmp/ancestor-proof.json
python scripts/audit_ancestor_applicability.py /tmp/ancestor-proof.json --output /tmp/ancestor-audit.json
python scripts/test_ancestor_applicability_audit.py --evidence /tmp/ancestor-proof.json -v
cargo test --locked -p universe-service -p universe-rules -p universe-schema -p universe-store -p universe-protocol -- --test-threads=1
cargo fmt --all -- --check
```

The [proof summary](ancestor-applicability-proof-results.json) binds the executed report and wire digests. Local report/wire evidence is retained under `/tmp/ancestor-proof-final.json` and `/tmp/ancestor-proof-final.jsonl`; the disposable installations and owned engines were removed/stopped by the driver. Repository policy excludes raw evidence under `docs/evidence`; the committed driver, oracle and auditor reproduce it.

## Failed attempts and limitations

Early harness attempts stopped for a missing Python schema dependency, a missing transcript sink, malformed relation/world inputs and reused proposal-reserved identities. These were corrected in the driver without bypassing the public schema or identity checks. A focused initial-value conflict test exposed and corrected mixing initial definitions with continuing shared witnesses. Source review also corrected rule hint handling to enumerate relevance without filtering explicit operands, and distinguished known nonapplicability from unresolved applicability. The final oracle reflects that distinction.

The first concurrent regression run timed out in two archive integration tests at export/restore calls. The unchanged 22-test workflow suite passed serially. No timeout or acceptance gate was widened.

Conditional applicability, realm-dependent claims and unsupported or unresolved clocks/bounds remain incomplete and cannot authorize blocking rules/events. This goal does not materialize initial values, simulate growth/refills, add dynamic collection/state-value operands, deliver an effective-object UI or certify external prose interpretation. Existing native/host qualification pauses remain outside this goal. No production data was migrated or published.
