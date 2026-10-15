# Universe Builder: Dart conversion and dual-database delivery plan

Date: October 11, 2026.

Status: implementation baseline approved by Vanna's conversion goal, subject to the explicitly unresolved decisions and subsequent instructions. Implementation and required platform checks with disposable data are authorized. Live-data conversion, hosting expenditure, production deployment and release publication require separate authorization. Unrelated paused work remains paused.

## 1. Intended outcome

Convert all project-owned runtime application logic to Dart, deliver a Flutter application for macOS, Windows, Linux, iOS, Android and web, and run the same factual service against either SQLite or PostgreSQL.

SQLite remains the default for an isolated installation on a user's machine. PostgreSQL can serve a local power user, a self-hosted installation, or our paid hosting. Database selection does not determine whether an instance is local or hosted.

Preserve the product's essential role: maintain attributed, scoped facts and continuity; evaluate supported declarations and rules; publish only authorized changes. The external writer interprets prose, researches sources and asks the author for clarification. UB does not become an internal writing model, a manuscript editor, a universal truth oracle, or a background simulator.

Real World is an explicit evidence and constraint policy for universes/worlds needing factual adherence. Vanna selected evidence-backed checks with strict treatment of unresolved facts, with research and source submission performed by the external writer.

The complete application includes the headless engine, author UI, local and remote clients, MCP adapters, CLI, database adapters, recovery/conversion paths, schema/contract generation, and maintained build/package tooling. Flutter, SQLite, database drivers and minimal operating-system integration will still include native dependencies; the objective is Dart ownership of application behavior.

## 2. Baseline and source precedence

Source was inspected in this checkout on October 11. No application tests, installed author packages, credentials or running service were opened for this plan. Approximately 77,000 lines of Rust exist under crates, including tests. The typed schema has 886 CREATE TABLE declarations and its catalog contains 1,620 model entries. These are scope indicators, not migration progress or a schedule estimate.

Use these owners rather than reconstructing behavior from old plans:

| Area | Owning sources |
| --- | --- |
| Product boundary and approved replacement model | [factual realignment](factual-universe-realignment-plan.md), [author workflow](ai-authoring-workflow.md) |
| Values, identities, chronology and canonical bytes | [domain](../crates/universe-domain/src/lib.rs), [canonical encoding](../crates/universe-domain/src/canonical.rs), [records](../crates/universe-domain/src/records.rs), [scope](../crates/universe-domain/src/scope.rs) |
| Factual evaluation and service orchestration | [rules](../crates/universe-rules/src/lib.rs), [service](../crates/universe-service/src/lib.rs), [workflow](../crates/universe-service/src/workflow.rs) |
| Author commands and public MCP contracts | [installation commands](../crates/universe-protocol/src/installation.rs), [tool requests](../crates/universe-protocol/src/request.rs), contracts/ |
| Typed relational persistence | [schema assembly](../crates/universe-store/src/schema.rs), [codec](../crates/universe-store/src/relational.rs), [normative mapping](decisions/relational-storage/README.md) |
| Atomic publication and historical reads | [kernel](../crates/universe-store/src/kernel.rs), [workflow storage](../crates/universe-store/src/workflow_storage.rs) |
| Installation identity and current grants | [registry](../crates/universe-service/src/registry.rs), [local client](../crates/universe-client/src/installation.rs) |
| Transfer and conversion | [archives](../crates/universe-store/src/archive.rs), [row transfer](../crates/universe-store/src/transfer.rs), [operator procedure](operator-conversion-procedure.md) |
| Current UX proposal | [UX redesign](ux-redesign-plan.md), existing universe-ui editors and workflows |
| Build and distribution | xtask/, scripts/, packaging/, .github/workflows/, [release runbook](release-runbook.md) |

The current contracts contain 16 tool definitions; default MCP discovery advertises the ordinary subset. Port the actual discovery filtering and request variants, including private author operations. Tool totals in historical prose are not a specification.

Current source limits differ from some older ADR wording: kernel membership is capped at 500,000 records, stored versions at 1,000,000 and replay chains at 10,000; package size is 8 GiB, while logical archives separately cap at 512 MiB and 2,000,000 rows. These include propositions/evidence, not just visible entities. Verify all limits at the owning code before implementation; none establishes demonstrated practical scale.

Keep the existing untracked UX proposal/assets intact. During implementation, reread current sources because other work may advance this checkout.

## 3. Product requirements by author workflow

Use one factual model with useful starting workflows. Campaign, novel and autobiography choices configure vocabulary, views and optional policy packs; they do not create separate engines.

Keep purpose and reality policy as independent choices. A campaign can use realistic historical foundations; a novel can be fantasy or Real World; an autobiography can preserve subjective accounts within a strict factual policy. Existing projects retain their authored policies until the author explicitly adopts another one.

| Author | Ordinary work | Continuity protections |
| --- | --- | --- |
| DnD/campaign author or GM | Prepare sessions, record what occurred, track NPCs, places, inventory, abilities and player knowledge | Edition/homebrew scope, exact resource changes, possession versus location, session order, plans versus occurrences, GM secrets and player-visible accounts |
| Fictional novelist | Track people, relationships, scenes, world rules and series continuity | Stable identities and aliases, appearance over time, perspective knowledge, chronological versus narrative order, alternate continuities, correction impact |
| Autobiographer | Reconcile memories, documents, dates, people and versions of an account | Approximate dates, firsthand recollection versus corroborated fact, attributed disagreement, source provenance, pseudonyms/private identities and responsible disclosure |
| Historical/realistic-fiction author | Combine invented people/events with sourced real-world setting | Place and era applicability, supported technology/institutions, sourced constraints, explicit fictional departures and scope-specific exceptions |

Campaign requirements:

- Session notes and proposed outcomes can be staged as sources; an outcome becomes objective state only through the existing occurred-event and reviewed publication paths.
- Ruleset edition, supplements and homebrew changes are explicit, pinned dependencies. No automatic latest-edition update changes an existing campaign.
- Resources remain instance-owned. Rest/recharge is an authored supported occurrence, not a wall-clock task or an implicit refill on reopening a session.
- Player knowledge and GM truth are separate. A knowledge fact is also distinct from an application's permission to disclose a record.
- Contributors may propose through their granted scope; campaign labels never grant approval rights. Preserve the current one approval owner per installation unless multiple owners are separately designed.
- This conversion does not promise dice automation, initiative tracking, character-sheet completeness, or a virtual tabletop. Optional packs use permitted content; do not bundle third-party game text merely to provide a familiar preset.

Novel requirements:

- A character renamed, disguised or reclassified remains the same identity. Uncertain identity matches require clarification.
- Scene order and in-world time remain independent. A flashback does not move the authored current clock.
- Dossiers show definition attributes, instance facts, current state and source evidence separately.
- Relationships carry their roles and validity. Co-occurrence does not invent a relationship or cause.
- Series works may span worlds. An alternate continuity pins its parent revision; later parent edits do not flow into it automatically.
- A retcon shows affected facts/rules/scenes and creates new history. It never erases the prior account or silently fixes unrelated works.

Autobiography requirements:

- “I remember it happened in summer” remains approximate firsthand testimony. A document dated later does not silently replace the memory.
- Store conflicting accounts with attribution and precise source bindings; distinguish a disputed proposition from a disagreement about its interpretation.
- Personal motives and feelings can be authored first-person accounts. Another person's intent must not be promoted to objective fact from speculation.
- Contextual names/pseudonyms retain identity. Private source attachments and identifying references must respect grants throughout search, graphs, timelines, exports and previews.
- Narration reconstructed later must not be displayed as a verbatim contemporaneous quotation without source support.
- A correction preserves the original statement and its provenance. A memoir's chosen narrative wording does not manufacture historical certainty.

Across all workflows, allow a name and minimal identity to start. Missing facts become obligations only when they matter to the proposed use or an explicitly selected policy. Avoid an exhaustive questionnaire at creation.

## 4. Real World policy design

### 4.1 Meaning and scope

Real World means: apply the declared evidence requirements and supported reality constraints to objective claims in the selected scope, and refuse affected publication when a required obligation remains unresolved.

It is not a claim that all facts have been independently verified. The UI must explain which constraints and source obligations were checked and which claims were interpreted by a person or external model.

Offer Fictional and Real World as understandable creation choices. For historical fiction, offer Real World foundations with explicitly authored departures through existing scoped rules/exceptions or a distinct continuity. Do not silently downgrade a strict real-world rule because the project is fiction.

The universe-level choice establishes a reviewed default policy. World-level selections compile into explicit policy applicability. The author sees the effective policy and its inherited origin. A world override changes applicability explicitly; it is not “nearest setting wins” over overlapping contradictory rules. Adding a world requires an explicit choice to use the universe policy or another reviewed policy.

The initial creation choice publishes the `real_world:default` evidence rule
with universe-wide applicability and an exact pin to an empty
`real_world.sources` category. Its review-method list is empty; scoped policies
may require interpretation review later. The author explicitly selects qualifying
source membership and reviews the resulting policy revision before those sources
can satisfy new claims. The creation action establishes this default together
with the authored context and calendar. Fictional creation adds no evidence
policy. Creation input recovery retains the choice; older unfinished input
defaults to its previous fictional behavior without replaying a request.

World omission in a request continues to select no individual world. It must not apply a convenient default world's policy. Represented beliefs, dialogue, reports, dreams and counterfactuals retain their current context/occurrence semantics even inside a Real World universe.

### 4.2 Evidence flow

1. The external writer identifies a material factual claim and its needed date/place/context.
2. It researches and submits source content/metadata with the relevant excerpt or anchor, source version, attribution and proposed interpretation.
3. UB verifies retained bytes, excerpt boundaries, IDs, references, source availability and the supported structured constraints.
4. Human or external-model judgments about what a source supports remain attributed assessments.
5. Validation reports source obligations, opposing evidence, unresolved interpretation and unsupported constraints separately.
6. The author reviews the exact claim, evidence and findings. Publication follows the existing approval/commit path.

An accessible URL alone is not retained evidence. A digest proves the identity of retained content, not that its claims are true. A matching excerpt proves an anchor, not entailment. Citation verification flags supplied by an agent are not trusted as service verification.

Firsthand testimony is legitimate source material. A memoir need not have a public external source for every recollection. The chosen policy defines the evidence needed for a private recollection versus an objective historical claim; uncertainty must remain explicit.

Research stays external. UB does not crawl the internet, fetch URLs supplied by sources, call an internal model, or add source-ranking heuristics in this conversion.

### 4.3 Required behavior

| Situation | Real World behavior |
| --- | --- |
| Applicable deterministic check contradicts the proposed objective claim | Block affected publication; identify the rule, facts, assumptions and repair |
| Required evidence is missing, inaccessible, stale for the declared use, or unresolved | Block affected publication; retain the draft and proposed claim |
| Required check uses unsupported semantics | Report unsupported and block the affected objective claim; no implied pass |
| Facts are independently plausible but conflict with established scoped canon | Surface the canon conflict and require an authored correction/resolution |
| A character reports something false or a person recalls something uncertain | Permit an accurately attributed account when its own evidence requirements are met; do not assert its content as objective truth |
| A submitted source disagrees with another source | Preserve both, with attributed resolution or explicit uncertainty; no newest-source precedence |
| A source/rule is updated later | New reviewed revision; flag impacted dependencies without rewriting earlier evidence or verdicts |
| A person breaks a law | Record the possible occurrence and normative violation; legal prohibition is not physical impossibility |
| An unknown unrelated fact exists elsewhere | Do not block an unrelated operation unless its declared dependency/policy makes that fact material |

Avoid a universal green “reality verified” badge. Useful labels include “Supported checks completed,” “Evidence interpretation attributed to …,” “Required evidence missing,” and “Reality check unsupported.”

### 4.4 Initial capability boundary

Reuse existing exact chronology, units, typed values, declared operational/physical rules, scoped knowledge, cardinality, source anchors and assessment bindings. Examples include age/date arithmetic from explicit dates, event ordering, possession/resource consistency, and whether an authored availability interval contains an event date.

Technology introduction, travel feasibility, historical institutions and real-world jurisdiction facts require sourced declarations. No universal travel-speed model, guessed GPS route, inferred physics, automatically synchronized calendars, or current-law database is implied. Gregorian offsets remain explicit; named historical timezones require a separately specified mapping and evidence instead of guessed DST.

Era, jurisdiction, observation time, source publication time and retrieval time are distinct. A present-day source may describe a historical fact; it is not automatically invalid or applicable. “Freshness” must be an explicit policy obligation for a time-sensitive fact, not a blanket age cutoff.

### 4.5 Domain changes needed

Real World is additional product behavior, not existing runtime parity. Its specification must precede its implementation.

- Prefer ordinary DomainPack, Rule, Source/SourceVersion/Anchor, Assertion and existing assessment records for vocabulary, reality constraints and evidence.
- Policy selection must resolve to published, exact dependencies. A display-only World setting_type label or a local preference cannot be its authority.
- Add the smallest typed extension needed for required evidence/interpretation obligations and their effect on admission. Existing byte-bound assessments do not presently establish universal truth or a generic source-requirement policy.
- Specify qualifying evidence categories, the exact claim/scope binding, accepted review method, unresolved/opposing evidence handling, policy revision and coverage before adding that extension.
- Keep strict evidence checks limited to claims covered by the selected policy. Ordinary fictional factual management retains its existing optional-assessment path.
- An author may change a policy through reviewed authority. Approval alone cannot waive an unresolved strict obligation. In Real World, a fictional exception must be explicitly labeled as a departure and cannot produce an “adheres to reality” result.
- Revise the single normative contracts/schema in place. Existing historical bodies/digests remain valid under their preserved recipes; never reinterpret them as having previously passed Real World checks.

The proposed evidence-requirement extension needs these typed bindings:

| Binding | Required meaning |
| --- | --- |
| Policy identity | Exact Rule/DomainPack factual version and its declared applicability; policy changes invalidate current dependent eligibility |
| Claim target | Exact objective assertion/event/effect or proposal candidate binding; no unscoped free-text verdict |
| Evaluation frame | Universe, continuity, base/candidate revision, world applicability, represented context, realm where relevant and authored time |
| Accepted basis | Explicit permitted source-anchor, recorded firsthand testimony or supported derivation categories for that claim purpose |
| Source binding | Exact SourceVersion/Anchor/content digest and retained range; multiple sources retain individual attribution and opposing evidence |
| Interpretation | Exact attributed human/external-model assessment where the policy requires interpretation review; an author's acceptance binds to that exact declaration |
| Dependency validity | Explicit temporal/jurisdiction/freshness obligations and relevant record/source revisions, not a guessed reliability score |
| Result axes | Content integrity, attributed interpretation, deterministic constraint outcome, coverage/restriction and publication eligibility remain separate |
| Unresolved obligation | Specific missing/contradictory/unsupported requirement and its repair; no pass through a generic approval or blanket waiver |

Use these as requirements for the smallest extension to existing typed rules/assessment bindings, not a second evidence ledger or independent auditor. A source-backed fact can satisfy its scoped obligation without a compulsory assessment of an entire manuscript.

Examples to specify as functional tests: conflicting birth dates; a date range too broad to establish age; a technology used before its sourced availability; a witness knowing information before a supported acquisition; a criminal act that remains physically possible; an approximate private memory; a changed source interpretation; a fictional world exception that does not weaken another world's policy.

### 4.6 Evidence review decision and initial typed policy contract

Evidence review is policy-dependent, as directed by Vanna. There is no mandatory
review of every Real World claim. An empty accepted-review-method list means
that the scoped policy does not require interpretation review; a nonempty list
requires an exact attributed assessment using one of those methods. Required
unresolved facts still block affected publication. Attributed private recollections
can qualify without public corroboration or a public URL.

The shared Flutter rule editor now exposes source-category selection and optional
accepted review methods for new rules and published revisions, alongside the
existing scope controls. It retains exact published category versions and saves
unfinished input through native/browser form recovery. Changes use the existing
review/publication path.
Changes now presents readable policy/claim names from the checked candidate and
base revision, with requirement scope, accepted review methods and source-category
selections. Missing display names do not alter the original findings or their
coverage. Published rule details show the same requirement summary.

Represent a required evidence policy on the existing published Rule record with
an optional `requiredEvidence` field. Its `sourceCategories` are exact VersionRef
bindings to published DomainPack records grouping qualifying SourceVersion record
IDs. Authors name and populate those categories; membership is an authored choice,
not a service reliability ranking. The existing rule applicability, subject types,
target predicates and validity delimit its use. The policy and category versions
are dependencies of the exact candidate and validation result.

`reviewMethods` contains zero or more of `human_review` and
`external_model_review`. Existing source anchors bind retained content and ranges;
existing attributed source assessments bind interpretations to exact candidate
versions. A URL, a caller-supplied verification flag, a digest, or ordinary author
approval cannot by itself discharge a required evidence or interpretation duty.
Category/policy changes require new reviewed versions and fresh dependent checks.
Publishing a category revision does not move a policy's exact pin. The policy
continues using its selected published membership until an authored policy
revision selects the new category version. Checks resolve that pinned category
through the existing immutable history under the admitted universe authority.
No historical payload receives a default policy or a retroactive pass.

Events use an optional `basis` with the existing EvidenceBasis type. Absence is
preserved in historical bytes. A required event source must be a qualifying
SourceAnchorBasis; an author decision alone does not satisfy the obligation.
The declared action supplies represented context and realm, while the event
supplies worlds, time and participants. A historical event without a declared
action has unresolved scope for this check. Only occurred events assert an
occurrence; plans, reports and hypotheticals keep their existing distinctions.
Policies without target predicates cover these occurrences as well as assertions.
Predicate-scoped policies cover matching effect assertions. Generated effects
may use their verified `establishedBy` event to obtain the source, but required
interpretation review must bind the exact effect claim, not merely its event.
Occurrence review uses the existing ActionSemanticMapping with exact action,
participants and effect proposition versions and an exact candidate event link.

The Dart service now applies this contract to objective assertions, occurred
events and their verified effects, through synchronous validation, queued evaluation and
publication rechecks in SQLite and PostgreSQL. Source/category revisions and
opposing assertions reopen affected dependencies. Selected interpretation review
must match the exact claim and passage and cover the required worlds and time;
unrelated unresolved material does not block it. An ordinary rule expression or
author approval cannot discharge these duties.

Policies may cover assertions and occurrences together or select named predicates
for assertions/effects. Arbitrary derivation chains remain explicitly unsupported.
The Rust engine still rejects all required-evidence declarations. Delivery still
requires world-level policy overrides and the
remaining platform workflows specified above.

### 4.7 Explicit scoped fictional departures

The existing Exception record now has optional `fictionalDeparture` (false/omitted
for ordinary historical exceptions). The author marks a departure in the exception
editor and selects the exact published rule, authorizing acceptance decision,
context, worlds and time. It uses the normal Changes and publication workflow.

A marked departure can permit publication under a required-evidence policy only
where that valid exception covers the affected claim's required scope. It does
not turn missing sources or interpretation review into factual support. Findings
retain their original outcome and coverage, identify the fictional departure in
their message, and include its exact version and author-decision version as
dependencies. Unsupported checks remain blocking. Ordinary approvals or unmarked
exceptions do not bypass evidence obligations.

Physical rules with the existing `block_unless_exception` policy keep their
exception behavior; marked departures are identified while the refuted factual
outcome remains visible. An `always_block` expression is still enforced. A narrow
departure cannot relax another world's obligation or an uncovered time/context.
Changing/removing an exception or its acceptance decision rechecks its dependent
claims. The Rust engine explicitly rejects marked departures; admission is
implemented by the shared Dart evaluator in SQLite/PostgreSQL.

## 5. Target application architecture

Use a Dart Pub workspace with one dependency resolution and lockfile. [Dart workspaces](https://dart.dev/tools/pub/workspaces) supports this without an additional monorepo framework.

~~~text
packages/
  ub_domain/       identities, records, values, time, canonical encoding
  ub_rules/        bounded factual evaluation
  ub_contracts/    public tool and private author DTOs, schemas, errors
  ub_store/        storage contract, SQLite and PostgreSQL implementations
  ub_service/      authorization, workflows, queries, jobs, recovery
  ub_client/       typed local/HTTPS connections and operation recovery
apps/
  ub_app/          Flutter desktop/mobile/web
  ub_engine/       headless Dart service
  ub_mcp/          stdio and Streamable HTTP adapters
  ub_cli/          author/operator commands
tool/             maintained Dart build, schema and packaging commands
~~~

Use subdirectories instead of more packages unless an actual dependency boundary requires one. Domain/rules/contracts do not import Flutter, a database driver or operating-system APIs. Presentation cannot access storage directly.

Native Dart can produce standalone executable programs, while Flutter supplies platform app runners. Pin the toolchain actually qualified in the first slice, rather than choosing versions from a documentation label. [Dart executable compilation](https://dart.dev/tools/dart-compile), [Flutter platforms](https://docs.flutter.dev/reference/supported-platforms).

### Runtime topology

| Installation | How the service runs | Canon storage |
| --- | --- | --- |
| Local desktop | Independent Dart engine started on demand; GUI/CLI/MCP connect to it | SQLite by default, or PostgreSQL configured for that engine |
| Local mobile | Same service library embedded in the app with isolated worker execution | App-private SQLite |
| Local power user with PostgreSQL | Desktop service points at their PostgreSQL database | PostgreSQL; normal local UX and MCP continue |
| Self-hosted/paid host | Headless Dart engine behind HTTPS | SQLite or PostgreSQL selected by service configuration; PostgreSQL recommended for hosted operation |
| Native hosted client | Flutter application connects to the service API | Server owns canon; client holds scoped draft/UI recovery only |
| Web client | Flutter web connects to authenticated HTTPS, or is served by the user's desktop engine on loopback | Service owns canon; browser-local database authority is not required |

Mobile PostgreSQL configurations can be supported through a user-owned service endpoint. Direct public-client database credentials are not the recommended mobile arrangement; a client cannot enforce server authority against itself.

Keep the engine usable without a desktop window. Preserve bounded admission, author-reserved work capacity, queue limits and cancellation behavior, adapting native threads to Dart isolates. SQLite work/large validation must not block rendering.

Mobile suspension/termination replaces daemon lifetime assumptions. Persist completed workflow transitions, recover unknown outcomes after resume, and never claim an operation completed because an isolate ended. Local mobile does not promise an always-running MCP server.

Use one authenticated loopback HTTP adapter for new desktop clients unless a concrete compatibility requirement necessitates retaining platform-local IPC during transition. Bind only loopback by default; local HTTP still needs credentials and origin/host validation. Existing local profile identities/secrets remain valid. Network transport never inherits Unix peer-UID authority.

Remote HTTPS accepts scoped app identity, not a PostgreSQL password. Separate private human review/approval commands from public model tools. Optional notifications can announce a new head; a disconnect/reconnect can also refresh it. Realtime editing, presence and chat are outside this migration.

For users who prefer a browser on their own computer, the installed engine can serve the bundled Flutter web assets and API from the same loopback origin. It continues to own SQLite or configured PostgreSQL. The browser does not open the package directly. Establish a short-lived browser session through an explicit authenticated native/CLI action; never put a durable profile secret in a URL. Validate origin/host and protect browser mutations against CSRF. A public hosted page need not probe or connect to arbitrary localhost ports.

## 6. Configuration contract

Vanna's required interface:

~~~text
UB_USE_POSTGRES=false

UB_USE_POSTGRES=true
UB_POSTGRES_ENDPOINT=<PostgreSQL connection string including credentials>
~~~

These variables belong to the service process. They are never embedded through Flutter compile-time defines, web assets, desktop preferences returned by APIs, or browser storage. Agents ordinarily get an app profile/service connection, not database credentials.

### Resolution and failure behavior

| Input | Result |
| --- | --- |
| Neither environment setting nor saved backend setting exists | SQLite in managed local storage |
| UB_USE_POSTGRES=false | SQLite, even if an endpoint happens to be present |
| UB_USE_POSTGRES=true with valid endpoint | PostgreSQL |
| UB_USE_POSTGRES=true with no endpoint | Configuration failure before opening/creating an alternative store |
| Invalid boolean, malformed URI or incompatible connection option | Redacted actionable configuration error |
| PostgreSQL unavailable, denied or containing an incompatible schema | Fail visibly; preserve the selected backend and pending work |
| Backend setting changed | Controlled restart and explicit connection to the selected installation; no automatic transfer |

Accept literal true/false with surrounding whitespace trimmed and case normalized; reject other boolean strings. Precedence is supplied environment values, then saved local values, then defaults. A supplied empty endpoint is an error when PostgreSQL is selected, not a reason to use a saved secret. A false selection does not access the endpoint.

Parse supported postgresql/postgres URI forms deliberately, including percent-encoded credentials, IPv6 hosts, database name and TLS options. Map SSL settings explicitly into the driver; do not silently ignore URI query options. Secret-bearing query fields must be redacted with userinfo. Hosted connections use verified TLS; loopback development alternatives require an explicit setting.

The URI names the database containing the installation; it is not a universe selector. Introduce no new database-per-universe environment settings. The service catalog resolves authorized universes by stable identity/name.

Configuration is read at service startup. A local Settings change performs a connection test, shows the target instance/backend, drains the current engine if needed, saves successfully and restarts. Failed connection/decryption preserves the prior saved configuration. Changing databases never means “migrate,” “clone” or “restore.”

Use one resolver shared by the engine and local setup/CLI. Finder/Dock launches do not assume shell environment variables are available; they use saved configuration. Clients connecting to an already-running engine use its reported backend rather than independently re-resolving environment settings. Do not persist a plaintext .env file as a convenience path.

The handshake returns backend, stable instance identity, capabilities and current access. URIs/hostnames are locators, not identity. Refuse to replay an unresolved publication on a replacement instance at the same URL.

### Local encrypted configuration recommendation

Use a protected local settings.sqlite with typed nonsecret fields and encrypted credential fields. Encrypt the exact endpoint scalar using AES-256-GCM, a fresh cryptographically random nonce and a random installation key; bind installation ID and field purpose as authenticated associated data. Store ciphertext, nonce/tag and key reference in fixed columns. Do not encrypt a generic JSON configuration document.

The file contains encrypted secrets; nonsecret settings such as backend choice can remain readable. If full-file encryption is specifically desired, use an encrypted SQLite implementation with the same typed settings schema, after verifying its packaging and SQLite patch compatibility. Whole-file encryption is an alternative to qualify, not a silent addition of another production database layer.

Keep the installation key in macOS/iOS Keychain, the appropriate Windows protected credential store, Android Keystore-backed storage or Linux Secret Service. Use a maintained authenticated-encryption implementation such as [cryptography](https://pub.dev/packages/cryptography), not application-written cryptography.

An alternative with fewer moving parts is to keep the endpoint entirely in the OS credential store and save only its reference and backend flag locally. Recommended encrypted-file behavior still gives a visible managed settings file and avoids plaintext credentials.

Headless engine access is part of the design: Flutter-only secure-storage plugins cannot simply be imported into a plain Dart executable. Qualify a thin native credential-store bridge usable by both binaries, including Keychain access/signing and Linux keyring availability. [Flutter platform integration](https://docs.flutter.dev/platform-integration/platform-channels) explains the UI-side bridge; headless access needs its own compatible adapter.

If a headless Linux/user environment has no credential store, support the environment variables already requested. A passphrase-unlocked encrypted configuration can be added only with a defined unlock/recovery flow; never put its decryption key beside the ciphertext or silently store plaintext.

Do not persist environment-provided credentials automatically. Save local settings only through the explicit setup action. Mask endpoints in status, logs, error formatting and crash telemetry. Universe exports/backups exclude connection secrets and OS keys. Device migration requires reconfiguration or an explicitly protected credential transfer, not copying a file and pretending its device key is available.

Credential-file encryption is separate from encryption of authored universe data. Preserve local sandbox/file protections and use hosted storage/backup encryption. Do not advertise end-to-end encryption: server-side validation requires readable data.

## 7. Dual-database storage design

### 7.1 One model, two physical implementations

Keep the typed canonical/semantic/workflow model and one domain codec contract. JSON may remain transient transport and checked-in software metadata/fixtures; it must not become persisted application authority, opaque workflow bodies, JSONB documents, or generic field-path/value storage.

The store contract exposes complete semantic transactions: exact historical reads, expected-generation draft save, immutable proposal/validation evidence, exact compared publication, source/media staging, operation recovery, continuity fork/adoption and archive transfer. It does not export a database Connection to application logic.

Port direct SQLite usage in Registry, import preview storage, conversion, credentials and kernel paths. Replacing universe-store alone would leave significant SQLite coupling in the service.

Retain one mapping catalog as software metadata. Use it to generate SQLite/PostgreSQL DDL and codec metadata. Ordered children, absent/null/present states, maps, tuples and closed variants must reconstruct the same domain value. Generated row pointers are storage details and never enter domain digests.

Recommendation: sqlite3 for explicit native SQLite access and postgres for PostgreSQL, with application-owned SQL for transaction-critical paths. [sqlite3](https://pub.dev/packages/sqlite3) and [postgres](https://pub.dev/packages/postgres) provide Dart implementations of the relevant access paths. Drift is an alternative to evaluate in the first representative slice; its PostgreSQL support has documented migration and feature limitations, so do not assume its dialect conversion covers this kernel. [Drift PostgreSQL](https://drift.simonbinder.eu/platforms/postgres/).

### 7.2 SQLite

Preserve one universe per package, a separate installation catalog and protected local credentials. Enforce foreign keys on every connection, WAL, FULL synchronous writes, bounded busy waits, the current required SQLite patch baseline and FTS5. Test the actual bundled library rather than relying on the wrapper version.

Preserve exclusive writer ownership, safe cold start, owned regular paths, symlink/hardlink refusal where supported, and consistent backup. Adapt permissions/locking to Windows and mobile sandboxes without pretending POSIX modes exist everywhere. No live package on a file-sync/network share becomes supported merely because Flutter can pick its path.

Do not automatically convert old layouts on startup. An incompatible existing installation is preserved and receives an actionable conversion/recovery path.

### 7.3 PostgreSQL within one configured database

Recommend one database per installation/account for the initial offering, with an installation control schema and one schema per universe. This revises the earlier database-per-universe suggestion to honor the single endpoint setup.

- The control schema owns stable instance identity, profile hashes, aliases, grants, administration audit, import previews and the universe catalog.
- A universe schema contains its singleton universe row, all typed bodies, immutable history, workflows, source/media content and rebuildable projections.
- Catalog locations are typed backend locators; PostgreSQL schemas do not acquire meaningless file device/inode values.
- Generate schema identifiers only from validated internal IDs. Universe display names and source text never become SQL identifiers.
- Qualify identifiers explicitly or use a transaction-local, trusted search path. Pool checkout must never carry another universe's namespace.
- The setup role can create the required schemas without database/server superuser rights. Separate migration/setup privileges from ordinary runtime mutation where operationally practical.
- Credentials authorize the service; app profiles/grants still control user operations.

Schemas are namespaces, not automatic tenant security. Remove untrusted schema creation from the runtime role and do not rely on search_path for isolation. PostgreSQL documents the trust implications of schemas and search paths. [PostgreSQL schemas](https://www.postgresql.org/docs/current/ddl-schemas.html).

For paid hosting, provision isolated installations/accounts with separate database roles and logical databases on shared infrastructure; the environment interface remains the same. Account credentials must not span unrelated customer databases. This keeps the first offering compatible with self-hosting.

886 typed tables per universe create real catalog/provisioning/migration overhead. Measure many-universe creation and migration in the first PostgreSQL slice. If that arrangement fails the intended deployment needs, bring the finding and the tradeoff to Vanna before switching to shared tenant-scoped tables. Do not introduce a shared-table tenant model while merely translating SQL.

A later consolidated tenant design would need tenant/universe scope on body rows and composite references throughout, plus protected routing and possibly row security. A top-level tenant column alone cannot protect the current unscoped body graph.

### 7.4 SQL and value portability

| Current assumption | PostgreSQL implementation |
| --- | --- |
| INTEGER PRIMARY KEY local row IDs / last_insert_rowid | BIGINT generated identity plus INSERT RETURNING |
| STRICT tables and SQLite boolean storage | Explicit PostgreSQL types/checks with equivalent codec values |
| PRAGMAs and sqlite_master inspection | Backend capability and schema introspection |
| BEGIN IMMEDIATE | Locked universe/authority rows inside a transaction |
| Deferred circular continuity/head references | Equivalent deferrable constraints |
| SQLite immutable-history triggers | PostgreSQL trigger functions and role restrictions |
| FTS5 | PostgreSQL indexed search with its own query implementation |
| Filesystem database package backup | Consistent server backup and backend-neutral logical export |

Keep exact authored numerics as the current exact text/token representation; do not substitute database NUMERIC formatting for canonical bytes. IDs stay the current namespaced strings, not automatic UUID replacements. Keep fixed authored offsets, fictional ticks and temporal expressions out of ordinary SQL timestamp conversion.

Keep normalized selector keys computed by the common Dart policy; compare them using an explicit deterministic collation in PostgreSQL. Database locale/collation changes must not redefine aliases or uniqueness.

Search backends may rank differently. Their shared contract is authorized, correctly framed candidates and explicit pagination/coverage. Validation enumerates applicable structured facts/rules, never only search matches. Intersect indexed historical versions with requested membership before disclosure.

## 8. Transactions, identity and service recovery

In PostgreSQL, initially serialize mutations per universe using its singleton row as a transaction-held lock. This preserves the existing package writer semantics across processes and encompasses reservations, continuity changes, drafts and workflow selection. Different universes can mutate concurrently. Use a defined lock order: installation authority, universe, then operation-specific rows.

Authority reads used to admit publication must hold database locks that conflict with revocation/grant edits. Specify and test the profile/grant locking protocol, including grant insertion/removal and author changes. A process-local mutex is insufficient for multiple service workers. Lock conflicting authority changes before they can publish; do not add a TTL authorization cache that can keep revoked access alive.

Use a defined transaction isolation level and repeatable snapshots for multi-query pinned reads/exports where necessary. Immutable records do not alone make mutable workflow/authority reads consistent. [PostgreSQL isolation](https://www.postgresql.org/docs/current/transaction-iso.html).

Atomic publication:

1. Authenticate and acquire the relevant authority/universe guards.
2. Look up the original operation receipt. A matching retry returns its durable result under current disclosure rules; mismatched payload reuse is rejected.
3. Compare exact workflow selection, proposal version/digest, base head, validation capture, approval and current footprint permissions.
4. Check expected prior versions and complete candidate dependencies.
5. Insert immutable body/version/history records, initialization receipts and source dependencies.
6. Update head/membership and required workflow/projection publication state.
7. Store the request-bound receipt in the same transaction and commit.

Validation may run outside the publication transaction against frozen inputs. Its dependencies and current authority are rechecked before publication. A fast PostgreSQL write must not bypass those checks.

Use unique receipt constraints, transaction retries only for explicitly safe aborts, and the original identity for uncertain outcomes. Application errors and dropped responses must not be treated as proof of rollback. No automatic mutation replay on another instance.

Keep source/media bytes transactional initially. Existing external content-addressed assets, where still used, retain reachability/durability rules. No object-storage service is introduced without measured need and a reviewed publication/recovery design.

Dart garbage collection, isolate termination and async cancellation need explicit resource cleanup. Closing the last client stops desktop service only under the existing idle/drain policy. Cancellation abandons or reports the admitted operation according to its durable state; it does not pretend to undo canon.

## 9. Dart semantic portability

These requirements are central to the conversion, not optional language cleanup:

- Implement the current canonical serializer and strict parser. Preserve duplicate/unknown-field rejection, raw UTF-8 content, minimal escapes, exact numeric tokens, canonical key order, authored array order and normalized set identity.
- Rust string ordering and Dart UTF-16 comparison can differ for non-BMP characters. Compare the required Unicode/UTF-8 ordering explicitly, with existing digest fixtures and added relevant boundary cases.
- Match NFC/full case folding/NFC, pinned Unicode behavior, surrounding trim, control/bidi rejection and selector length limits. toLowerCase is not full case folding.
- Represent exact integer/decimal computation using BigInt/coefficient-scale or the equivalent bounded representation. Preserve current overflow/precision failures; adopting BigInt does not grant unbounded semantics.
- JavaScript-target Dart integers lose precision beyond 53 bits. Byte sizes, counters, IDs, exact numbers and request tokens need explicit transport/domain handling on web. Raw JSON decoding cannot round a token before validation. [Dart numbers](https://dart.dev/resources/language/number-representation).
- Distinguish omitted, explicit null, empty list/map, unresolved and unbounded everywhere the owning contracts distinguish them. Do not let convenient generated serializers change inclusion rules.
- Retain namespaced references and same-universe/kind checks. Database row IDs must remain private implementation details.
- Preserve factual revision versus editorial history versus story/calendar time.
- Keep all evaluator limits, partial coverage and explicit unsupported outcomes. Do not weaken tests to fit a library or introduce a new inference engine.
- Port generated assertion/effect identity recipes, source digest recipes, import provenance and receipt hashes exactly. A new implementation cannot rehash old evidence and call it unchanged.
- JSON Schema generation must retain conditional requirements, closed alternatives, nullability and bounds. Generator support must be tested against actual contracts, not assumed from annotations.

## 10. Complete feature coverage

Port all 38 canonical record families:

| Group | Families and associated behavior |
| --- | --- |
| Topology and identity | Entity, World, Realm, RepresentedContext; contextual names, classifications, world associations |
| Definitions | EntityType, Property, Relation, Unit, Calendar, ValueDefinition, DomainPack; ancestry, applicability, typed values and dependencies |
| Facts and policy | Proposition, Assertion, Completeness, Boundary, Rule, Exception, IssueDecision; polarity, validity, supported constraints and resolution |
| Occurrences | Event, ItemPower, ActionDefinition; participation, declared effects, owner requirements and exact resource accounting |
| Knowledge and intent | EpistemicAttitude, Observation, Communication, Memory, Secret, Goal, Commitment; acquisition, channel timing, accounts and intent |

Story-secret authoring includes the existing covered-record scope, fictional
knowers, explicit reader disclosure, optional concealment and validity. Create
and revise through the reviewed publication flow; retain identity and history.
Fictional secrecy remains separate from application permissions and credentials.
| Narratives | Work, WorkVersion, SceneRef, PassageRef, Saga; source bindings, narrative order and cross-world association |
| Source and media | Source, SourceVersion, Anchor, Appearance, ImageAsset; bytes, citations, typed depiction and temporal provenance |

All existing DomainOperation alternatives and public/private request variants belong to parity. Group their implementation by these families, but do not implement only the most visible editors.

Workflow coverage also includes:

- Durable typed drafts, submission history, assessments/selections, validation captures, approvals, delegation, withdrawals and operation cancellation/recovery.
- Authored clock creation/advance/time travel; event corrections/endings; instance initialization; definition refinement; relationship transfers; knowledge establishment.
- Continuity fork, compare and selected adoption; protected-rule change and invalidation.
- Registration/rename, retained aliases, grants and limits/expiry, revocation, purge preview and execution, maintenance and shutdown.
- Source/image staging and retrieval, logical/physical backups, restore, clone, filtered dependency-closed export, import preview/admission and explicit legacy conversion.

Keep required product receipts/evidence and functional fixtures. The prohibition on substantiating artifacts does not remove domain evidence used by the application.

## 11. Flutter UX and platform behavior

Reuse the current proposal's Library, Overview, Records, Timeline, Changes, Manage universe, Settings and Help placement. Change the implementation technology, not the established factual distinctions. The existing “Reality, cosmology, and time” starter vocabulary is not an implemented strict Real World policy.

Use one design system with the approved logo and exact derivatives, readable tokens, System/Light/Dark themes, typography/text scaling, focus treatment and consistent findings language. Branding assets remain the source of truth.

| Platform/size | Required adaptation |
| --- | --- |
| Wide desktop/web | Sidebar or compact rail, paged browser, dossier, inspector; resizable layout |
| Tablet/medium window | Two panes where usable; inspector as a deliberate destination/sheet |
| Phone/narrow window | Compact navigation, list-to-detail flow, focused forms, sequential exact review |
| macOS/iOS | Appropriate keyboard/navigation conventions, menus/pickers, Cupertino controls where useful |
| Windows/Linux/Android | Platform input, back behavior, menus/pickers and Material controls where appropriate |
| Browser | Stable URLs, back/forward, reload recovery, accessible labels, download/upload semantics |

Flutter supplies platform adaptation mechanisms but renders most controls itself. Platform-native appearance and behavior must be implemented deliberately. OS-owned controls throughout would be a separate architecture requirement. [Flutter adaptations](https://docs.flutter.dev/ui/adaptive-responsive/platform-adaptations).

Ordinary journey:

1. Choose Use this device or Connect to an instance.
2. Open an accessible universe by name; no folder-path requirement.
3. Create minimal identities/facts or inspect existing dossiers and authored chronology.
4. Save unfinished work independently of canon.
5. Submit a proposal, run checks, review the exact diff/findings, approve, then publish separately.
6. Read the receipt revision and recover dependent work from fresh context.

Backend choice lives in local owner/server administration. Hosted clients see a connection name and access, not database setup. Real World is explained in creation/policy review and relevant claim findings; do not show an intimidating technical policy panel for every ordinary edit.

Draft protection must improve on the current completed-operation-only autosave: persist unfinished form state, selected IDs, entered exact values and rationale separately from proposal operations. Scope recovery by verified instance, profile, universe and continuity. Use typed fields/child rows rather than a serialized UI-state blob. Do not submit/publish recovered forms automatically.

Keep explicit expected-generation saves, safe navigation, failed-save text retention, local undo/redo, operation edit/remove and explicit rebase. Switching accounts/instances retains separately protected drafts and clears inaccessible cached views.

Dossiers show facts, relationships, timeline, appearance and history. Relation graph/list alternatives must expose the same roles, direction, validity and permissions. Timeline needs points, intervals, approximate/relative times and unplaced records, plus a readable list. Never turn a known event participant into an inferred lifespan.

Review remains usable on a phone: exact old/new values, scope/time, source interpretation and unresolved checks cannot disappear behind a summary. Approval and publication remain distinct controls.

Platform integration includes keyboard shortcuts, focus/selection, mouse/touch/stylus, native menus/context menus, file/share pickers, desktop window persistence, clipboard, deep links, screen readers, reduced motion and text scaling. Verify the changed workflows with real platform accessibility tooling; Flutter widgets alone do not establish accessibility. [Flutter accessibility](https://docs.flutter.dev/ui/accessibility).

Web is an authenticated application, suitable for Flutter's app-oriented rendering. Use a separate ordinary website for public marketing/search discovery if needed; it is not part of converting the factual workspace.

Browser-owned local authority is deferred: SQLite/WASM exists, but browser storage eviction, origin isolation, export, service lifecycle and credential protection need a separate product choice. [Drift web](https://drift.simonbinder.eu/platforms/web/). A locally served web UX uses the installed engine's normal durable backend instead. Without an installed engine or reachable instance, the web app must explain its connection requirement rather than offer a nonfunctional Use this device choice.

## 12. MCP, HTTP and CLI contracts

Preserve MCP names, ordinary/advanced discovery, descriptions, closed schemas, error codes, resource budgets and cancellation semantics. Keep exact universe selection on every domain request; context/proposal IDs never substitute.

Dart is not listed among the official MCP SDKs inspected for this plan. Early work must compare maintained community candidates against required lifecycle/transports; if none qualifies, use a narrow application-owned Dart adapter. Do not build a general-purpose SDK unnecessarily. [Official MCP SDKs](https://modelcontextprotocol.io/docs/sdk).

Stdio keeps stdout exclusively for protocol frames and bounds line/frame buffers before decode. Preserve malformed input, duplicate keys, initialization/version negotiation, request IDs, pagination and dropped-client behavior.

Remote MCP uses Streamable HTTP and the applicable MCP authorization contract, with resource/audience-bound credentials. App human sign-in and MCP agent authorization may share an identity provider while retaining separate privileges. Author approval is never advertised as a model tool. [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

The private HTTP command adapter shares service DTOs and returns instance/capability identity. Hosted commands referencing files use bounded upload/download content operations, not paths on the client's computer. Owner-only backup/purge/conversion cannot become arbitrary server filesystem APIs.

Contributor GUI support uses a permission-filtered catalog/read/draft contract. Do not remove require_author from current owner-wide Library/LoadDraft/SaveDraft branches and expose their results wholesale. Count, title, graph neighbour, thumbnail, validation and error disclosures need the same scope rules as direct reads.

Port the CLI's public launcher behavior and every maintained author/operator command. Preserve multiverse-mcp serve, ux, shortcut and admin interfaces where existing clients rely on them; do not mix branding changes into the migration. Keep absolute installed helper paths, no developer PATH dependency and no source-tree/runtime download requirement.

## 13. Transfer, conversion, backup and larger workloads

SQLite and PostgreSQL are alternative authoritative backends. Initial transfer is an explicit move or clone. Automatic bidirectional synchronization and offline publication queues are outside this plan.

1. Select and authenticate the source/target instances; detect identity/name conflicts.
2. Quiesce source mutations for a final move, or pin a consistent snapshot for a clone.
3. Stream a logical relational archive into a private target under the trusted schema.
4. Verify retained IDs, facts, commit ancestry, continuity baselines, source/media bytes, workflow evidence and digests.
5. Admit the target with current target-instance authority; historical imported approvals/delegations never become new permissions.
6. Publish catalog visibility atomically where possible and switch the user's connection explicitly.
7. Retain the original for recovery. If catalog/target publication fails across instances, preserve the staged complete target and report the recoverable outcome.

If no layout change is necessary, opening an existing normative SQLite package with Dart is an engine replacement, not a fabricated migration. Legacy conversion remains explicit and read-only on the source.

Do not rewrite canonical historical bodies merely to add Real World defaults. Separate authored policy records preserve historical payloads; actual required normalization keeps original digest provenance under the existing conversion rules.

Preserve complete-history export and explicit incomplete/dependency-filtered export behavior. Credentials/installation authority remain outside universe archives. Restore must refuse overwrite, validate a private target and distinguish restoring a backup in the same authority environment from importing historical workflow into a new one.

Current 512 MiB logical archive bounds can obstruct the requested large-data PostgreSQL path. Design bounded streaming row/content transfer instead of loading an entire archive graph in memory. Keep the same trusted relational archive meaning, checksums, dependency checks and explicit size/resource errors; changing chunk/container limits must not discard content/history or introduce an opaque JSON substitute.

A large PostgreSQL installation still needs explicit limits, indexed historical access, paging, batch codec reads and bounded validation. The current recursive codec can issue a query per body node; measure representative deep records and historical reads before optimizing. Avoid an assumed universal speedup.

Reuse the standard workload intent: 10,000 entities, 200,000 assertions, 2,000 rules and multiple continuities, along with the relevant real workflows. Its current ignored test includes legacy archive construction, so first reconcile its input with the normative archive before relying on it. Do not count the presence of that test as a current passing result.

Measure startup, universe provisioning, pinned dossier reads, search/pagination, source staging, validation, publication, restart, backup/export/restore and memory. Track many-universe PostgreSQL catalog/migration overhead and network latency. Select practical target budgets after a representative slice; retain explicit partial output and admission errors.

## 14. Paid hosting and operations

Start with a headless Dart service, HTTPS termination, PostgreSQL, persistent storage/backup and ordinary deployment automation. No microservice fleet, Kubernetes requirement, vector store, Redis coordination or object-storage dependency is justified by this plan.

Use one installation/account authority boundary initially. Customers may enroll bounded contributors; multiple independent approval owners inside an installation remain a separate design question. Hosted “account” is a commercial identity mapped to an app principal/installation, not a replacement for grants.

Before offering the paid service:

- Define sign-in, account-to-installation routing, agent enrollment, recovery, revocation and export access.
- Define billing provider, verified webhook handling and idempotent subscription events; keep billing rows outside canon.
- Define storage/compute/backups, contributor limits and cancellation/nonpayment behavior. Recommend retaining export/read recovery during an announced retention window rather than deleting canon automatically; commercial terms need Vanna's decision.
- Apply admission limits before durable work. A subscription change does not retroactively invalidate or duplicate a commit already admitted.
- Provide retained-history backup and tested restore; specify retention and operational restore targets from observed workload.
- Redact authored prose, source contents, credentials and claim details from routine telemetry. Operational logs need bounded errors/timing/IDs, not a copy of customers' drafts.
- Coordinate migrations with maintenance/drain and compatible app rollout. Startup fails on an incompatible store rather than rewriting live hosted data automatically.

Hosted at-rest encryption and TLS protect storage/transport; server operators remain within the trust boundary. End-to-end encrypted server validation is not promised.

Database isolation/provisioning overhead affects unit economics. Measure actual storage, backup, schema objects and per-installation resource usage before setting prices. No provider selection, expenditure or price is authorized by this plan.

## 15. Build, distribution and retirement

Pin a qualified Flutter/Dart toolchain and dependency lockfile. Build/test pure Dart packages on native targets and web numeric/codec paths. Flutter builds/package checks run on appropriate OS runners.

Port xtask duties and maintained Python packaging/schema/workflow helpers into Dart where they remain required. Retain existing functional inputs and independent host checks where useful; do not translate abandoned proof/evidence generators or create new ones. Software metadata, fixtures and required contracts can remain JSON files; this does not violate typed application persistence.

Platform delivery includes:

- macOS arm64/x64 packaging, approved icns, consistent helper bundles, signing/notarization when distribution is authorized, Homebrew formula/shortcut behavior and credential-store entitlements.
- Windows supported architecture packaging, icon derivatives, ACL/locking behavior, install/upgrade/uninstall data preservation and signing.
- Linux packaging, native SQLite assets, credential-store dependency disclosure, desktop launcher/icons and headless deployment.
- iOS/Android bundle identities, signing, app-private storage, lifecycle recovery, file/share import/export, backup exclusions and store-ready packaging.
- Web HTTPS delivery, deep-link routing, compatible asset updates, cache invalidation, CSP/CORS and session behavior. A cached client must not speak incompatible contracts silently.
- Headless executable/container distribution with on-demand project-owned test containers, pinned images, explicit volumes and controlled migrations. Existing suitable containers are inspected/reused; cleanup preserves state and other active work.

Port complete sealed-bundle/helper integrity behavior where it remains part of the chosen packaging contract. Public users do not install Rust/Dart/Python just to run the app.

Retire Rust runtime crates and obsolete build routes after corresponding Dart parity and controlled cutover. Git retains history; there is no permanent second active domain/schema implementation. Transitional source coexistence is allowed, but Rust/Dart engines must never both own the same live package.

Update affected README, source contracts, realignment/UX implementation references and operator runbooks during accepted implementation slices. Reconcile historical documents explicitly; do not silently overwrite their recorded qualification claims.

## 16. Dependency-ordered implementation work

These are work packages, not time-boxed goals or completion claims. Split large packages into coherent record/workflow slices. Use focused functional tests and normal temporary output; no proof reports, screenshots as evidence, duplicate audit framework or additional acceptance gates.

| Package | Depends on | Concrete delivery and focused verification |
| --- | --- | --- |
| P01 — Foundation decisions and toolchain | Reviewed plan | Pin toolchain/drivers; validate a representative canonical fixture, SQLite library capabilities, PostgreSQL schema/transaction and MCP candidate. Resolve any actual incompatibility before larger work. |
| P02 — Dart domain and canonical contracts | P01 | Port IDs, values, scope/time, all records, operations, strict parser/digests and generated DTO/schema rules. Reuse historical digests, exact-number/Unicode fixtures and invalid-input cases. |
| P03 — Storage boundary and SQLite kernel | P02 | Typed codec/DDL, head/history/receipts, projections/search, ownership and consistent reads. Test internal publication with an already-admitted input, receipt retry and historical retrieval after restart; public reviewed publication arrives with P04–P06. |
| P04 — Installation, configuration and secret access | P01–P03 | Required environment variables, encrypted local settings, local identities/grants, instance handshake, safe startup/shutdown. Test redaction, overrides, invalid backend, key loss, revoked profiles and no fallback. |
| P05 — Rules and effective objects | P02–P03 | Port supported rule/evidence evaluation, ancestry/applicability, definition/instance distinction, initial values, units and chronology. Reuse Cedar/Pistol/ancestor/exact resource tests. |
| P06 — Full authoring and recovery workflows | P03–P05 | Drafts, proposals, validation/approval/delegation, effects/knowledge/cardinality, assessments and operation recovery across all record groups. Test stale bindings, competing drafts, cancellation and interrupted responses. |
| P07 — PostgreSQL complete store | P02–P06 | Control/universe schemas, SQL codec, search, locks, authority coordination and backend capabilities. Run the same meaningful store/service cases against both backends; test two processes, cross-universe isolation and pooled namespace reset. |
| P08 — Logical transfer and large-data paths | P03, P06–P07 | Streaming SQLite ↔ PostgreSQL transfer, legacy conversion, content/history preservation, backups/restores, schema provisioning/scale checks. Test an interrupted move and retained original/uncertain target recovery. |
| P09 — Service transports, MCP and CLI | P04, P06–P08 | Loopback/HTTPS private commands, stdio/Streamable HTTP MCP, bounded IO, public launcher/operator commands and host config. Test real transport contracts, current rights and lost publication recovery. |
| P10 — Flutter shell and desktop ordinary journey | P02, P04, P06, P09 | Themes/logo/navigation/connections, minimal record edit, typed unfinished-form recovery and exact Changes flow. Validate keyboard/focus/accessibility and interruption behavior in the changed journey. |
| P11 — Complete desktop feature UX | P10 | Dossiers, graph/list, chronology, all typed editors, source/image views, continuity/adoption, grants and recovery/maintenance placement. Reuse functional editor semantics; every current capability remains reachable. |
| P12 — Mobile local and hosted UX | P06, P09–P11 | Compact/tablet layouts, embedded SQLite service, file/share flows, app lifecycle and hosted connection. Test termination during save/check/publish, text scaling, rotation and real touch/back behavior. |
| P13 — Web UX | P09–P11 | Hosted/local-engine web access, web-safe codec paths, URLs/session/upload/download, browser navigation and compatible deployment. Test refresh mid-editor/unknown publication, browser session boundaries, Unicode/exact values and absence of database credentials in delivered assets. |
| P14 — Real World product extension | P05–P06 plus approved evidence policy; UI completion uses P10–P13 | Typed policy/obligations, source/assessment integration, strict scoped admission and review UI on all surfaces. Test conflicting evidence, approximation, attribution, policy changes and scoped fictional departures. |
| P15 — Hosted commercial operation | P07–P09, commercial decisions | Account provisioning/authentication, isolated routing, billing entitlements, limits, backups and coordinated upgrades. Test one complete customer setup/export/recovery and cross-customer denial before paid release. |
| P16 — Packaging, controlled cutover and retirement | Required P01–P15 features | Platform packages, existing installation preservation, staged engine replacement/backend move, docs and obsolete runtime removal. Verify each claimed target independently; retain recovery originals. |

P14's policy specification belongs in P01; its implementation follows factual parity so new semantics do not obscure migration defects. Backend selection in P04 can initially refuse the not-yet-built PostgreSQL adapter explicitly; PostgreSQL is not advertised as supported until P07/P08 complete.

P07 can start with a narrow representative schema/transaction in P01 and grow by the same family/workflow slices as SQLite. P09 can establish transport skeletons earlier, but ordinary authoring is not advertised until exact workflow/recovery exists. Flutter shell work can begin after contracts stabilize; full UX completion requires service parity.

Delivery checkpoints:

1. Headless Dart local authoring is complete for existing supported semantics.
2. SQLite/PostgreSQL behave equivalently and explicit transfer works.
3. Flutter desktop provides the complete author workflow and feature coverage.
4. Mobile/web provide the required local/hosted experiences.
5. Real World and paid hosting deliver their separately specified product behavior.
6. Platform distributions and controlled data cutover are complete.

Each checkpoint can support a scoped preview; none means that later platforms, real-world coverage, prose interpretation or live release have been qualified.

## 17. Decisions and material tradeoffs

Already directed by Vanna: full Dart/Flutter conversion planning; desktop/mobile/web; selectable SQLite/PostgreSQL; UB_USE_POSTGRES and UB_POSTGRES_ENDPOINT; evidence-backed strict Real World with external research.

Recommended baseline:

- Platform-appropriate Flutter UX and shared Dart service.
- Desktop independent engine; embedded mobile-local service; web client for hosted or locally served instances.
- One PostgreSQL endpoint/database per installation with a schema per universe.
- Typed storage/archives and one canonical/domain implementation.
- Encrypted local credential fields with an OS-held installation key.
- Explicit moves/clones between authoritative backends.
- Real World represented by scoped, published policies and attributed evidence requirements; authors choose source categories and review is required only where the scoped policy requests it.

Choices to settle before their affected implementation:

| Choice | Recommendation and tradeoff |
| --- | --- |
| Meaning of native | Flutter-rendered adaptive UI plus OS integrations; actual OS-owned widgets throughout would require a different UI architecture |
| PostgreSQL tenancy | Schema per universe inside an installation database; simpler preservation/setup, substantial repeated catalog objects |
| Encrypted configuration | Typed settings with encrypted secret fields; full-file encrypted SQLite is an optional qualified alternative |
| Real World claim coverage | Apply the policy-dependent review decision in §4.6 to exact claim/effect bindings; no automatic truth ranking or mandatory public corroboration of private memories |
| Hosting ownership | One approval owner per installation initially; independent per-universe owners need a separate authority design |
| Commercial behavior | Decide pricing, quotas, retention/nonpayment and export access before paid rollout |
| Browser-owned local database | Defer; locally served web can already use the installed engine without treating browser persistence as equivalent to native package durability |
| Platform sequence | Complete desktop factual parity first, then mobile/web; implement shared layouts/contracts with all targets in mind from the start |

A failed implementation/test is not automatically a design flaw. If concrete evidence exposes one—for example schema-per-universe cannot satisfy the measured hosting workload—pause that affected slice, state the failing assumption, recommend the smallest change and material tradeoff, and wait for Vanna's decision. Do not replace approved model roles, add a parallel ledger, or loosen exact approval to make progress easier.

## 18. Effort and first executable slice

This is a substantial migration across language, persistence, authorization, platforms and distribution. Do not infer a completion date from line counts or divide the old goal count into new phases.

Estimate remaining work after the first representative slice records actual implementation time and ordinary test results in chat. PostgreSQL catalog operations, canonical encoding, headless secret access, MCP support and mobile lifecycle are the earliest uncertainties worth resolving.

The first implementation slice is a minimal vertical subset spanning P01 and the first portions of P02–P06/P07/P09. It does not require completing every domain family or all platforms before measuring the foundation. It should produce:

- A pinned Dart workspace.
- Exact domain/canonical reconstruction for a minimal universe, type, instance and typed fact using existing expectations.
- A SQLite transaction publishing that fact with the existing authority/receipt semantics and a fresh historical read after restart.
- A representative PostgreSQL namespace/codec transaction using the required endpoint, including rollback and receipt retry.
- A bounded transport/credential-store feasibility check covering the selected Dart MCP and headless local-secret path.

This slice establishes whether the proposed foundation is workable without implementing a second full application, migrating live data, or creating substantiation artifacts. Its result determines package sizing and a defensible schedule for the complete conversion.
