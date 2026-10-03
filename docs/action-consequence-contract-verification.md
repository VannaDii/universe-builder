# Action consequence definition contracts

October 3, 2026. Implements the definition-contract slice of approved
[D02](decisions/d02-action-consequences.md), from baseline
`f6265e5f822ca373503e3ce10b756a383bbe5ac4`.

## Delivered contract

`ActionDefinition.consequenceContract` is an optional versioned closed object:
`{kind: "action_consequences_v1", slots: [...]}`. Every declared slot is a
permitted effect; `presence: required` also declares an obligation when its
condition holds, while `optional` permits omission. Each slot names its owner
role and property, condition (`always` or `attribute_equals`), fixed change
(`set` with polarity/value or `delta` with bounds and exact nullable unit),
explicit order, and lifetime (`until_changed` or positive `ticks`).

The implementation uses the bounded representation in the supporting D02 notes
as a routine implementation choice for the approved behavior: at most 64 slots,
unique nonblank names and role/property targets, unique orders 0–63, names/roles
at most 120 UTF-8 bytes, canonical decimal strings within i128, nonzero deltas,
minimum no greater than maximum, and no expiring delta balances. It does not
introduce expressions, inferred quantities, conversion, or another state ledger.

Typed decoding rejects unsupported versions/variants, missing or unknown fields,
explicit null contracts, invalid bounds and duplicate slots. The existing wire
parser rejects duplicate JSON keys, including escaped key aliases. Candidate
structural validation checks target and condition property kinds and value
shapes, same-universe predicates, single-valued numeric delta properties, and
exact quantity units. Existing store reference traversal indexes nested
predicates, value references and units and applies namespace/reference guards.

Generated schemas expose the same closed shapes, required nullable unit,
supported variants and structural/scalar limits through the existing tool
catalog. Cross-field uniqueness, UTF-8 byte counts, exact i128 bounds,
property conformance and reference resolution remain owning decoder/candidate
checks; JSON Schema alone cannot certify those invariants.

## Compatibility

Missing contract remains missing after canonical serialization and retains the
historical meaning of an undeclared consequence contract. It is never defaulted
to an empty contract. An explicit empty contract declares no permitted effects;
null is rejected. Historical actionless events and existing event representations
are unchanged. Schema/digest versions and canonical discriminator recipes are
unchanged. No history is rewritten or automatically migrated.

This slice does not require migration of touched historical actions/events,
match events to slots, execute resource accounting, implement author clarification
or reusable world-rule enforcement, alter publication/authority gates, or certify
legacy consequences. Those behaviors need the subsequent enforcement work.
No new capability identifier or native UI is added.

## Proofs and reproduction

The frozen [fixtures](../fixtures/action-consequences/payload-digests.json) were
hand-authored as JSON separately from the Rust implementation. Expected UTF-8
bytes use sorted keys, preserved authored Unicode and compact separators;
SHA-256 expectations were calculated independently with Python and OpenSSL,
without importing the production serializer/digest functions. Seven fixtures
cover a historical action, historical actionless event, empty contract,
dimensionless consumption, exact-unit debit/credit, conditional optional timed
grant, and refutation. Rust round-trips compare these exact frozen bytes and
digests, rather than generating their expectations from the implementation.

Run with the repository's pinned `jsonschema==4.25.1` Python environment:

```sh
cargo run --locked -p xtask -- check
UNIVERSE_PYTHON=/path/to/python cargo run --locked -p xtask -- validate-contracts
```

Focused tests:

```sh
cargo test --locked -p universe-protocol --test action_consequence_contracts
cargo test --locked -p universe-service consequence_definition_tests
cargo test --locked -p universe-store consequence_reference_tests
```

The focused tests cover valid round-trip/digests, historical absence, explicit
empty/null distinctions, every new tagged shape, duplicate/escaped keys,
canonical numeric spelling, overflow, zero deltas, reversed bounds, unsupported
lifetimes, count/name/order limits, property/condition conformance, unit and
namespace rejection, and maximum supported slots/numeric values. The Python
proof checks every generated action schema in both request and response catalog
positions and independently recomputes all seven digests by both hash methods.

## Observed results

- Workspace check: 322 tests passed, zero failures, one existing ignored test;
  formatting, warnings-as-errors Clippy and generated-schema freshness passed.
- New focused Rust proofs: six decoding/compatibility tests, three definition
  conformance tests and one store reference-index/namespace test passed.
- Independent action schema/digest proof: five Python tests passed, including
  checks against every catalog position containing an action definition.
- Existing catalog proof: 26 schemas, 13 valid examples and 91 malformed examples
  passed; the six existing source-assessment proof tests also passed.
- All seven frozen payload bytes/digests agree, including both historical cases.

These results establish definition contract behavior only. They do not establish
resource spending, event consequence enforcement, author clarification behavior,
native UI qualification or real-world publication.
