# Universe Builder

Two modes are available: the disposable read/propose fixture and a persistent authenticated engine for author-defined factual universes. Persistent mode supports incremental definitions and instances, scoped factual constraints, retrieval, declared knowledge acquisition, scoped cross-instance cardinality, exact approval, atomic publication, history and recovery. The external writer interprets prose and asks for author clarification; the MCP validates supported factual declarations. Assessments remain optional attributed domain records. The connected writing workflow has been exercised through the native author interface and local packaged launcher. Prose interpretation remains fallible; release acceptance remains open.

## Dart conversion development

The approved [conversion plan](docs/dart-conversion-plan.md) is being implemented
alongside the current runtime. The Dart workspace currently contains the shared
canonical encoding, digests, typed identities, values, temporal/spatial expressions
and reference foundations, typed scopes, validity and evidence bases, and
20 of 38 record families: worlds, realms, entities, the seven definition
families, propositions, assertions, the five narrative families and the three
source/evidence families. It also contains the internal typed SQLite codec,
revision journal and connection policy. It is not yet a
replacement engine or application.

Use Dart **3.13.4** (enforced by the workspace SDK constraint) and Flutter
**3.47.5** (recorded in `.flutter-version`). Dependency resolution is locked in
the root `pubspec.lock`. Run `dart pub get` at the repository root, then:

```sh
dart analyze packages tool
dart format --output=none --set-exit-if-changed packages tool
cd packages/ub_domain
dart test
dart test test/canonical_test.dart test/identity_test.dart test/exact_amount_test.dart test/value_test.dart test/selector_test.dart test/scope_test.dart test/records_test.dart test/definitions_test.dart test/narrative_source_test.dart --platform chrome
cd ../ub_store
dart test
```

Browser tests must run from the package directory. Set `CHROME_EXECUTABLE` if
Chrome is not discoverable automatically. Tests consume existing canonical and
historical fixtures; they do not read or modify author installations.

The ownership bridge builds with the host C compiler through Dart build hooks.
Native command-line bundles must use `dart build cli`; `dart compile exe` alone
does not bundle the native assets.

The SQLite codec uses the existing fixed-column relational schema and keeps
absent/null states, exact numeric strings and ordered child rows. It does not
provide reviewed publication yet. The internal journal adds immutable revision
history, exact receipt lookup, tombstones and pinned branches within a
caller-owned transaction. Reference admission and per-record reference, world,
narrative, scalar and search projections are also implemented internally.
Foundation/value/ancestry admission and world selector reservations are
implemented internally. Selector keys preserve the existing NFC/full case
folding/NFC format with pinned Unicode tables; renamed or removed world names
remain reserved to their original identities. Internal semantic indexes resolve
definition attributes in the selected candidate. Initialization admission keeps
exact start/definition provenance and durable receipts through correction,
removal and restoration; receipt reads respect pinned fork ancestry, and the
history check detects missing or changed receipts. Disposable projection rebuilds
reconstruct all retained versions and pinned heads, switch generations atomically,
and preserve historical search results. The native POSIX ownership bridge uses
descriptor locks, protected regular files and private directories; owned SQLite
connections retain writer ownership through close. This has been exercised on
macOS, including processes, isolates, crash release and a bundled AOT executable.
Windows ownership is not implemented and fails explicitly; Linux and mobile
platform verification remains pending. Typed workflow storage and atomic compared
append preserve exact retries and inactive imported authority. Owned package
recovery verifies retained canonical bodies, source/media bytes, conversion
provenance and initialization receipts before rebuilding projections. Source and
media staging metadata remains separate from content-link admission. Service
authorization still needs its port before an author-facing publication
path can use it. Schema resources are compiled into the
package; after changing the owning files in `docs/decisions/relational-storage`,
run `dart run tool/embed_schema.dart` from the repository root to regenerate
them. Opening an incompatible database refuses conversion and preserves it.

Typed values retain their existing record-wire encoding independently from
domain-value comparison encoding. In particular, record ranges use
`lower_inclusive`/`upper_inclusive`, comparison ranges use
`lowerInclusive`/`upperInclusive`, and set comparison sorts canonical members
without changing authored record order or removing duplicates. Exact numeric
strings and approximate/unknown temporal bounds retain their authored meaning.
Typed record serialization matches the existing Rust DTO defaults and digests.
The raw relational fixtures retain omitted fields; decoding a typed view expands
only source-declared defaults and never rewrites the stored historical body. Scope world lists
use `world_ids` on the wire and `worldIds` in comparison encoding; derivation
evidence includes a null evaluator on the wire but omits it in comparison
encoding. Foundation admission and initialization scope/provenance checks use
these typed models, as do definition/classification indexes and world-name
reservations. Value shapes preserve typed unit/definition identities and recursive
sequence declarations without inferring executable behavior from labels. Unknown
validity remains distinct from unbounded time. Work bindings retain explicit
continuity/revision pins or ordered segment bindings; scene order, viewpoint,
depicted events and disclosed records remain independent. Source import metadata,
attributed origin and content digests remain distinct from payload digests.
Byte sizes, anchor offsets and narrative positions use exact unsigned 64-bit
values on VM and web. These record types describe evidence; content-link,
excerpt-boundary and factual-support admission still need their service ports.
The Dart rational validator rejects all zero denominator spellings, including
`00`, `+0` and `-0`, closing a missed case in the existing Rust validator.

## Approved logo and application icon

The **only approved Universe Builder (UB) logo** is
[the 4096 × 4096 transparent master](assets/branding/universe-builder-symbol-4k.png).
It **MUST** be used for the application icon and anywhere the UB logo is presented,
including the desktop, Finder/Dock shortcuts, documentation and distribution materials.
Use scaled copies of this master; preserve its colors, proportions, transparency
and centered composition. Do not redraw, recolor, stretch, crop the symbol or
substitute an earlier concept. Scale its margins with the image; add transparent
padding when a nonsquare destination requires it.

All other PNGs in `assets/branding/` are size-matched derivatives of this master,
including files retaining historical concept filenames. Those filenames do not
indicate alternative approved designs. `assets/branding/universe-builder.icns`
contains the scaled macOS icon representations used by both packaged apps and
generated Finder/Dock shortcuts. Regenerate derivatives from the master when
changing sizes; the master remains the source of truth.

## Homebrew and the desktop launcher

The public command is `multiverse-mcp`. The release workflow builds a complete
macOS app for Apple Silicon and Intel, attaches versioned archives and a
checksum-pinned Homebrew formula to a **draft preview release**, and leaves
publication for review. This checkout has no configured GitHub remote yet;
there is no published tap or downloadable release to install today.

Once the release is published and its generated `multiverse-mcp.rb` is committed
to `Formula/` in a Homebrew tap, install using that tap's actual owner/name:

```sh
brew install OWNER/TAP/multiverse-mcp
multiverse-mcp ux
multiverse-mcp shortcut --launcher "$(brew --prefix multiverse-mcp)/bin/multiverse-mcp"
```

The shortcut appears in `~/Applications` and can be dragged to the Dock. Add
`--destination "$HOME/Desktop"` to place it on the desktop instead. It runs
`multiverse-mcp ux` using a stable Homebrew path that survives upgrades. An
existing shortcut or application is never overwritten. The installed app and
shortcut open the persistent author workspace; fixture mode requires `--fixture`.

For a new installation, initialize it once and retain its returned author profile ID:

```sh
installation="$HOME/Library/Application Support/Multiverse MCP"
author=$(multiverse-mcp admin --installation "$installation" init)
multiverse-mcp ux --installation "$installation" --profile "$author"
multiverse-mcp shortcut --launcher "$(brew --prefix multiverse-mcp)/bin/multiverse-mcp" \
  --installation "$installation" --profile "$author"
```

Use the connection-specific shortcut command **instead of** the earlier generic
shortcut if you want it to remember the installation and profile ID. Credentials
remain in the protected installation directory. An unconfigured `ux` opens the
connection screen, where you can enter an existing installation and profile ID.

MCP hosts use the absolute Homebrew command with arguments
`serve --installation PATH --profile AGENT_PROFILE_ID`. Enroll and grant a
separate agent profile as described below. `multiverse-mcp admin --help` exposes
the existing administration commands. Homebrew installs the whole app bundle
without a development server, Rust toolchain or Python runtime dependency.

See the [release runbook](docs/release-runbook.md) for building archives, generating
the formula, publishing the tap and preserving data during upgrades. These are
preview packages: ad-hoc signed, not notarized, with release acceptance still open.

## Build and verify

Use the pinned Rust toolchain. On a Mac whose Xcode license has not been accepted, use the installed command-line tools:

```sh
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
cargo run --locked -p xtask -- check
```

The check runs formatting, Clippy with warnings denied, all workspace tests, and generated-contract drift checks. Native UI and model-host checks are separate gates.

Independent JSON Schema and MCP checks use Python and `jsonschema==4.25.1`:

```sh
python3 -m venv /tmp/universe-validation
/tmp/universe-validation/bin/pip install jsonschema==4.25.1
export UNIVERSE_PYTHON=/tmp/universe-validation/bin/python
cargo run --locked -p xtask -- validate-contracts
cargo run --locked -p xtask -- mcp-smoke
cargo run --locked -p xtask -- installation-smoke
```

After an intentional DTO change, run `cargo run --locked -p xtask -- schemas`, review the generated contract diff, then run both validation commands. Application arguments are generated from Rust; prose examples in the original specification are not executable API definitions.

## Native fixture

```sh
cargo run --locked -p xtask -- package-fixture
open 'target/fixture/Universe Builder Fixture.app' --args --fixture
```

The app bundles its engine, MCP helper, and administration CLI and embeds its CSS. It needs no development server, shell PATH, or network for fixture operations. The package is locally ad-hoc signed; it is **not notarized or a distribution release**. Open a universe, inspect records, enter an entity label, review, and save a noncanonical proposal. The engine exits when its parent app closes. Fixture data is discarded on exit.

## Standalone MCP fixture

```sh
runtime=$(mktemp -d /tmp/universe-fixture.XXXXXX)
cargo build --locked -p universe-engine -p universe-mcp
./target/debug/universe-engine --fixture --socket "$runtime/fixture.sock"
```

Leave that process running. In a second terminal, print a host configuration using the actual absolute binary and socket paths:

```sh
cargo run --locked -p xtask -- mcp-config /absolute/path/universe-mcp /absolute/path/fixture.sock
```

This command prints configuration; it does not edit a host's settings. Stop the fixture engine when finished. Its read/propose scope is deliberately limited to disposable data. Do not connect a production package to this endpoint.

The fixture implements describe, open-context, search, advanced get/propose, get-proposal, and operation lookup. Cancellation reports an already-completed proposal without pretending to undo it. Record retrieval supports the payload field group; history/evidence views return typed unsupported errors. World-scoped fixture proposals enforce explicit entity/work associations and supported target footprints; more complex footprints remain unsupported. Ordinary factual checks, state/context assembly, validation, and impact require the persistent engine; fixture commit returns policy denied. Default discovery exposes 11 tools; `--advanced-tools` exposes all 16 typed contracts, including raw record reads and proposals.

## Persistent installation

Build the helpers together so discovery can use the absolute sibling engine path:

```sh
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp -p universe-builder-desktop
installation="$HOME/Library/Application Support/Universe Builder"
author=$(./target/debug/universe --installation "$installation" init)
./target/debug/universe --installation "$installation" --profile "$author" create 'The Ashen Cycle' --first-time '2040-01-01T09:00:00+00:00'
./target/debug/universe --installation "$installation" --profile "$author" doctor
./target/debug/universe-builder --installation "$installation" --profile "$author"
```

`init` prints a profile ID, never its credential. Keep that ID for subsequent launches; initialization is a one-time operation. Credential files live in the protected installation directory. The persistent desktop opens a universe library, pinned paged explorer, entity/world/work/saga draft controls, durable draft autosave and recovery, typed value/relationship/fictional-time claim controls, typed inspector and authored-clock controls, agent proposal review, validation findings, exact approval, withdrawal and commit. Autosave preserves completed draft operations, their submitted proposal reference and rationale without publishing canon. Unfinished form fields are saved only when added to the draft. No raw JSON editor is exposed. A stale draft requires explicit rebase; competing windows cannot silently overwrite each other. You can also select **Open persistent author workspace** from the packaged fixture and enter the installation path and enrolled profile ID. Closing it preserves the service and packages. The engine stops after 15 minutes without connected clients or on an authenticated author `shutdown` command. Fixture mode keeps its original disposable lifetime.

Every new universe requires an authored starting timestamp. For a familiar calendar, pass an RFC3339 Gregorian date with an explicit offset as above. For a fictional calendar, use `--calendar 'Ashen days' --first-time 90 --tick-label days` and, if defined, `--ticks-per-month 30`. The native creation form offers both options with no prefilled date. The immutable first interaction and current story time belong to canon; reading, waiting and ordinary edits never move the clock. Time advances through a reviewed operation with an explicit destination and reason; backward travel requires the time-travel choice.

The desktop can inspect basic state at the current story date or another authored time and create timed attributes with explicit start and duration. Gregorian durations are seconds; fictional durations use the declared tick unit. “N months ago” uses the pinned date, rejects missing month conversions or nonexistent target dates, and never guesses from wall time. Gregorian rendering uses the authored fixed offset, not automatic DST rules. The scrollable Timeline filters declared world/region event locations and compares evidence immediately before and after an occurred event. Exact event effects can transfer or end possession; item powers follow established possession and explicit timers. Reports, plans and predictions have no automatic objective effects. Independent calendars and unresolved causality are never synchronized by guesswork.

Enroll a separate agent profile with `enroll`, then grant access with `grant PROFILE_ID UNIVERSE_ID [--world WORLD_ID] [--propose] [--edit] [--protected]`. An omitted world set creates a universe-wide grant. The proposal and commit paths check the complete world/shared/protected footprint against current grants. An edit grant never substitutes for exact author approval. `revoke PROFILE_ID` invalidates active and future sessions. Use `rename UNIVERSE_ID NAME` to retain the old exact alias; names cannot be rebound to another universe. `register ABSOLUTE_DATABASE_PATH NAME` checks package identity and writer ownership.

Configure an MCP host with an absolute `multiverse-mcp` command and arguments `serve --installation /absolute/installation/path --profile AGENT_PROFILE_ID`. The `serve` prefix is required for this public launcher. The bundled lower-level `universe-mcp` helper accepts the installation/profile arguments directly. Default discovery exposes 11 tools: plain fact and contract research, factual change checking, describe, open context, search, proposal/impact reads, commit, operation lookup and cancellation. Add `--advanced-tools` to expose all 16 contracts, including raw record/state/context reads, proposals and validation. Ordinary callers use names and factual deltas; the engine constructs internal records and checks candidate state.

Pinned discovery, contextual-name/FTS search, batched record reads, explicit assertion listing, budgeted dependency-closed context briefs with explicit partial delivery, durable proposals, validation, commit and operation recovery use real storage. Impact uses a conservative full-universe dependency closure. Queued proposal validation returns an operation ID; operation lookup pages findings independently of evaluation coverage. World-scoped validation returns restricted coverage and requires author validation; hidden findings are not disclosed. Unsupported semantic operators return explicit limitations. It never falls back to fixture data.

The packaged helpers are under `target/fixture/Universe Builder Fixture.app/Contents/MacOS/`. The bundle is still a local development package. See [storage and ownership decisions](docs/adr/ADR-0005-durable-kernel-and-ownership.md) for limits and recovery boundaries.

For the persistent author interface in that bundle, run its `multiverse-mcp ux --installation PATH --profile AUTHOR_PROFILE_ID`; the desktop executable's `--fixture` option opens the separate disposable feasibility interface. The local package workflow has exercised ordinary MCP changes, exact native source review, separate approval/publication and fresh committed retrieval. Native contextual-name metadata and validity, alias-based relationship transfer, blocked maximum revision, current and earlier scene-time participant displays, and immutable ownership history were exercised. Native dependent-action denial and restart-before-publication recovery were also exercised. This does not qualify mid-transaction crash recovery, exhaustive accessibility or prose interpretation, notarization or distribution acceptance.

## Scope and next work

The architecture and full backlog are in [the v0.4 specification](Universe_Builder_Full_Implementation_Plan_v0.4.md). The silver-gate scenarios in `fixtures/silver-gate.json` record semantic targets; the disposable fixture still reports them as unsupported. the broader story-level acceptance matrix remains open. Passing related unit tests does not complete that suite.

## Review, sources and recovery

For writing a novel with an external AI, follow the
[AI authoring workflow](docs/ai-authoring-workflow.md): verify provisional prose's
material continuity claims, then commit its universe changes when the author
chooses to use it. Only a successful `universe_commit` makes changes canon; fresh
context must include that revision before dependent writing continues. The
novel readiness assessment records the local
MLX evaluation, implementation strengths and remaining acceptance work.

The CLI exposes the same author boundary as the native UI:

```sh
universe --installation /path/to/installation --profile PROFILE_ID library 'Universe name'
universe --installation /path/to/installation --profile PROFILE_ID review 'Universe name' PROPOSAL_ID VERSION DIGEST
universe --installation /path/to/installation --profile PROFILE_ID approve 'Universe name' PROPOSAL_ID VERSION DIGEST VALIDATION_RUN_ID
universe --installation /path/to/installation --profile PROFILE_ID stage-source 'Universe name' 'Source label' /path/to/source.txt
universe --installation /path/to/installation --profile PROFILE_ID backup 'Universe name' /path/to/new-backup.sqlite
universe --installation /path/to/other-installation --profile OTHER_AUTHOR_PROFILE restore /path/to/backup.sqlite 'Restored name'
```

Machine integrations use closed public tool requests. Approval is a private author command, never an agent-supplied approval field. Commit uses `universe_commit` with the exact proposal reference, base revision, validation run and idempotency key. A revised proposal needs new validation and approval. An expired context must be explicitly reopened.

Source staging returns proposal operations and does not admit source records. UTF-8 bytes are preserved without normalization. Whole-universe backups include source text, immutable history and workflow receipts; installation credentials are excluded. Restore validates a private copy, preserves IDs and refuses an existing destination rather than overwriting it. The native recovery panel and CLI also provide checksummed logical exports, staged restore/clone imports, dependency-closed filtered exports and bounded v0.3 conversion. Retention-safe compaction preserves all immutable history, source assets and workflow receipts; only rebuildable data is collected.

## Milestone 7–8 development checks

The native author workspace includes rich selectors for event occurrence, possession, powers, knowledge and data packs. Definitions can be revised through typed inspector controls. Continuities fork an exact revision; comparison and selected adoption create reviewable draft operations. Later parent edits never enter a child automatically. Data packs contain references and exact dependencies, not executable plugins.

The [release runbook](docs/release-runbook.md) documents whole-bundle updates, rollback and headless checks. Packaging writes helper digests and a locked component inventory and seals them with the ad-hoc bundle signature. Packaged clients reject modified bundles before engine startup. This does not replace Developer ID signing, notarization, independent security review or clean-machine testing.
