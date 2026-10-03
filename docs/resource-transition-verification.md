# Exact resource transition verification

October 3, 2026. Extends the existing consequence contracts after Goal 16's
set-effect enforcement, from committed baseline `dc40453`.

## Behavior

Enabled, supplied delta slots on occurred events resolve stock on the exact entity
bound to their declared role, property, context and event worlds immediately before
the event. Only explicit direct or event-generated assertions establish stock.
An unasserted proposition, cap, possession-derived power or missing balance cannot
supply a value. Multiple agreeing assertions corroborate a single exact amount;
incompatible supported values, opposed support, uncertain evidence and unresolved
validity block admission. Expired evidence and evidence starting at the event do
not supply pre-event stock. Each affected world is checked separately; universe-wide
execution cannot borrow world-specific evidence.

Dimensionless integers and integer quantities in the exact declared unit use
bounded i128 arithmetic. Both the established pre-value and calculated post-value
must satisfy the declared inclusive bounds. Addition is checked for host overflow.
The authored supported post-proposition must equal pre-value plus declared delta;
no balance, missing effect, unit conversion or repair is inserted silently.
Consumption, replenishment and two-owner debit/credit effects use the existing
slots and atomic proposal commit. No conservation rule is inferred from names:
transfers in the proof explicitly declare equal opposite required changes. Missing
or invalid credit rejects the whole event, including its debit. Existing owner
alias rejection still applies.

Optional omitted and conditionally disabled slots execute no resource change.
Non-occurred events retain existing nonexecution semantics. All other Goal 16
checks remain in place. The full candidate check revalidates unchanged bound
events when their evidence changes. Generated assertions still use `events-v1`
and are frozen before author review. The evaluator binding is now
`finite-policy-v7-resource-transitions`; previous validation and approval bindings
cannot publish under these semantics. No schema, tool, state ledger or authority
model was added.

Multi-event ordering, simultaneous spending enforcement, reusable world rules
and prose qualification are excluded. This establishes exact single-event
transitions through the existing contracts, not completion of all D02 behavior.

## Proofs

The [frozen fixture](../fixtures/resource-transitions/expected.json) contains 44
independently authored cases. The Rust consequence regression runs all of them,
alongside Goal 16's 41 set-effect cases. Cases include consumption, replenishment,
last-round zero, forged balances, missing evidence/effects, wrong owners,
refutation-only and conflicting evidence, ambiguous balances, expiry, same-time
bootstrap, uncertain validity/precision, both bounds and i128 overflow directions,
values beyond float precision, exact i128 maximum, unsupported magnitudes/units,
corroboration, optional omission, planned nonexecution, atomic transfer failures,
world agreement/disagreement and possession power without spendable stock.

The separate [Fraction calculator](../scripts/resource_accounting.py) imports no
production arithmetic or evaluator and calculates all 44 outcomes from the frozen
inputs. Its [results](evidence/resource-transitions-final/independent-accounting.json)
record exact pre/change/expected-post/proposed-post values, including both sides
of the valid transfer (12 - 1 = 11; 4 + 1 = 5).

The [actual MCP proof](evidence/resource-transitions-final/result.json) passes
39 transition cases: **12 committed and 27 rejected**, plus two rejected evidence
retcons on an unchanged committed consumption event. It makes 339 actual MCP calls
in a disposable synthetic installation. Unsupported quantity magnitudes reach
validation; five malformed/nonconforming proposition cases additionally run in
the focused fixture regression rather than being represented as successful MCP
proposal creation.

The [independent auditor](../scripts/audit_resource_transitions.py) checks raw
JSON-RPC against reported requests/responses, independently binds every stimulus
to the frozen fixture, computes accounting, reconstructs complete canonical
SQLite history and checks validation, private author review, exact approval,
frozen operation changes, kernel receipts, commit footprints, generated assertion
identities/payloads and state queries at ticks 10, 11 and 15. Transfer state and
receipt replay agree after restart. Invalid transitions and evidence retcons
have identical before/after canonical snapshots and no event commit. This is an
independent program audit, not a human review.

All seven [auditor tests](evidence/resource-transitions-final/audit-negative-tests.json)
run: the saved proof passes; changed oracle, query, review, head, wire owner and
a rehashed forged accounting expectation fail. Source/binary/oracle hashes remain
unchanged during the final proof. The evidence manifest hashes every saved artifact.
The package contains synthetic records and no installation profile credentials.
Earlier attempts are retained locally; the first encountered repeated synthetic
world selectors, and the third encountered a fixture field spelling error. These
were proof harness errors, corrected in the final run.

## Reproduction

```sh
cargo run --locked -p xtask -- check
UNIVERSE_PYTHON=/path/to/jsonschema-4.25.1/python cargo run --locked -p xtask -- validate-contracts
cargo test --locked -p universe-service consequences::tests --lib
python3 scripts/resource_accounting.py
/path/to/jsonschema-4.25.1/python scripts/resource_transitions_pilot.py --output /tmp/fresh-resource-proof
```

Final workspace checks pass 325 tests with zero failures and one existing
ignored workload, formatting, warnings-as-errors Clippy and schema freshness.
Contract checks pass 26 schemas, 13 valid and 91 malformed examples, six
source-assessment tests and five action-contract tests. Results and full logs
are recorded in [verification](evidence/resource-transitions-final/verification.json).
