# Goal 31: reviewed once-only instance initialization

October 4, 2026. The explicit `initialize_instance` operation names the instance,
its occurred start, an approved initial-value assertion version, and the scope and
interval beginning at that start. Compilation freezes a separate proposition and
instance assertion before review. Definition evidence alone never supplies current
stock. No retrieval, mention, scene, name, classification, holder association,
definition edit or process restart invokes initialization.

The compiler evaluates the full resolved classification ancestry and every
applicable initial-value candidate for the property, context, requested worlds and
start time. The explicitly selected source must be applicable and unchanged from
the review base. Agreeing supported values can coexist with explicit source
provenance; differing supported values, opposed evidence and unresolved candidate
applicability/value/precision require authored resolution. Candidate records remain
available; initialization never chooses a winner or discards evidence.

Reviewed publication creates an `instance_initialization` basis pinning start
and definition versions and the source snapshot revision. A relational receipt
binds instance, start, property, definition version, source revision, generated
assertion version and admitting revision. It shares the canonical transaction
with versions, changes, head and ordinary commit receipt. Preview rolls these
back. The universe-owned instance/property guard prevents another initialization,
even after retraction or expiration of current stock. Missing current evidence is
not permission to bootstrap again.

Historical correction remains an explicit reviewed edit. Revising or restoring
the original assertion identity retains its original receipt; corrected stock and
downstream event effects do not rewrite the admission. Startup verifies receipt
bindings against immutable original admissions. Complete and filtered logical
archives retain receipt history and the initialization assertion dependencies.
The single unreleased relational schema changes in place; existing installations
are not automatically converted.

`universe_get_state` objects report `initialization_receipts` separately from facts
and candidates. Receipt history follows the queried revision's commit ancestry,
including baseline ancestry, and its property/context/world filters. It does not
filter original admission by story time or claim a current balance. Unrestricted
author views report complete initialization history; restricted authority and
non-author perspectives withhold it and report restricted coverage.

The actual disposable MCP installation uses exact proposal, completed validation,
private author review, explicit approval and exact commit/retry. The independent
handwritten audit reconstructs typed canonical rows, verifies received immutable
record digests, and checks literal balances and provenance without importing the
production initializer or evaluator. Its proofs include:

- Pistol A starts at 7 and consumes to 6 then 5. Pistol B independently starts at
  3 after an approved definition edit, while A stays consumed. A later definition
  edit to 9 changes neither existing pistol.
- Rename, descendant classification refinement, holder transfer, an unasserted
  mention and a scene preserve stock and the two original receipts.
- Proposal replay across restart and exact commit retries reuse frozen outcomes.
  Restart preserves stock and receipts; same-start/later-start/stale-source
  initialization attempts publish nothing.
- Reviewed historical correction changes A's initial evidence to 8 and its
  downstream balances to 7 then 6. The old revision still returns 7, 6 and 5;
  original receipts remain unchanged.
- A third pistol retains competing exact and unresolved definitions, with no
  stock or receipt. Rejected starts leave canonical and workflow counts unchanged.
  After explicit author withdrawal of the competitor, an injected midpublication
  failure leaves head, canonical readback and receipts unchanged. The exact
  request succeeds once after restart. Its later missing balance cannot refill;
  the earlier conflicting revision never gains its future receipt.
- Storage tests cover all six publication fault points, all application-table
  counts, startup tampering/missing receipts, restoration, pinned history and
  complete/filtered archive recovery. Compiler tests cover agreeing/conflicting/
  opposed/unknown candidates, exact start boundaries, source jurisdiction,
  same-batch source changes and raw evidence bypass rejection.
- Coherent forged canonical and received-wire records are rehashed before audit
  controls. Refill, shared-to-instance promotion, replaced provenance, erased
  scope, resolved-unknown forgery, rewritten history, receipt misbinding, future
  receipt leakage and partial publication must all fail the independent oracle.

Reproduce the scoped proof after building the three binaries:

```sh
cargo build --locked -p universe-engine -p universe-cli -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/instance_initialization_pilot.py --output /tmp/instance-initialization-proof/actual.json
python3 scripts/audit_instance_initialization.py /tmp/instance-initialization-proof/actual.json
python3 scripts/test_instance_initialization_audit.py --evidence /tmp/instance-initialization-proof/actual.json -v
RUST_TEST_THREADS=1 cargo run --locked -p xtask -- check
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
python3 docs/decisions/relational-storage/prototype.py
```

CI executes the MCP proof and independent oracle controls. The proof result
summary records evidence and binary digests, executed check results and scope.
Raw local evidence includes MCP wire frames, author CLI outcomes, canonical
snapshots and SQL receipts; the owned engine and temporary installation are
removed when the pilot ends.

Limitations: starts require exact authored clock coordinates, resolved executable
ancestry, property predicates, explicit supported values and world/universe
jurisdiction. Realm-based or unresolved jurisdiction requires resolution. This
is a synthetic structured-authoring fixture with actual MCP and private review,
not external-model prose qualification, native GUI/VoiceOver, production
conversion, deployment or release evidence. Overall state coverage remains
partial for existing unsupported inference capabilities; complete initialization
history covers durable admissions only.

Executed final checks: 390 passing workspace tests, zero failures and one existing
ignored workload; formatting, strict Clippy and schema consistency pass. The MCP
oracle covers 15 canonical snapshots, 21 state checks, 62 delivered immutable
versions, 18 reviewed publications, three receipts and six rejected starts.
All ten oracle tests pass, including nine forged-evidence controls. Contracts pass
26 schemas, 13 valid and 91 invalid examples. The independent relational prototype
passes with 867 tables and 518 closed-union/workflow round trips.
