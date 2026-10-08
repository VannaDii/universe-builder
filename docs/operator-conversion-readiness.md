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
