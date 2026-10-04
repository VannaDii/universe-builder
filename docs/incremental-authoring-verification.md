# Goal 30: incremental factual authoring

October 4, 2026. Adds four typed operations to the existing `universe_propose`
catalog. The service lowers them before freezing the canonical assignments for
review; validation, author approval, current grants, head comparison, publication
and receipts remain on the established path.

| Operation | Canonical result |
| --- | --- |
| `introduce_definition` | An EntityType with explicit namespace/key/name, applicability and executable-classification choice. A supplied parent is resolved; no parent declares a root. Labels start empty. |
| `introduce_instance` | An Entity with one contextual name, explicit world associations, optional classification and empty labels/metadata. No classification retains `unclassified`; name/world validity remains authored. |
| `add_named_attribute` | A named Property plus a Proposition and Assertion, or just the proposition/assertion when an exactly matching property already exists. |
| `refine_classification` | A new version of the same Entity, retaining every field except classification/resolution, guarded by its exact expected version. |

A minimal definition does not need properties, units, rules, actions or an
instance. A minimal instance does not need classification or factual attributes.
World association is separate from physical location. Missing height, units and
growth conditions are not populated with defaults.

An attribute names its namespace/key, typed shape, subject-type restrictions and
multiplicity. Its evidence explicitly supplies attribute mode, polarity, scope,
validity, persistence, precision, alternatives and basis. The property uses the
same declared persistence; inverse/symmetric/transitive/exclusive behavior is not
introduced. Existing property labels are retained. Conflicting named definitions
reject rather than silently revising semantics. Properties created explicitly in
the same batch can be reused by name when their `client_ref` reserves a `rec_` ID.
Friendly references allocate identities; explicit IDs support cross-operation
references. Duplicate friendly or reserved references reject.

The assertion retains its authored evidence and represented context. Shared
facts retain their definition subject; instance hazards retain their instance
subject. Unknown validity, unresolved precision and imported evidence are
preserved. This convenience never manufactures event linkage, source verification
or current state from an initial-value declaration. Advanced property semantics
and fact revisions continue to use the existing canonical operations.

Refinement assigns a first known classification to an unclassified instance or
moves an established classification along a resolved descendant chain. Ambiguous
classification requires an explicit authored correction. An unrelated type is
not accepted as refinement. The check uses the candidate definition graph,
including same-batch creations, revisions, adoptions and tombstones, independent
of operation ordering. It retains stable identity and does not describe a physical
transformation. Corrections are explicit authored factual changes; this goal adds
no arbitrary classification-correction convenience. Physical transformations
remain separately authored occurrences through the event/effect path.

## Executed proof

The [driver](../scripts/incremental_authoring_pilot.py) uses actual stdio MCP
calls, authenticated private author review/approval and one owned disposable
installation. It creates a minimal Tree definition and an unclassified North tree,
classifies it as Tree, adds a shared climbing capability and a North-tree-only
broken-branch hazard, then introduces Cedar and refines that same instance in one
batch. A second tree reuses the named hazard property with a different observation;
it does not receive the first tree's hazard. An inspection note retains unknown
validity and unresolved precision; height/unit/growth-condition facts remain absent.

Five proposals complete propose → validate → exact private approval → commit.
Each ordinary publication also proves denial before approval and exact commit
retry. Proposal retry survives a forced engine restart with unchanged frozen
assignments. An approved pending commit survives permission denial, a forced
restart, an injected publication failure and another restart before successful
retry. Current and historical canonical readback remain equal across recovery.

The independent [auditor](../scripts/audit_incremental_authoring.py) reconstructs
canonical bodies directly from typed SQLite columns/children using the existing
independent reader and handwritten canonical encoder. It verifies payload digests
and reconstructs membership from ordered historical commits/changes, without the
service compiler or cached head membership. Seven snapshots are compared against
actual received MCP records, and separate factual expectations check exact identity,
classification, ownership, scope, provenance and unknowns. The captured object view
also separates definition capabilities from instance observations and unresolved
applicability.

Six propose failures leave canonical counts and durable workflow counts unchanged:
unrelated Stone refinement after a same-batch definition creation, stale expected
version, a conflicting named shape after a same-batch instance creation, attempted
event-effect provenance, duplicate friendly references and a shared type outside a
world-only grant. The hostile event-effect control calls the server directly: the
existing public schema also excludes that input through its event/event-side
constraint; the compiler independently rejects it.

An invalid typed value fails actual validation; approval with another candidate's
run and commit both reject without canonical writes. Revoking edit/protected access
after approval denies commit under current grants. A disposable SQLite trigger on
`commit_changes` forces publication to fail after publication begins. Record
versions, commits, changes, memberships and canonical receipts remain unchanged;
independent canonical reconstruction is identical. The resumable workflow intent
is allowed to remain for exact retry. Removing the trigger and restarting permits
the same approved request to finish exactly once.

Four focused Rust tests cover ambiguous classification, candidate reparenting,
tombstoned refinement targets and same-batch property reuse with unresolved/imported
evidence. Six [audit controls](../scripts/test_incremental_authoring_audit.py)
include a passing original and five coherent report/wire forgeries, with rewritten
payload digests: unrelated classification, shared hazard promotion, erased world
scope, unknown validity promotion and replaced evidence basis all fail the oracle.

The typed relational catalog appends four operation variants and their evidence
fields. Every preexisting model and the first fifty operation branches remain
unchanged. Canonical fact families and their digests are not redefined.
The final serial workspace gate passed 377 tests, with zero failures and one
existing ignored workload benchmark, strict workspace Clippy, formatting and
schema consistency. Public contracts passed 26 schemas, 13 valid examples and 91
invalid examples; the six assessment and five action-consequence contract tests
also passed. The [proof summary](incremental-authoring-proof-results.json) records
evidence hashes and final checks. CI now reproduces the lifecycle and independent
audit.

## Reproduction and limits

Use the existing Python `jsonschema` test dependency:

```sh
cargo build --locked -p universe-engine -p universe-cli -p universe-mcp
python scripts/incremental_authoring_pilot.py --output /tmp/incremental-authoring.json
python scripts/audit_incremental_authoring.py /tmp/incremental-authoring.json
python scripts/test_incremental_authoring_audit.py --evidence /tmp/incremental-authoring.json -v
RUST_TEST_THREADS=1 cargo run --locked -p xtask -- check
python scripts/validate_contracts.py
```

The concurrent workspace run hit the previously observed archive integration RPC
deadline. Final results are recorded for the unchanged serial suite; no timeout or
acceptance gate was widened. Early implementation attempts exposed a missing typed
operation storage mapping and malformed harness assumptions about world-association
fields and validation errors. These were corrected before the final passing run.

The driver stops its owned engine and deletes the disposable installation. Raw
report/wire evidence remains locally under `/tmp/incremental-authoring-proof-final`
with `.json`/`.jsonl` extensions. No production package or installation migration,
native UI/VoiceOver, model prose interpretation or host/release qualification was
performed. This goal does not initialize missing state, infer physical behavior,
perform a correction or execute a transformation implicitly.
