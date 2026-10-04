# Normalized foundation verification

October 3, 2026. Implemented against the approved
[relational storage decision](decisions/relational-storage/README.md).
This is the scoped definitions, instances and temporal facts foundation.

## Runtime implementation

New packages install the single normative typed, kernel and semantic SQL
layouts atomically. Record versions point to fixed typed body rows; snapshot
membership uses child rows. There is no persisted generic record JSON body,
active payload schema tag, schema-version dispatch or automatic old-package
conversion. Existing serialized packages are refused before journal or policy
changes, preserving the original for a separately authorized conversion.

The existing kernel writes bodies, history, head, projections and receipts in
one transaction. Reads reconstruct domain records from typed rows and compare
the canonical digest with the stored digest; disagreement fails closed.
Exact digits and units, Unicode, collection order and duplicates, absent/null,
unknown/unbounded time and empty/universe applicability remain distinct.

Definitions have one resolved parent or an explicit root/ambiguous state.
Instances have one resolved classification or an explicit
unclassified/ambiguous state. Names remain authored labels. Assertions distinguish
instance, shared and initial-value attributes. The existing classification
operation refines along an ancestry chain while preserving instance identity;
unrelated reclassification requires an explicit authored correction.
Snapshot admission validates definition ancestry, reference identity and kind,
pinned versions, contexts, scope, evidence anchors and exact typed values.

## Independent factual and integrity proofs

`fixtures/normalized-foundation/facts.json` specifies 32 initial records and
five later versions independently of the Rust writer. The disposable package
contains Tree/Cedar/Western red cedar and Gun/Pistol definitions, three instances,
30.00 then 31.2500 feet, independent pistol balances (7 then 6, and 3),
shared and initial-value assertions, rename/refinement history and pinned source
evidence. Metadata includes false, zero, empty text, a large exact integer,
rational, decimal range, ordered duplicate Unicode values, references and time.

`crates/universe-store/tests/normalized_foundation.rs` checks:

- Publication, pinned fork membership, restart, exact history, receipt retry and
  all 37 frozen canonical digests. `scripts/verify_normalized_foundation.py`
  separately reconstructs typed bodies and commit membership directly from
  read-only SQL, using the independent decision-package reader and Python hashes.
- Dangling/wrong-kind classifications, cyclic parents, incorrect pinned versions,
  cross-universe scope, invalid context/proposition/mode and malformed values
  leave every typed-body and kernel-authority row count unchanged, with no receipt.
- All six precommit fault points roll back children, history, head and receipts.
  Abrupt subprocess exit at those six points and after commit proves all-or-none
  publication after restart, followed by safe idempotent retry.

The codec's separate independent SQL proof covers 72 frozen canonical bodies
and 50 Cedar/Pistol body versions after restart. It verifies canonical bytes and
hashes, immutable rows, foreign keys, rollback, ordinal gaps and cyclic pointers.

Original `fixtures/action-consequences/payload-digests.json` remains unchanged.
Its exact source bytes and old digest recipe are checked as historical evidence.
`fixtures/normalized-foundation/historical-digests.json` freezes the corresponding
normative bytes and hashes, including removal of the prerelease consequence tag.
The old recipe is test-only; no alternative runtime serializer accepts it.

## Executed gates and scope

Passed `cargo run -p xtask -- check`: formatting, workspace Clippy with
warnings denied, 335 passed tests, zero failures and generated-contract
freshness. One pre-existing service workload test remains ignored and was not
qualified by this run. All five normalized-foundation tests and all 26 existing
kernel tests passed. `git diff --check` passed.
The existing kernel backup, rollback, process-exit and large-import regressions
now run against the relational format. Native UI/VoiceOver and live author
packages were not used for this scoped proof.

Unsupported-family qualification, live migration, workflow/installation
conversion and whole-persistence completion remain excluded. Workflow entries
retain their existing serialized storage. Broader record families represented
by the codec catalog are not thereby semantically qualified. Logical archives
remain boundary serialization, outside the full persistence-conversion claim.
