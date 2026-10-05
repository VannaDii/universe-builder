# Goal 31: reviewed instance initialization

October 4, 2026. **In progress.** The first implementation slice supplies durable
publication evidence. It does not yet qualify the full writer-facing workflow.

An instance assertion can carry `instance_initialization` evidence, pinning the
start event version, initial-value assertion version and source snapshot revision.
The existing relational initialization receipt additionally binds the instance,
property, generated assertion version and admitting revision. The receipt is
written in the same kernel transaction as canonical versions, changes, head and
ordinary commit receipt. Proposal preview rolls all of these back.

The kernel requires an occurred start with an exact authored clock coordinate and
the instance as a participant. The generated interval begins at that coordinate.
It requires a supported, exact initial-value assertion at the review base and a
matching instance proposition/value/context/scope. The source assertion and its
proposition cannot change in the same proposal. A resolved explicit classification
chain must contain the definition subject. Existing instance evidence requires
resolution rather than bootstrap. Prior receipts prevent another initialization
of the same instance/property, including after retraction. The receipt guards the
universe-owned identity; it is not a scene-local or continuity-local balance.

Corrections remain ordinary reviewed factual edits. Changing a proposition or
retaining the initialization basis on a revised assertion does not write another
receipt. Immutable historical versions and original receipts remain available.
Provenance cannot be attached to an existing unrelated assertion as a correction.
Startup compares receipt rows with original initialization admissions in immutable
commit history and rejects missing or altered bindings.

Logical archives retain receipt rows, including canon-only exports. Filtered
exports of an initialized instance include its historical initializing assertion
and the assertion's provenance dependencies; cloning cannot discard the guard.
This changes the single unreleased relational schema in place. No automatic
conversion of an existing installation is introduced.

Executed storage proof:

```sh
cargo test --locked -p universe-store --test initialization -- --nocapture
```

Five tests prove separate instance receipts, exact commit retry, restart,
proposition correction with original historical readback, assertion retraction,
duplicate initialization, a value inconsistent with the definition, preview
rollback, all six publication fault points, startup receipt tamper/missing-row
detection, and complete/filtered logical archive recovery. Fault tests compare
row counts in every application table before and after failure. Each fault also
restarts and publishes the original exact request once.

Additional executed checks:

- `RUST_TEST_THREADS=1 cargo run --locked -p xtask -- check`: 382 passing tests,
  zero failures, one existing ignored workload, formatting, strict workspace
  Clippy and generated-schema consistency.
- `uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py`:
  26 schemas, 13 valid examples and 91 invalid examples pass.
- `python3 docs/decisions/relational-storage/prototype.py`: the independent
  typed reconstruction, semantic examples, archive and installation probes pass;
  866 tables inspected and 517 closed-union/workflow round trips. These remain
  disposable schema prototypes, separate from actual MCP qualification.

Remaining Goal 31 work includes the explicit authoring operation, complete scoped
candidate selection and unresolved/conflicting-candidate preservation, historical
adoption semantics, receipt retrieval through the public workflow, and actual MCP
pistol proofs with resource consumption, mention/scene/rename/refinement/holder/
definition-edit controls, private review, failed publication and independent
relational/wire auditing. These storage tests are not evidence of those outcomes.
The goal remains active until the complete scope passes and all work is committed.
