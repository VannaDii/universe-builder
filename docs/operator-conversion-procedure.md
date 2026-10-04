# Explicit operator conversion — Goal 27

These offline commands build new targets. They do not register packages, switch an
installation, start the engine, regenerate credentials, or convert live author data.
Keep the original installation, packages, credentials, backups and referenced media
available. An installation target preserves its catalog paths/device/inode values;
it still refers to the original packages. It is not a self-contained installation backup.

## Prepare inputs

1. Stop the owning application/engine through its normal shutdown procedure. Use a
   disposable copy for qualification; live author conversion requires its own later
   authorization. Do not delete journal/WAL/SHM files to make an input acceptable.
   Let the owning SQLite writer complete its clean shutdown, or obtain a verified
   consistent offline snapshot with its recovery files retained separately.
2. Use owned regular files with mode `0600`, private directories with mode `0700`,
   and fresh output paths inside an owned private directory. Symlinks, hard-linked
   source files, unsafe permissions, recovery sidecars and oversized packages are
   refused. Conversion reads originals using read-only file descriptors and SQLite
   read-only transactions. Original hashes are checked again before publication.
3. Inventory all source files. The package command handles a single SQLite package;
   the installation command handles `installation.sqlite` and every
   `profiles/{profile}.json` credential, including unenrolled credentials. Referenced
   package files remain separate inputs. Unknown source tables/columns, populated
   retired preview state and pending purge work block installation publication.

## Build targets

Use the commands below for identity-preserving operator conversion. The older
`convert-legacy` command produces a limited canon archive with rebuilt revision
identities and does not satisfy this procedure.

Build the executable with `cargo build --locked -p universe-cli`. The common CLI
requires `--installation`; for these offline commands this argument does not open
or initialize that directory, and no profile or running engine is required.

```sh
universe --installation /private/legacy-installation convert-package \
  /private/legacy-package.sqlite /private/targets/package.sqlite

universe --installation /private/legacy-installation convert-installation \
  /private/legacy-installation /private/targets/installation

universe --installation /private/legacy-installation convert-credential \
  /private/legacy-installation/profiles/prf_ID.json \
  /private/targets/profiles/prf_ID.sqlite
```

Replace `prf_ID` with the exact existing profile identity; retain the same filename
identity for use by the client. The installation command already converts all its
credentials; use the standalone credential command only for a separately retained
credential input. Save each returned report with the source inventory. Reports
include original file SHA-256 values and verification counts, never secrets.

The package converter verifies known original digest recipes, writes one normative
schema, retains original record/workflow hashes separately from normalized hashes,
and independently compares complete retained scalar tables, bodies, classifications,
workflow evidence and snapshots. Histories retain their original IDs, baselines,
sequences, prior/next versions, tombstones and receipt tuples. Fully relational
packages with the prior matching schema can also be copied into a fresh normative
target after exact trusted-schema comparison. Input SQL is never installed.

Legacy membership/parent vectors with one candidate select that identity. Empty
vectors remain unclassified/root. Multiple candidates remain ambiguous with a null
selected identity and ordered `classification_evidence` rows, even when candidates
form a chain. Missing applicability remains explicitly unspecified. Ancestry checks
include ambiguous candidates at every historical snapshot; cycles, missing,
wrong-kind and cross-universe references block publication. No executable ancestry
is inferred through an ambiguous or nonexecutable classification.

Recognized raw draft operation arrays become ordered typed operations. Draft keys,
versions, frames, rationale and proposal references are retained. Original workflow
hashes remain conversion provenance when the operation representation changes.
Historical approvals, validation bindings and receipts are retained exactly; the
converter creates no replacement approval or grant. Normal service authorization
and revalidation still apply to subsequent use.

Installation audit sequences, profile hashes/revocation, catalog reservations and
all grant flags/boundaries retain their exact meaning, including null versus empty
lists and expired grants. Every enrolled credential must match its stored hash.
Unenrolled credential files are retained without creating an enrolled profile.

## Diagnose, retry and recover

A diagnostic identifies the affected table, version, workflow key or ancestry
reference. Repair a separate copy explicitly and retain its original beside it.
Invalid/incomplete drafts, unknown bodies/recipes, source digest mismatches and
unnamed scaffold type definitions block conversion; they are not omitted or
rehash-repaired. Populated retired import previews require explicit restaging from
retained original archives. Pending purge work requires separate operator recovery.
The converter never performs either action implicitly.

Construction and audit occur in a private `.operator-conversion-*`,
`.installation-conversion-*` or `.credential-conversion-*` directory beside the
output. Normal failures remove their private targets. Abrupt process termination
can leave private scratch directories: preserve them until the original inventory
and hashes have been checked, then remove only the identified disposable scratch.
No final destination exists for the qualified interruptions before publication.
Retry from the unchanged originals into a fresh destination. Existing destinations
are refused, including one created concurrently immediately before publication.

File targets and installation directories publish through the platform's atomic
exclusive rename, without a temporary extra hard link. SQLite contents are flushed
before publication, and the destination parent is synced. A filesystem error after
publication can leave a complete verified target despite an error response: retain
and inspect that target rather than overwrite it. Publication never replaces an
existing target or original source.

Inspect the readiness report and saved conversion reports before considering any
later cutover. Changing catalog paths/device/inode values, replacing the active
installation, authenticating live credentials or converting live author packages is
outside this procedure's qualified execution. Startup continues to refuse legacy
layouts and does not call the conversion routines.
