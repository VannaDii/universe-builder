# Universe Builder

A local universe-management application with a shared Rust engine, a Dioxus desktop, and an MCP interface for external agents.

Two modes are available: the disposable read/propose fixture, and a **persistent authenticated engine** with durable universe packages, installation profiles, grants, aliases, recovery, and diagnostics. The persistent desktop now uses the engine for pinned research, durable proposals, basic validation, exact author approval, atomic commits, UTF-8 source staging and verified backups. The first-six-milestone workflow is implemented; milestone 7–8 work adds event timelines, possession powers, explicit knowledge, validation jobs, pinned forks, reviewed adoption, versioned data packs and release checks. Full semantic and release acceptance remains open. See [implementation status](IMPLEMENTATION_STATUS.md), [authoring evidence and remaining work](docs/authoring-verification.md), and [milestone 3–4 evidence](docs/kernel-engine-verification.md).

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

The fixture implements describe, open-context, search, get, propose, get-proposal, and operation lookup. Cancellation reports an already-completed proposal without pretending to undo it. Record retrieval supports the payload field group; history/evidence views return typed unsupported errors. World-scoped fixture proposals enforce explicit entity/work associations and supported target footprints; more complex footprints remain unsupported. State/context assembly, validation, and impact return typed unsupported errors; commit returns policy denied. All 13 tools have typed input/output contracts and require the universe name on every invocation.

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

Configure an MCP host with absolute `universe-mcp` as its command and `--installation /absolute/installation/path --profile PROFILE_ID` as arguments. This mode exposes the same 13 contracts. Pinned discovery, contextual-name/FTS search, batched record reads, explicit assertion listing, budgeted dependency-closed context briefs with explicit partial delivery, durable proposals, validation, commit and operation recovery use real storage. Impact uses a conservative full-universe dependency closure. Queued proposal validation returns an operation ID; operation lookup pages findings independently of evaluation coverage. World-scoped validation returns restricted coverage and requires author validation; hidden findings are not disclosed. Unsupported semantic operators return explicit limitations. It never falls back to fixture data.

The packaged helpers are under `target/fixture/Universe Builder Fixture.app/Contents/MacOS/`. The bundle is still a local development package. See [storage and ownership decisions](docs/adr/ADR-0005-durable-kernel-and-ownership.md) for limits and recovery boundaries.

## Scope and next work

The architecture and full backlog are in [the v0.4 specification](Universe_Builder_Full_Implementation_Plan_v0.4.md). The implemented author/agent loop and pending verification gates are recorded in [authoring verification](docs/authoring-verification.md). The silver-gate scenarios in `fixtures/silver-gate.json` record semantic targets; the disposable fixture still reports them as unsupported. Persistent-engine S01–S10 evidence is listed separately; the broader story-level acceptance matrix remains open. Passing related unit tests does not complete that suite.

## Review, sources and recovery

For writing a novel with an external AI, follow the
[AI authoring workflow](docs/ai-authoring-workflow.md): verify provisional prose's
material continuity claims, then commit its universe changes when the author
chooses to use it. Only a successful `universe_commit` makes changes canon; fresh
context must include that revision before dependent writing continues. The
[novel readiness assessment](docs/novel-authoring-readiness.md) records the local
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

The [milestone 7–8 evidence](docs/semantic-release-verification.md) distinguishes implemented behavior, representation fixtures and remaining acceptance. The [release runbook](docs/release-runbook.md) documents whole-bundle updates, rollback and headless checks. Packaging writes helper digests and a locked component inventory and seals them with the ad-hoc bundle signature. Packaged clients reject modified bundles before engine startup. This does not replace Developer ID signing, notarization, independent security review or clean-machine testing.
