# Universe Builder

Two modes are available: the disposable read/propose fixture and a persistent authenticated engine for author-defined factual universes. Persistent mode supports incremental definitions and instances, scoped factual constraints, retrieval, declared knowledge acquisition, scoped cross-instance cardinality, exact approval, atomic publication, history and recovery. The external writer interprets prose and asks for author clarification; the MCP validates supported factual declarations. Assessments remain optional attributed domain records. The connected writing workflow has been exercised through the native author interface and local packaged launcher. Prose interpretation remains fallible; release acceptance remains open.

## Dart conversion development

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
a report to objective fact. Consequence execution still needs its port.
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
or author approval. Retained-image byte verification and proposal
validation/publication integration remain pending.
The Dart definition registry now verifies incoming payload digests, isolates
definition universes, retains active versions and rejects duplicate family names.
Registry admission checks typed references, parent consistency and cycles,
property units/dimensions/inverses, relation roles, unit scales and bases, calendar
conversion targets, structured definition recursion and exact pack dependencies.
Packs remain limited to the existing declared capability allowlist. This registry
still requires integration into candidate validation/publication.
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
Driver integration/connection verification, setup orchestration and backend
startup remain pending; these components do not make PostgreSQL available in the
Dart engine yet. Native ownership remains qualified on macOS; the other platform
ports still need their required checks.
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
transport handshake integration, pending-purge recovery and existing-installation
cutover remain pending; these profile components do not start the Dart engine.
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
