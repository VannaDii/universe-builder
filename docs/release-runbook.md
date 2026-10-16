# Local package and release procedure

The fixture and preview distribution procedures below do not satisfy clean-machine, accessibility, host, signing or notarization acceptance. Generated GitHub releases remain drafts until reviewed and explicitly published.

## Homebrew preview distribution

Both fixture and release bundles use `assets/branding/universe-builder.icns`,
derived from the only approved logo, `assets/branding/universe-builder-symbol-4k.png`.
The bundle includes it in `Contents/Resources` and declares it through
`CFBundleIconFile`. Generated Finder/Dock shortcuts embed the same icon.
The approved logo MUST be used anywhere UB branding appears; see the
[branding rules](../README.md#approved-logo-and-application-icon).
Existing installed bundles and shortcuts retain their old icon until replaced
using the normal whole-bundle update or explicit shortcut recreation procedure.

`dart run apps/ub_cli/tool/package_macos.dart --mode release` builds
`apps/ub_app/build/macos/Build/Products/Release/Universe Builder.app`, including
the Flutter workspace, bundled web assets and public `multiverse-mcp` launcher.
The bundle is ad-hoc signed. The release workflow targets macOS 15 or later;
this build constraint does not establish clean-machine support on every Mac.

Use the pinned Flutter version in `.flutter-version` with its bundled Dart,
then `flutter pub get --enforce-lockfile`. Keep the app version in
`apps/ub_app/pubspec.yaml`, CLI version and public launcher's `--version`
consistent. After committing the intended source, a matching `vVERSION` tag
triggers `.github/workflows/release.yml`. Creating/pushing a release tag and
publishing its draft require explicit authorization. The workflow builds Apple
Silicon and Intel packages, checks generated schema/contracts and Dart tests,
then installs each archive through Homebrew and runs the existing CLI/MCP
functional tests against its installed launcher. Archive version and tag must
match exactly. Dirty source is rejected; `--allow-dirty` is for local checks.
The workflow conversion has not yet been run on hosted CI.

The workflow uses its actual GitHub repository as the release destination. It
attaches two `multiverse-mcp-VERSION-TARGET.tar.gz` files, their SHA256 files, and
`multiverse-mcp.rb` generated from those exact archives. There are no guessed
checksums or mutable `latest` download URLs. The template is
`packaging/multiverse-mcp.rb.in`; it cannot be installed until rendered.

To render manually after both archives exist:

```sh
dart run apps/ub_cli/tool/distribution.dart formula --assets dist --version VERSION \
  --repository OWNER/REPOSITORY --output dist/multiverse-mcp.rb
```

For the first release, choose/configure the GitHub repository and a Homebrew tap
(normally `OWNER/homebrew-multiverse`). Review and publish the draft preview,
then commit its generated formula to `Formula/multiverse-mcp.rb` in the tap.
Users can then run `brew install OWNER/multiverse/multiverse-mcp`. For a tap
hosted in this source repository instead, use `brew tap OWNER/multiverse
https://github.com/OWNER/REPOSITORY` before installing. Each published version
requires committing that version's regenerated formula to the tap; ordinary
`brew update` and `brew upgrade multiverse-mcp` then select it. Do not publish a
formula referencing draft or private release assets as publicly installable.

The formula keeps the entire sealed app in `libexec`, exposes only the public
launcher and preserves the signed Mach-O files. It installs no background login
service and writes no user installation or shortcut during `brew install`.
`multiverse-mcp shortcut --launcher "$(brew --prefix multiverse-mcp)/bin/multiverse-mcp"`
creates an optional Finder/Dock app in `~/Applications`; `--destination
"$HOME/Desktop"` puts it on the desktop. It executes the same `ux` command,
quotes literal paths safely, survives upgrades through Homebrew's stable opt
path, and refuses to overwrite any existing application. Use the optional
paired `--installation PATH --profile ID` to remember an existing connection.
Remove the generated shortcut explicitly if desired after uninstalling; user
installations, profiles and backups are always outside the Homebrew prefix.

For local packaging, `dart run apps/ub_cli/tool/distribution.dart archive
--bundle APP --output dist --tag vVERSION` creates the archive and checksum
sidecar. `distribution.dart formula --local` emits file URLs for a temporary
test tap. Do not distribute that local formula. The former Python archive and
formula commands have been retired.

## Build and inspect

The Flutter assembly command enforces the pinned SDKs, checks that its runner
and helpers support the engine's actual architecture, and signs the complete
bundle with the app/helper entitlements. `release-manifest.json` records the
version, build mode, architecture, source revision, dirty-source flag and helper
checksums. It declares `release_accepted: false`; this is a local preview, not a
notarized distribution. The archive command checks the sealed signature before
packaging and the Homebrew formula pins the actual archive checksum.

From `apps/ub_cli`, `dart test test/distribution_test.dart` covers formula
metadata, archive links/signatures and tamper rejection on macOS. Existing
functional tests accept `UB_TEST_MACOS_BUNDLE=/absolute/Universe Builder.app`:
run `dart test test/universe_cli_test.dart --name 'standalone universe command'`
from `apps/ub_cli` and `dart test test/mcp_cli_test.dart --name 'stdio reaches
real service'` from `apps/ub_mcp`. They use disposable installations and launch
the packaged command outside the checkout with an empty PATH. This does not
establish that the host has no developer tools installed. They do not open the
desktop. Rust fixture packaging and its remaining Python checks are legacy
migration tooling, not the version-tag distribution route.

## Linux desktop package

Use the pinned Flutter/Dart toolchain on Linux with Clang, CMake, Ninja,
pkg-config, GTK 3 and libsecret development packages. Run
`dart run apps/ub_cli/tool/package_linux.dart --output NEW_DIRECTORY` from the
workspace. The destination must not exist. This builds release desktop/web
clients and their native CLI/MCP/engine helpers for the current arm64 or x64
host. Runtime systems need compatible glibc, GTK 3 and libsecret libraries;
this is not a static binary or a cross-distribution compatibility claim.

Move the complete package to its intended location before creating a shortcut.
Run `bin/multiverse-mcp ux` there. The desktop uses XDG application-data storage
for its default local installation. Native GTK file choosers supply the existing
source/image and backup/import workflows; copies are asynchronous, bounded to
8 GiB and refuse an existing destination. Picker cancellation does not admit or
publish anything.

`bin/multiverse-mcp shortcut --launcher /absolute/package/bin/multiverse-mcp`
creates `universe-builder.desktop` in the XDG applications directory. Supply
`--destination DIRECTORY` for another location or pair `--installation PATH
--profile ID` to remember a connection. The entry contains literal arguments
and the approved bundled icon. It does not overwrite an existing entry or
initialize an installation. Use a stable absolute launcher path for upgrades;
if the package moves, remove and explicitly recreate its menu entry. To
uninstall, remove the entry and package while retaining installation data and
backups. Desktop environments may require their own trust confirmation for an
entry copied to the desktop instead of the applications directory.

The `desktop/`, `bin/` and `lib/` directories form one package. Stop its app and
engines before whole-directory replacement. Do not copy an individual executable
without its libraries or mix helpers from different builds. Signing/distribution
publication and native graphical qualification remain separate work.

## Headless container

On the intended Linux architecture, assemble the headless package with the pinned
Flutter/Dart toolchain, then build using only that output directory as context:

```sh
dart run apps/ub_cli/tool/package_headless.dart --output target/headless/linux
docker build --file packaging/Dockerfile.headless \
  --tag universe-builder-mcp-headless:local target/headless/linux
docker volume create --label io.universe-builder-mcp.project=universe-builder-mcp \
  --label io.universe-builder-mcp.purpose=installation universe-builder-mcp-data
docker run --rm --name universe-builder-mcp-setup \
  --mount type=volume,source=universe-builder-mcp-data,target=/data \
  --env UB_USE_POSTGRES=false universe-builder-mcp-headless:local \
  --installation /data/installation --initialize
docker run -d --name universe-builder-mcp-service \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,size=64m \
  --mount type=volume,source=universe-builder-mcp-data,target=/data \
  --env UB_USE_POSTGRES=false universe-builder-mcp-headless:local
```

Retain the approval-owner profile ID printed by initialization. Profile
credentials remain in the volume. Existing installation directories must be
owned by UID/GID 10001 and private; startup never repairs permissions or
overwrites an installation. Reuse an existing suitable volume and container
rather than creating duplicates. The image inherits project/purpose labels.

The image runs as UID/GID 10001, has no Dart/Flutter/Rust/Python SDK, and includes
system TLS trust roots. The default command opens `/data/installation` without
initializing or converting it. No ports are published by default. The local API
is available only inside the container; without an HTTPS listener the existing
15-minute idle shutdown applies. Local administration and stdio MCP use:

```sh
docker exec universe-builder-mcp-service multiverse-mcp admin \
  --installation /data/installation --profile PROFILE_ID status
docker exec -i universe-builder-mcp-service multiverse-mcp serve \
  --installation /data/installation --profile PROFILE_ID
```

For remote clients, supply the engine's existing HTTPS options and publish only
that TLS port. Mount the certificate and private-key files read-only, readable
by UID 10001. HTTPS mode stays running until explicit shutdown or a signal.
For PostgreSQL, supply `UB_USE_POSTGRES=true` and `UB_POSTGRES_ENDPOINT` to both
setup and service from an operator-managed environment or protected env file;
never bake credentials into the image. Encrypted Linux configuration requires
an existing unlocked default collection in the user's Secret Service session.
The image includes libsecret but neither a keyring daemon nor a session bus;
normal server containers use the environment-variable configuration path. Do
not mount a desktop session bus merely to configure a server container.
The requested database must already exist; backend selection
does not transfer data or silently provision/convert schemas.

Before replacement, finish queued work, retain backups outside the container,
and stop the service with `docker stop --timeout 60 universe-builder-mcp-service`.
SIGTERM drains the engine. Keep the volume, prior image and compatible backups;
replace the entire container using the same volume only when its schema is
compatible. Do not delete the volume on uninstall or try an older image against
an upgraded schema. Perform an explicit supported conversion separately when
required. This local image recipe does not deploy or publish a hosted service.

## Workload and recovery drill

Run the opt-in Dart storage/evaluator workload from `packages/ub_service`
with the pinned toolchain:

```sh
UB_RUN_STANDARD_WORKLOAD=1 dart test test/standard_workload_test.dart --reporter expanded
```

It creates a disposable normative SQLite package containing 10,000 entities,
200,000 propositions and their 200,000 assertions, 2,000 rules and ten
continuities (412,002 records). The initial fixture is already admitted data;
it does not bypass or increase the application's 100-change commit limit.
Ordinary recovery validates its retained data and rebuilds projections. The
case evaluates all 2,000 rules, creates a complete physical backup, restarts
and restores into a separate package, then compares every retained payload
digest and continuity head. It removes only its own temporary directory.

Phase timings go to ordinary test output; no report file is needed. These
measurements describe this workload and machine, not an SLA, an interactive
latency target or mobile/clean-machine qualification. Do not run it against an
author's installation. The former Rust standard-workload test and Python
benchmark are transitional procedures, not the Dart migration check.

The separate PostgreSQL catalog workload uses the existing disposable test
database (`ub_disposable`) selected by `UB_TEST_POSTGRES_PORT`. Run it alone
against that database, without other PostgreSQL suites:

```sh
UB_TEST_POSTGRES_PORT=PORT UB_RUN_STANDARD_WORKLOAD=1 dart test test/postgres_catalog_workload_test.dart --reporter expanded
```

It provisions twenty universes through the service, reopens the installation,
checks their catalog names and exact continuity heads, reads every library and
checks that an ungranted profile sees no universes. It prints phase timings and
the universe tables' storage footprint, then removes only its own namespaces.
This small-record catalog case does not establish large-record, network-latency
or commercial capacity targets. Use a disposable database, never a hosted or
author database.

For the full PostgreSQL record-count workload, use the same disposable database
and run this case alone:

```sh
umask 077
UB_TEST_POSTGRES_PORT=PORT UB_RUN_STANDARD_WORKLOAD=1 dart test test/postgres_standard_workload_test.dart --reporter expanded
```

It reuses the 412,002-record admitted SQLite fixture and ten continuities,
imports them through the core PostgreSQL transfer path, rebuilds projections,
evaluates all 2,000 indexed rules, reopens the connection and restores a complete
portable backup into a separate SQLite package. Exact version membership,
digests and heads must survive. The test refuses an existing fixture namespace
and removes only the namespace and temporary directory it created. This is a
long-running core workload, separate from the reviewed service transfer cases;
its harness timeout is not a product latency target.

## Data preservation guarantees and bounds

Canonical revisions, source bytes, original image bytes, workflow entries and receipts are immutable and retained. Writes use one SQLite transaction with WAL, FULL synchronization and foreign keys; failed writes do not publish a partial event or receipt. Recovery and admission use compatible history/version/ancestry limits, so reaching a work limit cannot make previously accepted history unreadable.

A physical backup is first copied to a private temporary file and synchronized. The copy must pass SQLite page/foreign-key checks, every canonical payload/workflow digest check, and head reconstruction/reference validation before it is published and its parent directory synchronized. Existing backups are never overwritten. Interrupted or failed copies are not reported as successful backups.

Supported schema upgrades first retain a verified private rollback copy alongside the original, named `.PACKAGE.before-schema-VERSION-UNIQUE.sqlite`. Keep these copies until the upgraded universe has passed recovery checks. If the copy cannot be verified or synchronized, the upgrade stops. An older binary must use the matching pre-upgrade copy in a separate installation; never point it at the upgraded original.

Current bounds: 500,000 records per snapshot, one million stored versions, a bounded 10,000-commit chain, 512 MiB logical archives and 8 GiB physical restore files. Logical history replay has a separate ten-million-membership budget. Every writer uses the same 8 GiB SQLite page-growth ceiling as physical restore; a growth failure rolls back its transaction. Existing oversized packages are never truncated. An explicit limit error preserves the original package; it is not permission to delete history. Physical backups and complete-history relational archives preserve full workflow evidence. Canon-only archives omit workflows and operation receipts. Imported approvals and operation receipts remain historical evidence; current authority and delegation come from the owning installation. Keep author-selected backups on a separate protected device/location as part of final recovery acceptance; no off-device backup is configured automatically.

## Appearance image recovery

Image originals are stored in checksummed SQLite workflow chunks alongside their immutable metadata. External source paths are not retained. Preview JPEGs are derived from originals and do not replace them. Physical backups retain staged images and draft operations; logical exports include bytes referenced by canonical image versions, including historical versions and dependencies of filtered entry exports. Uncommitted form fields must first be added to the proposal draft and its autosave confirmed.

A missing chunk or digest mismatch fails package verification and recovery. A logical import also validates decoded format/dimensions before accepting its image metadata. Keep the damaged original; restore a verified copy into a separate installation. Maintenance does not collect original image chunks. Image limits (10 MiB, 8192 pixels per edge, 32 megapixels) and package/archive limits still apply; source files are never deleted by import.

## Whole-bundle update and rollback

1. Record the current app manifest and each universe's `doctor` report. Create verified backups outside the app bundle. Keep the previous complete app bundle.
2. Finish or cancel queued work. An interrupted validation is retried with its original idempotency key and immutable proposal reference; a completed run is retrieved by operation ID. Retrieve uncertain commit receipts before retrying publication.
3. Use the authenticated command-line `shutdown` and confirm that the installation socket is gone. Never replace live helper binaries individually.
4. Verify the replacement's signature and manifest. Replace the whole app bundle; preserve installation directories, profiles, databases, source blobs and backups.
5. Start the engine explicitly, inspect `doctor`, read pinned historical revisions and compare heads, receipts and source digests. Reopen the desktop only when native interaction is authorized.
6. If startup or integrity checks fail, stop the new engine. Preserve the failed installation for diagnosis. Restore the last verified backup into a separate installation and use the previous compatible complete bundle. Never open an upgraded database with an older binary unless that exact downgrade was tested.

A same-version restart/restore drill is implemented. A historical released-version upgrade/downgrade matrix cannot be claimed from it. Future schema changes require golden packages from each supported source version, including immutable workflows, continuity baselines, source bytes and approvals.

## Diagnostics and release gate

- A full universe queue returns an explicit work-limit error. Retry with the same request key; do not invent a new key after an uncertain mutation.
- Failed or restricted validation is not a successful check. Finding pagination is delivery state; fetching the final page does not change evaluation coverage.
- A tampered bundle fails before helper startup. Reinstall a complete verified bundle rather than bypassing signature checks.
- Missing or incompatible schemas, damaged workflow digests, stale approvals and absent dependencies fail closed. Preserve the offending package and use verified recovery paths.
- Native layout, keyboard/VoiceOver interaction, LM Studio, clean supported Macs, true offline operation, hosted CI, Developer ID/notarization, broader security/fuzz/scale acceptance and the full scope-case matrix remain release gates until evidence is recorded. Publish OS support only for actually tested environments.


Relational archive transfer is verified in Goal 26 evidence. `universe export NAME /absolute/archive.sqlite` creates a canon-only archive; add `--complete-history` to retain workflows, drafts, receipts and staged content. Complete-history export requires the entire universe. `--record ID` creates a dependency-closed canon-only archive with declared omissions. Validate an import preview and accept its exact digest; use restore for original identities or clone for a fresh universe identity. Canon-only completeness describes canonical identities; `includes_workflow` separately declares workflow inclusion. Installation grants, credentials and profile secrets are excluded from both archive modes. Old serialized packages and preview layouts require explicit operator conversion; this work does not migrate active author data.

Goal 27's [explicit operator procedure](operator-conversion-procedure.md) and
[readiness report](operator-conversion-readiness.md) qualify disposable offline
package, installation and credential conversion. Startup does not convert legacy
data. Live author conversion and installation/catalog cutover require a separate
operator decision and remain unexecuted.
