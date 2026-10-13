# Universe Builder

Two modes are available: the disposable read/propose fixture and a persistent authenticated engine for author-defined factual universes. Persistent mode supports incremental definitions and instances, scoped factual constraints, retrieval, declared knowledge acquisition, scoped cross-instance cardinality, exact approval, atomic publication, history and recovery. The external writer interprets prose and asks for author clarification; the MCP validates supported factual declarations. Assessments remain optional attributed domain records. The connected writing workflow has been exercised through the native author interface and local packaged launcher. Prose interpretation remains fallible; release acceptance remains open.

## Dart conversion development

The initial Flutter shell is in `apps/ub_app`, with desktop and compact navigation,
the approved branding, and System/Light/Dark appearance controls in Settings.
Its native connection adapter accepts `--installation`, `--profile` and optional
`--engine` arguments and reads the accessible library and universe summaries
through authenticated loopback HTTP. A disposable service regression covers
owner access and the empty library of a contributor without universe grants.
The packaged macOS app's **Use this computer** action sets up its app-private
installation in Application Support, retains the owner profile and reconnects
through its bundled engine. Build this local bundle with
`python3 scripts/build_flutter_macos.py`; it includes native Dart assets, the
approved icns, an inherited helper sandbox and a local ad-hoc code signature.
This does not publish a release or provide distribution signing/notarization.
Stop the bundle's engine before rebuilding; the build command refuses to replace
a running helper.
An explicit installation without a profile uses the same local device setup.
The engine's `--device-profile` action prints only the retained profile ID;
`--initialize` keeps its existing create-only behavior. The app starts HTTP-only
helpers, avoiding Unix socket path limits in Application Support. Linux uses
XDG data storage (or `~/.local/share`) once its helper is installed; that platform
journey remains unqualified.
Appearance currently lasts for the app session. Native access to installations
outside the macOS sandbox, editing/recovery and remote connections remain in
progress. Web explains its instance connection requirement;
it does not offer local database authority. Generated mobile/Windows/Linux runners
are not yet qualified. Build the shell from `apps/ub_app` with `flutter build web`
or, on macOS, `flutter build macos --debug`.

Connected approval owners can create a universe from Library. Gregorian creation
uses an explicitly entered date, whole-second time and fixed UTC offset, with an
exact start preview. Fictional creation uses a calendar name, signed initial tick,
tick label and optional authored month conversion. No current date or inferred
month conversion is supplied. Successful creation refreshes the catalog and opens
the universe summary. Invalid input and known rejection retain the form; an
interrupted response requires an explicit library check rather than resubmitting
creation automatically. Unfinished creation fields are not yet recovered after
app termination; typed durable form recovery remains in progress.

Overview offers a **Represented context** selector for each continuity. A sole
context is selected automatically; multiple contexts require an explicit choice.
World reads use that context at the continuity's exact revision, and returning
from an editor retains an accessible selection while refreshing the revision.
Opening a listed world displays its complete published record in that frame,
including aliases, multilingual labels and metadata. **Rename world** opens a
recoverable name-and-rationale form pinned to the record's version. **Add rename
to changes** appends an expected-version rename to the compatible author draft;
it preserves other work and does not change canon. Repeating the same addition
does not duplicate the rename. A different existing rename, another base or
context, or a submitted draft requires review in Changes. Recovered fields from
an older record or revision remain visible until the author explicitly replaces
them with the current published world. Publication retains the earlier name as
an alias. Returning to the detail view refreshes the accessible current record.
**World draft** opens the first unfinished record editor in the chosen context.
World name, English display label, setting type and
rationale autosave on this device, including blank or incomplete input. Ordered
aliases, multilingual labels, the intended record ID, original revision and
represented context are retained in typed rows. Pending input can still save
after the service connection closes; opening saved work checks current service
access and the exact instance/profile/universe/continuity/context binding. New
world forms in different contexts have separate recovery slots. Older
single-context fields remain available in their original context. Concurrent
windows use expected generations, and conflicting saves retain the current text.
**Saved on this device** means the local transaction completed. Fields changed
just before termination may still be pending. This recovery file lives under
`client-recovery/world-forms.sqlite` and is separate from canon and proposal
operations. **Add to changes** explicitly adds a completed world operation to the
existing author-owned service draft, preserving its other operations. A retry
checks the saved draft before adding, so the same world is not duplicated. Fields
can then be cleared with **Start another world**, which creates a fresh operation
reference and saves a new unfinished form in the same context and revision.
Previously completed world operations and their rationale remain in Changes.
The next world's incomplete fields use the existing device recovery slot.
Fields are preserved exactly, with empty optional fields omitted. Different revisions
or contexts, changed fields for an already-added world, and drafts already linked
to proposals require review rather than silent replacement. Adding leaves canon
unchanged. **Changes** opens the author-owned draft for a continuity, showing
entered operations and rationale. Before submission, the rationale can be edited
and explicitly saved with the draft's expected generation; failed saves retain
the text. Empty rationale remains recoverable but the service's required
rationale rejection explains what to complete. **Submit proposal** pins its original revision
and context and creates a submitted proposal through the existing service. The
frozen review loads every page and shows compiled before/after record fields,
including prior values from the pinned revision. Submission does not approve or
publish. Reopening checks durable operation recovery before offering submission;
an interrupted draft-link save can be completed with **Save proposal with
changes**, preserving the existing proposal. **Run checks** evaluates the exact
proposal against the complete universe. Findings retain their outcome, coverage,
records and evidence, with opposing evidence, unsupported checks and the submitted
assessment available for review. The service's existing rules decide whether
approval is admissible. **Approve reviewed changes** retains approval for this
exact proposal and check run; **Publish approved changes** is a separate action.
**Check publication** and reopening use existing approvals and operation lookup
to recover the outcome without retrying publication automatically. The confirmed
receipt names its revision, and **Read published records** opens that exact
revision with current access. Returning to Overview refreshes the canon summary.
Unsubmitted operations can be removed with **Remove from draft**. Draft changes
for a new world can also be edited through **Edit world fields**. Name, English
label and setting type save explicitly with **Save world changes**, preserving
the operation reference, aliases, other languages, metadata and rationale.
Unfinished edits autosave in separate typed recovery slots for each world
operation, leaving the completed draft intact. Reopening retains the draft
generation; edits from an older draft remain visible but require review before
replacing pending fields with the current saved world. Existing unfinished
new-world fields are retained when the recovery schema is upgraded. Draft changes
use expected generations; **Undo draft change** and **Redo draft change** save
the selected prior content without changing canon. Undo/redo history stays within
the current Changes page and resets on reload. **Continue editing separately**
copies a submitted proposal's operations into an editable draft, retaining the
original proposal and approvals. **Rebase draft to current revision** explicitly
updates the draft's base while preserving exact operations and expected record
versions; conflicting record edits must still be resolved. After publication,
**Start new changes** opens an empty draft at the current revision. Operation
field editing for other operations, other record forms and creation-form recovery
remain in progress. Existing owner-only service draft
permissions remain unchanged.

The approved [conversion plan](docs/dart-conversion-plan.md) is being implemented
alongside the current runtime. The Dart workspace currently contains the shared
canonical encoding, digests, typed identities, values, temporal/spatial expressions
and reference foundations, typed scopes, validity and evidence bases, and
all 38 record families: worlds, realms, entities, the seven definition
families, propositions, assertions, the five narrative families and the three
source/evidence families, the five knowledge families, completeness, appearances,
image assets, goals, commitments, rules, creative boundaries, exceptions and
issue decisions, events, action definitions, item powers and represented contexts.
The shared domain also contains all 61 current operation variants, their coarse
authority classifications, incremental attribute evidence and immutable record
version DTOs. Pinned query frames and perspectives are typed too. The new
`ub_contracts` package contains proposal references, proposals, compiled changes,
impact and commit-receipt DTOs, validation findings and opposing diagnostics,
versioned validation reporting, stored/public operation views and typed source
assessment declarations, selections and review pages. The workspace
also contains the internal typed SQLite
codec,
revision journal and connection policy. It is not yet a
replacement engine or application.

The owned SQLite store now exports verified complete-history and canon-only
logical archives, and stages identity-preserving imports or named clones.
Reconstruction preserves record/version IDs and pinned revision history, maps
canonical universe references, retains original digest provenance across repeated
clones, and leaves authored strings and historical editorial evidence unchanged.
Imported approvals and receipts remain historical rather than granting authority.
Canon-only exports retain canonical source/image bytes and omit editorial workflow
and uncommitted assets. Filtered archives cannot restore the source universe ID.
The native service now saves author-owned exact import previews with a private
copy of the verified input. Acceptance compares the retained preview digest,
rechecks current authority and name/identity reservations, and publishes an
admission receipt before catalog registration. Restart and repeated acceptance
recover only a package bearing that exact receipt; unrelated destinations are
refused. Imported workflow never supplies installation credentials or grants.
The native service also exports complete history, canon-only history, or a
dependency-closed record selection. Selection follows all retained versions,
keeps global definitions/policies and contexts, and includes universe appearances,
selected entry appearances and initialization attachments. Omitted counts are
explicit; incomplete archives require a named clone. Full-history export rejects
a record filter, and all exports refuse an existing destination.
Native logical archive byte limits now use the existing 8 GiB package bound,
including PostgreSQL export and retained import chunks. The 2,000,000-row budget,
per-record/content bounds, trusted-schema copying and typed-row checksums remain
in force. Legacy source conversion retains its separate 512 MiB input bound.
Author transport/CLI integration remains pending.
The native author service now supports explicit bounded v0.3 `convert_legacy`.
It reads the original without modification and emits a verified canon-only
archive for separate import review. Record/version IDs remain intact; old
continuity/revision IDs have explicit deterministic mappings. Create, replace
and tombstone history is retained. Unsupported source/workflow side tables,
digest/identity mismatches, inherited baselines and broken history are refused.
This limited command is separate from the identity-preserving offline operator
conversion procedure.
The protected credential store now exposes offline `convertCredential` for
legacy version-1 profile JSON. It preserves the exact profile identity and secret,
verifies the complete converted credential and unchanged source hash, and publishes
through an exclusive atomic rename. Input reads use an owned private read-only
descriptor with the existing 4096-byte bound; failures do not expose parser/driver
credential values. Conversion creates no enrollment, grant or installation.
Credential storage, authentication and both serialized/relational conversion
retain leading and inline U+FEFF characters as part of the exact secret, together
with Unicode, NUL and line endings. A BOM before the JSON credential document is
rejected as invalid syntax rather than silently consumed. Focused checks use
disposable credentials and leave recovery originals unchanged.
The SQLite store also exposes offline `convertPackage` for maintained serialized
v1/v2 and relational package layouts. It retains IDs, history, pinned branches,
ordered classification ambiguity, exact workflow authority and receipts. It
checks source digests, retained rows, snapshots and historical ancestry in a
private target, then revalidates the read-only original before exclusive durable
publication. Unknown schemas, journal sidecars, changed sources and existing
destinations are refused. It creates no installation or catalog registration.
The installation store exposes offline `convertInstallation` for the maintained
serialized and relational authority layouts. Relational input requires an exact
normative schema match and all authority tables are copied and compared. It
preserves enrolled/revoked profiles, exact
credentials (including unenrolled files), catalog paths, aliases, audit entries
and ordered grant scopes/limits. Pending purges, retained import previews,
unknown tables, orphan limits and missing/mismatched credentials block publication.
It compares the converted grants through the ordinary installation reader and
rechecks the original database and credential inventory before exclusively
publishing the complete private directory. Existing installation identity is
preserved; explicit conversion establishes one when absent for the Dart handshake.
Offline SQLite originals use immutable read-only access after journal-sidecar
refusal, including clean databases retaining a WAL-format header. This avoids
creating journal files in the source directory; final hashes and credential
inventory are rechecked before publication. This mode is never used for live
runtime connections.
Conversion does not move or convert catalog packages or switch a live engine.
The Dart operator CLI now exposes `convert-package`, `convert-installation` and
`convert-credential` with the maintained `--installation` and optional `--profile`
syntax. These commands stay offline: they do not start an engine, resolve backend
settings, authenticate a profile or register a target. Success writes one JSON
conversion report to standard output; failures return nonzero status with redacted
diagnostics. The same Dart executable now exposes the maintained author commands:
initialization, status/doctor, universe creation/registration/renaming, profile
enrollment/grants/revocation, public tool files, library/review/exact approval,
private author-writing stdin, source staging, backup/restore/maintenance, legacy
conversion and logical export/import. Service commands require the selected
profile and use the authenticated local engine; initialization invokes its
installed sibling explicitly. Approval does not publish. Private stdin is bounded
at 1,000,000 bytes; tool/source files and encoded requests respect the 1 MiB frame
limit. Source text retains leading BOM characters, Unicode and line endings;
JSON inputs use strict parsing without silently removing a BOM.
For development, run `dart run --verbosity=error apps/ub_cli/bin/universe.dart --help`.
Build a standalone bundle with
`dart build cli --target apps/ub_cli/bin/universe.dart --output target/dart-operator-cli`.
Keep the generated bundle's `bin/` and `lib/` directories together; `dart compile exe`
does not include this project's required build hooks. The compiled operator bundle
has been functionally checked on macOS with disposable data, without release signing
or publication. The compiled author CLI has also exercised sibling initialization,
on-demand creation and shutdown outside the source tree. Keep the sibling
`universe-engine` available with its required bundle libraries. Desktop launcher
UX/shortcut interfaces and complete platform packaging remain pending.
Focused functional checks currently cover macOS only.

The Dart MCP foundation now embeds the maintained tool schemas, descriptions and
initialization instructions, preserving ordinary discovery of 11 tools and advanced
discovery of all 16. Regenerate these resources with `dart run tool/embed_mcp.dart`;
the maintained contracts and Rust instructions remain their owners during parity.
The portable stdio codec bounds raw input lines at 1 MiB, rejects duplicate keys,
malformed UTF-8 and JSON BOMs, and preserves exact numeric tokens. Output contains
canonical JSON plus a newline; the full advanced catalog legitimately exceeds the
engine's separate response frame limit. Functional tests cover VM and browser codec
behavior and compare the embedded catalog against its owning contracts. Portable
MCP protocol types now retain string/signed-i64 correlation IDs separately from
engine u64 IDs, map discovery schemas to MCP keys, and construct structured
success/error and cancellation responses. Initialization result construction
preserves known legacy version negotiation with a `2025-11-25` fallback, including
when a client requests a stateless version. These helpers do not provide a byte
transport or executable.

The `ub_mcp` package now implements the legacy session lifecycle and public-tool
dispatch against a supplied backend: pre-initialization ping, version negotiation,
ordinary/advanced discovery, strict application request admission, structured
service failures and responsive cancellation. Disconnect signals backend cleanup
and suppresses late output; cancellation never claims an admitted mutation was
rolled back. Session and stdio behavior are checked on VM and Chrome. The native
`universe-mcp` executable now connects this session to the local SQLite engine.
Startup uses the installed sibling engine once; each tool authenticates a fresh
connection using the selected profile, without replaying uncertain calls. Retained
calls, including blocked output, are bounded at the engine's eight-call capacity;
excess calls receive `EVALUATION_LIMIT_REACHED`. Controls remain responsive during
tool work, stdout contains serialized protocol frames, and diagnostics go to
stderr. Its compiled bundle has exercised handshake and service retrieval on
macOS outside the source tree with an empty PATH. Real service checks cover scope
denial and profile revocation. Fixture mode, stateless MCP and remote HTTP remain
pending. The conversion uses the plan's narrow application-owned
adapter fallback. Candidate review found `mcp_dart` validates JSON numbers as Dart
`num`, while `dart_mcp`'s standard channel uses generic JSON codecs; preserving UB's
exact tokens would require replacing those boundaries. See the
[mcp_dart value validator](https://github.com/leehack/mcp_dart/blob/main/lib/src/types/validation.dart)
and [dart_mcp channel](https://github.com/dart-lang/ai/blob/main/pkgs/dart_mcp/lib/stdio.dart).

For development, run
`dart run apps/ub_mcp/bin/universe-mcp.dart --installation /absolute/installation --profile PROFILE_ID`
and add `--advanced-tools` for all 16 tools. Build with
`dart build cli --target apps/ub_mcp/bin/universe-mcp.dart --output target/dart-mcp`.
Keep the generated `bin/` and `lib/` directories together, with the engine sibling
and its bundle libraries available for on-demand startup. These development checks
do not qualify other platforms, release packaging, signing or publication.

The Dart `multiverse-mcp` public launcher now preserves `serve` forwarding to
`universe-mcp` and `admin` forwarding to `universe`, including literal arguments,
inherited standard streams, helper exit status and termination forwarding. It uses
the shared installed-sibling resolver and macOS bundle check; it does not search
PATH or interpret forwarded arguments through a shell. Build with
`dart build cli --target apps/ub_cli/bin/multiverse-mcp.dart --output target/dart-launcher`.
The launcher needs its installed sibling executables and their native libraries.
Compiled forwarding has been checked on macOS outside the workspace with an empty
PATH. Explicit launcher help/version and MCP help do not start an engine. Dart
`ux` and `shortcut` remain unavailable until the Flutter desktop executable and
packaging are delivered; the maintained Rust launcher continues to provide them.

Use Dart **3.13.4** (enforced by the workspace SDK constraint) and Flutter
**3.47.5** (recorded in `.flutter-version`). Dependency resolution is locked in
the root `pubspec.lock`. Run `dart pub get` at the repository root, then:

```sh
dart analyze packages tool
dart format --output=none --set-exit-if-changed packages tool
cd packages/ub_domain
dart test
dart test test/canonical_test.dart test/identity_test.dart test/exact_amount_test.dart test/value_test.dart test/selector_test.dart test/scope_test.dart test/records_test.dart test/definitions_test.dart test/narrative_source_test.dart test/knowledge_appearance_test.dart test/expr_test.dart test/rule_records_test.dart test/event_contract_test.dart test/operations_test.dart test/frame_test.dart --platform chrome
cd ../ub_store
dart test
cd ../ub_rules
dart test
dart test test/compiler_test.dart --platform chrome
cd ../ub_contracts
dart test
dart test test/workflow_test.dart test/validation_test.dart test/validation_scope_test.dart test/assessment_test.dart test/assessment_integrity_test.dart test/read_request_test.dart test/read_response_test.dart test/state_response_test.dart test/response_test.dart test/wire_message_test.dart test/installation_test.dart test/author_writing_action_test.dart test/engine_request_test.dart test/workflow_request_test.dart test/writing_test.dart test/writing_knowledge_test.dart test/writing_delta_test.dart --platform chrome
cd ../ub_service
dart test
dart test test/configuration_test.dart test/postgres_endpoint_test.dart test/endpoint_encryption_test.dart --platform chrome
```

Browser tests must run from the package directory. Set `CHROME_EXECUTABLE` if
Chrome is not discoverable automatically. Tests consume existing canonical and
historical fixtures; they do not read or modify author installations.

The ownership bridge builds with the host C compiler through Dart build hooks.
Native command-line bundles must use `dart build cli`; `dart compile exe` alone
does not bundle the native assets.

The Dart persistent engine is available for local SQLite installations:

```sh
dart run --verbosity=error apps/ub_engine/bin/universe-engine.dart --installation /path/to/disposable-installation --initialize
dart run --verbosity=error apps/ub_engine/bin/universe-engine.dart --installation /path/to/disposable-installation
dart build cli --target apps/ub_engine/bin/universe-engine.dart --output /path/to/build-output
```

Initialization prints only the approval-owner profile ID and refuses replacement
of existing profiles. Ordinary startup opens an existing installation. Keep the
compiled `bundle/bin/universe-engine` with its adjacent bundled libraries. Author
shutdown, interrupt and termination signals drain the server and release ownership.
Startup resolves `UB_USE_POSTGRES`/`UB_POSTGRES_ENDPOINT` and existing protected
`settings.sqlite` before opening installation authority. Environment credentials
are never saved. PostgreSQL runtime selection currently fails explicitly without
opening a SQLite installation; no automatic fallback or conversion occurs.
The PostgreSQL storage foundation pins `postgres` 3.5.20. Its internal authored-text
codec stores strict UTF-8 in typed `bytea` columns, preserving NUL, BOM characters,
Unicode and line endings; exact numeric tokens remain text. Universe namespaces
come from validated internal IDs. Live functional checks on PostgreSQL 16.15 cover
non-superuser schema setup, exact values/null versus empty, transaction rollback,
competing row locks and namespace reset on a reused pooled connection. These are
representative driver/storage checks, not complete PostgreSQL store or service
support. The internal PostgreSQL body schema and transaction-owned codec now use
the same normative mapping catalog as SQLite, generating all 886 typed body
tables. Focused checks cover restricted-role provisioning, complete provisioning
rollback, frozen payload/digest reconstruction through a new connection, absent
versus null fields, ordered collections, exact numbers/text, immutable rows,
foreign keys, collection gaps and recursive-graph refusal. The internal canonical
journal now has qualified history/membership tables, deferred continuity/head
references, transaction-held universe locks, exact authored commit text and
idempotency keys, durable receipts, pinned branching/history, and immutable world
name reservations. Focused connection tests cover rollback at history write
boundaries, reconnect/retry, historical receipt exclusion, stale writers and
independent universe namespaces with matching record/version IDs. This journal
is not an application publication entry point: candidate/definition/initialization
admission, current installation authority and semantic/search projection work must
be integrated by the complete PostgreSQL kernel. PostgreSQL's retained workflow
schema and transaction-owned storage now support all closed evidence families,
source/media content, typed staging, continuity names, historical authority
exclusion, exact retries and compared append. Workflow keys and authored names
use strict UTF-8 byte columns, preserving BOM/NUL characters without opaque
metadata bodies. Writes retain the universe lock through awaited verification;
the caller retains installation authority and owns final commit/rollback. Focused
checks cover retained draft/approval evidence, exact counters, complete batch
rollback, content/digest corruption refusal, family constraints and matching keys
in independent namespaces. The internal PostgreSQL control schema and authority
primitives now retain installation identity/normalization, profile hashes,
revocation, typed ordered grants, exact unsigned expiry, administration audit,
permission-filtered catalog reads and historical rename aliases. Catalog entries
use validated universe namespace locators without filesystem device/inode fields.
All authority reads and changes acquire the installation singleton row before
universe locks, preserving the existing serialized authority section across
database connections, including absent-grant insertion and withdrawal. Focused
checks cover reconnect, scope/expiry/delegation bounds, relevant authority sequence,
audit-failure rollback and lock conflicts for grant/revocation/author changes.
PostgreSQL candidate admission now uses the same factual foundation and reference
policy as SQLite, loading exact pinned versions and checking work bindings in
their named continuity. Focused checks cover definition ancestry/classification,
historical edition pins, unit/world kinds, current dependencies, namespace guards
and prose that resembles an ID. Frozen semantic fixture records retain their
digests; their duplicated normalized world selectors are rejected by reference
admission, rather than being treated as a publishable candidate. These are the
foundation/reference gates only; initialization, projection coordination,
exact approval and current authority remain required before publication.
The internal PostgreSQL semantic schema now preserves definition ancestry,
ordered world applicability, instance classifications, classification evidence
and initialization receipt constraints. Both backends use the same fixed
definition-index policy; PostgreSQL retains exact authored type names in UTF-8
byte columns and resolves definition propositions from the selected candidate.
Focused checks cover frozen semantic identities/digests, historical names and
ancestry, selected versus newer persisted propositions, attribute modes, foreign
keys and complete canonical/semantic rollback. Indexing does not grant publication
or create initialization receipts; the initialization gate remains to be ported.
PostgreSQL now has internal transactional reference, scalar, world, narrative and
search projections generated by the same fixed policy as SQLite. Search keeps
exact authored bytes separate from its disposable document and uses PostgreSQL's
simple-configuration [literal phrase parsing](https://www.postgresql.org/docs/16/textsearch-controls.html)
with a [GIN document index](https://www.postgresql.org/docs/16/textsearch-indexes.html).
Search intersects historical matches with the requested immutable membership;
the service still owns grants, perspective, pagination and coverage. Rebuild
retains the universe lock, verifies canonical bodies/current candidate heads,
repairs head caches and switches generations atomically within the caller's
transaction. Focused checks cover pinned forks/tombstones, reconnect, literal
queries, Unicode/BOM/NUL bytes, exact scalar paths, narrative/world dependencies,
interrupted generation switches, corruption refusal and matching IDs in another
namespace despite a changed session search path.
The internal PostgreSQL publication coordinator now runs workflow comparison,
retained-image decode checks, candidate admission, definition indexing,
initialization, immutable history, head/membership, projections and the durable
receipt inside one caller-owned transaction. Exact matching receipt retries
precede stale head/workflow comparison; changed-content reuse fails. Preview runs
the same path with a fresh request key inside a discarded savepoint. Current
installation authority must be held before the universe lock; returning a
revision is not durable until outer commit succeeds. Focused checks cover all
commit checkpoints, stale workflow, retained image metadata, savepoint recovery,
reconnect/retry and authority held through awaited publication while revocation
conflicts. Initialization cases now exercise this coordinator. This internal path
does not authenticate callers or confer exact approval/delegated rights.
The PostgreSQL service authority adapter now authenticates exact UTF-8 profile
credentials through the same credential/handshake policy as SQLite and creates
the same installation-bound principal and current authority capture. It rechecks
profile activity, catalog, grant scope/expiry, write permissions, approval author
and relevant authority sequence inside the transaction-held installation lock.
Profile summaries exclude credential hashes. Focused checks cover BOM credentials,
malformed/unknown/revoked denial, handshake bounds, SQLite/PostgreSQL capture
parity, identical regrant invalidation, expiry/withdrawal, installation identity
and revocation conflicting with an awaited authority callback. This is an adapter
for the owning backend transaction; it does not open endpoints or approve a
proposal by itself.
The native PostgreSQL opener now maps resolved environment/encrypted settings
into the pinned driver, including TLS mode, trusted roots, client certificate/key,
application name and connection timeout. Explicit installation creation and
ordinary opening are separate: opening discovers exactly one compatible control
namespace, preserves its stable identity and refuses missing, ambiguous or
incomplete authority. Database-local setup locking prevents competing setup
connections from creating two installations. Service transactions retain current
authority through commit/rollback, and close drains admitted work before releasing
the connection. Universe provisioning creates the complete typed/kernel/semantic/
workflow/projection schema, genesis and catalog entry atomically. Focused
`test/postgres_open_test.dart` checks use disposable data for configured opening,
authenticated internal publication, reconnect/retry, projection recovery, alias
collision rollback, competing setup, shutdown draining, incompatible layout
preservation and redacted certificate-loading failures. The publication fixture
supplies already-admitted input; it does not qualify proposal approval.
The native PostgreSQL proposal service now creates/revises/submits/withdraws
frozen proposals and reservations, evaluates candidates through the shared factual
rules and real kernel preview, retains exact validation bindings, accepts private
human author approval, and publishes only after checking current permissions,
latest proposal, validation, approval, head and a fresh candidate evaluation.
Durable operation/receipt retry precedes stale workflow/head checks under current
access rules. Bounded delegation follows the existing entity/predicate/continuity,
shared-work, expiry and complete-coverage policy. All writes remain inside the
owning installation transaction. `test/postgres_validation_test.dart` exercises
this authoring path with disposable profiles/data and a seeded represented
context; proposals and validation are produced by the service, rather than seeded
as already-admitted publication input. Context opening now resolves head or exact
revision through the shared perspective/world/temporal policy, retains a pinned
owner/scope/expiry-bound context, and admits proposal and validation requests from
that context under current authority. The PostgreSQL authoring tests now use
these request routes, including reconnect, foreign/expired/changed-scope context
denial, unknown represented context/universe guards and a different pinned
validation frame. Assessment request routes now verify the authenticated
assessor, retained source bytes, candidate dependencies, current footprint access,
proposal/head and expected selection generation before atomically retaining the
immutable envelope, selection and exact retry receipt. Clearing and reselection
preserve original evidence; changed selections invalidate prior validation and
approval bindings. Focused cases cover source-assessed validation/approval/
publication, reconnect and historical retry, stale generations, changed-key reuse,
wrong attribution and unverifiable source refusal without partial retention.
Queued PostgreSQL validation now retains an exact selection/authority capture,
prepares a frozen task using real kernel preview and source checks, and evaluates
without database handles outside the transaction. Completion rechecks that
capture and retains checked evidence plus terminal status atomically. A completion
savepoint discards partial rows and clears failed SQL before retaining a failure;
rolled-back notifications are discarded as well. Cancellation retains its marker
and retry receipt before signaling a worker after outer commit, and late results
cannot become checked evidence. Focused cases cover source-assessed completion,
interrupted work after reconnect, exact retry, changed selection, cancellation
rollback/retry and a real SQL failure inside the savepoint. Worker liveness is
provided by the owning runtime. The PostgreSQL job bridge now uses the existing
native isolate scheduler, opening fresh authority-coordinated transactions for
preparation and completion; a focused isolate case proceeds through approval and
publication. SQLite uses the same scheduler job interface. The in-process
PostgreSQL engine now authenticates connections, creates universes with their
objective context/calendar, manages grants and names, and dispatches retained
contexts, discovery, records/history, search, research briefs, effective state,
plain facts/contracts, ordinary writing checks, proposals and proposal/assessment
views, conservative impact,
assessments, synchronous/queued validation, operation
lookup/cancellation, private source staging/review/approval and publication.
Queued work starts only after submission commits. Engine functional checks cover
creation through author-reviewed publication, receipt recovery after reopening,
renamed aliases and current access withdrawal. The runtime drains requests and
workers before its caller closes the installation store. Unmigrated requests fail
explicitly. PostgreSQL reads apply the same world/perspective visibility,
dependency closure and history coverage as SQLite. Search and research cursors
retain the exact frame, arguments, principal and current scope across reopen;
advancing canon does not refresh an existing context. Focused engine checks cover
historical payloads/history, required research dependencies, paging recovery,
changed-argument refusal and denial of hidden records or another profile's context.
State reads preserve explicit/unresolved evidence, event entry/exit and immutable
initialization history, even when the original assertion has left current canon.
Plain fact reads await the same state projection under the pinned frame; hidden
namesakes never change visible name counts. Scoped readers retain restricted
initialization/contract coverage. These reads retain no validation or publication.
Ordinary PostgreSQL writing checks normalize dates, compile the existing factual
stages, retain an exact provisional draft and return validation plus impact.
Retries recover that draft and recheck it; they grant no approval and do not
advance canon. The shared writing/disclosure/source-preparation helpers now accept
asynchronous pinned edition reads, preserving exact dependency checks. Private
PostgreSQL writing actions now prepare exact source or explicitly reviewed
contracts, inspect checked reviews, reject candidates, establish/edit attributed
knowledge, accept exact supported resource findings, and publish by exact author
decision. Preparation/acceptance creates no approval or canon. Source bytes and
allocated versions survive retries; knowledge establishment creates no objective
assertion, and duration edits preserve acquisition history. Publication and
rejection recover their original receipts after reopen and later canon changes.
These actions use the owning PostgreSQL transaction and current author authority.
Inline research now runs through public tool dispatch without writing rights;
it retains query evidence without proposal state, reservations or approval.
Scoped research resolves only visible selectors and never compiles hidden
candidate definitions. Private author drafts retain immutable expected-version
saves, recover exact retries across reconnect, reject competing edits and keep
an old base edition after canon advances. Draft size and represented-context
checks match SQLite; saving a draft creates no proposal, approval or publication.
The private PostgreSQL library now reads current continuity/world/context views,
latest named pending candidates and immutable approval history. Published writing
leaves the pending list only when its durable publication receipt exists.
Owner-wide library and image routes remain author-only. Image staging uses the
same bounded regular-file reader, decoder and retained original-byte checks;
staging creates no canonical identity. Preview requires an image asset in the
selected pinned edition, and originals/previews survive installation reopen.
Library storage status identifies PostgreSQL and reports actual server/durability
settings and heads without exposing connection credentials.
Private PostgreSQL continuity routes now fork from an exact pinned edition,
compare immutable editions and prepare explicitly selected adoption/tombstone
operations. Fork/name retention is atomic and retries recover the original fork
revision. Comparison omits event-generated assertions and retains the existing
1,000-difference bound; adoption preserves selection order and the 1..100-record
limit. Comparison/preparation grants no approval and changes neither head.
Publishing adoption uses the existing proposal validation, exact author approval
and durable receipt recovery, preserving source and target history. The private
profiles/grants view now reads current installation authority and returns only
profile IDs, author/revoked status and typed grants; contributors cannot read it.
PostgreSQL first-use recovery now verifies every retained body and workflow entry,
import digest provenance, canonical media bytes and initialization receipts before
atomically rebuilding disposable projections. Successful recovery is cached only
after commit. The private health route checks each universe independently with
redacted failures; a failed recovery leaves its prior projection generation intact
and can be retried after repair. Private maintenance retains all author history,
workflow evidence, media, drafts, approvals and publication receipts; collection
removes only reconstructible snapshot caches. PostgreSQL manages physical vacuuming
outside these service transactions. Complete retained-content verification for
transfer additionally checks staged media/source metadata, exact anchor excerpts,
historical world-name reservations and unique historical memberships.
Private PostgreSQL logical export now streams retained rows in bounded server
cursor pages into a fresh trusted SQLite carrier, preserving canonical record
and workflow digests while translating private typed-row pointers. It uses the
existing checksummed relational archive format and its dependency-closed filtered
export/reconstruction. Complete export includes exact source/media bytes, history,
drafts, approvals and receipts; importing into SQLite retains approvals, contexts
and receipts as historical evidence. Existing destinations are never overwritten,
failed export removes unpublished temporary files, and installation authority or
connection credentials are excluded. The internal PostgreSQL installation
transaction now admits verified complete-history restores, canon-only imports
and named clones through the existing trusted archive staging/reconstruction.
Typed bodies are translated without retaining backend row pointers; imported
approvals, contexts and receipts remain historical evidence. History verification,
projection recovery and catalog registration are atomic with fresh schema creation;
failed admission removes the target namespace even when the caller catches the
failure. Private PostgreSQL import previews now retain the exact reviewed archive
in bounded installation-database chunks, surviving service restarts and deletion
of the original input. Acceptance rechecks current author rights, the preview and
archive digests, and identity/name reservations; the admission receipt commits
with the target namespace and catalog entry, allowing exact lost-response retries.
Imported evidence grants no installation permissions. The PostgreSQL control
schema is now version 2; opening rejects older or incomplete layouts without
implicitly migrating them. Private PostgreSQL purge previews bind exact current
heads and retained-history/workflow counts. Purge requires the current name's exact
confirmation and author rights, then atomically removes the universe namespace,
grants, all retained aliases and catalog entry while retaining the purge audit.
Validation jobs retire only after commit. Reviewed import archives and external
copies remain outside this operation, as stated in the preview; forensic erasure
is not promised. Private PostgreSQL universe backup now streams a consistent
retained snapshot into the existing protected typed SQLite package format, with
the package's 8 GiB bound and no installation credentials or archive metadata.
Existing destinations are never overwritten. Restore uses the trusted package
reader, preserves IDs, history, exact source/media bytes and workflow evidence,
keeps restored approvals/contexts/receipts historical, and atomically provisions
and verifies the namespace before catalog admission. Identity/name conflicts,
incompatible sources and failed registration leave the original unchanged.
Explicit PostgreSQL author bootstrap and private enrollment now reuse the
existing protected, create-only local profile credential files. Supply the trusted
`profileRoot` when constructing the native runtime; an absent/unusable root cannot
publish a new hash. Generated secrets are durable before registry enrollment,
PostgreSQL retains only hashes, and enrollment responses expose only the profile
identity. Writers cannot enroll other profiles, and current revocation still
applies after restart. Failed registry transactions retain the credential file
for an uncertain outcome, while unpublished profiles cannot authenticate.
Private PostgreSQL registration accepts an existing generated `ub_unv_…`
namespace. It verifies and rebuilds that namespace in place before atomic catalog
admission, preserving history and active workflow evidence. Identity and retained
name conflicts are rejected; failed admission rolls back recovery and visibility
without dropping the original namespace. SQLite file locators use reviewed import
or restore instead. Private legacy conversion uses the existing canon-only archive
converter, preserves the original source and requires separate reviewed admission;
it never registers its output automatically or overwrites an existing destination.
Native PostgreSQL runtime checks now use a compiled second OS process to verify
that connected writers observe grant withdrawal and revocation without restart,
competing author draft saves retain one winner with an exact version conflict,
and separate universe drafts recover byte-for-byte after process restart. Retrying
the winning save returns the same retained draft without another version.
PostgreSQL validation recovery also checks termination of a compiled preparation
peer after its running marker commits. Resumption retains the exact selection
capture, completes through the native isolate scheduler and preserves the terminal
result after reopening the store, without advancing canon or creating approval.
PostgreSQL scheduled validation now holds a connection-owned advisory guard per
installation/universe/operation across frozen evaluation. Another process reads
live ownership from the database and skips duplicate scheduling; disconnect
releases ownership so the original operation can resume. Completion, cancellation
and failed preparation release the guard without granting publication authority.
The cross-process regression checks live ownership, skipped competing evaluation,
termination/resumption and guard cleanup. No heartbeat or authorization cache is
introduced. See PostgreSQL's [advisory lock semantics](https://www.postgresql.org/docs/16/explicit-locking.html#ADVISORY-LOCKS).
SQLite and PostgreSQL have an author-only durable source
quiescence primitive. It binds one universe and move operation to another
installation identity, suspends ordinary source access across connected service
workers and restart, and retains the source catalog, aliases, grants and universe
data. Exact retries retain one audit event; changed bindings and self-targets are
refused. This metadata lives in SQLite's installation database or PostgreSQL
control schema version 5 and never enters universe exports. Opening older or
incomplete control layouts refuses them unchanged. Explicit SQLite installation
conversion adds the move table to the prior normative layout and retains existing
move bindings and any complete retained move archives; PostgreSQL control
conversion is still required. The trusted SQLite runtime can stage a complete
source archive under its exact move operation. Restart revalidates and reuses
that protected archive without replacing it; failures retain the source guard
and original data. Functional checks cover SQLite and PostgreSQL target review,
restart before admission and exact receipt recovery after admission. The trusted
PostgreSQL runtime commits complete source archives in installation-owned chunks
of at most 256 KiB, then publishes a verified protected transport copy. Restart
reuses those exact chunks; failed file publication retains them, and a failed
stage transaction leaves no partial archive. Missing or changed chunks refuse
recovery without regenerating the original. Checks cover PostgreSQL-to-SQLite
admission, retained revision/draft evidence and independent source/target restart.
The trusted SQLite and PostgreSQL source coordinators retain the exact target
review and its `reviewed`, `admitting` or `admitted` state. They record the
admission attempt before calling the target. Restart retains that binding, and
explicit SQLite installation conversion preserves it for an exact target retry.
The client receives the operation receipt from
the authenticated target; the source accepts only an exact match to its retained
review. Changed reviews and receipts refuse, retries retain one audit
event per transition, and failed source writes preserve the previous state.
The original stays suspended and retained after admission. The private author-only
`stage_move` command takes universe, operation and target-instance IDs, suspends
the source and retains its complete archive. It returns the verified digest,
manifest and byte count without accepting a caller filesystem path or returning
host paths or credentials. Exact retries after restart reuse the retained archive.
Staging failure leaves the source suspended for recovery with the same binding.
The author-only `read_move_chunk` command reads retained archive bytes in chunks
of at most 256 KiB, using that exact universe/operation/target binding and a
zero-based ordinal. It refuses missing chunks, out-of-range ordinals and changed
bindings. Reconnects can request the same ordinal; reads never restage the source.
Clients use the staging byte count to bound reconstruction and verify the complete
archive digest before target import review. Socket and PostgreSQL regressions
cover multiple chunks, exact Unicode/source bytes and reconstruction after restart.
The target's author-only `begin_archive_upload` command binds an upload ID to
the expected archive digest and byte count (up to 8 GiB). Its progress reports
allow reconnects to resume at the next ordinal. `write_archive_chunk` retains
fixed 256 KiB chunks, with the exact remaining length for the final chunk;
identical retries reuse bytes, while changed metadata/bytes and out-of-order
writes refuse. Uploads belong to the current author and survive service restart.
`review_archive_upload` reconstructs the private archive, verifies its expected
digest and prepares the existing restore/clone review without caller server
paths. The upload ID becomes the retained preview ID; identical review retries
preserve the target identity and review digest, and changed names/modes refuse.
Ordinary `accept_import` still requires that exact review digest before admission.
Received upload bytes are not an admitted universe. SQLite explicit installation
conversion preserves partial uploads; ordinary opening refuses older upload-free
layouts unchanged. PostgreSQL control layout version 6 includes durable uploads;
older control layouts require explicit conversion rather than startup repair.
Explicit conversion of older PostgreSQL control layouts remains pending.
The shared client's `prepareMoveTransfer` uses caller-supplied authenticated
source and target connections to check target identity/name conflicts, stage,
stream or resume an upload, and return the target review after recording it at
the source. Retain its source operation and target upload IDs for an
explicit retry after reconnecting. It stops before approval; the target still
requires the existing exact `accept_import` request. Connections need not be
owned by a service coordinator. `admitMoveTransfer` takes the author's exact
`accept_import` approval, checks it against the retained source review, records
the pending attempt, calls the target and records its returned receipt at the
source. Explicit retries recover an unknown outcome with the same approval;
completed retries return the retained receipt. Private author commands
`get_import`, `review_move`, `begin_move_admission` and `record_move_admission`
expose these existing operations through SQLite and PostgreSQL services.
The Dart CLI exposes `prepare-move`, `accept-move`, `moves` and `move-status`.
Preparation authenticates both local installations, checks for universe, name
and retained-alias conflicts before suspending the source, and returns the exact
review without admitting it. Use fresh operation/upload IDs for a new move and
reuse them for recovery. `status` includes the stable `instance_id`; the CLI
checks the selected target against the source's retained binding before approval.

```text
universe --installation SOURCE --profile SOURCE_AUTHOR prepare-move UNIVERSE_ID OPERATION_ID UPLOAD_ID 'Target name' --target-installation TARGET --target-profile TARGET_AUTHOR
universe --installation SOURCE --profile SOURCE_AUTHOR move-status OPERATION_ID
universe --installation SOURCE --profile SOURCE_AUTHOR accept-move OPERATION_ID PREVIEW_ID EXACT_REVIEW_DIGEST --target-installation TARGET --target-profile TARGET_AUTHOR
universe --installation SOURCE --profile SOURCE_AUTHOR moves --limit 20
```

Each command closes its connections without shutting down either engine.
These CLI controls currently use the native local transport; PostgreSQL runtime
selection, remote transport and Flutter transfer controls remain pending. The private
author-only `list_moves` command discovers retained operations in pages of
1–100, with an operation-ID cursor. `get_move` returns the retained state, target
review, exact target retry request and completed receipt without host-path or
credential fields. These reads do not resume or alter the source. Recovery
metadata remains readable if a package file or archive chunks are unavailable;
staging still verifies original file identity and archive integrity. The SQLite
socket regression covers authenticated staging, restart retries, recovery discovery
and contributor denial.
PostgreSQL stores the exact
authored target name as bytes and binds its review to the retained source archive
digest and record count. Functional checks cover source/target restart and audit
failure before target admission and after target completion, with one retained
audit event per successful transition. Source retirement
and the Flutter move flow remain pending.
The shared native service now includes an authenticated loopback HTTP adapter.
`LocalSqliteEngineServer` starts it alongside its compatibility Unix socket and
exposes the dynamically assigned loopback address through `httpEndpoint`.
`LoopbackEngineServer.postgres` adapts an explicitly opened PostgreSQL runtime;
the caller retains runtime/store ownership and closes them after the listener.
HTTP activity participates in the installed engine's existing idle shutdown.

The private HTTP contract uses `POST /engine/hello` with an empty body to return
the existing welcome, and `POST /engine/call` with an existing `EngineCall` JSON
body to return its correlated `EngineReply`. Each request carries
`Authorization: UB <base64 of the UTF-8 EngineHello JSON>` and authenticates the
current profile. Credentials never enter URLs. The adapter binds only IPv4
loopback, checks the exact host and any supplied origin, bounds input/output and
concurrent requests, and marks responses `no-store`. Failed transport does not
replay a command; callers recover uncertain outcomes through existing receipts.
An authorized HTTP shutdown drains the listener and closes the installed engine.
`LoopbackEngineClient` performs the authenticated hello, validates the existing
welcome, correlates sequential typed calls, bounds responses and requires an
explicit new connection after transport uncertainty. It refuses non-loopback
addresses, credentials/query data in endpoints and HTTP redirects.
`discover` reads the service's protected `engine-http.json`, which contains only
the loopback endpoint and protocol version. Startup replaces this ephemeral file
under the installation lock; shutdown removes it. It is not authority or a backup.
The Dart author CLI and local MCP adapter send application calls through HTTP.
Their startup discovers and authenticates HTTP directly, rechecks under the
existing installation bootstrap lock, and starts the absolute installed helper
only when discovery is missing or refused. Invalid discovery, unavailable
credentials and failed authentication do not launch a helper. Readiness retries
never replay application calls. The server also supports an HTTP-only mode
(`compatibilitySocket: false`); the compatibility socket remains enabled by
default during migration. Browser sessions, complete Flutter authoring, Windows ownership
integration and hosted HTTPS remain pending. This is not a browser cookie
session or a public hosted endpoint.

Coordinated backend cutover and hosted server backup operation remain pending.
Socket/launcher integration, cross-process worker qualification and
backend parity checks are pending. Coordinated transfer and live
verified-TLS checks also remain pending. The Dart engine can now select
PostgreSQL for local HTTP service startup and explicit installation/device setup.
This does not complete backend parity, hosted operation or platform delivery.
Run `test/postgres_foundation_test.dart`, `test/postgres_relational_test.dart`,
`test/postgres_journal_test.dart`, `test/postgres_workflow_test.dart` and
`test/postgres_authority_test.dart`, `test/postgres_candidate_test.dart` and
`test/postgres_definition_test.dart`, `test/postgres_initialization_test.dart` and
`test/postgres_projection_test.dart` and `test/postgres_kernel_test.dart` from
`packages/ub_store` with
`UB_TEST_POSTGRES_PORT` set to a disposable loopback `ub_disposable` database. Without
that selection the live database cases are explicitly skipped. Service authority cases are in
`test/postgres_installation_authority_test.dart`; installation, authoring and
engine cases are in `test/postgres_open_test.dart`, `test/postgres_validation_test.dart`
and `test/postgres_runtime_test.dart` under `packages/ub_service` with
the same disposable database selection. These checks use
local fixture setup privileges and cleans its generated schemas and role.
Full-schema operations need enough server object-lock capacity: on the disposable
PostgreSQL 16.15 server with 100 connections, the default
`max_locks_per_transaction=64` exhausted shared locks during schema removal;
`256` passed provisioning, provisioning rollback and removal. This is a tested
local setting, not a sizing guarantee for concurrent hosted installations. Size
that server-start setting for the intended operations and concurrency; see
[PostgreSQL lock configuration](https://www.postgresql.org/docs/16/runtime-config-locks.html).
Compiled engine startup and shutdown have focused coverage on macOS with disposable
data. Native clients can now use `LocalEngineClient.ensureRunning` with an absolute
installed `universe-engine` helper, or select the sibling through `siblingEngine`.
Healthy connections are reused before helper lookup. Missing/refused endpoints use
the shared bootstrap lock, recheck readiness and launch once with a ten-second
deadline. Authentication and unsafe endpoint failures never trigger launch. The
helper runs detached so its client can exit independently; early child exit is
reported through the readiness deadline rather than an exit code. Sibling lookup
retains manifest/signature checks for macOS app bundles. Focused compiled-client
checks cover concurrent launches, reuse, revoked profiles and stale-socket recovery
on macOS. Other platform packages remain pending. These
commands do not authorize converting or replacing a live author installation.

The SQLite codec uses the existing fixed-column relational schema and keeps
absent/null states, exact numeric strings and ordered child rows. It does not
provide reviewed publication yet. The internal journal adds immutable revision
history, exact receipt lookup, tombstones and pinned branches within a
caller-owned transaction. Reference admission and per-record reference, world,
narrative, scalar and search projections are also implemented internally.
The internal SQLite kernel now coordinates candidate admission, definition and
initialization indexes, head advancement, projections and durable commit receipts
in one transaction. Exact retries precede current-head/workflow comparisons.
Preview runs that same write path and deliberately rolls it back before returning
the candidate; failed gates and interrupted checkpoints leave canon intact.
Changed images now require retained original bytes and decoded metadata agreement
in commit and preview. Atomic byte staging retains the import receipt separately
from canonical publication. Public reviewed publication and owning-service
integration remain pending.
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
Typed knowledge records retain attitudes, sensory access, interpretation, actual
receipt and remembered allegations independently. Fictional secrecy remains
separate from application rights. Completeness retains its existing externally
tagged record encoding independently from comparison encoding. Typed appearance
and image records preserve authored visual references; SQLite recovery applies
the existing image metadata and retained-content checks through the typed model.
Knowledge evaluation and acquisition authorization still need their service ports.
The typed expression tree has all 15 branches and six operand forms, separate
wire/comparison encodings, bounded structural analysis and explicit quantifier
scopes. Claim roles preserve ordered wire pairs and comparison objects;
comparators and quantifiers retain their existing distinct spellings. Analysis
enforces depth 32 and 1,000 expression nodes. It preserves the existing Rust
domain summary's zero `nodes` field; the rules compiler's separate operand-inclusive
budget is now implemented in `ub_rules`; full factual evaluation still needs its port. Goals and commitments retain
expressions as declarations without executing steps or inventing consequences.
Typed rule records keep semantic kind separate from commit policy, explicit
knowledge/channel/cardinality declarations, scoped creative boundaries, version-pinned
exceptions and attributed issue decisions. The shared rules package currently
contains the structural compiler, preserving existing node/depth metrics and
sorted reference extraction; descriptive rules remain non-executable. Compilation
does not establish truth, verify evaluator capabilities, or confer publication
rights. Full factual rule evaluation and boundary/exception admission still need their ports.
The rules package also preserves the evaluator's four evidence outcomes and
independent support/refutation derivations. Conjunction retains both source
sets, composition sorts and deduplicates exact record-version identities, and
absence does not imply refutation. This evidence logic is shared by native and
browser targets; factual evaluation and Real World obligations remain pending.
Authored-clock validity and temporal relations now preserve half-open intervals,
bounded uncertainty and exact signed 128-bit values. Unknown boundaries and
independent calendars remain unresolved. Strict relative-order cycle checks
use exact positive assertions partitioned by calendar, scope, validity and
predicate, retaining the existing 10,000-node work bound. These checks do not
advance story clocks. Event-relative queries use separate event checks.
Definition ancestry and type applicability now resolve from one supplied factual
snapshot. Missing, ambiguous, cyclic, nonexecutable or cross-universe ancestry
remains unresolved; each ancestor retains its own world applicability. Type
hints establish rule relevance without filtering expression operands, and
fact admission checks the full authored scope, including explicit universe-wide
permission. Reference and indexed paths retain their existing lookup semantics.
Effective instance attributes, initialization and the full evaluator remain pending.
Exact scalar and uncertain-range comparison now preserves the existing signed
128-bit parse and cross-product limits without floating-point rounding. Text
uses UTF-8 ordering; quantities require identical unit identities. Range
endpoints retain their authored inclusivity, while overlap, invalid bounds,
overflow and unsupported types remain unresolved. These comparison primitives
do not perform unit conversion or execute a rule by themselves.
Candidate claim lookup now groups property/relation definitions, matching
propositions, all assertions, completeness declarations and rule exceptions
without interpreting their truth or applicability. Exact subject/context
references and existing record order remain intact. This index captures one
supplied candidate and must be rebuilt for changed snapshots; it carries no
permission authority and does not admit exceptions or completeness by itself.
The bounded expression executor now evaluates literals, negation/connectives,
exact comparisons, temporal relations, membership, cardinality and finite
quantifiers with the existing shared 10,000-step work budget. Incomplete
collections preserve witnesses/counterexamples without assuming completeness;
sets deduplicate wire-identical members and nested bindings remain local.
Rule execution preserves executable/world-applicability gates and reports
evidence outcome separately from coverage. Factual claims
and opposing-evidence execution remain unported and explicitly unsupported;
action-precondition admission and public publication workflows are still pending.
Event-relative validity now resolves before/after boundaries only for occurred
events with exact named-calendar coordinates and matching universe references.
Deterministic `events-v1` expansion preserves hashed effect identities and exact
provenance, ends superseded generated values and refuses simultaneous
noncommuting effects. Recompilation detects missing, duplicate or forged generated
assertions. Existing event/effect/precondition and expansion-work limits remain
in force; expansion does not execute action preconditions or publish canon.
Attitude expressions now evaluate exact holder/proposition/attitude bindings in
the selected base snapshot and represented context, retaining source versions
and authored/event-relative time validity. Belief, suspicion, rejection, memory
and knowledge remain distinct from objective truth. Missing attitudes do not
refute; unresolved timing leaves coverage incomplete. Timeless queries accept
only unspecified attitude validity. Knowledge acquisition/policy admission and
disclosure permissions still require the remaining service workflows.
Possession-derived item powers now retain their rule, owning holder and complete
positive evidence chain. Competing or uncertain custody, applicable refutation
and recipient suspension prevent a grant; explicit transfer and expiry remove
prior-holder access without changing authored records. World/context/realm and
event-time constraints remain explicit, and timeless queries grant no powers.
Derivation retains the existing one-million-step work bound. These transient
facts are not persisted as independent assertions; canonical publication remains
pending. Factual claim evaluation now includes exact direct and shared inherited
attributes, candidate changes, role and existence queries, possession-derived
powers and authored objective completeness. Support and refutation remain
independent with their source versions; unresolved applicability, timing,
classification or precision leaves coverage incomplete. Indexing preserves the
same dependencies and cannot reuse an old candidate after changes. Missing facts
do not imply refutation. Opposing-evidence scans now compare resolved meanings,
pairwise values, scope and validity within one active revision. They retain exact
dependency versions and separate definite conflicts from unresolved overlap or
provenance gaps; absent archived versions never resolve to active replacements.
The no-opposing-evidence expression shares the existing evaluation work budget,
and incomplete scans cannot establish a completed check. Service admission and
publication workflows remain pending.
The Dart service now checks a rule at every relevant exact evidence boundary and
each world in its requested footprint, preserving half-open intervals and point
boundaries. Exact-version exceptions require an accepted scoped decision and
cannot widen the rule's validity or jurisdiction; a waiver retains the original
finding. Unsupported semantics/capabilities and unresolved partitions cannot be
waived into acceptance. This candidate checker does not grant publication rights;
the remaining authoring workflows must bind its results to exact review inputs.
Explicit instance initialization now compiles an approved initial-value assertion
into separate frozen instance facts. The source assertion/proposition must remain
unchanged at the review base, and an exact occurred start must establish the
requested interval and every applicable world. Conflicting or unresolved ancestor
candidates prevent compilation. Generated facts retain the exact source, start
version and revision; classification and application lifecycle do not initialize
state. These changes still require the remaining reviewed publication workflow.
Authoring input preparation now expands definition/instance introductions, named
attributes and classification refinements into the existing canonical operations.
Named attributes reuse an exact compatible property, including definitions in the
same batch regardless of input order; conflicting or ambiguous definitions require
an explicit revision. Submitted uncertainty and evidence remain intact, and event
or initialization provenance cannot be manufactured through a named attribute.
This preparation feeds canonical compilation; admission and reviewed publication
remain pending. The canonical compiler freezes fresh versions for supported
creations, corrections and adoption, checks explicit local references and expected
base versions, and retains the existing correction restrictions. Classification
refinements use the candidate definition graph, including same-batch revisions,
adoptions and removals. Explicit initialization and event effects compile last.
Privately allocated immutable source versions remain an internal service input.
Proposal scope now includes both old and new world assignments and worlds reached
through the existing typed dependency traversal. Unassigned changes remain shared,
and removals require protected-write authority. Entity, predicate and continuity
boundaries check the complete old/new changes. Scoped visibility hides private
source records and closes over hidden or missing dependencies, including cycles.
Prose that resembles an identity does not grant access. These helpers still need
the remaining workflow integration with current grants and exact approval.
Event compilation now freezes derived assertions into the exact changes for
review. Revisions and withdrawals replace or remove their effects and recompute
affected intervals; unchanged effects retain their versions. Generated assertions
cannot be edited directly or overwrite an existing record. A surviving instance
initialization prevents removal of its occurred start. This preparation does not
publish changes or grant approval rights.
Typed events preserve occurrence modes, authored participants and ordered effects.
Action consequences validate exact decimal bounds, slot uniqueness and lifetimes;
an absent historical contract remains distinct from an explicitly empty contract,
and an explicit null contract is rejected. Represented contexts retain authored
Gregorian or fictional clock data. Explicit chronology arithmetic now builds
the authored starting calendar, preserves the first interaction, and distinguishes
forward elapsed time from deliberate time travel. Gregorian inputs require an
explicit offset and whole seconds; month offsets use pinned time and reject a
nonexistent target day. Fictional month offsets require a declared month length
and retain exact signed 128-bit coordinates. Decoding and arithmetic never read
the system clock. Clock changes now compile into exact review changes; reviewed
publication remains pending.
Storing these declarations does not execute effects, advance clocks or promote
a report to objective fact. Mechanical consequence realization now uses authored
mandatory slots, exact owner references, pre-event conditions and explicit direct
resource balances. Conditions and resource results must agree across event worlds;
optional consequences require author choice. Checked coefficient/scale arithmetic
preserves exact values and enforces resource bounds and declared lifetimes. This
function produces proposed effects without writing or approving them. Submitted
consequence validation now checks exact assignments, mandatory slots, full event
scope and lifetime, per-world conditions and explicit resource transitions.
Dependent resource uses require distinct times on the same named clock; existing
contract-bearing actions cannot discard their contract. Historical undeclared
events remain explicit coverage exclusions. Workflow integration remains pending.
Candidate action checks now require new or revised events to name a declared
action and each mandatory role to identify exactly one owning entity. Occurred
events must establish every required attribute before the event in every declared
world, using the candidate's definitions and evidence. Missing, conflicting or
unresolved evidence does not establish capability; an event cannot grant its own
pre-event capability. Changed evidence also revalidates unchanged action events.
Historical actionless events remain readable. These checks still require the
remaining proposal validation/publication integration.
Candidate communication chronology now reassesses declared channel policies
against every message, including unchanged messages when a policy changes.
Authored delay bounds are inclusive exact signed 128-bit clock ticks. Missing
actual recipients or receipt times, non-exact or different clocks, and uncovered
channels remain unresolved; delivery and clock conversion are not inferred.
This lane stays inactive without authored channel policies.
Candidate knowledge checks now distinguish author-established acquisition from
justified communication receipt. Justified knowledge requires an actual holder
recipient, explicit interpretation, supported transmission timing and unopposed
truth in its acquisition context, world and exact time. An omitted world never
selects a convenient world. Missing evidence remains unresolved; belief, memory
and receipt alone do not establish knowledge. Policy and evidence corrections
reassess unchanged knowledge facts. These checks still require integration with
proposal validation/publication and its author authority checks.
Explicit knowledge-boundary checks now report knowing claims that overlap an
authored prohibition, including author-established knowledge. Missing attitudes
do not certify absence; unresolved world or temporal overlap remains unsupported.
Boundaries require a protected wrapper, finite exact period and resolved typed
targets. Typed citation-link checks separately require source evidence and
passage citations to reference anchor records, regardless of a writer's verified
flag. The candidate structural validator now composes these typed rule and
citation checks with chronology and event expansion verification, declaration
value shapes, context nesting, typed fact targets, appearances and bounded image
metadata. Passing structure does not establish conflict resolution, permissions
or author approval. Proposal validation/publication integration remains pending.
Immutable import verification now compares complete source/image payloads with
retained staging receipts, verifies original UTF-8 digests, byte lengths and
decoding declarations, and checks exact citation excerpts at UTF-8 byte boundaries.
Anchors retain their pinned historical source version when a newer head exists;
structural-path anchors remain explicitly unsupported. Image byte reconstruction
requires every bounded chunk, canonical standard Base64, exact chunk lengths and
the complete content digest. These portable checks work with retained SQLite
workflow entries after reopen; full workflow wiring remains pending.
Image admission and previews now decode PNG, JPEG and WebP with the existing
10 MiB input, 8192-pixel edge and 32-megapixel limits, plus a 128 MiB decoded
output budget. That budget does not promise a total process heap cap. Original
digests bind exact encoded bytes; metadata is checked against decoded dimensions
and format. Animated files use their first frame/canvas and JPEG EXIF orientation
does not change encoded dimensions. Disposable JPEG previews use quality 75,
edges 768/512/256 and a 512 KiB output limit. Native file selection and service
import/preview authorization still require integration.
The Dart definition registry now verifies incoming payload digests, isolates
definition universes, retains active versions and rejects duplicate family names.
Registry admission checks typed references, parent consistency and cycles,
property units/dimensions/inverses, relation roles, unit scales and bases, calendar
conversion targets, structured definition recursion and exact pack dependencies.
Packs remain limited to the existing declared capability allowlist. The registry
now participates in complete-candidate evaluation; durable workflow integration
remains pending.
Creative boundary checks now follow transitive record references, exact predicate
subjects and declared classifications through both candidate and historical
records. Assertions and event effects retain their own context, world, realm and
period; proposition edits use their accompanying assertion periods. Exceptions
must cover every affected exact cell and preserve the original finding. Unknown
timing, unsupported scope and exhausted work remain incomplete. Author reservation
requires actual author origin; this check still needs full workflow integration.
Candidate scalar comparisons now retain original shared witnesses when checking
known descendants, separate initial values from ongoing facts and account for
exact numeric equality, definition jurisdiction, worlds, realms and temporal
overlap. Unresolved scopes and exhausted comparison budgets remain explicit gaps.
Candidate definition applicability rechecks unchanged assertions after definition
changes. Objective collection completeness constrains only exact supported entity
members in the declared scope; observer-known sets do not close reality. These
checks still require proposal validation/publication integration.
Opposing-evidence diagnostics now bind original assertion/proposition chains,
their exact dependency versions, evaluation frame, candidate digest, evaluator,
policy and exception versions to fingerprints matching the Rust service. Definite
opposition and partial provenance remain distinct; unresolved comparisons do not
select a truth winner. This diagnostic adapter still needs validation/publication
integration.
Event prerequisite assessment now checks every occurred event in its pre-event
frame, with the first effect context taking precedence over action and proposal
contexts. Complete support is required; conflicting or missing evidence retains
its original sources and numbered repair message. Final finding binding fills
references from candidate versions and preserves exact Rust fingerprints or
existing authored fingerprints. These stages still need full workflow integration.
Complete-candidate evaluation now composes registry and structural admission,
action requirements and consequences, event prerequisites, typed knowledge,
communication and cardinality policies, resource accounting, creative boundaries,
ordinary rules, scalar conflicts, definition applicability and collection
completeness. It checks unchanged records as well as proposed changes, preserves
blocking versus advisory policies and binds findings and opposing diagnostics to
the pinned frame, candidate digest and evaluator. New issue decisions require the
installation author and actual author origin; author-established knowledge cannot
be manufactured by ordinary approval. Cancellation propagates without returning
an execution. Snapshot preview, immutable source/import verification, validation
storage, exact approval and publication still require the service workflow.
Exact validation bindings now capture assessment selection/state, submitted
scope, head, latest proposal key and installation authority. Completed reports
bind the full execution result; unfinished and legacy reports cannot manufacture
a publication binding. Head, proposal, assessment and authority changes make the
capture stale, while publication re-resolves and compares the exact report.
Authority sequences retain signed 64-bit precision on native and web targets.
The existing typed Checked storage family retains these reports/captures across
SQLite reopen and compares selection/proposal keys atomically before append.
Owning installation locks and the complete approval/publication workflow remain
pending; decoding retained evidence does not authenticate it.
Frozen proposal state now preserves the existing typed StoredProposal envelope,
compiled changes, owner, author origin and full write footprint. Create/revise
preparation compiles against the selected base and uses the acting profile's
origin; submit/withdraw create a new version while preserving the original
changes and origin. Exact represented frames are required for these transitions,
and named-world focus cannot narrow a shared or cross-world footprint. Proposal
version keys retain twenty-digit ordering; immutable versions survive SQLite
reopen and competing updates can be rejected by an atomic latest-key comparison.
Portable reservation checks reject identities owned by canon or another proposal,
except for exact historical adoption. Immutable adoption compares the complete
stored source version. Reservation entries retain their original owner after
withdrawal; SQLite persists them across reopen and rolls back competing appends.
Preparation alone does not admit a proposal: these checks must run inside the
owning workflow, with kernel preview and atomic proposal/operation/receipt writes.
Proposal candidate checks now assemble the exact frozen commit input, verify
immutable adoptions, run kernel preview, verify retained sources and evaluate
the candidate against its pinned base. Changed scene disclosures require the
exact edition and complete dependencies to match that edition's bound canon;
unbound or segmented editions cannot establish reader disclosures. Restricted
checks return restricted coverage without reading complete canon or sources.
SQLite integration rejects stale heads and blocking rules without publishing
facts or approvals. Queued operation lifecycle, approval and publication routes
remain owning-workflow work.
External source-assessment admission now builds the complete frozen candidate
from its pinned base, verifies accounting/frame bindings, distinguishes proposed,
unchanged and explicit historical links, and requires semantic prerequisites to
remain active. Source editions/passages and dependency anchors must match their
declared byte ranges; original staging receipts and exact UTF-8 bytes are checked.
Retained assessments revalidate after SQLite reopen without replacing externally
declared unresolved conclusions. Staleness compares the latest frozen candidate
or advanced continuity head, distinguishing source, edition and dependency drift;
only exact historical evidence is exempt from dependency drift.
Selection resolution now preserves exact historical views separately from the
current selected state, hides missing selected bodies from partial viewers, and
distinguishes stale, missing and byte-verified evidence after SQLite reopen.
Assessment access now checks continuity limits before reads, complete-candidate
entity/predicate boundaries, and scoped visibility including historical
dependencies. Resolver and SQLite-retention tests use these checks. The owner
must still supply current installation grants within its consistent authority
context. The SQLite installation owner now serializes asynchronous authority
sections, queues coordinated grant/revocation work, and refuses outside mutations
or closure while a section is held. The service must route authority-sensitive
capture, persistence and grant changes through those sections; durable
queued operation routes still require integration.
The native authority API now resolves authenticated current scope, permissions,
limits, approval author and audit sequence within those sections. Its validation
digest preserves the existing canonical authority tuple. An owned SQLite package
test captures against these live values and rejects an identical regrant by its
changed sequence before retaining any validation.
Validation capture now resolves selected assessments into exact submitted source/inventory
bindings, preserves stale/unavailable states as record input, and captures current
head, proposal key and supplied authority digest/sequence. Unassessed proposals
retain ordinary write-boundary admission. The owner must hold authority and
universe coordination while capturing and revalidating before atomic retention.
The native SQLite validation workflow now loads exact retained proposals under
current installation authority, admits their write boundaries, resolves source
assessment captures, and retains checked results atomically. Revalidation and
selection/proposal comparisons share the SQLite write transaction with the
append. Authority changes, stale heads and competing selections reject retention;
verification or append failures roll back every entry. This path stores checked
results only; it does not approve or publish canonical facts.
The same native owner now attaches byte-verified external assessments and changes
their selections under current authority and a SQLite write transaction. The
immutable body, generation and principal-bound idempotency receipt are retained
together. Fresh changes require the submitted latest proposal and pinned head;
exact authorized retries return their original selection, including after clear,
reselection and package reopen. Selecting retained evidence rechecks its bindings
and bytes; clearing evidence retains its original history.
Durable operation state now retains typed commit inputs, ownership, footprint
and validation capture. The native owner resolves terminal/running markers,
current cancellation and durable commit receipts under current authority without
rewriting immutable history. Running validation becomes interrupted when the
live scheduler reports no active job; committed receipts remain successful after
a lost response even when a cancellation marker exists. Public status now
preserves completed retained reports and renders captured pending checks without
a final binding. Failed/cancelled/interrupted fallback reports mark assessment
unavailable and use record input; legacy reports cannot manufacture completion.
Scoped validation responses avoid complete evidence reads and hide failure and
proposal contents. These responses also work after owned package reopen.
Native queued validation now retains the principal-bound request and operation
atomically with its exact capture. Authorized retries preserve operation/run
identity and resolve retained terminal state; changed requests or mismatched
resolved frames are refused. Scoped queues retain no complete assessment capture
and return restricted validation; unscoped source-assessed queues bind the exact
selected inventory. Preparation rechecks current authority and exact captures,
previews the candidate without canonical writes, verifies adopted versions and
source bytes, then retains the running state. The portable evaluator receives
frozen snapshots and supports cancellation probes; scoped preparation supplies
no complete snapshots and produces restricted evidence. Completion revalidates
captured bindings in the transaction retaining both the finished report and
terminal state. A stale capture or worker failure retains failure with the
original pending validation, and cancellation or an existing terminal state
suppresses late results. Restricted completion remains inadmissible. The native
cancellation route admits the retained owner and current world scope, atomically
retains its marker and principal-bound request receipt, then signals the live
worker. Authorized retries survive reopen; changed requests are refused and
succeeded/failed results remain unchanged. A native scheduler now admits two
concurrent validations, deduplicates active universe/operation pairs and reports
busy capacity with the existing same-key retry instruction. Evaluation runs in
isolates receiving frozen inputs only; the owning service prepares and retains
results. Cancellation terminates evaluation without undoing facts. Shutdown
drains preparation and abandons evaluation without completed evidence, allowing
the retained running state to resolve as interrupted. Engine dispatch, general
database-worker isolation, admission wiring and transport integration
remain pending.
Native runtime admission now preserves 32 total connections, at most 24 agent
connections, eight connections/requests per principal, and separate work pools
of eight agent requests and four author requests. Failed actions release their
work capacity; closing a connection releases its slot without cancelling an
admitted mutation. Admission uses authenticated identity but never replaces
current permission checks. Engine transport wiring remains pending.
The native private approval route now admits only the current author and binds
their decision to the exact retained Checked digest and evaluator. It requires
the latest submitted, unwithdrawn proposal at the pinned head, an admissible
validation and an unchanged completed assessment report. Report resolution and
approval retention share the write transaction and current authority section;
authorized identical retries survive reopen. Reviewed publication now admits
current write permissions and exact approval, or explicitly bounded delegated
commit authority. It privately rechecks the complete candidate and compares the
approved validation and current assessment report before retaining a committing
operation and publishing canon with expected workflow comparisons and a durable
receipt. Same-key retries recover that receipt after reopen; changed evidence
and cancelled operations cannot publish. Human transport/UI and engine dispatch
wiring remain pending.
The native proposal route now creates, revises, submits and withdraws immutable
proposal versions under current authority. Creation/revision checks record
reservations and structural kernel preview before admission; failed preview
retains no proposal receipt or reservation. Proposal history, operation/request
receipts and new reservations append atomically. Latest-version checks reject
stale transitions; exact retries preserve their original result after newer
versions or reopen. The native functional journey now covers creation through
submission, isolated validation, author approval and receipt-backed publication.
Context-backed native proposal dispatch now admits the retained context's owner,
scope hash, universe and expiry before retry or mutation, then resolves visible
world selectors/aliases and exact world guards within the same authority section
as retention. Context scope changes and expiry cannot be bypassed by a retained
request receipt. Native context opening now pins a head or exact revision,
admits visible represented contexts, temporal queries/calendars and event frames,
and retains owner/scope/expiry with the opened frame. Character and narrator
perspectives require matching contexts; reader perspectives require a positioned
scene and disclosures/dependencies matching the edition's pinned canon. Named
contexts and scenes require one exact accessible match. Queued validation and
assessment attachment/selection now resolve retained contexts within their
mutation authority section and require the proposal's exact base frame. Expiry
and scope admission precede retry lookup; source checks and historical assessment
receipts retain their existing semantics. The native authoring journey now uses
an opened context through proposal submission and queued validation. Remaining
read/check routes and public engine dispatch remain pending. Synchronous native
proposal validation now admits the retained author-perspective context, checks
the exact proposal frame and retains completed evidence with current source and
selection bindings. Its result can feed exact author approval and publication;
the check itself creates no queued operation and does not publish canon. Scoped
checks retain only restricted evidence. Both context-backed validation modes
reject non-author perspectives before loading the proposal. Native inline checks
now compile and preview an ephemeral candidate against the retained frame and
retain query evidence without a proposal, reservation or final publication
binding. These research checks do not require write permission. A named world
must contain the full write footprint. Scoped inline checks resolve only visible
world selectors and return restricted output before compilation, preventing
compiler errors from disclosing hidden definitions; they retain no result.
Native record retrieval now admits the retained context and intersects current
world permissions with its author, character, narrator or reader perspective.
Payload, summary and evidence field groups read the pinned revision; research
follows evidence about a subject without reversing context/predicate edges into
unrelated facts. Named-world reads include visible required dependencies and
appearance attachments. History follows exact fork baselines and tombstones,
survives restart and retains the 100-change limit per record. Only unrestricted
author-perspective reads disclose history; scoped/perspective views report
restricted coverage. Deleted records require an admitted history request.
Native context briefs now prioritize every visible rule, the requested focus,
effective object evidence and transitive research dependencies. Purpose text
does not remove constraints. Pages respect the byte budget and retain opaque
cursors bound to exact arguments, the pinned frame, principal and current scope.
Pagination survives package restart. Delivery completion is distinct from
evidence coverage: paginated, scoped or perspective-limited briefs remain
partial, as do briefs with missing dependencies or hidden rules/active appearance
references. A budget that cannot fit the next mandatory record fails explicitly.
Native search now intersects literal-phrase index matches with the retained
revision, current world permissions and fictional perspective. Name/alias
substring and exact-record-ID fallbacks stay within that visibility; typed
filters and selected/shared/unassigned/dependency categories are preserved.
Author-perspective research labels describe visible item powers, messages and
knowledge without inferring facts or disclosing unavailable dependencies.
Search pages use exact bound cursors and survive package restart; later canon
and hidden records do not enter a pinned result. Invalid limits and queries
exceeding the existing 1 KiB search bound fail explicitly.
Native state retrieval now selects explicit propositions, assertions,
completeness and epistemic evidence at the retained frame, with predicate and
named-world filters. Unknown validity remains visible and overall state coverage
remains partial. Visible occurred events support distinct before/after reads;
plans and inaccessible events cannot supply an event frame. Effective objects
and explicit possession powers use the shared evaluator without persisting
derived facts. Unrestricted author-perspective reads include exact initialization
receipts from the pinned revision and fork ancestry, including after restart;
scoped and fictional-perspective reads disclose restricted history coverage.
Native proposal retrieval now pages exact retained operations and compiled
changes under current ownership, write permissions and boundary limits, without
altering the proposal digest or publishing canon. Assessment views resolve
permission-checked selected or explicitly requested historical evidence before
counts, offsets or cursor creation. Small envelopes return whole; larger ones
use canonical UTF-8 fragments of at most 32 KiB with byte-aligned boundaries.
Assessment cursors pin the selection generation and exact envelope reference;
selection changes invalidate an existing stream. Proposal pagination survives
package restart and cannot bypass subsequently revoked write rights.
Native operation lookup supports exact operation IDs and principal-owned retry
keys. Validation findings page in groups of 100, with cursors bound to the full
execution digest and resolved operation identity. Pages preserve retained review
bindings and survive restart; a changed execution invalidates an old cursor.
Scoped validation returns restricted output without finding counts or cursors.
Lookup uses the existing durable receipt and live-worker recovery rules, so a
committed publication remains successful after a lost response and an inactive
running validation is reported as interrupted.
Native impact requests now use retained author-perspective contexts and current
permissions. Inline requests return the conservative accessible universe closure;
proposal requests include exact unpublished changes and require the same base
frame. A named world resolves focus without narrowing that conservative closure.
Hidden or missing changed records are denied before result sizing; hidden closure
members produce restricted coverage, and an insufficient byte budget fails
explicitly. Impact reads do not publish changes or retain validation results.
Native discovery now supports summary, capabilities, worlds and definitions.
Summary lists current continuity heads, retained names and accessible represented
contexts, omitting continuities with no accessible context. World and definition
views use retained frames and intersect current permissions with the fictional
perspective; named-world definition selection retains applicable shared policy.
Pinned views and typed continuity names survive package restart. Capability
descriptions distinguish the remaining native fork/adoption, reviewed restoration
and image staging/retrieval gaps from the implemented factual evaluator paths.
Native plain factual research now resolves requested names from the pinned,
permission/perspective-filtered snapshot and projects the existing effective state.
Ambiguous and missing identities remain explicit, with no object introduction.
Instance facts, inherited attributes and initial candidates stay separate;
conflicts, unsupported plain values and unresolved applicability remain visible.
The read includes explicit occurred events and authored clock information without
promoting plans to occurrences or inventing time. Numeric presentation preserves
exact tokens on native and web, and research creates no proposal or validation.
Native plain contract research now projects visible pinned actions, effects,
properties, units, policies, relationship declarations, powers and exhaustive
sets, alongside communications, attributed attitudes and narrative disclosures.
Action-name selection includes authored labels. Conditional/optional effects and
exact deltas remain declarations; they do not execute on read. Private edit
handles, narrative metadata and knowledge boundaries follow author-perspective
rules, with current scope filtering applied first. Scene depiction and reader
disclosure stay distinct, and ordinary research creates no approval or canon.
Candidate relation cardinality now enforces authored cross-instance maxima at
overlapping exact times, partitioned by grouping key, world and realm. Repeated
evidence for one participant counts once; half-open interval ends stay exclusive.
Unknown time, scope, precision or opposing evidence leaves the count unresolved.
These maxima are separate from local role multiplicity and do not infer a
minimum or completeness. Proposal validation/publication integration remains
pending.
Candidate resource accounting now checks the full authored stock timeline for
opted-in single numeric properties. A first observation establishes a baseline;
later changes need a linked delta consequence, a coherent correction, or separate
exact acceptance of the unexplained arrival. Acceptance binds claim contents,
preceding evidence and world, preserving the existing fingerprint recipe across
version regeneration. It does not invent an event or replace author approval.
Effective object assembly now projects inherited attributes, instance facts and
initial value candidates separately from a pinned, permission-filtered snapshot.
It retains unresolved ancestry endpoints, scoped/time-qualified evidence and
every conflicting witness. Requirements show relevance without establishing
capability; resource acceptance keeps unexplained arrivals visible. Initialization
history hydration, service query authorization and proposal validation/publication
integration remain pending.
Typed operation contracts preserve bare nested record DTOs separately from tagged stored
payloads, snake-case operation fields and exact expected versions. Decoding an
adoption request preserves its supplied digest; compilation verifies it and the
target version before allocating a fresh version. Current adoption rights remain
a separate service check. An operation's coarse authority
classification never grants permission. Remaining workflow/request DTOs, service operation
admission and execution still need their ports; completing record and operation
types does not complete the conversion.
Frames preserve timeless queries, exact revision pins, event entry/exit sides,
reader-scene selection and personal sequences. Character/narrator perspectives
use externally tagged wire values and separate comparison values; timeless frame
time is a tagged wire object and a comparison string. World focus remains
per-request rather than hidden frame state. Proposal versions retain exact u64
integers on VM and web, and authored operations remain separate from compiled
changes. A typed proposal or receipt is data, not proof of validation or
publication. Typed validation reports preserve execution coverage independently
from submitted-input scope, source-assessment state and the nullable final
binding digest. Restricted reports have only their fixed restricted reporting
axes. Exact source bindings require explicit nullable edition/passage fields;
assessment generations, byte counts and ranges retain exact u64 values on VM
and web. Opposing diagnostics preserve both evidence chains, policy/exception
versions, intersection uncertainty and unresolved reasons. The execution-result
digest uses the complete unpaged execution core's owning wire encoding and
excludes the assessment wrapper. Typed assessment bodies retain assessor/tool
attribution, source/material accounting declarations, exact references, narrative
positions, semantic mappings and unresolved dispositions. Nullable assessment
selection and review fields are explicitly required; fragments remain distinct
from partial body declarations. Final binding validation checks exact proposal,
selection identity/generation and declared inventory digest, refusing query and
inappropriate source-assessed scopes. Its prefixed digest preserves the existing
owning field serialization. An unavailable assessment can remain attached to a
record-only validation; unavailability is distinct from absence. The strict
assessment import validates bounded input, UTC timestamps, declared exact
references, active versus historical versions, reciprocal material links,
uncertainty dispositions and conclusions before hashing. Trusted retained-byte
verification checks exact size/SHA, strict UTF-8 and source/item/exclusion range
boundaries. Envelope verification and frozen proposal/frame binding preserve
the existing digest preimages. Structural DTO decoding remains separate from
these checks. The read-request subset now covers all describe modes, context
opening, search, record retrieval, effective state and context briefs. It
preserves required universe selectors, omitted-versus-null optional fields,
world name/ID guards, paired event/side queries and request limits. Closed typed
protocol errors retain their historical wire codes and protocol-failure
classification, including the `DOMAIN` wire / `DOMAIN_ERROR` public-code
distinction. Shared request contracts also cover inline/proposal/queued
validation, proposal creation/revision/submission/withdrawal, assessment
attachment/selection, proposal review, impact queries, exact commit and operation
lookup/cancellation. Selection requires an explicit nullable assessment;
assessment review references require the assessment view. Proposal versions and
selection generations retain exact u64 values on web. Strict request decoding
bounds raw frames and rejects duplicate keys/invalid UTF-8; structural decoding
remains separate from semantic validation and service admission. Commit input
binds a proposal, expected base revision, validation run and retry key; it has no
inline approval flag. These contracts do not execute queries or grant access.
Read response contracts now include the common typed envelope, delivery paging,
description/capabilities and visible continuity/context choices, opened contexts,
search hits and their four scope categories, record/summary/evidence/history pages,
and context briefs with required-dependency manifests. Request IDs preserve exact
u64 values on web. Delivery completeness remains independent of evidence and
history coverage; a complete page does not upgrade restricted evidence. Record
pages retain supplied historical digests and tombstones without certifying them,
and all collections are immutable snapshots. Typed Rust fixtures preserve the
existing nullable fields, omitted empty optional lists and closed result shapes.
Effective-state response contracts now preserve visible ancestry, authored/shared
evidence, initial-value candidates, initialization receipts, contextual names,
behavioral requirements, rules, dependencies and conflicts. Nullable applicability
keeps unknown separate from true and false. Initialization history coverage stays
separate from object coverage, and unavailable contextual-name projections do not
establish absence. State pages retain exact authored chronology coordinates,
unresolved assertions, qualified propositions and explicit completeness records;
decoding never advances time or selects a candidate as fact. Initialization
receipts are shared domain DTOs used by both the store and response contracts,
preserving admission and source revisions independently. State evaluation remains
pending; these types only carry its eventual results.
Typed response dispatch now covers all 16 public tools and exposes both the IPC
wrapper and the envelope body used by MCP. It preserves the historical `ReadFacts`
IPC tag while accepting `universe_read_facts` for public tool/body dispatch.
Proposal outcomes and review views preserve their untagged semantic/assessment
variants; assessment selection does not modify or authorize the frozen proposal.
Response decoding bounds frames and rejects invalid UTF-8, duplicate keys and
unknown wrapper fields. Generic research JSON retains exact numeric tokens too.
Owning Rust fixtures cover all tool variants and both assessment alternatives.
IPC contracts now cover Hello/HelloReply, request/cancel messages and typed
success/error replies. Request correlation IDs and 64-bit native handshake limits
remain exact on web. The shared strict decoder enforces the existing 1 MiB frame
limit before decoding UTF-8/JSON, rejects duplicate keys and retains raw numeric
tokens. Exported protocol defaults remain version 3 and 16 in-flight requests.
These DTOs do not negotiate compatibility, authenticate an instance, schedule work
or cancel a durable operation. Service and transport execution still need their
ports.
Private installation contracts now include the credential/profile handshake and
instance welcome, grant scopes/limits, structured draft contents/versions and
restore/clone modes. Credential diagnostic formatting is redacted; explicit wire
serialization retains the exact credential for the private handshake. Grant
collections preserve unspecified versus explicitly empty boundaries, and
delegated commit/shared-write flags default to false. Drafts retain pinned
revision/context, authored operations and optional exact proposal references.
The shared local IPC codec now reads/writes four-byte big-endian length-prefixed
frames, checks the 1 MiB declared size before payload allocation, handles split
and coalesced packets, preserves backpressure and rejects truncated final frames.
Strict DTO decoding remains separate. The private engine welcome advertises eight
in-flight requests, matching the maintained engine/client protocol; the general
fixture protocol retains its separate sixteen-request default.
Native Unix socket helpers now check OS peer credentials against the effective
user before a profile handshake, validate private owned single-link socket paths,
protect newly bound endpoints and remove only owned stale sockets. Links, regular
files, permissive endpoints and TCP substitutions are refused. The native bridge
uses each platform's declared credential structure rather than Dart byte offsets;
functional peer/endpoint checks currently cover macOS. Unsupported platforms fail
closed. The native `ub_client` local adapter now checks endpoint ownership and OS
peer identity before transmitting a profile credential, authenticates through
the strict welcome contract, and correlates sequential requests. Typed service
errors leave the connection usable; interrupted, malformed, mismatched or timed-out
replies require an explicit reconnect and never replay the request. Connection and
handshake deadlines are five seconds; request deadlines are fifteen seconds.
The `ub_service` local server now holds installation ownership before removing a
stale endpoint, validates peer identity before profile authentication, dispatches
through the native runtime, rejects duplicate request IDs and carries exact IDs
into public envelopes. It bounds all connections at 32, preserves runtime author
capacity, expires incomplete handshakes after five seconds and request input after
sixty seconds, and stops after fifteen minutes without connected clients. Shutdown
closes transports, drains admitted work and releases the installation lock. Focused
Unix-socket client/server checks currently cover macOS, including restart,
revocation, creation, correlation and author shutdown. Remote/web adapters and
qualification on other platforms remain pending.
Expiry timestamps, draft versions and engine limits preserve exact unsigned
values on web. These contracts do not authenticate profiles, grant permissions,
save drafts or implement encrypted settings; private command dispatch and those
service behaviors remain pending.
Private author-writing action contracts now cover exact inspection, source and
contract preparation, knowledge correction/establishment, rejection, publication
and finding acceptance. Publication retains the exact proposal version/digest,
validation run and retry key; finding acceptance keeps its authored fingerprint,
scope and rationale. Knowledge corrections preserve explicit clear flags and
remain separate from new knowledge declarations. All eight variants retain their
existing closed wire shapes and cannot be decoded as public model requests.
Decoding does not stage source, approve changes, accept a finding or publish;
private command routing and service enforcement remain pending.
All 33 private engine command contracts now have closed typed variants, including
catalog/profile controls, exact grant and proposal review, draft save/load,
continuity comparison/adoption, source/image staging, recovery/transfer and
maintenance. Engine calls and success/error replies retain exact correlation IDs
and generic result numbers; private handshake decoders use the shared strict
frame boundary too. Paths remain authored strings and purge/import confirmation
fields are not synthesized. Universe creation requires an explicit Gregorian or
fictional start, preserving timestamp/tick text and optional authored month size.
These contracts do not perform filesystem work, build clocks, authenticate an
author, enforce grants or publish changes; their service handlers remain pending.
The new `ub_service` package starts with the shared backend-settings resolver.
`UB_USE_POSTGRES` accepts only trimmed, case-normalized true/false; supplied
environment values override saved values, with SQLite as the default. SQLite
selection never reads an endpoint or unlocks saved credentials. An explicitly
empty environment endpoint cannot fall back to a saved secret, and missing or
unavailable selected secrets fail with redacted errors. The resolver preserves
the exact endpoint scalar and never persists credentials or opens/transfers a
database. Selected PostgreSQL endpoints now require an explicit single TCP host
and database, with `postgres`/`postgresql` schemes, percent-decoded credentials
and IPv6 support. Query overrides support `user`/`username`, `password`,
`dbname`/`database` and `port`; duplicate/conflicting options fail. TLS defaults
to `verify-full`. Explicit unverified `require`/`disable` modes need a separate
loopback-development selection and literal loopback host. Opportunistic and
CA-only modes are rejected rather than approximated. Certificate paths,
`application_name` and positive `connect_timeout` values remain typed options;
unsupported/incompatible options and malformed URIs fail with redacted errors.
Certificate files are not read during parsing. The service also provides endpoint
scalar encryption with pinned `cryptography` 2.9.0 AES-256-GCM, random 256-bit
installation keys and fresh 96-bit nonces. Authenticated associated data binds
the installation identity, endpoint field purpose, format version and key
reference. Immutable ciphertext/nonce/tag columns contain neither plaintext nor
key material. Explicit key import/export is for the native OS credential-store
adapter; keys must not be saved beside these columns. Unlocking rejects altered
columns, another installation or a wrong key with redacted errors, and saving
rejects Unicode that cannot round-trip exactly. `ub_store/local_settings.dart`
now provides a separate protected native settings database with a stable
installation identity, backend flag and fixed encrypted endpoint columns.
Explicit saves atomically replace these fields, preserve identity, and reject
PostgreSQL without encrypted credentials. The writer lock lasts through close;
unsupported schemas, unsafe files and competing owners are refused. It accepts
only encrypted endpoint values, never plaintext endpoints or installation keys.
This storage component does not unlock keys or test/drain/restart an engine.
`ub_service/native_credentials.dart` now provides macOS Keychain installation-key
creation, exact-reference retrieval and cleanup for headless Dart callers.
Blocking OS calls run in worker isolates. The fixed service namespace and random
account references avoid overwriting existing keys; missing keys never regenerate
on read, and diagnostics expose no key/reference values. The current macOS bridge
uses the file-based Keychain for unsigned local development, with synchronization
disabled. It serializes calls while temporarily disabling legacy Keychain
authentication UI, then restores the prior process setting. Those interaction
APIs are deprecated by Apple; signed application/helper access still requires
packaging qualification. Disposable native tests cover settings restart, key
isolation, cleanup, and a compiled CLI reading the same key across processes.
Other OS adapters explicitly refuse saved-key operations until ported; the
environment configuration path remains independent of them.
`ub_service/local_configuration.dart` now connects protected saved settings and
OS key retrieval to the same backend resolver used for environment inputs.
Saved backend selection reads only nonsecret columns. An explicit environment
backend selection takes precedence without reading saved settings; a supplied
endpoint overrides the saved secret without unlocking or persisting it. Selected
saved PostgreSQL credentials use their exact key reference and installation
identity; missing/unavailable keys or failed decryption stop resolution with
redacted errors and preserve settings. The loader never regenerates keys,
creates settings, transfers data or starts a backend. Empty/invalid environment
values keep the shared resolver's existing failure behavior.
The Dart engine uses this resolver for backend startup and explicit setup.
`UB_USE_POSTGRES=true` selects PostgreSQL and `UB_POSTGRES_ENDPOINT` supplies its
connection URI. `--initialize` creates installation authority and an owner in an
empty configured database, or enrolls the owner in existing empty authority;
`--device-profile` retains that authenticated owner for device reconnection.
Neither command replaces enrolled profiles or synthesizes missing credentials.
Ordinary startup only opens existing authority. Failures never open SQLite as a
fallback. PostgreSQL uses the local authenticated HTTP adapter and protected
endpoint discovery; its installation directory retains local profiles/settings,
with no SQLite installation canon. Verified TLS remains the default. The explicit
`--allow-loopback-postgres-development` engine option permits unverified TLS only
for loopback development endpoints. Native ownership has been checked on macOS;
the other platform ports still need their required checks.
`ub_store/profile_credentials.dart` now ports the existing create-only
`profiles/{profile}.sqlite` credential format. Exact UTF-8 secrets remain in
separate private installation files, with file and directory synchronization
after the committed database closes. Reads require one matching profile row,
strict UTF-8 and private ownership; missing files never synthesize a credential.
Replacement writes, unsafe links and permissive paths are refused with redacted
errors. The normative credential DDL is embedded by the existing schema build
tool. These files are separate from encrypted PostgreSQL settings and universe
canon. `ub_store/installation.dart` now provides the separate protected SQLite
installation registry using the normative installation DDL, with current profile
rows and transactional enrollment/revocation audit entries. New installations
persist a stable instance identity and retain it across restart; opening a legacy
registry without that identity refuses it unchanged pending controlled cutover.
`ub_service/local_profiles.dart` supplies author bootstrap, author-controlled profile
enrollment, exact UTF-8 SHA-256 credential authentication and revocation. Author
operations recheck current registry authority, and authenticated principals bind
to their installation identity. Profile listings expose no hash or secret.
Unknown, wrong and revoked credentials receive the same denial. Failed audit
appends roll back authority mutations. Private engine handshake authentication
checks the exact protocol and 128-byte UTF-8 client-name bound before checking
current credentials. It does not reserve transport capacity or grant lasting
access; request transport integration remains pending. Author catalog operations now register an
existing package only after owned startup recovery and derive its universe ID
from that package. Registration stores its canonical path and exact device/inode
identity while retaining the package writer lock through catalog publication.
Name matching uses the shared pinned Unicode normalization; renames preserve
old aliases for the original universe. Alias/file collisions roll back catalog
and audit changes, and resolution refuses replaced files, symlinks and hard
links. Catalog listing retains the original 1,000-entry bound and name order.
Author-controlled grant replacement and withdrawal now persist ordered scope
boundaries, exact unsigned expiry values and transactional authority audit
entries. Agent catalog and alias access require a current, unexpired universe
grant. Base write checks enforce proposal/edit, protected and world permissions;
withdrawal, expiry and revocation invalidate cached principals. Authority
sequences distinguish withdrawal and identical regrant. Exact proposal footprint,
approval and delegated-publication checks remain pending, as do
transport handshake integration and existing-installation cutover; these profile
components do not start the Dart engine. The native Dart runtime now provides
author-only whole-package purge preview and execution. Purge checks the current
impact digest and exact `PURGE <current catalog name>` confirmation, retires
validation jobs and atomically removes catalog access, aliases and grants before
deleting the owned package files. Startup resumes durable pending deletion and
refuses a changed file identity. Installation identities and audit history remain;
external backups and exports are untouched, and forensic erasure is not promised.
Ordinary writer types now preserve JSON scalar fact values, named objects and
explicit unit amounts, fact lifetimes, object/definition deltas, claims and
historical corrections/endings/withdrawals. Research requests for exact object
names and contract discovery are available as typed contracts. Writer JSON uses
`CanonicalValue.parseWireJson` to retain decimals, arbitrary-precision numbers
and exponent spelling as numeric inputs; the historical `parseJson` digest
bridge remains unchanged. Quoted numeric text remains text. Fact values retain
the existing untagged object-before-quantity precedence and ignored extra object
members; surrounding DTOs remain closed. Defaults preserve unspecified
scope/time/lifetime and false introduction intent. Shared definition attributes
and instance initial values remain separate. These are declarations, with no
inferred current time, truth, stock initialization or publication. Typed writing
inputs also preserve events and explicit knowledge requirements, communication
recipients/receipt/understanding, the five epistemic attitudes, knowledge
boundaries and knowledge/channel policies. Historical event, message, attitude,
interpretation and policy corrections distinguish omitted fields from explicit
empty replacements and explicit clear flags. Author knowledge declarations
remain a distinct input for private author controls; decoding grants no
permission or communication-based acquisition. Recipient and role collections
are immutable copies, and missing ticks/dates never select current time.
The complete `universe_check_changes` request now has typed contracts for all 42
change collections, completing request decoding for all 16 public tools. These
include worlds and story contexts, works/editions/scenes and explicit disclosures,
properties/units/actions/item powers, initialization provenance, finite constraints,
exhaustive sets, aliases and relationship contracts/occurrences/corrections. Reader
order remains independent of story time and disclosure. Local role multiplicity
remains separate from cross-occurrence maxima, and selected initialization handles
do not imply approval. Omitted correction collections retain authored values;
explicit empty collections remain replacements. Exact numeric JSON and immutable
participant collections work on VM and web. Historical Rust serialization fixtures
cover the remaining writing families and a fully populated delta. These are input
contracts; attachment admission,
evaluator execution and exact approval enforcement still need their ports. Byte verification remains
distinct from factual support; it does not establish truth or authenticate an
assessor.
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
