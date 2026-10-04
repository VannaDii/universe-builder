# Goal 27 readiness — explicit operator conversion

The offline operator path is implemented and qualified on disposable inputs. No
live author package, installation or credential was converted, registered or
replaced. The readiness claim is for recognized inputs that pass the complete audit;
unsupported or unrecoverable inputs remain recoverable and block publication.

## Delivered behavior

`convert-package`, `convert-installation` and `convert-credential` dispatch before
engine discovery/authentication. Targets contain the normative relational schema.
Original files are opened read-only, retained with their exact bytes, and rehashed
before publication. Independent comparisons precede atomic no-clobber publication.
Retrying an existing destination fails; retrying to a fresh destination succeeds.

Package conversion preserves factual IDs, revision chains, pinned branches,
tombstones, snapshots, head memberships, reservations and receipt tuples. Recognized
serialized canonical/workflow bodies become typed rows with source and normalized
hash provenance. All workflow families pass through the closed normative codec;
unsupported shapes block with their exact key. Draft operation strings normalize
only when they decode into ordered recognized operations. Converted workflow
provenance is also checked by ordinary integrity/backup/restore readers.

Multiple parents/memberships retain ordered candidates and explicit ambiguity.
Historical ancestry is audited across all snapshots, including ambiguous parent
candidates. Installation conversion retains authority flags, scopes, nullable/empty
boundary distinctions, audit sequences, exact credential identities/secrets/hashes,
revocation and credentials from interrupted enrollment without activating them.
Catalog package paths and filesystem identities remain unchanged.

## Concrete evidence

The independent actual-CLI proof is
[`operator-conversion-proof-results.json`](operator-conversion-proof-results.json).
The auditor imports neither the Rust converter nor its serializer: it reads original
serialized inputs, uses the separately implemented Python relational decoder, and
compares whole reconstructed values and all retained scalar rows.

Its disposable package has five canonical versions (three definitions, one entity,
one represented context), two continuities with a pinned baseline, a tombstone,
receipts, one snapshot, exact UTF-8 source content, a continuity name and a raw
editor draft. Both membership and parent ambiguity retain their ordered candidates;
a nonexecutable type keeps its flag and unspecified applicability. It compares
five complete bodies, three workflows, one snapshot, eight complete scalar tables,
classification evidence and original/normalized digests.

Its installation has two enrolled profiles, a revoked profile, three exact synthetic
credentials including an unenrolled interrupted-enrollment credential, one scoped
grant with ordered/empty/null boundaries and expiry, catalog aliases and an audit
sequence of seven. The independent auditor compares six complete scalar tables,
every grant field and child row, and every credential. Six original files remain
byte-identical. All three real CLI commands pass fresh retries and no-clobber
rejections; no engine socket is created.

Rust qualification covers faults during row construction, after audit and immediately
before publication for package and installation targets. Child processes terminate
at each of these three points (package SIGKILL; installation abrupt abort), then the
parent proves absent final targets, byte-identical recoverable originals and successful
fresh retries. Publication-race tests retain a competing file/directory unchanged.
Normal-error scratch cleanup is checked; process-crash scratch is retained privately
until the disposable test root is cleaned.

Negative cases include malformed draft operations, original digest mismatch,
missing/cyclic ancestry, unknown author-data tables, forged snapshot membership,
unsafe input permissions/symlinks, recovery sidecars, missing/mismatching
credentials, pending purges and orphan grant limits. Ordinary package/installation
startup rejects serialized originals unchanged. A prior fully relational package
missing the conversion-provenance table is refused on startup, explicitly converted,
and compared across every typed table before normal restart.

## Compatibility and limits

Supported serialized packages have recognized immutable kernel scalar headers,
serialized `record_versions`, `workflow_entries` and `snapshot_membership` layouts.
The verified historical canonical recipe is `kind:v1:v1:` followed by canonical body
bytes; an unversioned serialized body uses the normative `kind:` recipe. Unknown
recipes/layouts fail. Fully relational conversion requires the exact trusted schema,
with only the known absent conversion-provenance table accepted as an input difference.
Partially rewritten relational schemas and arbitrary scaffold-era side tables remain
unsupported and block rather than silently losing evidence.

Scaffold type definitions without an authored name require an explicitly repaired
copy. Invalid drafts cannot be carried as opaque text. Populated retired import
previews require explicit restaging from retained archives; pending purges require
operator recovery. These are actionable compatibility denials, not universal
legacy-format readiness. Original evidence remains available to the author.

Targets are independently verified datasets. Installation targets reference retained
original package paths and are not self-contained backups. Live catalog reassociation,
credential authentication/cutover, physical power-loss durability, Linux execution,
large-workload latency and native GUI behavior are not claimed. Atomic directory
publication has macOS/Linux implementations; this qualification ran on macOS.

## Executed checks

- `RUST_TEST_THREADS=2 cargo run --locked -p xtask -- check`: passed formatting,
  workspace/all-target Clippy with warnings denied, all 362 workspace tests,
  and contract-schema freshness. One existing opt-in standard workload is ignored;
  the ordinary 10,000-entity import/backup/restore/restart regression passed.
- `python3 scripts/operator_conversion_proof.py --output docs/operator-conversion-proof-results.json`:
  passed against the final CLI, including independent semantic projections,
  complete provenance/snapshot tables, exact credentials and all three retries.
- Isolated archive integration rerun: one passed, existing deadline unchanged.
- `git diff --check`: passed.

All 17 new conversion test functions passed in the workspace gate (four are fixture/
child-process entry points). Their parent tests exercise actual injected faults,
process termination, no-clobber races, corruption denials and restart behavior.
Disposable source/target/scratch directories were cleaned by their owning test
roots. No container or live author-data operation was needed.
The first concurrent workspace run timed out in
`logical_archives_preview_clone_history_sources_and_filtered_dependencies` at its
existing deadline. No timeout was widened or architectural behavior changed; the
case and final workspace suite are rerun with bounded test concurrency.

Actual working wall time through final qualification/documentation: 38 minutes 51 seconds, measured from 18:22:50 UTC to 19:01:41 UTC on October 4, 2026. This includes executed build/test waits; final commit/report bookkeeping follows.
