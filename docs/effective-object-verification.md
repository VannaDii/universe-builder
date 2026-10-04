# Goal 29: effective object retrieval

October 4, 2026. Implements the retrieval portion of the approved [definition model](decisions/relational-storage/README.md#attributes-and-applicability), extending the existing state and context tools.

`universe_get_state.result.objects` assembles each requested visible entity/type from the context's exact continuity and revision. Identity retains the full instance payload, including classification resolution. Ancestry retains exact type versions, including a visible unresolved endpoint; `ancestry_complete` distinguishes an executable chain from incomplete provenance.

The result separates `shared_attributes`, `instance_facts`, and `initial_value_candidates`. Each candidate retains the original assertion, exact version/digest, authored owner, scope, validity, polarity, precision and basis. `dependencies` delivers its visible proposition/property records; ancestry delivers definition provenance. Shared propositions retain their type owner: retrieval does not rewrite them into instance assertions. Initial candidates never appear as observed facts.

Each source has `applicability: true` or `null` and named unknowns. Known inapplicable sources are excluded. World membership is checked independently on each ancestor, alongside assertion scope, represented context, property subject applicability and authored time. An omitted world does not establish a bounded world's applicability. Unknown ancestry, realm applicability, clock/bounds, missing instance state, qualified precision/value and current authority/perspective limitations remain explicit.

`behavioral_requirements` delivers the exact relevant action definitions, including owning roles, required values and declared consequence contracts. Relevance follows each requirement property's subject types. These are possible owning-role requirements; inclusion does not bind an object to an action participant or establish that an action can occur. `rules` delivers exact relevant rule versions using their declared subject ancestry, world and validity, without changing rule operands or evaluating a new verdict.

`conflicts` reports both exact assertion versions. Continuing shared/instance evidence is compared together; initial candidates are compared separately. Opposing polarity and competing single/exclusive-property values remain visible. Multiple-valued properties and disjoint authored intervals do not falsely conflict. Exact scalar equality uses the existing comparator. A conflict with unresolved applicability/precision is marked `null`. A shared comparison budget marks incomplete work explicitly rather than choosing a value.

Object coverage describes completeness of the visible authored evidence assembly. It does not certify physical, manuscript or action completeness. The existing overall state coverage remains partial for its broader unsupported inference capabilities. Restricted views receive a generic limitation and no hidden source identifiers. Current permissions are rechecked through the existing authenticated context path; revocation invalidates retained contexts. Context briefs now seed relevant action/evidence records before the existing mandatory dependency closure and pagination, preserving the existing byte budget.

## Independent MCP qualification

The [expected table](../fixtures/effective-object/expected.json) is separate from the [driver](../scripts/effective_object_pilot.py) and [auditor](../scripts/audit_effective_object.py). The driver captures actual stdio MCP envelopes from an owned disposable installation. Normal publications use existing private author review, exact approval, validation and atomic commit/retry. The auditor reads received envelopes and compares object rows, exact visible record provenance, conflicts, coverage and action revisions against the independent expected table. It binds provenance to actual `universe_get` delivery rather than accepting the driver's labels alone.

| Views | Evidence checked |
| --- | --- |
| Original, historical, current | Tree/Cedar identity and ancestry; exact action revision; both opposing inherited witnesses |
| Later and expired | Height remains 7; ammunition remains 2; initial ammunition 6 remains a candidate; half-open expiry and unknown validity |
| Predicate filter | Only requested attribute rows; behavioral constraints retained |
| Unclassified | Empty executable ancestry, relevant unresolved requirements/rules, partial coverage |
| Separate represented context and character | No borrowing objective state; perspective limitation explicit |
| Omitted world, A and B | B-bounded evidence remains unresolved without a world, excluded in A, applicable in B |
| Current world grant and revocation | B evidence absent with no identifier/version leakage; retained context denied after revocation |
| Restart, historical/current and scalar | Equal object results and exact witnesses survive process restart |
| Competing inherited scalar values | Both values and both conflict pairs remain visible; no subtype/instance/newest-value override |

The scalar-conflict specimen uses the [test-only historical seed example](../crates/universe-store/examples/seed_effective_object_conflict.rs), constrained to two exact record families/identities and an `effective-object-` disposable path. Normal scalar admission rejects this inconsistent state. This bootstrap qualifies retrieval of inconsistent stored history; it does not claim that public admission accepts competing values. The other specimen records use public proposal/commit paths.

Every state read checks unchanged canonical table and operation-receipt counts. Exact source comparison checks unchanged identity, height, ammunition, assertion payloads and digests. Restart comparisons check the complete state result. The auditor's six controls include a passing original and rejection of a dropped inherited witness, removed conflict, initial candidate promoted to observed fact, unknown promoted to applicable, and forged ancestry version. Mutations also alter captured wire delivery so the table/provenance checks must reject them.

Reproduction:

```sh
cargo build --locked -p universe-engine -p universe-mcp -p universe-cli
cargo build --locked -p universe-store --example seed_effective_object_conflict
python scripts/effective_object_pilot.py --output /tmp/effective-object-proof.json
python scripts/audit_effective_object.py /tmp/effective-object-proof.json
python scripts/test_effective_object_audit.py --evidence /tmp/effective-object-proof.json -v
cargo test --workspace --locked -- --test-threads=1
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo fmt --all -- --check
cargo run --locked -p xtask -- check-schemas
```

The [proof summary](effective-object-proof-results.json) binds the final report/wire digests and executed checks. The driver stops its owned engine and removes disposable installation state; only local report/wire artifacts remain. CI includes the driver, independent audit and mutation controls.

## Limits and qualification notes

There is no implicit growth, refill, initial-value materialization, new physics, action execution, prose interpretation or native effective-object UI. Conditional/realm-dependent applicability and unsupported temporal relationships remain unknown. Required-role enumeration does not establish execution eligibility. Predicate filters restrict attribute rows while retaining relevant action/rule definitions.

Concurrent test runs encountered the existing archive integration test's RPC deadline. Its isolated rerun passed. The final serial workspace result is recorded in the proof summary. The strict lint gate also exposed preexisting borrowed-slice warnings in ancestor resolution/tests; those were fixed without changing semantics. Native/VoiceOver, hosted CI, production migration and release qualification remain outside this goal.
