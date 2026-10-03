# Immutable assessment persistence — verification

October 2, 2026, America/Los_Angeles. Implements the internal persistence slice of
[the approved D03/D08 decision](decisions/d03-d08-source-assessments.md), using
Goal 7's existing assessment contracts. Public submission, native transport,
final validation/approval/commit integration and prose qualification remain
subsequent work. The service methods are internal and intentionally have no
public dispatcher or capability advertisement yet.

`Workflow::attach_assessment`, `select_assessment` and `get_assessment` use the
existing authenticated principal, proposal ownership, write permissions, grant
boundaries and authority lock. Bodies and service-generated envelopes are
immutable workflow entries. Selection keys contain the exact proposal version
and an ordered generation; there is no mutable latest pointer. Kernel publication
checks the latest proposal key and selection generation inside one immediate
SQLite transaction and appends selection, request receipt and envelope together.
The existing package writer lock and serialized universe worker prevent head
movement during these internal synchronous operations. No proposal digest,
canonical operation or canonical approval is modified by these methods.

Admission checks the complete frozen proposal/frame, authenticated assessor,
active record identities and versions, source types, staged metadata, actual
retained UTF-8 bytes, byte sizes/digests/ranges, exact anchor excerpts and source
bindings, edition types and passage anchors. Proposed/unchanged links resolve to
the correct compiled/active versions. Historical links require retained immutable
versions; labeling a dependency historical cannot substitute it for an active
semantic reference. Accounting and closed-body limits use the owning Goal 7
contract implementation. Scope checks cover candidate and referenced historical
material, including transitive visibility and entity/predicate restrictions.

Identical authorized retries recover original identities and generations, even
after replacement; differing retries, no-change selections, cross-proposal
selection and stale writes fail. Prior envelopes and selection generations remain
readable. Readback recomputes current usability: missing selection is `absent`,
applicable attachments are `bound`, unresolved attachments are `bound` with their
unresolved conclusion/count, and replaced proposals or moved heads are `stale`.
Source/edition/dependency differences add their approved stale reasons. Missing
retained material is `unavailable/missing_retained_material`; integrity failures
remain failures, with no latest-text reconstruction. An unavailable envelope
cannot establish partial-view dependency scope and therefore fails access for
partial viewers. Legacy validation reporting is unchanged.

## Proofs

Final service/store/protocol suite: **125 passed, 0 failed; 1 deliberately ignored
standard workload test**. Independent Goal 7 contract checks: **6 passed**.

The two service-to-storage integration tests invoke the actual internal Workflow
methods against real SQLite packages, rather than exposing the deferred public
API. They cover absent/bound/unresolved/stale/unavailable states, exact retries,
selection withdrawal/reselection, candidate/frame/source/version/digest/UTF-8
mismatches, assessor impersonation, denied write/retry, owner and scope denial,
non-disclosing lookup errors, edition type mismatch, anchor scope/excerpt/digest/
source-version mismatches, invalid dependency identity/universe, and unchanged
stored state after rejected writes. A storage collision after an earlier insert
rolls back the whole transaction; failed generation comparison also leaves every
workflow row unchanged. Ordinary SQL deletion of retained text fails. The
unavailable test deliberately removes text only from a disposable fixture after
temporarily removing and then restoring its deletion trigger.

The independent Python auditor opens SQLite read-only in a separate process. It
imports no Rust service/store serializer. It checks SQLite integrity, raw canonical
payload bytes and hashes, assessment hash preimages, exact proposal/frame/source
bindings, source bytes and ranges, declared anchor dependencies/excerpts,
receipt-to-envelope/selection equality and gap-free selection history. The primary
fixture replaces source text and proposal, retains consistent and unresolved
superseded attachments, and attaches a fresh assessment to the replacement.
The anchor fixture independently audits exact anchors. Both are read before and
after closing and reopening the kernel; every row and raw payload digest agrees.
These are internal storage restart proofs, not public transport or prose proofs.

Retained synthetic audit outputs and their hashes are in
[evidence/assessment-persistence/summary.json](evidence/assessment-persistence/summary.json).
No real manuscript or credentials are included.

Reproduce from the repository root:

```sh
cargo test -p universe-service -p universe-store -p universe-protocol
uv run --with jsonschema==4.25.1 python scripts/test_source_assessment_contracts.py
ASSESSMENT_PROOF_DIR="$PWD/docs/evidence/assessment-persistence" \
  cargo test -p universe-service --lib assessments -- --nocapture
```

The proof tests launch `scripts/audit_assessment_storage.py` against their isolated
packages before and after restart; the packages are removed when the tests end.
