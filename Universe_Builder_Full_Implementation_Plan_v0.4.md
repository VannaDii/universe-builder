# Universe Builder — Full Implementation Specification

**Document revision:** 0.4 — named universes, multiple worlds, explicit MCP scope  
**Date:** September 20, 2026  
**Status:** Proposed build specification. No application implementation, native macOS build, model interoperability run, or performance result is claimed.  
**Audience:** Vanna and the engineers or coding agents implementing the application.

This document supersedes v0.3 and all earlier implementation-plan revisions. The former top-level “world” project is now a **universe**; actual worlds are named records inside that universe. This is a structural scope change, not only a terminology change. It contains the product contract, full architectural plan, domain coverage, detailed implementation contracts, dependency-ordered work, and acceptance criteria in one place. It is not a UI-only amendment. The companion backlog and test catalog are extracts for execution; this document is the authoritative plan.

## Evidence, authority, and confidence

**Established requirements / High confidence:** Universe Builder manages multiple named universes, each supporting multiple named worlds and associated novels, stories, and sagas; every domain MCP call explicitly specifies its universe, with world selection supported where appropriate. Universe management only; external applications own research conversations and manuscript writing; expose agent-callable operations through MCP; use Dioxus with selected Rust/UI components; preserve the supplied universe's entity/fact/state distinctions and authorial control.

**Proposed engineering decisions / High confidence in the need, not proof of implementation:** Explicit revision contexts, separate proposal/approval/validation, bounded evaluation, immutable history, current authorization, idempotent writes, source-version evidence, and tested recovery.

**Proposed implementation choices / Medium confidence until tested:** The exact Rust/Dioxus/SDK dependency resolution, native component compatibility, initial throughput/memory limits, and deployment mechanics. The documented version candidate is a starting point for verification, not a claim of compatibility or the latest release.

**Acceptance targets:** Every test, latency, resource budget, and release gate below specifies work to demonstrate. No unchecked box or specified test means it has passed.

Authority order is: explicit user decisions in this conversation; the supplied universe-model requirements; then this plan's labeled implementation proposals. External documentation establishes platform capabilities and limitations, not fictional truth or product approval. The earlier combined writing/model-hosting idea in the source was explicitly narrowed by the user and is not reintroduced here.

## Consolidation and clarification register

| ID | What this revision makes explicit | Status |
|---|---|---|
| C01 | Dioxus Desktop and selected Rust/UI source replace the previously proposed Tauri/React application stack. | User-selected direction. |
| C02 | Event effects compile to canonical assertions in the same changeset; event replay and editable current-state fields do not become competing authorities. | Proposed implementation detail resolving an underspecified area. |
| C03 | Ending a fact at a fictional time, editorially retracting a fact, replacing its evidence, and tombstoning a record are distinct operations. | Clarifies source-required time/revision separation. |
| C04 | Approval is bound evidence of authority, not a permanently valid proposal state. Scoped grants can authorize a commit without a manual approval step. | Clarifies the earlier lifecycle sketch. |
| C05 | Application context handles, MCP protocol state, authentication credentials, and durable operation IDs are different concepts. | Proposed contract clarification. |
| C06 | A restricted validator must not become a yes/no oracle for secrets; access-limited checking and privileged commit checking have explicit boundaries. | Security refinement. |
| C07 | S03 now explicitly tests an objective assertion that Iven knows a location, not merely a character saying that he knows it. S02 continues to test speech as speech. | Wording clarification, preserving intended semantics. |
| C08 | Adds an explicit cancellation tool for application jobs rather than making the status tool mutate state. | Proposed MCP surface addition. |
| C09 | The packaged SQLite build must contain the documented WAL-reset fix; an old wrapper dependency is not sufficient evidence. | New externally verified release requirement; [R10]. |
| C10 | Detailed work packages retain WP01–WP15, with added dependency edges and subtask identifiers. Existing S/T/U acceptance identifiers are retained; supplemental E and domain D cases extend them. | Execution refinement. |

### v0.4 scope decisions

| ID | What this revision changes | Status |
|---|---|---|
| C11 | Product nomenclature is Universe Builder. A universe is the top-level named project, canon, revision, reference, and storage boundary; it may contain many named worlds. | Explicit user requirement; boundary mechanics are proposed implementation details. |
| C12 | Every domain MCP tool requires `universe` by name. A context, proposal, operation ID, profile, or UI selection never substitutes for that argument. | Explicit user requirement. |
| C13 | `world` is a per-command optional selector where meaningful. Omission selects no individual world and never chooses a default. | Required optionality; explicit omission semantics are the proposed contract. |
| C14 | Narrative works and sagas belong to a universe and can reference several worlds. World association is not a mandatory single-world ownership field. | Explicit user requirement and model consequence. |
| C15 | Names are human-facing selectors resolving to stable IDs. Exact matching, retained aliases, non-rebinding reservations, current permissions, and mismatch rejection protect isolation. | Proposed identity/naming implementation. |
| C16 | Cross-world canon changes are atomic within one universe continuity. Separate universes do not share live canonical references, transaction heads, or permissions. | Proposed implementation preserving the user's hierarchy. |
| C17 | Adds V01–V40 scope acceptance cases and integrates the requirement into WP01–WP15 rather than deferring multi-world support. | Execution amendment; specified tests, not executed tests. |

## How to use this specification

Read §§1–4 for scope and invariants; §§5–16 for the universe model and system design; §§17–26 for release gates and original acceptance coverage; §§27–32 for concrete contracts and algorithms; §§33–35 for execution, expanded acceptance, and operating runbooks. The named-universe, cross-world, and migration contract is in §36. Sources and verification limits are in §37.

A coding agent should implement one dependency-ready work package at a time. Before changing a contract or weakening a test, record the proposed deviation and its consequences in an architecture decision record. Descriptive support for a concept must never be reported as executable validation support.

## Contents

1. [Product contract](#section-1)
2. [Highest-impact failure modes](#section-2)
3. [Architecture decisions](#section-3)
4. [Non-negotiable invariants](#section-4)
5. [Canonical domain model](#section-5)
6. [Storage and revision design](#section-6)
7. [Temporal, spatial, and state semantics](#section-7)
8. [Truth, knowledge, completeness, and boundaries](#section-8)
9. [Validation engine](#section-9)
10. [Proposal, approval, and commit protocol](#section-10)
11. [MCP tool contract](#section-11)
12. [Retrieval and context assembly](#section-12)
13. [Security and privacy model](#section-13)
14. [Sources, imports, exports, and recovery](#section-14)
15. [Author desktop interface](#section-15)
16. [Domain coverage and starter packs](#section-16)
17. [Implementation sequence and release gates](#section-17)
18. [First implementation work packages](#section-18)
19. [Semantic acceptance suite](#section-19)
20. [Reliability, security, and protocol acceptance suite](#section-20)
21. [Performance and observability](#section-21)
22. [Build, packaging, and update plan](#section-22)
23. [Requirements traceability](#section-23)
24. [Explicit residual risks](#section-24)
25. [Definition of done for v1.0](#section-25)
26. [Starting implementation instruction](#section-26)
27. [Concrete domain contracts](#section-27)
28. [Storage implementation specification](#section-28)
29. [Service, authorization, and operation state machines](#section-29)
30. [Application tool schemas and interaction contracts](#section-30)
31. [Validator and state-evaluation algorithms](#section-31)
32. [Dioxus desktop implementation specification](#section-32)
33. [Detailed dependency-ordered implementation backlog](#section-33)
34. [Expanded acceptance and traceability](#section-34)
35. [Operational runbooks and release checklist](#section-35)
36. [Named universes, worlds, narratives, and scope migration](#section-36)
37. [Sources and verification notes](#section-37)

<a id="section-1"></a>

## 1. Product contract

### 1.1 Established scope

Build **Universe Builder**, a local application managing multiple named universes, with an author-facing desktop interface and an MCP interface for external LLM agents. Authors research and write in LM Studio or another external application. The universe manager manages definitions, history, evidence, proposed changes, and canon—not the writing conversation or manuscript editor.

The application must let authorized agents research, validate, propose, create, and revise material within the author's universe boundaries. Author permissions, canon approval, and validation are separate decisions.

Preserve the supplied brief's distinctions between entities and assertions, reality and accounts, continuity and editorial revision, time and narrative position, possibility and availability, absence and missing information, and schema constraints versus fictional rules. The supplied taxonomy is optional coverage, not a questionnaire authors must complete. [S0]

### 1.2 Acceptance-level product promise

> Given an explicitly named universe, a continuity and canon revision, the appropriate temporal and perspective frame, and optional world scope, return the applicable established definitions and evidence; evaluate the supported structured claims and rules; and apply only authorized, attributable changes. A call never implicitly selects another universe or a default world.

The system can protect its own operations. It cannot guarantee that an external model will invoke the tools, extract every claim from prose, respect the results, or avoid publishing text that contradicts them.

A universe may contain zero or more worlds while being defined and may support one or more novels, stories, or sagas when works are associated. World creation is not a prerequisite for defining universe-wide rules, interstellar space, shared species, or external work metadata. Universes and worlds are identified by author-facing names; stable IDs preserve their identities through renaming. The complete naming and request-scope contract is in §36.

### 1.3 Exclusions from the initial product

No manuscript editor, chat interface, model hosting, model downloads, fine-tuning, multi-model orchestration, universal literary critic, automatic universe simulation, mandatory cloud account, cloud synchronization, or multiplayer collaborative editing. No mandatory graph-database service or vector database. No requirement to model every detail of a fictional universe before using it.

External work, scene, passage, and source references remain in scope as evidence and review anchors. They do not become manuscript-authoring features.

### 1.4 Proposed release assumptions

| Area | Proposed starting point | Consequence |
|---|---|---|
| Platform | macOS on Apple Silicon first | Package and test on an actual Mac; keep engine and file format portable. |
| Ownership | One author per installation, multiple universes and multiple authorized agent clients | Concurrent requests and cross-universe isolation matter; shared-user collaboration is deferred. |
| Storage | Local disk | Live projects on network or file-sync storage are unsupported. |
| Connectivity | No outbound network needed for universe operations | Remote tools and model connectivity belong to the host, unless explicitly added later. |
| Authorization | Read/propose by default | Scoped direct commits can be granted by the author. |
| Language | Unicode throughout; English starter labels | No ASCII-only identifiers in user content or English-only name assumptions. |
| Availability | Engine usable with the desktop window closed | MCP must not depend on a visible UI process. |

<a id="section-2"></a>

## 2. Highest-impact failure modes

| Failure | Required design response |
|---|---|
| A model interprets “no conflict found” as universal approval | Separate evaluation outcome, coverage, permission, and canon status in every result. |
| The wrong continuity or outdated universe is consulted | Bind reads to an immutable context and require a base revision for writes. |
| A valid proposal changes after review | Approvals bind to the exact proposal revision and content digest. |
| A definition or permission changes between validation and commit | Recheck the head revision and current authority inside the commit transaction. |
| A successful commit times out before the host receives its result | Durable idempotency and a recoverable operation receipt prevent duplicate changes. |
| Missing facts are interpreted as false | Open-world default; negative conclusions require explicit evidence or a scoped completeness declaration. |
| Search omits a rule | Validation enumerates applicable rules from structured indexes, never only the top search matches. |
| Belief or dialogue becomes objective truth | Distinct proposition, assertion, and represented-context records. |
| A historical correction rewrites an alternate timeline | Separate continuity inheritance from editorial history, with pinned branch baselines. |
| A document contains malicious tool instructions | Treat source content as data; deny arbitrary file, network, code, and shell operations. |
| A backup contains the database but not all referenced assets | Snapshot the database and its reachable blob set under a consistent manifest. |
| An agent has unrestricted filesystem tools outside this application | State the security boundary explicitly; app permissions do not confine unrelated same-user tools. |

These are known risks addressed by this plan, not a claim that every future failure has been enumerated.

<a id="section-3"></a>

## 3. Architecture decisions

### 3.1 Proposed implementation stack

| Component | Decision | Reason and trade-off |
|---|---|---|
| Domain engine | Rust workspace | A compiled headless engine with explicit types and shared implementation between adapters. More upfront development friction than a scripting-language prototype. |
| MCP adapter | Official Rust SDK, `rmcp` | Avoid hand-writing MCP lifecycle and compatibility behavior. Lock and test an exact release. |
| Desktop shell and UI | Dioxus Desktop 0.7.x with Rust/RSX | Use one application language and shared Rust boundary types. The selected desktop renderer uses a system WebView; native packaging, platform behavior, and accessibility still require tests. |
| UI primitives | Selected Rust/UI component source, vendored from a recorded commit | Tailwind-styled Dioxus components under application ownership. Experimental upstream code is reviewed, adapted, and tested; it is not assumed to be a stable packaged toolkit. |
| Styling | Tailwind CSS v4, compiled and bundled locally | Use a pinned build toolchain and a bounded set of app-owned design tokens. No CDN or runtime registry access. |
| Persistence | Bundled SQLite with FTS5 | Local storage, transactional writes, and lexical search without an external service. |
| Rules | Typed, declarative application-owned expression language | Bounded and explainable evaluation; no arbitrary author or agent code execution. |
| Test automation | Rust tests/property tests/fuzzing; Dioxus component tests; native WebView interaction and packaging tests | Test semantics independently of any model. A browser-only test does not establish macOS desktop correctness. |
| Build automation | Checked-in Rust `xtask`, pinned Dioxus CLI, and locked Tailwind build tooling | Rust application logic; Node/pnpm are permitted build-only tools for the documented Rust/UI styling path. End users need neither. |

The existing MCP SDK decision is unchanged. Dioxus documents Rust UI components, a system-WebView desktop renderer, and packaging support. Rust/UI identifies Dioxus 0.7 and Tailwind v4 as its stack and explicitly describes itself as experimental copy-in components. These are evidence of an integration path, not proof that the selected components work in our native application. [R04, R05, R06, R07, R08, R16]

Do not add Python, an HTTP application framework, PostgreSQL, Neo4j, RDF tooling, or an embedding runtime merely because they are common in AI projects. Reconsider a component when a failing acceptance test establishes a concrete need.

### 3.2 Process topology

```text
External agent host                         Author desktop
LM Studio / another MCP client              Dioxus Desktop + typed Rust client
             |                                          |
        MCP over stdio                           private local IPC
             |                                          |
       universe-mcp adapter -------------------------------+
             |                                          |
             +-------- private local IPC ---------------+
                                      |
                              universe-engine service
                    authorization / queries / proposals /
                    rules / revisions / imports / backups
                                      |
                     one serialized writer per universe
                                      |
                   SQLite + content-addressed assets
```

This is a modular application, not a fleet of microservices. The service and adapters are local processes used for lifecycle and authority boundaries.

The MCP subprocess owns its standard streams and ends with the host connection. It connects to a per-user engine service, starting the installed service when necessary. The desktop connects to the same service. Opening two hosts must not produce two competing engines for one universe.

Use a per-user Unix-domain socket and owner-only runtime directory on macOS. Abstract the transport for a future Windows named-pipe implementation. Use OS locking plus a service handshake; a stale PID file alone is not authority. Clients compare executable/IPC versions and fail visibly on incompatible versions.

### 3.3 Lifecycle requirements

The engine starts on demand. Closing the desktop window must not terminate active agent work. When no clients or operations remain, an idle shutdown policy may stop it. There is no always-on login service requirement for the first release.

Migration and application updates require exclusive maintenance mode. Drain or reject new mutations, preserve operation receipts, close the database cleanly, and restart clients against the supported version. A failed launch or incompatible helper must not silently spawn an alternate database owner.

The MCP command uses an installed, absolute executable path. It must work without the developer's shell PATH, package manager, source tree, current working directory, or network downloads.

### 3.4 Module boundaries

```text
crates/
  universe-domain/        Typed records, values, invariants; no transport or database
  universe-schema/        Definitions, schema validation, contract generation
  universe-rules/         Type checking, temporal predicates, bounded evaluators
  universe-store/         SQLite, snapshots, projections, migrations
  universe-service/       Authorization, queries, proposals, commits, orchestration
  universe-protocol/      Shared Rust IPC DTOs and error contract; no UI dependencies
  universe-client/        Typed, authenticated async IPC client for UI/MCP/CLI
  universe-ui/            Dioxus presentation components and reviewed Rust/UI source
  universe-mcp/           MCP adaptation only
  universe-cli/           Doctor, fixture import, backup, export, recovery
  universe-engine/        Local service process and lifecycle
apps/
  desktop/             Dioxus Desktop binary, RSX screens, assets, native integration
contracts/              Generated JSON schemas and stable examples
fixtures/               Semantic universes, adversarial inputs, scale generators
tests/                  Cross-module, protocol, crash, migration, native tests
docs/                   ADRs, release manifest, threat model, compatibility matrix
xtask/                  Build, test, package, verify, and fixture commands
```

`universe-domain` and `universe-rules` must be testable without LM Studio, a webview, SQLite, or a model. Both UI and MCP call the same service commands; neither implements its own approval or temporal semantics.

### 3.5 Dioxus / Rust/UI adoption contract

**Design decision:** Dioxus replaces both the proposed Tauri shell and React frontend. Do not retain a second application shell by default. Use the standard Dioxus Desktop renderer for v1, not an unvalidated alternative renderer. Rust runs natively while HTML/CSS are rendered by the system WebView. This is not a promise of native platform widgets or a JavaScript-free rendering stack. [R06, R07]

#### 3.5.1 Preserve the headless boundary

The desktop depends on `universe-client` and `universe-protocol`, not `universe-store`. Components can validate input shape for immediate feedback, but the service rechecks every command. No component opens the canonical database, implements approval policy, or becomes the owner of the engine lifecycle.

Keep Dioxus signals, component props, and presentation-specific models out of the shared wire types. Sharing Rust structures removes the need for generated TypeScript DTOs in our own desktop; it does not remove serialization validation or API versioning across separately running binaries. JSON Schema remains required for MCP and non-Rust clients.

Use a bounded asynchronous IPC client. Never block the UI event thread with database access, rule evaluation, synchronous IPC, or large parsing jobs. A component unmounting may cancel its read, but must not be interpreted as cancelling a durable commit. Recover commit status through its operation receipt.

UI responses carry the requested universe, continuity, revision, and a request-generation marker. Discard stale responses after navigation. Live notifications announce a newer canon head; they do not silently rewrite a revision-pinned view or a proposal the author is reviewing.

#### 3.5.2 Adopt component source selectively

Place copied Rust/UI code and its required hooks/utilities behind application-owned presentation modules in `universe-ui`. Do not clone the upstream showcase, fullstack server, deployment settings, or sample business logic as our application architecture. Rust/UI's source-copy distribution model makes this selective adoption intentional. [R16]

For each adopted component, record its upstream repository, exact commit, path, file digest, license notices, dependency closure, local modifications, and acceptance tests. Retain the upstream license notices. No automatic runtime updates, registry downloads at launch, or silent replacement of customized source. Review upstream updates as explicit diffs; keep pristine source references for comparison.

Start with buttons, labels, inputs, select/combobox, badges, tabs, dialogs, basic tables, and navigation. Adopt a complex data grid only after its platform, performance, and edit-semantics tests pass. Missing or unsuitable controls can be implemented with Dioxus primitives without replacing the engine or the rest of the component set.

#### 3.5.3 Pin a tested dependency set, not just a version family

The reviewed repository commit is `10dfc3511d03644dce1d05715d384a97c41662e1` (September 18, 2026). Its root manifest pins `dioxus` and `dioxus-html` to `=0.7.9`. A maintainer comment attributes this pin to a desktop dependency publication problem with 0.7.10; the comment is evidence of upstream's rationale, not an independently reproduced registry failure. [R17]

Use 0.7.9 as the first compatibility-test candidate, not an asserted latest release or a proven build. Record and lock the complete dependency resolution, Rust toolchain, Dioxus CLI, Tailwind tooling, and selected component snapshot after the native test succeeds. Enable the desktop features our application requires; do not copy a web/fullstack example's feature set blindly.

The reviewed public installation page still describes Leptos support and future Dioxus support, while the repository README and manifest describe Dioxus. This documentation mismatch is unresolved in the published sources. For adoption, follow the inspected Dioxus source snapshot and record locally validated steps rather than combining inconsistent instructions or blindly running the site's installer. [R16, R17, R18]

#### 3.5.4 Styling and offline assets

Compile Tailwind CSS at build time. Include all adopted Rust/RSX source locations in content discovery and use complete class names or explicit allowlists for variants; dynamically assembled class names must not disappear from release CSS. Runtime-defined universe types select bounded presentation tokens, not arbitrary CSS or scripts.

Bundle CSS, icons, and any licensed fonts locally. The initial documented tooling path may use Node/pnpm during development and CI, as Rust/UI's README specifies; it must add no Node runtime requirement or network dependency to the installed app. [R16]

Maintain a light/dark theme, readable focus and error states, text enlargement, and reduced-motion behavior. Rendering, interaction, and CSS compatibility are tested on the actual supported macOS WebView. Website screenshots and browser-only tests are not substitutes.

<a id="section-4"></a>

## 4. Non-negotiable invariants

| ID | Invariant |
|---|---|
| I01 | Names and aliases never serve as record identity. |
| I02 | Every canonical record/reference belongs to exactly one universe. Cross-world references inside it are supported; live cross-universe references and accidental joins are rejected. |
| I03 | A proposal is not canon, even when it is compatible with every evaluated rule. |
| I04 | An approved belief is not automatically an approved assertion of its underlying proposition. |
| I05 | Missing, unknown-to-an-observer, explicitly absent, disputed, and intentionally unresolved remain distinct. |
| I06 | Every canon read can identify its immutable revision and applicable perspective. |
| I07 | Every canon mutation is atomic, attributable, and idempotent under retries. |
| I08 | A stale approval, stale validation run, or stale base revision cannot authorize a new commit. |
| I09 | No rule evaluation can execute arbitrary code or obtain extra permissions. |
| I10 | Unimplemented, timed-out, restricted, or truncated checks cannot be reported as passed. |
| I11 | Query caches and generated summaries are not authoritative data. |
| I12 | Editorial changes do not imply fictional events, and fictional events do not substitute for editorial history. |
| I13 | The server determines the caller's principal; user/model-supplied attribution is not authentication. |
| I14 | Every inference has an explicit derivation and evaluator version, or remains labeled an unverified proposal. |
| I15 | Historical records retain their historical schema and rule versions. |
| I16 | Author overrides never bypass storage integrity or access control. |
| I17 | A current access revocation also applies to reads of old revisions. |
| I18 | Narrative excerpts are evidence with context, not executable instructions or automatically true claims. |
| I19 | Zero findings and complete evaluation are independent values. |
| I20 | An unresolved universe question remains usable data without silently receiving an invented answer. |

Additional universe-scope invariants:

| ID | Invariant |
|---|---|
| I21 | Every domain MCP call supplies a nonempty `universe` name, even when a context or operation ID exists. |
| I22 | Exact universe-name resolution precedes record/context lookup; a known handle never selects its own universe. |
| I23 | World names are unique selectors within their universe, not installation-wide. The same name in separate universes is allowed. |
| I24 | Omitting `world` means no individual-world narrowing, never last-used/default world and never permission to invent one. |
| I25 | World filtering does not hide applicable universe-wide rules or required authorized cross-world dependencies. |
| I26 | An entity keeps one universe identity when moving between worlds. World association, location, origin, and applicability are separate facts. |
| I27 | One universe continuity has one canon revision head; a cross-world event and its effects commit atomically. |
| I28 | A world-limited request or grant cannot silently authorize changes to another world or shared universe-wide definitions. |
| I29 | A novel/story/saga association does not create a private canon or require a single world. Editions/reference bindings identify their actual continuity/revision. |
| I30 | Selector renames preserve IDs and do not rebind old names to other identities. A canon-context mismatch is an error, not an instruction to switch scope. |

<a id="section-5"></a>

## 5. Canonical domain model

### 5.1 Record families

| Family | Main records and responsibility |
|---|---|
| Frame | Named universe; named world records within it; realms, continuity, immutable canon revision, and adopted external baseline. |
| Definitions | Entity types, predicate/property definitions, role definitions, units, calendars, value types, templates. |
| Identity | Entity, contextual name, alias, identity relationship, type membership. |
| Propositions | A claimable statement with predicate, participants/value, quantification, and represented context. |
| Assertions | Support or refutation of a proposition, scope, time, provenance, persistence, and editorial basis. |
| Relations | N-ary participant assignments; not restricted to subject/object pairs. |
| Events | Occurrence, participants, conditions, ordered effects, observations, and communications. |
| Rules | Scope, prerequisites, constraints, effects, costs, exceptions, and evaluator capability. |
| Perspectives | Beliefs, knowledge claims, observations, memories, disclosures, nested beliefs. |
| Boundaries | Fixed/open/reserved/prohibited/intentionally unresolved areas; scoped completeness declarations. |
| Provenance | Sources, immutable source versions, anchors, author decisions, derivations. |
| Editorial | Changesets, approvals, issues, resolutions, validation runs, operation receipts. |
| External narrative references | Universe-owned novel/story/work and saga/series records, work versions, ordered/typed memberships, optional multi-world associations, scene/passage IDs, viewpoints, commitments and reveals. |
| Assets | Immutable attachment blobs, media metadata, external reference metadata. |

A relationship can have several signatories, guarantors, territories, or beneficiaries. An entity can have multiple types. A ship that is also an individual does not require duplicate identities simply to fit the taxonomy.

### 5.2 Proposition versus assertion

A proposition describes something that may be asserted. An assertion identifies who or what establishes it, in which context, and with what scope.

Example:

```text
P1: The silver gate is located in the northern ruins.
A1: Approved objective assertion supporting P1 during interval T.
P2: Iven believes P1.
A2: Approved objective assertion supporting P2 after communication E18.
P3: Iven told Mara P1.
A3: Approved occurrence/account assertion supporting P3 at E19.
```

A2 and A3 do not independently establish A1. The tool can represent P2 even when P1 is false or intentionally unsettled. A source can disagree with another source without producing an objective-reality contradiction.

Do not collapse polarity, editorial status, perspective, source reliability, and uncertainty into one `status` enum.

### 5.3 Value model

Use a discriminated value type, not arbitrary JSON for every field:

```text
Text | Boolean | IntegerString | DecimalString | Rational
Quantity(value, unit_id) | Range(bounds, inclusivity)
EntityRef | RecordRef | PropositionRef
TemporalExpression | SpatialExpression
Enum(definition_id, key) | Sequence | StructuredValue(definition_id, fields)
```

Exact integers and decimal quantities are encoded as strings at the JSON boundary when precision may exceed host-language number handling. Preserve original author precision and display units. Conversion requires an explicit compatible unit definition. Monetary units in the fiction are setting data, not live external exchange rates.

Reject NaN, infinity, impossible rational denominators, ambiguous numeric coercions, and unit-incompatible arithmetic. Do not turn “about ten days” into a probability distribution or exact ten-day duration without an author definition.

Optional data has explicit states. An omitted time boundary is not automatically negative or positive infinity. Distinguish unknown boundary, unbounded interval, exact boundary, and approximate bounds.

### 5.4 Names, identity, and deduplication

Contextual names carry language, community, time, and optional role. Preserve original Unicode spelling; maintain a separate normalized search form. Normalization helps search, not identity assignment.

Ambiguous lookup returns candidates. The service must not merge records or choose an identity based solely on fuzzy similarity. Creating an existing name is permitted unless an explicit uniqueness rule applies to that context.

Entity merge is a privileged, previewed revision with redirected references and retained aliases. It must be reversible through a new revision. A clone, impersonator, body, role, or alternate-continuity counterpart is not a duplicate by default.

### 5.5 Definitions are versioned data

A property definition declares allowed subjects, value shape, units, multiplicity, semantic relations, and persistence behavior. Inverse, symmetric, transitive, or exclusive behavior is opt-in. Typical population characteristics are not universal individual assertions.

Starter definitions use a reserved namespace; author definitions use an author namespace. Agents can propose schema additions but cannot silently redefine built-ins or relax constraints. Template upgrades are explicit migrations with a diff and affected-record validation.

A field displayed in a desktop form is a view of an assertion when it carries continuity meaning. Do not keep an independently editable `current_location` or `current_owner` field that can drift from the assertion history.

### 5.6 Universe, world, and narrative hierarchy

```text
Author library (installation catalog, not fictional canon)
  Universe “The Ashen Cycle” [stable UniverseId]
    Shared rules, entities, sources, and definitions
    Worlds: “Aster”, “Nacre”, ... [stable WorldIds]
    Realms, space, and other locations not forced into one world
    Continuities and their universe-wide revision histories
    Narrative works: novels, stories, other works
    Sagas/series: memberships and ordering across works
  Universe “The Glass Archive” [different stable UniverseId]
    Worlds: “Aster”, ... [different WorldId, even with same name]
```

Worlds and narrative works are parallel associations beneath the universe, not a mandatory `universe → world → book` tree. One novel can visit several worlds; several novels and sagas can share one world. A saga can span worlds and contain several works, and a work can participate in more than one named grouping where authored. No manuscript text editor is introduced.

The product's universe is an editorial/container namespace, not a claim that its fictional cosmology contains exactly one physical cosmos. A world can represent a planet, inhabited domain, simulation, or another authored setting type. Realms, planets, and worlds do not automatically become identical records. A fictional multiverse can be modeled **inside** one project universe when shared canon is required.

### 5.7 Record ownership versus world applicability

Every canonical identity has `universe_id`. Do not add a mandatory single `world_id` foreign key to every entity, source, work, rule, or event. Use typed, qualified relationships and scope expressions to represent world association, location, origin, and applicability. Shared entities and unplaced entities remain valid universe records.

Assertions and rules explicitly distinguish universe-wide applicability, selected-world applicability, conditional applicability, and unspecified applicability. Storage under a universe does not by itself make an assertion true on every world. A world selector is not an implicit authorial assertion about a record's home or location. Names, constraints, scope expansion, and cross-world writes are specified in §36.

<a id="section-6"></a>

## 6. Storage and revision design

### 6.1 Universe package

```text
ExampleUniverse/
  manifest.json              Format version and stable universe identity; no access secrets
  universe.sqlite            All worlds, shared canon, works, and editorial history
  blobs/sha256/<digest>      Immutable source and media content
  derived/                   Disposable indexes or cached exports, if needed
```

Install-wide profiles, credentials, socket metadata, and access grants live outside exportable universe packages. Importing a universe must not import authority to run tools or broaden filesystem access.

One database/transaction namespace covers **all worlds in the universe**. Do not partition canon into independent world databases or world-specific revision heads. Whole-universe backup/restore is the recovery unit; exporting selected worlds is a dependency-checked partial interchange export, not an independently restorable universe backup.

### 6.2 Database organization

Use a hybrid design: normalized structural tables plus immutable, schema-validated record payloads and typed query projections. Do not build an untyped key/value encyclopedia.

| Tables/projections | Key purpose |
|---|---|
| `universes`, `record_identities` | Stable universe identity and universe-scoped record identity/kind. |
| World records, `world_name_reservations`, world-scope indexes | Named world identities and non-rebinding selector reservations; effective names/applicability resolve at a pinned revision. |
| Narrative records and membership indexes | Works, sagas/series, versions, and multi-world/multi-work associations; no separate manuscript store. |
| `record_versions` | Immutable typed payload, schema version, digest, and record identity. |
| `commits`, `commit_changes` | Editorial parent, author principal, reason, record-version additions/replacements/tombstones. |
| `continuities` | Current head and pinned inheritance baseline. |
| `head_membership` | Effective record-version map for each continuity head; reproducible from commits. |
| `record_reference_index` | Universe-scoped typed references extracted from immutable record versions. |
| `assertion_index`, `participant_index`, `time_index` | Indexed query access by predicate, entity, scope, and temporal frame. |
| `source_versions`, `anchors`, `blob_refs` | Version-specific provenance and reachable assets. |
| `changesets`, `changeset_versions`, `approvals` | Proposal lifecycle and exact approved payload. |
| `validation_runs`, `findings`, `dependencies` | Bounded results, evidence, coverage, and invalidation basis. |
| `operation_receipts`, `idempotency_keys` | Durable retry and recovery behavior. |
| FTS indexes | Names, descriptions, and approved searchable text; never independent canon. |

`record_versions` is authoritative for domain payloads. Extracted indexes and head membership are projections with schema-checked rebuild tests, not a second source of meaning. Foreign keys and composite universe/record keys protect structural references; the service handles semantic invariants.

Enable and verify foreign-key enforcement on every connection. At startup and in release verification, inspect the actual SQLite library version and compile options. Require SQLite 3.51.3 or later containing the WAL-reset fix, or an explicitly reviewed fixed backport; do not infer safety solely from a Rust crate version. The official WAL page identifies the affected/fixed versions. [R10] Use a bundled SQLite build with the required extensions; pin its exact patched version in the release manifest. SQLite documents both explicit foreign-key configuration and FTS5 support. [R12, R13]

### 6.3 History strategy

Use immutable record versions and an append-only editorial commit log. Fictional events are ordinary domain records. Do not require every application operation to be reconstructed through a general-purpose event-sourcing framework.

Within one continuity, use a linear editorial parent chain for the first release. A new continuity pins an exact parent snapshot. Its inherited records are resolved from that snapshot plus explicit overrides/tombstones. Later edits to the parent do not automatically flow into the child.

Materialize head membership and cache selected historical snapshots. Avoid replaying the entire project on every read, but preserve the ability to verify projections from immutable records.

A restore that replaces damaged local files is a maintenance operation. An author's “undo” is a new compensating canon revision with impact validation. It is not a destructive history rewind.

### 6.4 Transactions and durability

Use WAL mode, a single serialized writer per universe, bounded write transactions, and a documented busy timeout. Set the durability policy explicitly rather than relying on unknown defaults. For author data, start with `synchronous=FULL` and benchmark before changing it.

SQLite WAL allows readers alongside a writer but only one writer at a time, and its shared-memory design is unsuitable for network filesystems. Long read transactions can delay checkpointing. [R10]

An application-level revision handle is not an open SQLite transaction. Materialize the immutable revision view and close database read transactions promptly. Never leave a database transaction open while waiting for an LLM or an author.

### 6.5 Blob atomicity

Stage a blob into a controlled temporary path, enforce size/type limits, compute its digest, flush it, then atomically rename it into the content store before committing the database reference. A crash may leave an unreferenced blob; it must not leave a committed reference to unwritten content.

Garbage collection considers all retained revisions, proposals, exports, and backup manifests. A blob absent from the latest head may still be needed by history.

<a id="section-7"></a>

## 7. Temporal, spatial, and state semantics

### 7.1 Separate clocks and orderings

Represent fictional time, personal experienced sequence, narration time, narrative position, and editorial time separately. Each temporal expression identifies its calendar/reference system and applicable local domain; two worlds in one universe do not automatically share clocks or a comparable “now.” Recurring display labels such as “Day 3” are not unique moments in a loop; use separate occurrence IDs and iteration/realm context.

Start with exact instants, explicit intervals, durations/ranges, relative ordering, and named temporal reference systems. Use half-open intervals `[start, end)` where exact interval algebra applies. The author-facing display must explain boundary meaning.

Relative constraints can establish `before`, `after`, `during`, or `overlaps` without inventing a date. Queries distinguish definitely before, definitely after, overlapping, and indeterminate. Strict-before cycles in one declared acyclic ordering are invalid; a fictional time loop is modeled in a separate ordering or with distinct occurrences, not by silently tolerating a contradictory strict-order graph.

### 7.2 Persistence and state

Property definitions declare one of: explicit validity interval, persistent-until-explicit-change, instantaneous observation, condition-dependent, or unspecified persistence. Do not carry weather or fatigue forward simply because ownership usually persists.

An observed state and an established transition are different. Learning that an object is in a room does not prove how it arrived. Approved off-page events can fill transitions; absent depictions cannot automatically prove a continuity error.

A state query returns supported assertions, their validity, provenance, and unresolved alternatives. State projections must not manufacture a single value when multiple values remain possible.

### 7.3 Events

Events have occurrence mode, time frame, participants with roles, preconditions, effects, and evidence. The detailed effect-to-assertion contract is in §§27.5 and 31.4; it prevents two independently writable state models. A plan or hypothetical is not an actual occurrence, even when its existence as a plan is canon.

Preconditions are evaluated against the pre-event state. Effects are applied atomically to the candidate post-event state. Within-event sequence is explicit when necessary; no reliance on record insertion order.

An event template describes permitted transitions. It does not autonomously simulate the universe or invent intermediate events. A prophecy may be recorded without causing its predicted outcome.

### 7.4 Space

Start with qualitative containment, adjacency, connectivity, optional coordinates and distances, route conditions, and declared exclusivity/disjointness. Overlapping jurisdictions or cultural regions are not containment errors.

Ownership, custody, containment, control, occupancy, legal access, physical access, and knowledge of an entrance are separate predicates. Do not hard-code that every person has one body or every actor can occupy only one place.

Travel validation uses only defined mode, route, time, access, and capability information. Unknown speed or unresolved route availability yields indeterminate—not a guessed travel time. In v1, evaluate explicit routes and simple bounded graphs, not continuous physics or navigation simulation.

Cross-world journeys and communication use explicit endpoint worlds/locations, local reference systems, and authored ordering or conversion relationships. Unknown cross-world simultaneity remains unresolved. A universe-wide revision is an editorial snapshot, not a universal fictional clock. Objects and characters retain one identity during travel; crossing does not create copies or imply teleportation, observation, or knowledge.

### 7.5 Advanced temporal coverage

Custom calendar labels and definitions can be stored before every conversion system can be evaluated. Cross-realm conversions, time dilation, paradox reasoning, nonstandard geometry, and complex recurrence need explicit capability IDs. Unsupported semantics must survive import/export but return `unsupported` when a validation depends on them.

<a id="section-8"></a>

## 8. Truth, knowledge, completeness, and boundaries

### 8.1 Evidence outcomes

For a proposition in an explicit frame, maintain independent support and refutation evidence:

| Support | Refutation | Evidence outcome |
|---|---|---|
| Present | Absent | Supported in the evaluated frame. |
| Absent | Present | Refuted in the evaluated frame. |
| Present | Present | Conflicting evidence; do not select a winner implicitly. |
| Absent | Absent | Not established in this frame. |

These are evidence outcomes, not universal philosophical truth labels. Objective-universe author definitions, in-world accounts, and character attitudes are evaluated in their own contexts.

Do not use “anything follows from a contradiction.” An accepted unresolved conflict must remain local to the relevant assertions. Unrelated queries remain usable.

### 8.2 Completeness

Completeness is an explicit, versioned record over subject, predicate/collection, continuity, time, and scope. It may apply to objective reality or only to an observer's known set.

A complete empty sibling set establishes no siblings in its scope. An empty search result does not. An inventory complete yesterday is not automatically complete today. A list complete for one room does not cover an entire building.

Adding a member to an exhaustive list at the same time and scope is a proposal to change the complete set, not automatically an impossible fictional event. Validate whether the author permits changing that definition and whether it contradicts other fixed facts. Historical acquisition at a later time is a different case.

### 8.3 Knowledge and belief

Use explicit observations, transmissions, receptions, interpretations, memories, and disclosures. Being present does not establish seeing; receiving does not establish reading; reading does not establish understanding or believing.

Knowledge availability checks can detect an explicitly contradicted knowledge claim or a missing acquisition basis. They cannot infer a psychological certainty from sparse records. Store nested beliefs as proposition references with bounded depth; cycles and excessive nesting must not cause nontermination.

Author-known truth, character perspective, and reader disclosure are separate views. Author permissions are a security dimension; character knowledge is fictional data. A point-of-view filter is not an access-control mechanism unless the author explicitly configures a restricted principal.

### 8.4 Creative boundary resolution

Supported boundary modes: `fixed`, `open_with_constraints`, `proposal_required`, `author_reserved`, `intentionally_unresolved`, and `prohibited`.

Evaluate all applicable boundaries. For constraints that can coexist, apply their intersection. A more permissive local boundary must not silently override a stricter ancestor. Overriding one requires an explicit, authorized exception that names the affected boundary and exact scope. Conflicting boundary definitions return an issue and block delegated direct commit.

An undefined area defaults to proposal-required, not automatic permission to invent. Authors may grant broader creation authority explicitly.

Separate universe-content restrictions from application grants. “Anyone may invent local tavern names” as universe metadata does not itself authorize a new MCP principal to write.

<a id="section-9"></a>

## 9. Validation engine

### 9.1 Result dimensions

A validation result must contain separate fields for:

- Evaluation outcome: conflict found, no conflict found in evaluated scope, or indeterminate.
- Execution coverage: complete, partial, failed, cancelled, or unsupported.
- Canon state: existing approved data versus a proposal or hypothetical.
- Authorization state: permitted, requires author approval, or denied.
- Evidence/definition gaps and skipped checks.

Do not publish a single `valid: true` flag that hides these distinctions. A completed check can be indeterminate because the universe itself is underdefined. A conflicting result can still be partial because other checks were not evaluated.

### 9.2 Validation stages

| Stage | Work | Failure behavior |
|---|---|---|
| Structural | Parse typed values; validate IDs, references, schemas, limits, and universe isolation. | Invalid input; never commit malformed records. |
| Frame resolution | Resolve continuity, revision, realms, time, and perspective. | Require explicit disambiguation or return frame indeterminate. |
| Rule applicability | Enumerate applicable definitions, constraints, boundaries, and authorized exceptions. | Missing or unsupported applicability is reported, not skipped invisibly. |
| Candidate state | Overlay the proposed changes on the pinned revision. | No canonical mutation occurs. |
| Temporal/state checks | Evaluate overlap, exclusive values, prerequisites, explicit transitions, and resources. | Produce concrete evidence or indeterminate conditions. |
| Knowledge checks | Evaluate explicit knowledge claims and acquisition/disclosure constraints. | Distinguish contradiction from missing support. |
| Impact checks | Check affected existing facts/events/rules, not only the new facts. | Return impacted IDs and unresolved dependencies. |
| Permission and commit policy | Check current authority and required approvals. | A compatible change may still be denied or require approval. |

### 9.3 Rule kinds and policy effects

| Kind | Meaning | Default behavior |
|---|---|---|
| Structural invariant | Invalid record shape, foreign-universe reference, corrupt revision relationship. | Always blocks commit; no author waiver. |
| Physical/metaphysical constraint | Cannot occur under the established rules and scope. | Blocks delegated commit unless a valid scoped exception or authorized canon revision resolves it. |
| Operational requirement | A specified action/outcome requires defined prerequisites. | Missing prerequisites are indeterminate; disproved prerequisites conflict. |
| Law, duty, social norm | Actors may violate it. | Record a normative departure, not physical impossibility. |
| Behavioral tendency | Typical rather than universal behavior. | Advisory characterization concern only. |
| Authorial restriction | Controls permitted additions or revisions. | Enforced by scope and authorization. |
| Descriptive or unsupported rule | Stored but not executable by this evaluator. | Report unsupported coverage; never imply enforcement. |

Severity, commit-blocking policy, and semantic type are distinct. An author can deliberately retain a fictional inconsistency with a scoped decision, but cannot waive database integrity or let an agent approve its own permission escalation.

### 9.4 Initial executable rule language

Use a versioned, declarative JSON expression tree, compiled and type-checked before activation. Include:

| Operator family | v1 semantics |
|---|---|
| Equality and inequality | Typed values with defined exact or interval comparisons. |
| Numeric comparisons | Unit-compatible quantities and explicit uncertainty ranges. |
| Boolean composition | `all`, `any`, explicit negation with unknown/conflict propagation. |
| Temporal relations | Exact/interval/relative predicates with indeterminate results when unresolved. |
| Membership and cardinality | Finite sets; negative/cardinality conclusions require completeness. |
| Existence | Positive evidence from explicit matches; missing matches alone do not prove absence. |
| References and roles | Bounded traversal of declared relationships. |
| Preconditions and effects | Explicit pre-state requirements and atomic proposed post-state changes. |
| Exception application | Named rule, applicable scope, validity, and authorizing decision. |

Use finite, bounded binding domains. Exclude arbitrary user functions, SQL, shell calls, regular expressions with uncontrolled cost, unrestricted recursion, and general theorem proving. Do not implement negation-as-failure over incomplete universe data.

Derived facts are query-time or cached results with a derivation chain. They become independently authored canon only through a separate authorized decision. Changing a premise invalidates dependent derivations.

### 9.5 Soundness and coverage policy

Unknown antecedents do not make an implication “pass” for the purpose of author reassurance. They make applicability or compliance indeterminate. Distinguish “not applicable with established evidence” from “possibly applicable but unresolved.”

Bound graph visits, variable bindings, nesting, result size, and runtime. Hitting a bound returns a partial result with the exhausted limit and resume/job information, where supported. Budget exhaustion never converts to success.

The evaluator must enumerate all applicable hard checks within its declared scope. Search ranking, embeddings, and context-window budgets must not decide which hard rule exists.

### 9.6 Impact analysis and invalidation

Track positive record dependencies and query-scope dependencies. A conclusion based on no matching fact, a cardinality count, or an exhaustive set can change when a new record appears—even if it did not previously depend on that record ID.

For v1, use conservative revision-based invalidation: a new continuity head invalidates head-based cached validations. For bounded commits, re-enumerate applicable rules for touched predicates and scopes. A rule-definition, calendar, boundary, or completeness change may require a full-scope job.

Do not introduce fine-grained incremental validation until it passes parity tests against full reevaluation. When a reliable affected set cannot be established, broaden the scan or explicitly decline complete impact coverage.

### 9.7 Durable findings

A finding includes rule ID/version, affected records and source anchors, the frame examined, evidence, missing information, category, severity, and evaluator version. An intentional resolution names a particular finding fingerprint and scope.

A finding resolution must not suppress a materially different future problem. Reopen or create a new finding when its evidence, rule, scope, or candidate changes.

<a id="section-10"></a>

## 10. Proposal, approval, and commit protocol

### 10.1 Changesets

Every mutation goes through a changeset, whether initiated by an author or agent. The author UI may execute a simple edit in one interaction, but the service still creates the revision, runs the relevant checks, and records the authority.

Changesets include a base canon revision, author/agent principal, rationale, operation list, sources, temporary ID mappings, and expected affected-record versions. The service assigns persistent IDs and actor attribution.

Use domain operations rather than unrestricted JSON Patch:

```text
create_entity          add_name              add_type_membership
assert_proposition     supersede_assertion   retract_assertion
record_event           revise_event          end_assertion_at
add_belief
define_property        define_rule           add_exception
set_completeness       set_creative_boundary add_source_anchor
record_issue_decision  tombstone_record
```

Definition, boundary, exception, identity-merge, purge, and access-grant operations need stronger permissions than ordinary detail creation. Future domain-specific convenience tools compile into the same operations.

### 10.2 Lifecycle

```text
Draft → Submitted → Committed
   └──────────────→ Rejected / Withdrawn

Authority to commit: current scoped grant OR exact author approval.
Validation freshness and approval validity are independent of lifecycle.
```

Validation freshness is metadata, not a permanent truth about a lifecycle state. Editing a submitted proposal creates a new proposal revision and invalidates any approval of the old content. A proposal with an approval can require revalidation and renewed approval after the canon changes. “Approved” may be a derived display label; it must not bypass binding checks.

Proposals may be stored while incomplete or conflicting, with their findings attached. Structurally invalid imported payloads remain in a staging/error record, not the typed canon tables.

### 10.3 Default authority modes

| Mode | Allowed behavior |
|---|---|
| Research | Read authorized definitions and run bounded checks. |
| Collaborator | Research plus create/update proposals. No canon commits. |
| Scoped editor | Commit within explicitly granted entity/predicate/continuity boundaries and policy. |
| Author administration | Approvals, policy changes, privileged revisions, merges, backup/restore, and purge. Not exposed to default agent tools. |

The presence of an MCP tool or a host-side confirmation does not establish universe-level authority. The service rechecks the grant on every call. Tool annotations are metadata, not security controls. MCP itself warns that annotations require a trusted source. [R03]

### 10.4 Atomic commit sequence

1. Authenticate the transport principal and check current project access.
2. Look up the durable idempotency receipt. A completed matching request returns the original result. Reusing a key with a different payload is rejected.
3. Load the immutable proposal revision and expected base revision.
4. Validate the candidate and compute its impact against that revision outside a long-lived write lock.
5. Acquire the per-universe authorization/commit gate and begin a short write transaction. Recheck the actual head, current policy/grants, proposal revision, exact validation binding, and approval binding. Grant changes and commits use the same gate so revocation cannot race the final authority check even when local grants are stored outside the universe database.
6. If any binding changed, abort with a conflict or revalidation-required result and release the gate. Do not silently rebase.
7. Append immutable record versions, the editorial commit, head projections, provenance, approval/decision references, and the operation receipt atomically.
8. Commit and release the gate. Only then publish the success response and invalidate revision-dependent caches.

An approval binds at least: universe, continuity, base revision, proposal ID/version/digest, relevant boundary/schema/rule revision, approval scope, author principal, and expiry/revocation policy. A validation run similarly binds its evaluator version and coverage. Changing the validator invalidates previously cached executable conclusions unless an explicit compatibility rule proves otherwise.

### 10.5 Conflicts and retries

Initial concurrency policy: coarse optimistic concurrency at the continuity head. Two agents can draft from the same revision, but after one commits the second must rebase explicitly and revalidate. This is intentionally conservative and avoids lost updates and predicate-level phantom conflicts.

Idempotency keys are scoped to principal, universe, and operation kind. Store the canonical payload digest and original result. Check current access before disclosing old receipts. Preserve a non-reusable key tombstone when detailed receipt retention ends.

Cancellation before commit causes no canonical mutation. Cancellation after commit cannot reverse it; the receipt still reports the committed revision. A client timeout means unknown delivery status, not proof of failure. Clients query the operation receipt before retrying with a new key.

### 10.6 Accepted uncertainty and overrides

The author may explicitly accept a scoped unresolved issue or intentional inconsistency. That decision is itself data, including what remains unchecked. It does not relabel the validation as passed or weaken the general rule everywhere.

Direct-agent commit requires the checks mandated by its grant to complete. Broad delegated permissions may allow recording underdefined descriptive facts, but cannot manufacture approval for prohibited changes or hide unsupported evaluation.

<a id="section-11"></a>

## 11. MCP tool contract

### 11.1 Compatibility strategy

The documented integration routes are LM Studio's built-in MCP host, its native chat API using configured MCP integrations, and a custom application that executes tool calls around the model API. Native API integrations require the documented settings; an OpenAI-compatible inference call is not by itself a tool executor. [R01, R02]

Use local stdio for the initial MCP interface. Streamable HTTP is a later optional adapter, not a prerequisite for local multi-client use. MCP defines both transports. [R03, R09]

Use the SDK's supported negotiation and backward compatibility paths, and record the actual host/SDK/protocol combination in tests. Do not require the newest lifecycle, subscriptions, tasks, resources, elicitation, or sampling for the base workflow. Current and older MCP lifecycles differ; compatibility is a test requirement, not a version-number assumption. [R04, R09]

### 11.2 Initial tool surface

**All domain tools require `universe: string`, an exact author-facing universe name.** A matching optional `universe_id` may guard against name mistakes; it never replaces the name. The service resolves the name and checks authorization before resolving any context or record ID. The following table lists additional arguments; no row creates an exception to that requirement.

| Tool | World selector | Principal arguments and result |
|---|---|---|
| `universe_describe` | Conditional | Describe the selected universe, accessible continuities, worlds, schemas, and limits. Never enumerate other universes. |
| `universe_open_context` | No | Resolve/pin the universe revision and frame. No current/default world is stored. |
| `universe_search` | Yes | Find authorized candidates in the universe or focused world, with applicable shared material and labeled dependencies. |
| `universe_get` | Yes | Read exact effective records. Explicit IDs inconsistent with world focus receive a scoped result/error, never another identity. |
| `universe_get_state` | Yes | Evaluate state within the pinned temporal frame; world focus never erases relevant incoming/outgoing transitions. |
| `universe_get_context` | Yes | Assemble research context including applicable universe-wide rules and necessary authorized cross-world dependencies. |
| `universe_validate` | Conditional | Validate inline candidates with declared focus, or the entire immutable proposal footprint. A proposal cannot be partially validated through a world filter. |
| `universe_propose` | Conditional | Create/revise explicit local or cross-world changes. World-local creation requires authored scope/association; the selector never fills missing canon facts. Submit/withdraw use the stored footprint. |
| `universe_get_proposal` | No | Read the exact whole proposal, changed worlds/shared definitions, impact, and authorization requirements. |
| `universe_get_impact` | Conditional | Return the complete authorized dependency impact or explicit restricted/partial coverage, not only the selected world. |
| `universe_commit` | No | Commit the entire authorized universe changeset atomically. Reject filters and caller-supplied approval flags. |
| `universe_get_operation` | No | Read/recover the operation or receipt in the supplied universe. An operation ID cannot select another universe. |
| `universe_cancel_operation` | No | Request eligible cancellation in the named universe; never infer scope from the handle or undo committed canon. |

`world: string` is accepted only by the commands/actions marked Yes or Conditional. Its exact name resolves inside the already selected universe and requested canon frame. A `world_id` guard requires `world`. Closed schemas reject world filters for lifecycle operations whose immutable objects already define their complete scope.

`universe_describe` can list worlds **inside the explicitly selected universe**, not all universes. The author UI/administrative CLI supplies universe creation, selection, and global library browsing. An agent is given the universe name by the author or external application; that application must still serialize it into every call. No `universe_list_all` or wildcard-universe data tool is part of this surface. MCP protocol negotiation, `tools/list`, and health checks are protocol metadata operations, not domain tools exposing universe data.

Definition discovery uses `universe_describe`, `universe_get`, and `universe_search`; world and narrative creation use typed operations inside `universe_propose`. Do not add hundreds of tools for individual categories. Optional future resources use universe-qualified immutable URIs and the same authorization boundary; tools remain the compatibility path.

### 11.3 Frame handling

A context handle pins the stable universe ID, continuity, canon revision, represented context, temporal query/reference systems, and perspective. It does **not** store a hidden current-world selection. World focus is per supporting request. An omitted world means no individual-world narrowing within the pinned frame and current permissions, including universe-wide, shared, and unassigned material.

Every call supplies the named universe, resolves it under current authorization, and compares it with every supplied context, proposal, validation, record, cursor, and operation namespace before use. Context IDs and opaque object IDs never substitute for the required universe field. Reject a mismatch; never switch to the handle's universe or search other universes for a matching ID.

Expired/unknown handles return recoverable errors. The caller cannot change continuity, revision, time, or perspective by adding fields inconsistent with a handle. A call with a new world focus can reuse the same universe-level context, but must name that world explicitly each time. Responses echo stable universe identity, matched selector metadata, pinned canon frame, and the resolved per-call world scope. See §36 for aliases and scope expansion.

### 11.4 Request and response schemas

Use short descriptions, closed object schemas, shallow argument structures, documented enums, and copyable examples. Server-side validation remains strict even when the model ignores the schema. The server must not silently convert a guessed name into an identity or a malformed date into an approximate one.

Share the Rust boundary types through `universe-protocol` and generate JSON Schema from that authoritative contract. The Dioxus desktop consumes those types through `universe-client`; it needs no TypeScript DTO generation. Test both serialization and schema examples, including older supported IPC versions. Keep application contract versions separate from MCP protocol and database versions.

MCP supports structured tool results and output schemas, with text serialization for backward compatibility. Return one canonical JSON object and an equivalent text form for hosts that need it; test whether each host duplicates these in model context before enabling larger payloads. [R03]

### 11.5 Example validation result

This conceptual result uses symbolic IDs. It illustrates identity/scope and coverage, not a production-generated schema instance:

```json
{
  "contract_version": "1",
  "request_id": "req_example_42",
  "universe": {
    "id": "unv_ashen_cycle",
    "name": "The Ashen Cycle",
    "matched_name": "The Ashen Cycle"
  },
  "context": {
    "continuity_id": "cont_main",
    "canon_revision": "rev_42",
    "time_frame_id": "before_event_18",
    "perspective": "author"
  },
  "world_scope": {
    "kind": "world_focus",
    "world_id": "wld_aster",
    "world_name": "Aster",
    "dependency_expansion": "applicable_shared_and_cross_world"
  },
  "result": {
    "outcome": "indeterminate",
    "execution_coverage": "complete",
    "input_coverage": "submitted_structured_claims_only",
    "universe_completeness": "not_assessed",
    "checks_evaluated": 7,
    "conflicts_found": 0,
    "unsupported_checks": [],
    "missing_information": [
      {
        "predicate_id": "travel:route_access",
        "subject_id": "iven",
        "reason": "No applicable route-access assertion or exhaustive route set."
      }
    ],
    "canon_changed": false,
    "validation_run_id": "validation_93"
  },
  "pagination": { "truncated": false, "next_cursor": null }
}
```

Complete execution does not mean that this universe, or the selected world, contains sufficient information. It means the declared checks finished and explicitly reported the gap. Omitted `world` is reported as `world_scope.kind = "universe"`, not the first world in the package.

### 11.6 Error taxonomy

| Code | Caller action |
|---|---|
| `INVALID_ARGUMENT` | Correct typed input; includes field path and expected form. |
| `AMBIGUOUS_REFERENCE` | Choose an authorized candidate explicitly; never use fuzzy routing. |
| `UNIVERSE_REQUIRED` | Supply a nonempty universe name; no context/profile/default fallback. |
| `UNIVERSE_ID_MISMATCH` | Correct the name/ID guard; emitted only when both are safely disclosable, otherwise generic inaccessible result. |
| `UNIVERSE_SCOPE_MISMATCH` | A handle/reference conflicts with the explicitly selected authorized universe; never auto-switch. |
| `WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE` | The named world is absent from this accessible universe/revision; never search another universe. |
| `WORLD_SCOPE_CONFLICT` | The requested world focus/write envelope conflicts with explicit targets or effects. |
| `NAME_UNAVAILABLE` | Select another administrative name or resolve a duplicate/alias through author controls; disclose no hidden owner. |
| `NOT_FOUND_OR_NOT_ACCESSIBLE` | Do not infer whether a restricted record exists. |
| `CONTEXT_EXPIRED` | Open a new context; do not silently switch revision. |
| `BASE_REVISION_CONFLICT` | Inspect diff, explicitly rebase, and revalidate. |
| `APPROVAL_REQUIRED` | Present the proposal to the author; do not retry with a fabricated approval field. |
| `APPROVAL_STALE` | Review the changed proposal/canon/policy again. |
| `IDEMPOTENCY_KEY_REUSED` | Recover the original operation or use a genuinely new request key. |
| `UNSUPPORTED_SEMANTICS` | Preserve the data; report the unsupported capability. |
| `EVALUATION_LIMIT_REACHED` | Retrieve partial output/job status; no pass claim. |
| `POLICY_DENIED` | Stop that mutation path. |
| `STORAGE_FAILURE` | Preserve input and use diagnostics/recovery; no success claim. |
| `MAINTENANCE_REQUIRED` | Wait for explicit maintenance completion; no alternate writer. |

Use protocol errors for malformed/unroutable MCP messages and tool-visible errors for valid tool requests that cannot complete. A successful validation that finds a fictional contradiction is a successful tool execution with findings, not a protocol failure. [R03]

### 11.7 Bounded operations

Initial limits are configurable acceptance defaults, not established performance results:

| Limit | Proposed default |
|---|---|
| Search page | 25 items; maximum 100. |
| Record batch | 50 IDs. |
| Proposal batch | 100 domain operations or 1 MiB of structured input, whichever first. |
| Research brief | 24 KiB serialized canonical payload by default; 256 KiB hard cap. |
| Nested belief depth | 8. |
| Rule expression depth | 32. |
| Rule AST nodes | 1,000 per rule. |
| Relationship expansion | 3 hops by default; explicit bounded maximum 6. |
| Interactive evaluation | Target 2 seconds of engine work; larger work becomes an explicit job. |

These are engineering starting points to benchmark, not claims that all authors' universes fit them. A byte budget is not an exact tokenizer budget; record measured rendered token overhead for each tested host/model.

For long validations or imports, expose application job IDs and polling through `universe_get_operation`; do not depend on a host supporting protocol-specific task features. On restart, interrupted read-only jobs become interrupted/restartable. Committed mutations remain recoverable through receipts.

<a id="section-12"></a>

## 12. Retrieval and context assembly

### 12.1 Retrieval sequence

Resolve exact IDs first, then contextual names, then lexical full-text matches. Apply universe, revision, perspective, and access filters before returning results or computing user-visible counts.

Expand directly relevant structured relationships, negative assertions, applicable rules, authorial boundaries, completeness declarations, and unresolved conflicts. Deduplicate by stable record/version IDs. Rank descriptive material only after mandatory context components are identified.

For briefs, reserve budget for constraints and unresolved issues before background lore. If mandatory context exceeds the budget, return explicit overflow/truncation and a paginated continuation. Never silently drop a hard rule to fit an attractive narrative summary.

Apply universe isolation before search, ranking, reference expansion, and snippet generation. An omitted world selector includes shared and unassigned records; do not implement it as `world_id IS NOT NULL` or as the union of only world-owned rows. A selected-world brief includes explicit universe-wide definitions and authorized cross-world dependencies needed for its focus. Unknown world applicability is returned as a relevant gap where material, not silently excluded as irrelevant. Scope filtering is not a replacement for the validator's rule enumeration.

### 12.2 Optional semantic search

Do not require embeddings for v1. A later optional local semantic index may improve discovery, but it remains a derived index keyed by source revision and embedding-model/version. The universe remains usable without it. It does not supply authoritative negative evidence or select the complete validation rule set.

Evaluate semantic retrieval against a fixture with known relevant records, including low-lexical-overlap rules. Add it only when measured retrieval misses justify the memory, latency, and dependency cost.

### 12.3 No second hidden model

The universe engine does not need its own LLM for the base contract. External agents propose structured interpretations of prose; the engine checks those interpretations and stores their evidence. Plain-text imports preserve content first, rather than pretending reliable semantic extraction happened.

A future extraction assistant must keep original text, extracted proposals, extraction source/version, ambiguity, and author decisions separate. “The model extracted this” is never enough to mark it approved canon.

World focus, universe identity, and dependency scope must not be conflated. A cross-world portal, traveling actor, or shared resource can require authorized records outside the requested world to explain a result. Such dependencies are labeled as context expansion, not silently treated as local canon. When necessary dependency data is inaccessible, use the existing generic restricted-coverage contract.

### 12.4 Cache keys and disclosure

Cache keys include stable universe ID, explicit world-ID focus or universe-scope tag, continuity, immutable revision, schema/evaluator versions, requested time/reference-system/sequence, perspective, current access-policy version, dependency-expansion policy, and query parameters. Never share an author-omniscient brief with a restricted point-of-view principal.

Restricted queries must not reveal secrets through snippets, titles, result counts, dependency IDs, or validation explanations. When checking a hidden condition would reveal privileged facts, deny or return a generic restricted-coverage result appropriate to the configured access policy.

<a id="section-13"></a>

## 13. Security and privacy model

### 13.1 Trust boundaries

Treat the external agent, all tool arguments, imported files, source passages, custom definitions, and any rendered rich text as untrusted input. Trust comes from an authenticated application principal and explicit grants, not a model saying “the author approved this.”

The application must not expose raw SQL, arbitrary paths, shell execution, generic network fetch, executable plugins, or dynamic code evaluation through its default tools. Source URIs are identifiers unless a separately authorized importer fetches them.

Grant administration is a privileged author operation. MCP profiles hold least-privilege access and cannot select an administrative principal through tool parameters. Never export credentials with a universe.

### 13.2 Local does not mean unrestricted

The service authenticates local clients, checks owner-only socket/config permissions, constrains universe access, and limits per-principal work. Connecting from the same computer is not sufficient application authorization.

At the same time, this design does not protect a database against an unrelated process already permitted to modify that database as the same OS user. An LLM host with unrestricted filesystem or shell tools may bypass this application's command layer. The secure deployment profile excludes direct write access to project files; stronger isolation requires OS sandboxing or a separate OS principal.

Similarly, once an authorized host receives universe content, this application cannot prevent the host from sending it to another service. “Offline-capable engine” is not an end-to-end privacy guarantee for every external client.

### 13.3 Rendering and import isolation

Sanitize Markdown and HTML. Disable active scripts, remote resource loading, embedded remote frames, and automatic link execution in source previews. Treat SVG and other potentially active formats as untrusted; use a safe preview or explicit inert conversion.

Do not carry Tauri-specific capability assumptions into the Dioxus implementation. Dioxus Desktop runs native Rust behind a WebView and provides a JavaScript evaluation bridge. Audit those actual entry points and keep the authenticated engine service as the authorization boundary. [R07]

Render source material as text or allowlisted inert markup; never interpolate it into RSX markup strings, scripts passed to `document::eval`, event-handler code, or unrestricted asset paths. Trusted UI code may require the framework's own bridge: disabling that bridge indiscriminately is not the security design. Restrict navigation, new windows, remote subresources, and asset access using the controls available in the pinned renderer; prove each restriction in native tests. Where a preview cannot be made inert, fall back to plain text or a reviewed raster preview. Deny remote content access to privileged application operations. CSP is defense-in-depth and must be tested with the actual renderer, not treated as complete isolation.

Archive import must reject path traversal, symlink escapes, decompression bombs, excessive entry counts, oversized data, malformed schemas, and unsupported active content. Keep staging separate from canon. Disable executable SQLite extensions and do not execute imported database schema triggers or arbitrary SQL.

Prefer the portable logical interchange format for untrusted universe packages. A native SQLite backup from an untrusted source opens only through a hardened read-only validator and is converted to the logical format before adoption; it is never installed directly as a trusted live database.

### 13.4 MCP transport security

For stdio, send only protocol frames to stdout. Send bounded diagnostics to stderr and never print tokens or full universe passages by default. Parse framed input through the SDK with input-size and concurrency limits. [R09]

For a later HTTP adapter, require explicit opt-in, authenticated principals, restrictive origin/host validation, current MCP authorization compliance for remote deployments, and a documented transport threat model. Do not expose an unauthenticated service on all network interfaces. Do not treat a protocol session ID as a permission grant. MCP's transport and security guidance discusses these concerns. [R09, R14]

### 13.5 Deletion and sensitive data

Normal deletion creates a tombstone so history remains understandable. Explicit purge is a distinct privileged maintenance workflow that explains affected revisions, sources, logs, backups, and exports.

Do not promise forensic erasure from SSDs, external backups, or previous exports. Initial storage is not application-level encrypted. Authors relying on encrypted storage must use an appropriate underlying encrypted volume; application-level encryption is a separately scoped feature with key-recovery implications.

<a id="section-14"></a>

## 14. Sources, imports, exports, and recovery

### 14.1 Evidence anchors

Each source version records source identity, content digest, import time, origin metadata, media type, and any externally asserted author attribution. Each anchor points to an immutable source version with a structural path or range and an exact excerpt/digest.

For text, preserve original bytes and record the canonical decoded representation used by anchors. Define offset units explicitly; do not mix UTF-8 bytes, Unicode code points, and frontend UTF-16 offsets. New source versions get new anchors. Quote/context matching can propose a moved anchor, but cannot silently reattach evidence to a changed passage.

Distinguish verified matching source content from agent-provided citations that the application has not seen. A source citation from an agent is not automatically verified provenance.

### 14.2 Import workflow

```text
Select/authorize source → stage → validate format and limits → preview mapping
→ propose definitions → detect identity conflicts → validate → approve/commit
```

v1 imports: native logical project archive, versioned JSON/JSONL, Markdown/plain text as source material, and bounded media attachments. A delimited-table mapper can follow after the logical import path. Direct PDF/DOCX semantic extraction is not required for v1; external hosts may submit excerpts with source references.

An imported encyclopedia remains source material until its asserted definitions are mapped and accepted. Do not create canon merely because text uses confident wording.

On conflicting IDs or names, choose an explicit mode: restore the same universe, clone with a new universe namespace, or merge through reviewed changesets. Never silently overwrite an existing universe or copy access grants.

### 14.3 Portable export

The interchange archive includes a versioned manifest, logical records, continuities, editorial history, sources, attachments, and content checksums. Export IDs and references without dependence on absolute local paths.

Support both a complete project export and a clearly labeled filtered snapshot. A filtered snapshot must state that it excludes history, hidden material, or unselected records; it must not masquerade as a complete backup. Excluding credentials and local grants is mandatory.

A deterministic logical export makes review and version-control use possible. Git is optional; it is not the primary storage engine or the runtime transaction manager.

### 14.4 Backup and restore

Use SQLite's Online Backup API or another documented consistent snapshot method, not a casual copy of the live main database file. SQLite documents snapshot backup while the database is active. [R11]

Backups record the captured canon heads, database/application format versions, blob manifest, and digests. Preserve blobs reachable from that database snapshot, even when the live project changes during backup.

A restore drill loads the backup into a separate directory, checks database integrity and references, verifies asset digests, rebuilds projections, and runs known queries/validations at selected revisions. “The file copied successfully” is not a backup acceptance test.

Local recovery copies protect against application mistakes, not loss of the physical device. Export to another storage location remains an author-controlled operation; do not add automatic cloud upload.

### 14.5 Migrations

Version the database schema, record schema, ontology packs, expression language, API contract, and MCP SDK independently. Each migration is transactional where possible and preceded by a verified snapshot.

Maintain golden projects from every supported release. Upgrades must preserve IDs, provenance, unresolved states, boundaries, and historical query results except where the migration explicitly documents a semantic correction. Unknown future versions open read-only or are rejected safely; never attempt a guessed downgrade.

When an evaluator bug is fixed, preserve old validation runs for audit, mark their engine version, and revalidate rather than altering past reported results in place.

<a id="section-15"></a>

## 15. Author desktop interface

### 15.1 Required workspaces

| Workspace | Required behavior |
|---|---|
| Universe library/setup | Create/select/rename named universes, show stable identity, manage packages, select starter packs, define baseline/boundaries, and connect scoped MCP profiles. |
| Worlds | Create/browse named worlds inside the selected universe; select “All universe content” or a named world; show shared and unassigned material. |
| Works and sagas | Associate novels/stories/works, versions, and saga/series memberships with the universe and any number of worlds; inspect external evidence without editing manuscripts. |
| Explorer | Search/browse entities and definitions with optional types and contextual names. |
| Entity inspector | Show facts, relations, provenance, time validity, negative facts, alternatives, and issues. |
| Timeline/state | Inspect state before/after an event or at a known/relative time; visibly label uncertainty. |
| Proposal review | Show exact additions/removals, sources, impact, conflicts, gaps, and approval scope. |
| Rules and boundaries | Edit declarative rules through typed forms; show executable versus descriptive status. |
| Issues and history | View findings, scoped resolutions, revision diffs, and compensating edits. |
| Maintenance | Backups, import/export, integrity checks, active clients, access grants, and diagnostics. |

Ship a narrow author UI early: universe selection, entity view, proposal diff, and approve/reject. Rich graph navigation and decorative maps are later features, not prerequisites for testing author control.

### 15.2 Interaction requirements

Show selected universe name/identity, the explicit “All universe content” or named-world focus, continuity, revision, and time/perspective persistently. Give proposal mode and canon mode distinct labels. Do not rely only on color, hover text, or icon meaning.

Use progressive disclosure instead of requiring every qualifier on every fact. A simple statement can start with a name and value while retaining room for temporal/evidence detail later. Do not hide default scopes; show them in a concise summary before approval.

Support keyboard navigation, screen-reader names, text enlargement, clear focus states, ordinary paragraph spacing, and undo as a previewed new revision. Use list/table views as the default, with graph views as optional aids rather than the only navigation method.

Large proposal batches must show counts and privileged changes prominently. A 100-line detail addition must not hide a boundary relaxation in the middle. Changing rules, completeness, or identity gets a separate highlighted review section.

Universe and world selections are local to each view/tab. The typed client serializes the explicit universe into every domain request; changing the visible selection cannot retarget an existing draft, approval, background job, or MCP conversation. Before approval, show the universe and the full changed-world/shared-definition footprint, even when review began from a world-filtered screen.

### 15.3 Authoring versus administration

The UI can edit notes and universe definitions, not a book manuscript. It may display an external passage for evidence but must not take ownership of the host's manuscript file lifecycle.

Permissions determine whether edits auto-commit after checks or remain proposals. A desktop shortcut is not a bypass around the service invariants.

### 15.4 Component-to-domain adaptation

Rust/UI supplies presentation primitives, not this application's universe semantics. Introduce application-owned controls for qualified values, provenance, time scopes, relationship roles, and approval review. Never let a generic form or grid turn absent input into an objective fact.

| Area | Required adaptation |
|---|---|
| Entity explorer | Stable entity IDs as keys; server-side filtering/pagination; preserve selection through reordering. Never put the entire universe's assertions into one reactive collection. |
| Fact editor | Explicit positive/negative/unset alternatives; distinguish false, zero, empty text, empty set, and unspecified. Invalid numeric input stays visible with an error; no coercion to zero or silent precision loss. |
| Time editor | Preserve fictional calendars, intervals, approximate values, and relative order. A Gregorian date picker may serve editorial dates, but must not define the universe's time representation. |
| Proposal review | Render an immutable proposal version and exact approval binding; make permission/rule changes conspicuous. Revalidate after relevant edits or canon changes. |
| Data grid | Inline edits create draft changes, not immediate canon writes. Preserve stable identity, dirty state, focus, selection, and errors through sorting, paging, and refresh. |
| Evidence viewer | Keep source-version anchors exact and markup inert. Explicitly map WebView text offsets to the service's declared units. |
| Dialogs and menus | Test focus placement, trapping/restoration where appropriate, Escape behavior, keyboard-only use, VoiceOver names, and nesting. A styled component is not automatically accessible. |
| Connection state | Distinguish loading, disconnected, stale revision, permission denied, empty results, and failed requests. Never display transport failure as an empty universe. |

One reviewed upstream grid demo uses default numeric values when parsing fails. That is demo behavior, not an acceptable universe-data conversion policy; our editor must reject invalid input without manufacturing a value. [R19]

For native-only interactions such as clipboard and file access, use reviewed platform adapters. Audit any copied `web-sys`/`wasm-bindgen` paths: a web example is not proof that the same operation works from native Rust. Dioxus's desktop documentation explicitly distinguishes native Rust from browser API access. [R07]

<a id="section-16"></a>

## 16. Domain coverage and starter packs

All supplied categories remain representable through the common model. Domain packs add names, fields, examples, and applicable rule templates—not separate silos or independent storage models. [S0]

| Supplied domain | Implementation mapping | Initial validation boundary |
|---|---|---|
| Reality, cosmology, and time | Realms, reference systems, identity/existence definitions, typed rules. | Explicit constraints; no automatic cosmological simulation. |
| Geography and environment | Regions, topology, resources, observations, conditions. | Declared spatial relations and route conditions; no inferred map physics. |
| Life, ecology, and health | Species/types, traits, populations, conditions, processes. | Typed properties and authored requirements; no real-world medical model. |
| People, minds, and identity | Agents, bodies, aliases, memberships, traits, capabilities. | Explicit facts and identity relations; personality is not deterministic. |
| Kinship, households, and populations | N-ary kinship/household/partnership relations and membership. | No binary-family or exclusive-partnership assumptions. |
| Culture and everyday life | Customs, practices, works, materials, communities, tendencies. | Normative/descriptive checks; no universal cultural inheritance. |
| Government and political power | State, government, office, assignment, jurisdiction, claims/control. | Explicit scoped authority and tenure; no collapsed nation/state/government identity. |
| Law, justice, and diplomacy | Jurisdictional rules, proceedings, treaties, obligations. | A violation can occur; physical possibility is separate. |
| Organizations and institutions | Organization structure, membership, resources, agendas. | Declared structure/authority rules; stated and actual practice stay separate. |
| Economy, resources, and work | Units/currencies, inventories, flows, production, obligations. | Exact/range quantities and explicit requirements; no autonomous economy. |
| Religion, philosophy, and belief | Doctrine propositions, institutions, narratives, attitudes. | Doctrine, believer state, and objective reality remain independent. |
| Language, knowledge, and communication | Names, languages, scripts, competence, messages, channels. | Explicit availability and knowledge; no automatic fluency inference. |
| Science, technology, and magic | Capabilities, discoveries, devices, rules, prerequisites/effects. | Declared rules and exceptions; no solving arbitrary descriptive systems. |
| Settlements, buildings, and infrastructure | Containment, connections, capacity, occupation, dependencies. | Structured topology and defined operational requirements. |
| Transportation, logistics, and security | Routes, vehicles, journeys, access, shipments, units. | Defined travel/resource conditions; uncertainty preserved. |
| Objects, art, and records | Design, work, version, copy, custody, condition, source content. | Individual versus type; statement content versus truth. |
| History, events, and processes | Occurrences, periods, event parts, effects, accounts. | Explicit ordering and effects; no automatic causal inference. |
| Intentions, knowledge, and disputed information | Plans, commitments, beliefs, observations, evidence, secrets. | Actual versus planned; incomplete and contradictory evidence supported. |
| Narrative and authoring records | External work/scene/passage IDs, viewpoints, reveals, issues. | Reference/evidence management only; no manuscript editor. |

Pack-level tests include one minimal fixture and one misleading edge case per domain. Packs declare supported evaluator capability IDs; adding a field to a form is not evidence that its meaning can be validated.

<a id="section-17"></a>

## 17. Implementation sequence and release gates

Do not build the entire encyclopedia UI first. Prove the smallest end-to-end canon transaction, then expand semantics without changing the truth/approval contract.

### Phase 0 — Contract, interoperability, and desktop feasibility proof

**Deliverables:** ADRs for the decisions above; machine-readable fixture for the silver-gate example; generated request/response schemas; one installed stdio MCP executable exposing describe/read/propose on a disposable fixture; compatibility manifest; a packaged Dioxus Desktop fixture screen using a recorded Rust/UI snapshot.

**Work:** Run the actual LM Studio desktop workflow, its configured-MCP native API workflow, and a small external client tool loop. Exercise a representative tool-capable model and a writing-oriented model, with exact configuration recorded. Test Unicode, path-with-spaces, cold launch, absent shell PATH, malformed tool arguments, cancellation, and text/structured result rendering.

**Exit:** Each supported route can retrieve a known fact, return a typed input error, and create a noncanonical proposal. No claim of support is made for an untested route/model combination. A model that cannot perform the protocol is labeled unsupported for agent use rather than weakening server validation.

**Desktop gate:** On an actual Apple Silicon Mac, install and launch the release-mode fixture, disconnected from development servers. Exercise an entity list, qualified-value form, searchable select, and proposal dialog with keyboard and VoiceOver; check CSS/assets offline. Verify clipboard/file-dialog integrations and execution of the bundled helper by absolute path. Record exact versions and source snapshots. This gate demonstrates the selected UI primitives and packaging path, not the complete universe-management workflow. Component failures are isolated and fixed/replaced before broad screen implementation.

**Fallback:** If the chosen `rmcp` release fails a host's required older lifecycle, first test a compatible pinned SDK release. If a small TypeScript adapter is necessary, replace only `universe-mcp`, not the domain engine or persistence design. Document that deviation before shipping.

The Phase 0 fixture contains at least two named universes and two named worlds in one universe. Every domain tool sample names its universe; lookup by name, optional world focus, and namespace-mismatch failure are part of the initial contract proof, not later extensions.

### Phase 1 — Durable universe kernel

**Depends on:** Phase 0 contract shape.

**Deliverables:** Identity/version store, schema registry, assertions/propositions, universe isolation, revision snapshots, changesets, idempotent commits, CLI import/export, real backups, and crash-safe writer lifecycle.

**Exit:** Seed data survives restart; historical queries are stable; interrupted writes are all-or-none; a duplicate commit creates exactly one editorial revision; export/import preserves meaning and IDs in restore mode. No unsupported direct database writes exist in the UI or adapter.

### Phase 2 — First usable author/agent loop

**Depends on:** Phase 1.

**Deliverables:** Exact/interval time, negative facts, simple cardinality/precondition rules, search/get/state, source anchors, basic boundaries, and a Dioxus Desktop explorer/proposal review screen using reviewed Rust/UI primitives and the typed service client. Apply the component-to-domain adaptations in §15.4.

**Exit:** An author defines a gate and seal, an agent proposes a change, the engine explains its conflict or compatibility, the author approves an exact proposal, and both interfaces show the same new canon revision. Denied or rejected proposals do not affect canon.

**Release:** Internal alpha. Limited semantic coverage is explicit.

The first usable author/agent loop must work both with a named world and with no world filter. It must demonstrate one shared character across two worlds and independent content in a second universe with a duplicate world name. World/novel/saga creation can remain simple forms; their scopes must already be correct.

### Phase 3 — Continuity semantics

**Depends on:** Phase 2.

**Deliverables:** Relative ordering, persistent state, event effects, knowledge/belief records, scoped completeness, distinction among rule kinds, exceptions, unresolved conflicts, impact analysis, and strict coverage reporting.

**Exit:** The semantic fixture suite in §19 passes, including false-positive tests for dialogue, myths, legal violations, incomplete route data, and misleading population traits. Full and incremental/bounded evaluation agree wherever complete coverage is claimed.

### Phase 4 — Multiple continuities and broad universe coverage

**Depends on:** Phase 3.

**Deliverables:** Pinned continuity inheritance, explicit branch diffs, custom type/property packs, all supplied domain packs as data, source-version revisions, advanced temporal capability declarations, and external narrative references.

**Exit:** A parent retcon does not alter a child continuity silently. A custom religion or technology system is representable without changing the database schema or MCP tool names. Unsupported calendar/paradox reasoning is reported correctly and survives export/import.

**Release:** Feature beta, with documentation of evaluated versus descriptive capabilities.

### Phase 5 — Security, recovery, packaging, and performance

**Depends on:** All earlier semantic gates. Security/recovery work begins in Phase 1; this is the final integrated gate, not when it is first considered.

**Deliverables:** Least-privilege profiles, sanitized previews, malicious import suite, signed native package, stable helper installation, lifecycle/update checks, workload benchmarks, restore drills, and diagnostics.

**Exit:** No known release-blocking authority bypass, silent false pass, history loss, secret disclosure through a restricted query, or acknowledged-commit loss under the specified failure model. The package works without development toolchains or outbound networking for universe operations.

**Release:** v1.0 with a published compatibility matrix and capability manifest.

### Later extensions, not hidden prerequisites

Optional semantic search, Streamable HTTP, additional desktop platforms, advanced calendar conversion/paradox evaluators, semantic three-way merges, rich graph/map interfaces, application encryption, and shared-user collaboration. Each requires its own semantics, threat model, and acceptance tests; none may silently change the base contract.

<a id="section-18"></a>

## 18. First implementation work packages

| ID | Implementable output | Dependencies | Acceptance evidence |
|---|---|---|---|
| WP01 | ADRs, invariant IDs, example universes, capability manifest, Dioxus/Rust/UI packaged fixture. | None | Fixtures define semantic outcomes; native UI gate records dependency pins and component provenance. |
| WP02 | Domain identifiers, typed values, scope, proposition and assertion types. | WP01 | Serialization round trips and rejection of malformed values. |
| WP03 | Shared Rust IPC types, generated JSON schemas, typed client interface, example validation. | WP02 | UI/MCP examples serialize and validate against one authoritative contract; IPC versions remain explicit. |
| WP04 | `rmcp` executable and transport harness using immutable test data. | WP03 | Actual LM Studio and standalone-client transcripts. |
| WP05 | SQLite migrations, immutable versions, commit/head projection, foreign-key guard. | WP02 | Restart, projection rebuild, and historical snapshot tests. |
| WP06 | Per-user service, local authentication, writer lock, status/doctor. | WP03, WP05 | Concurrent launch and stale-lock tests. |
| WP07 | Changeset versions, current grants, approvals, atomic commit and receipts. | WP03, WP05, WP06; executable-rule integration after WP08 | Stale approval, duplicate retry, and crash tests. |
| WP08 | Temporal intervals, explicit negative evidence, scalar/cardinality rules. | WP02, WP05 | Boundary-time and unknown-versus-false tests. |
| WP09 | Read/search/state/context tools backed by real store. | WP03, WP04, WP05, WP06, WP08 | No cross-universe/revision leakage; stable cursors. |
| WP10 | Source blobs, anchors, logical imports, snapshot backup/export/restore. | WP05, WP07 | Unicode anchor and restore drills. |
| WP11 | Dioxus Desktop explorer, app-owned Rust/UI components, qualified fact editor, exact proposal review. | WP01, WP03, WP07, WP09 | Author review changes nothing until commit; UI/core parity; applicable U01–U10 tests. |
| WP12 | Event transitions, knowledge, completeness, scopes, rule-kind policy. | WP07, WP08, WP10 | Silver-gate and adversarial semantic suite. |
| WP13 | Impact analysis, validation jobs, caches, coverage reporting. | WP12 | Full-evaluation parity and budget-exhaustion tests. |
| WP14 | Continuities, pack versioning, external narrative references. | WP10, WP12, WP13 | Fork isolation and round-trip source-coverage matrix. |
| WP15 | Dioxus packaging/signing, helper updates, native regression/scale/security gate. | WP04, WP06, WP10, WP11, WP13, WP14 | Clean-machine install, full U01–U10 suite, and published release/component manifest. |

Every package includes tests, error behavior, observability, and documentation. Do not treat those as cleanup after feature completion.

<a id="section-19"></a>

## 19. Semantic acceptance suite

### 19.1 Silver-gate fixture

Define these explicitly so tests do not rely on hidden assumptions:

- The gate-opening action requires the actor to physically possess the unique seal.
- The seal's physical possession is exclusive under a declared rule; ownership is a separate property.
- Mara continuously possesses it throughout the interval from Event 12 up to Event 20.
- Iven is explicitly unaware of the gate's location before Event 18; Event 18 establishes the knowledge acquisition.
- Main continuity revision R1 contains those definitions.
- A side-entrance list has independent open/exhaustive variants and an authorial-boundary variant.

Expected tests:

| ID | Input | Expected result |
|---|---|---|
| S01 | Iven opens the gate alone with the seal at Event 16. | Conflict with explicit requirement and exclusive possession. |
| S02 | Iven merely says he has the seal. | Dialogue/account assertion; no automatic custody conflict. |
| S03 | An objective submitted assertion says Iven knows the exact location before Event 18. | Conflict with explicit prior ignorance in the same frame; a spoken claim alone is not this case. |
| S04 | Iven arrives accidentally before Event 18. | No knowledge conflict solely from arrival; other travel facts may remain indeterminate. |
| S05 | New side entrance where the entrance set is not exhaustive. | New definition; boundary/approval check, not automatic contradiction. |
| S06 | Same new entrance contradicts an exhaustive fixed set. | Conflict requiring an authorized set revision or scoped exception. |
| S07 | Approved off-page transfer before the opening. | Candidate event/state can resolve possession if compatible with all affected definitions. |
| S08 | Transfer asserted while Mara's continuous possession remains fixed. | Conflict; do not silently shorten the established interval. |
| S09 | Gate rule revised to permit a new method only after Event 21. | Earlier opening remains conflicting; scope does not leak backward. |
| S10 | Retrospective narrator describes the gate during the Event 16 passage. | Use narration-time and narrator scope, not Iven's knowledge by default. |

### 19.2 Additional semantic cases

| ID | Case | Required behavior |
|---|---|---|
| S11 | No sibling records. | Unspecified, not no siblings. |
| S12 | Complete empty sibling set. | Explicit absence in that scope. |
| S13 | Complete inventory at yesterday's time only. | No completeness claim today without persistence semantics. |
| S14 | Two witnesses report incompatible outcomes. | Competing accounts, not automatically incompatible objective canon. |
| S15 | Objective assertions both support and refute a claim. | Local conflict; no arbitrary conclusion elsewhere. |
| S16 | Approved belief in a false proposition. | Belief remains canon; proposition stays false/unsupported independently. |
| S17 | Species usually has wings; individual lacks wings. | No contradiction with a typical trait. |
| S18 | Explicit universal species rule plus individual exception. | Exception is scoped and explained, not global rule deletion. |
| S19 | Character violates a law. | Normative departure, not physical impossibility. |
| S20 | Character changes behavior after a recorded experience. | Advisory characterization only unless an explicit hard constraint exists. |
| S21 | Two treaty signatories plus guarantor and beneficiary. | Correct n-ary role representation. |
| S22 | One household with several unrelated partners. | No binary-tree or exclusive-couple constraint. |
| S23 | Two offices with the same title in different states. | Distinct identities; no name-based merge. |
| S24 | Original, clone, body, and avatar share an appearance. | Distinct or related identities as authored. |
| S25 | Approximate intervals may or may not overlap. | Indeterminate, not a manufactured collision. |
| S26 | Ownership ends exactly when the new owner begins. | Half-open interval rule behaves as specified. |
| S27 | Undefined time endpoint. | Not silently infinite or zero-length. |
| S28 | Relative temporal constraints contain a strict-before cycle. | Invalid in that ordering; no silent date invention. |
| S29 | Time loop repeats a day label. | Occurrence IDs and personal sequence stay distinguishable. |
| S30 | Unknown cross-calendar conversion. | Unsupported/indeterminate with original dates preserved. |
| S31 | Proposed event has atomic interdependent effects. | Evaluate preconditions before effects; no partial post-state. |
| S32 | Planned event exists in canon. | Does not become an actual occurrence. |
| S33 | A witness is present but sensory access is unknown. | Does not acquire all event knowledge. |
| S34 | Message sent but not received. | Recipient knowledge unchanged without evidence. |
| S35 | Law applies only in one jurisdiction/period. | No global or historical leakage. |
| S36 | Cultural and political regions overlap. | Valid overlapping regions. |
| S37 | Unknown route or speed. | No invented feasibility or impossibility. |
| S38 | Object owner is not its current custodian. | Both facts coexist. |
| S39 | Work, edition, and individual copy differ. | Sources and custody attach to the correct record. |
| S40 | Figurative description says a person is “made of fire.” | No literal material assertion without an explicit submitted interpretation. |
| S41 | A rule needs an unsupported evaluator. | Stored and visible; not marked evaluated. |
| S42 | Adding a new fact changes an absence-based conclusion. | Scope dependency invalidates the old result. |
| S43 | New parent revision after a child continuity fork. | Child unchanged until explicit adoption. |
| S44 | A source passage changes but its old anchor remains. | Anchor still points to old version, not arbitrary new text. |
| S45 | An intentionally unanswered divine question. | No pressure to choose an objective answer. |

<a id="section-20"></a>

## 20. Reliability, security, and protocol acceptance suite

| ID | Failure injection | Required outcome |
|---|---|---|
| T01 | Kill process before canon transaction. | No canonical mutation. |
| T02 | Kill process during canon transaction. | All-or-none commit after restart. |
| T03 | Kill process after commit but before response. | Receipt recovers the exact committed result. |
| T04 | Retry identical request/key. | One commit and the same IDs/result. |
| T05 | Reuse key with different payload. | Explicit idempotency conflict. |
| T06 | Two agents commit from the same base. | One succeeds; the other receives a stale-base response. |
| T07 | Modify proposal after approval. | Old approval unusable. |
| T08 | Revoke write grant after validation. | Commit denied using current authority. |
| T09 | Change rule/boundary/schema after validation. | Binding stale; no silent approval reuse. |
| T10 | Cancel or disconnect during a commit. | Receipt determines outcome; no duplicate retry damage. |
| T11 | Agent supplies `approved: true` or fake author metadata. | No authority escalation. |
| T12 | Guess another universe or secret record ID. | No access or existence leakage. |
| T13 | Restricted query matches a secret's title or snippet. | Secret not returned through search metadata. |
| T14 | Validation depends on a secret for a restricted principal. | Safe restricted-coverage/denial behavior, not a revealing explanation. |
| T15 | Source content asks to delete canon or run shell commands. | Stored as content only; no action. |
| T16 | Archive path traversal, symlink escape, or zip bomb. | Rejected in staging; no out-of-root writes. |
| T17 | Oversized/deep JSON or hostile rule expansion. | Bounded rejection/partial result; service remains available. |
| T18 | Engine emits diagnostics. | No nonprotocol bytes on MCP stdout. |
| T19 | Host ignores structured results. | Text fallback conveys the same bounded outcome. |
| T20 | Host has an older compatible lifecycle. | Negotiated tested behavior or clear unsupported result. |
| T21 | Host lacks resources, subscriptions, or task support. | Base tools and polling still work. |
| T22 | Two MCP hosts cold-launch the engine simultaneously. | One service owns the universe; no split writer. |
| T23 | Desktop closes during active MCP work. | Tool operation continues or returns explicit status; no silent loss. |
| T24 | Application/helper versions disagree. | Clear version failure; no opportunistic incompatible writes. |
| T25 | Disk full during blob staging or commit. | No committed missing blob and no false success. |
| T26 | Backup while changes occur. | Internally consistent snapshot with matching reachable blobs. |
| T27 | Restore to another directory. | IDs, history, anchors, queries, and assets recover. |
| T28 | Interrupted migration. | Recoverable prior snapshot or atomic new schema; no half-migrated open. |
| T29 | Future-version universe import. | Safe refusal/read-only behavior, not guessed conversion. |
| T30 | Search or validation exceeds limits. | Explicit truncation/partial coverage, never a silent pass. |
| T31 | Cached result after changing perspective or access. | Cache miss/recheck; no leak. |
| T32 | Unicode normalization, emoji, right-to-left names, large integers. | Original values and source anchors survive round trip. |
| T33 | Projection/index deleted or corrupted. | Rebuild verifies against authoritative record versions. |
| T34 | MCP connection points at an untrusted profile path. | Profile validation and filesystem ownership checks reject it. |
| T35 | Install/run with no developer tools and network disabled. | Core workflows operate using packaged binaries. |

For transaction tests, assert database content and receipts, not only returned messages. For temporal/property tests, compare the optimized evaluator with a simple reference evaluator on generated bounded universes.

### Desktop adoption acceptance cases

These are additional specified tests, not tests executed in preparing this revision. Existing S01–S45 and T01–T35 retain their IDs and intended outcomes; S03 wording is explicitly clarified in C07.

| ID | Scenario | Required outcome |
|---|---|---|
| U01 | Package the selected Dioxus/Rust/UI dependency set and start it on macOS without a dev server or installed toolchain. | Fixture and core UI load with bundled CSS/icons/fonts; exact versions and platform recorded. |
| U02 | Navigate forms, selects, menus, and nested dialogs with keyboard and VoiceOver; enlarge text and enable reduced motion. | Controls remain named and operable; focus is visible and restored; content and errors remain readable. |
| U03 | Display at least 10,000 discoverable entities through paging/windowing; reorder and edit selected rows. | Bounded rendered records, stable IDs, and preserved draft/focus/selection; no row-index misattribution or hidden edits. |
| U04 | Enter invalid numbers, large integers, false, zero, empty text, absent values, fictional dates, and relative time. | Explicit typed outcomes; no default-to-zero, rounding, Gregorian coercion, or collapse of unspecified into false. |
| U05 | Navigate to a different universe/revision while a slow query completes. | Old response cannot overwrite the new context; revision and loading/error state stay accurate. |
| U06 | Edit a proposal or change canon while its review dialog remains open. | Exact proposal and validation bindings are rechecked; old approval cannot commit changed material. |
| U07 | Close/unmount the desktop view during a commit, then reopen it. | The engine continues independently; the receipt establishes outcome without duplicate mutation. |
| U08 | Preview malicious HTML/SVG/links and text resembling scripts or file paths. | No source-driven script, navigation, network load, privileged bridge call, or out-of-scope file access. |
| U09 | Exercise native clipboard/file access, Unicode source selection, dark theme, release CSS, and offline assets. | Native adapters behave correctly; offsets round-trip; required styles survive optimization; no CDN dependency. |
| U10 | Update a vendored component or framework/toolchain dependency; replace/restart packaged helpers. | Explicit provenance/diff, component regression and IPC-compatibility tests; signed package verification; no incompatible active writer. |

<a id="section-21"></a>

## 21. Performance and observability

### 21.1 Proposed workload fixtures

| Tier | Fixture size | Purpose |
|---|---|---|
| Small | 1,000 entities and 20,000 assertions | Interactive daily use and correctness debugging. |
| Standard | 10,000 entities, 200,000 assertions, 2,000 rules, 10 continuities | Primary v1 acceptance workload. |
| Stress | 100,000 entities and 2 million assertions, with skewed high-degree nodes | Find nonlinear behavior and exhaustion paths; not automatically a v1 support promise. |

Include long revision histories, large provenance graphs, homonymous names, many closed sets, and one high-degree organization. Uniform random data alone will miss realistic bottlenecks. The standard primary-universe fixture distributes its records across ten named worlds, with a proposed 20% shared or unassigned records; additionally load two small universes with duplicate world/entity names. Report primary-universe latency separately from concurrent multi-universe fairness and aggregate memory. These are benchmark-design assumptions, not established user content distributions.

### 21.2 Targets, not promises

On a recorded reference Mac configuration, with model inference excluded: target p95 exact lookup under 100 ms, filtered search under 250 ms, bounded state/context queries under 750 ms, and ordinary 100-operation validation under 2 seconds on the standard fixture. Measure cold and warm cases separately.

Target engine idle memory below 150 MiB and standard-workload peak below 750 MiB; report desktop/webview memory separately. These targets are provisional budgets to prevent competing unnecessarily with local inference. Do not claim they are achievable until benchmarked.

Record query plans and profiling evidence before adding a second datastore. If a target fails, optimize indexing, projection materialization, batching, and bounded traversal first. Change technology only against a documented failing workload.

### 21.3 Telemetry and diagnostics

Structured local logs include request/operation ID, principal ID, universe/continuity/revision, explicit world scope and authorized write/dependency-footprint summaries, tool name, duration, rows/bindings examined, result size, coverage, evaluator version, and error code. Full prose, secrets, credentials, and model conversations are excluded by default.

Expose a diagnostic command for engine/helper versions, SQLite version/configuration, schema status, active jobs, failed operations, lock ownership, project integrity, and MCP compatibility. Export diagnostics only on explicit author action and allow inspection/redaction.

Track false-positive and false-negative findings in the curated corpus separately from model tool-call success. No single “AI accuracy” score can substitute for both.

<a id="section-22"></a>

## 22. Build, packaging, and update plan

Pin toolchain/dependency lockfiles and application schemas. CI runs format/lint, domain tests, property tests, migration fixtures, projection rebuilds, import fuzzing, protocol compatibility, and packaging smoke tests.

Native macOS tests must run on the packaged app and helpers, not only in a browser. Test cold launch, paths with spaces, Unicode project paths, multiple hosts, close/reopen, sleep/resume, upgrade with an active project, and a revoked grant during an active context.

Bundle the engine and MCP helper so users need no Rust, Node, Python, package manager, or development directory to run them. Dioxus documents desktop bundling and asset inclusion; its bundle configuration includes extra binaries and macOS signing settings. Verify their behavior with the pinned CLI on a real release bundle rather than assuming the old Tauri configuration transfers. [R08, R15]

Build/sign/package the desktop and helpers as one release unit. Record bundle-relative executable locations, executable permissions, supported architectures, and the installed absolute MCP command path. Verify signing/notarization and launch from the installed location, including paths with spaces and a moved application bundle. Use release-only renderer/security configuration; do not ship dev servers or exposed debugging endpoints.

CI also verifies the adopted-component manifest, local patches, license notices, locked styling toolchain, CSS generation, offline asset completeness, native UI tests U01–U10, and that UI crates cannot import the canonical store. A browser fixture is useful for fast component tests but cannot replace native WebView/security/accessibility tests.

The updater must not replace a running writer underneath active operations. Use maintenance mode and a restart handshake. Back up before schema migrations. Initial update checks are explicit rather than a dependency of offline startup.

Publish a release manifest with application version, database/record/API/rule-language versions, bundled SQLite version, MCP SDK and supported protocol versions, supported host/OS combinations, tested model configurations, evaluator capabilities, and known unsupported semantics. Include Rust/Dioxus/CLI/Tailwind versions, the resolved dependency lock digest, adopted Rust/UI commit/file manifests, and the tested macOS versions.

<a id="section-23"></a>

## 23. Requirements traceability

| Source requirement | Primary implementation sections | Key proof |
|---|---|---|
| Multiple named universes, multiple named worlds, and narrative associations | §§1, 5–6, 15, 27–28, 32, 36 | V01–V05, V16–V26, V30–V36. |
| Explicit universe on every domain tool; conditional world scope | §§4, 11, 30, 36 | Parameterized V06 plus V07–V15, V27–V29, V37–V40. |
| Qualified facts, n-ary roles, type/instance/office distinction | §§5–6 | S21, S23, S24, S38, S39. |
| Independent time dimensions and changing state | §7 | S25–S32 and historical snapshot tests. |
| Truth, belief, uncertainty, disputed accounts | §8 | S14–S20, S33–S34, S45. |
| Rules, dependencies, exceptions, bounded validation | §9 | S01–S10, S35, S41–S42. |
| Canon proposals and author boundaries | §§8, 10 | T06–T11, exact review/commit alpha. |
| External agent tooling, no internal writing app | §§1, 3, 11–12, 15 | LM Studio/standalone host acceptance. |
| Complete collections versus partial definitions | §8 | S05–S06, S11–S13. |
| Provenance, source versions, revisions, retcons | §§6, 10, 14 | S43–S44, T26–T29. |
| Entire optional domain catalog | §16 | One minimal and one adversarial fixture per pack. |
| Local-first durability and failure transparency | §§13–14, 20–22 | Crash/retry/restore/native offline suite. |
| Dioxus / Rust/UI preferred desktop stack | §§3.5, 15.4, 17–18, 20, 22 | Packaged native feasibility gate and U01–U10; component provenance. |

<a id="section-24"></a>

## 24. Explicit residual risks

The implementation can only validate submitted structured claims, not all unstated meanings in a novel. It can test modeled rules, not infer arbitrary descriptive rules soundly. Retrieval quality and model tool-use reliability require ongoing measured evaluation. Complete coverage of advanced causality, personal time, uncertain quantities, and nested belief reasoning is not a v1 claim.

An author may create contradictory or incomplete definitions deliberately. The application should make those states inspectable and keep them scoped rather than force consistency by deleting evidence. A successful technical transaction establishes what was approved, not that the fiction is universally correct.

Local application permissions do not defeat malicious software with equivalent OS access. Immutable local history is not tamper-proof against a user or process that directly controls the files. Content hashes detect mismatches against a trusted manifest; they do not independently authenticate an author.

The selected UI framework/component pairing is source-reviewed, not natively tested in this planning revision. Rust/UI marks itself experimental; source ownership, dependency drift, accessibility, and desktop-only behavior remain explicit implementation responsibilities. This choice does not establish better performance or lower overall delivery cost than the prior stack. [R16]

<a id="section-25"></a>

## 25. Definition of done for v1.0

The application is ready for v1.0 only when an author can install it on the supported Mac without development tools, create and inspect multiple named universes containing multiple named worlds and associated novels/stories/sagas, connect a tested LM Studio workflow that explicitly names its universe on every domain call, retrieve revision-specific evidence, submit structured proposals, receive bounded validation, approve exact changes, and recover the same universe/history after a tested backup restore.

The required semantic, reliability, and native desktop tests pass. The UI and MCP agree because they use one service implementation. Unsupported capabilities are visible. No release documentation claims universal continuity validation, guaranteed model compliance, or security beyond the stated boundary.

<a id="section-26"></a>

## 26. Starting implementation instruction

Begin with WP01–WP04 and the silver-gate fixture embedded in the two-universe/multi-world fixture from §36 and V01–V40. Commit the contracts, reference fixture, and real MCP compatibility test together. Then implement WP05–WP08 so the first working feature is a durable, authorized, revision-bound change—not merely a successful model response.

The first author-visible milestone is the Phase 2 alpha: **define → query → propose → validate → review → commit → re-query**, with history and recovery already present.

<a id="section-27"></a>

## 27. Concrete domain contracts

**Status:** Proposed implementation specification expanding the source model. These are contracts to implement and test, not existing library APIs. Required fields are required unless a tagged alternative explicitly represents an unresolved value. A field omitted from a draft is not automatically an empty, false, or negative canonical value.

### 27.1 Identity, version, and frame types

Use distinct Rust newtypes and serialized prefixes for `UniverseId`, `WorldId`, `WorkId`, `SagaId`, `ContinuityId`, `RevisionId`, `RecordId`, `RecordVersionId`, `ProposalId`, `ProposalVersionId`, `OperationId`, and `PrincipalId`. Generate opaque, collision-resistant IDs in the service. Human names are separate data. A prefix helps detect mistakes but does not confer authority or establish membership in a universe.

Every persisted domain reference carries its universe namespace. Every tool's top-level arguments explicitly supply `universe`; neither a context nor an opaque ID can substitute. Nested record references may omit a repeated universe ID because that required named request scope supplies it; the service expands them and rejects any conflicting namespace. A reference to a stable record resolves through the requested revision's membership map. An evidence reference to a specific record version resolves to that exact immutable version. The two reference kinds must not be interchangeable.

| Contract | Required fields | Interpretation |
|---|---|---|
| Record identity | `universe_id`, `record_id`, `record_kind` | Identity and kind are immutable. A kind change requires a reviewed migration or a new identity, not a loosely typed replacement. |
| Record version | `record_version_id`, identity, `payload_schema_version`, typed `payload`, `payload_digest` | Immutable content. Actor/time/decision attribution is linked through the editorial operation that admitted it. |
| Canon revision | `revision_id`, `continuity_id`, parent or explicit genesis marker, ordered changes, commit basis | An editorial snapshot, not a fictional moment. |
| Effective frame | universe ID, continuity, revision, represented context, temporal query/reference systems, optional personal sequence, perspective | Fully resolved before evaluation. An omitted time means an explicitly timeless/all-validities query where the operation allows that—not silently “now.” |
| Context handle | opaque token, resolved frame, owner principal, installation/session scope, expiry | A convenience for repeated calls. It is not a grant, bearer identity, or historical database transaction. |
| Record reference | universe, stable record ID | Used for identity across revisions; resolve at the requested snapshot. |
| Version reference | universe, stable record ID, immutable version ID | Used for exact evidence, review, and historical bindings. |

A revision handle must include enough information to detect an accidental continuity mismatch. Reject a request whose revision does not belong to the selected continuity's accessible revision history. A child continuity's inheritance can refer to its parent's pinned snapshot internally; this does not make every parent revision a valid child revision.

Universe and world selectors are not opaque record IDs. Common wire input is `universe: string` with an optional `universe_id` consistency guard. Commands supporting world scope also accept `world: string` and an optional `world_id` consistency guard, which is invalid without `world`. `WorldId` is a typed identifier for a canonical world record within the selected universe, not a second top-level namespace. `WorkId` and `SagaId` likewise identify universe-owned editorial records.

Context handles pin the universe/continuity/revision/temporal/perspective frame, **not a hidden current world**. World focus is explicit per supporting command. Every output returns the resolved universe ID/name and any effective world scope. Proposal/job records retain stable resolved IDs and immutable frames rather than relying on mutable names.

### 27.2 Definitions and values

| Record | Minimum fields | Important validation |
|---|---|---|
| Entity type | namespace/key, display labels, optional parent types, classification semantics, allowed property families | Reject inheritance cycles for executable subtype traversal. Multiple types are permitted. |
| Property definition | key, subject types, value schema, multiplicity, unit dimension, persistence, optional inverse/symmetry/transitivity/exclusivity | No implicit behavior from the display label. Definitions are versioned at the same canon snapshot as their use. |
| Relation definition | key, named role definitions, cardinalities, participant types, optional ordering and constraints | Support more than two roles and more than one participant per role where declared. |
| Unit definition | dimension ID, symbol/labels, exact scale and optional offset to a declared base, validity/context | Conversion must be defined and compatible. Unknown exchange rates or cross-realm units remain unresolved. |
| Calendar/reference system | identity, labels, origin/epoch if defined, unit structure, supported conversion definition | A label-only calendar is storable but cannot support invented arithmetic. |
| Structured value definition | named typed fields, requiredness, permitted unknown alternatives, validation rules | No executable field expressions, arbitrary SQL, or unbounded recursive schemas. |
| Domain pack | namespace, version, dependency versions, definitions, forms, examples, evaluator capabilities | Install/update through a reviewed changeset; never silently rewrite existing definitions. |

Quantities use exact integer, decimal, or rational representations. Arrays that represent sets are normalized by stable identity; arrays that represent sequences retain authored order. Preserve a separate display representation when the author's formatting matters. Numeric equality must not depend on display formatting.

Use explicit precision alternatives: `exact`, `approximate`, `range`, `one_of`, and `unresolved`. A distribution is supported as a descriptive structured value until its executable operators are implemented. Do not silently convert an estimate into an exact value or a probabilistic model.

For interval endpoints, distinguish `known`, `bounded_uncertainty`, `unknown`, and `unbounded`. For ordinary optional values, distinguish “no author definition” from an explicitly authored absence assertion. A nullable database column is not the universe's uncertainty model.

### 27.3 Proposition, assertion, and represented context

| Record | Minimum fields | What it does not establish |
|---|---|---|
| Proposition | predicate definition reference; role/subject bindings; typed object/value where applicable; quantification; represented-context reference | Its existence does not assert its truth. |
| Assertion | proposition reference; support/refutation polarity; scope; fictional-time validity; persistence; basis references; precision/alternatives where appropriate | Approval of the assertion does not erase its context, evidence limitations, or opposing assertions. |
| Represented context | kind, owning entity/source/narrator if relevant, parent context, explicit bridge rules if any | A dream, myth, quotation, or embedded story is not automatically objective reality. |
| Evidence basis | author decision, source anchor, event effect, imported claim, or derivation; verified/unverified link status | A content match verifies a citation anchor, not necessarily the source's truth. |
| Completeness declaration | subject/set definition; predicate and role scope; exact complete membership basis; time; context; continuity membership | Completeness for an observer's known set is not completeness for objective reality. |

Use a versioned assertion payload for validity and evidence. Editorial approval belongs to the admitting commit/proposal records; do not mutate an assertion payload from `proposed` to `approved` without a new immutable version. Candidate views can show proposed assertions using proposal overlays; canon views only use admitted membership.

Nested belief propositions refer to other proposition records, never recursively duplicate entire subtrees into every payload. Enforce depth and traversal budgets during reads and evaluation. Cyclic references may be preserved as descriptive records only when allowed by their schema; they must not activate an endlessly recursive executable definition.

No default source-ranking rule picks the “most reliable” assertion as truth. A source-precedence rule, when needed, is an explicit author definition with a scope and an explanation. Otherwise return alternatives and conflicts.

### 27.4 Four operations that must not be conflated

| Operation | Meaning | Required history behavior |
|---|---|---|
| `end_assertion_at` | Establish that a state stopped being true at a fictional boundary, with an event or explicit authorial basis. | Preserve the earlier validity period in the resulting canon. |
| `supersede_assertion` | Correct or replace an editorial definition. | Keep the earlier version accessible in previous canon revisions; show the retcon and impacted material. |
| `retract_assertion` | Withdraw this assertion as an accepted basis in the new editorial revision. | Do not assert the proposition's opposite and do not invent a fictional event. |
| `tombstone_record` | Remove a record from the new effective canon view without erasing its identity/history. | Historical references remain resolvable; current dangling dependencies are reviewed. |

Changing an evidence anchor is another explicit revision: it does not change the old source bytes. A custody transfer may need two validity changes and one event, not a delete of the old custodian's historical possession.

A proposal cannot silently shorten an established “Mara continuously possesses the seal from E12 to E20” assertion simply to make another action possible. The shortening must be one of its visible operations, and it must satisfy the relevant authorial boundary.

### 27.5 Event effects: one canonical state authority

An event definition contains occurrence mode, participants, temporal/sequence frame, preconditions, and authored effect specifications. `record_event` compiles those effects into explicit assertion operations in the same immutable proposal revision. The proposal records the expansion version and generated IDs before approval.

Each effect-generated assertion identifies the event and effect slot that established it. The compiled assertion operations—not a second mutable `current_state` object—are the canonical state representation used by queries. Event specifications and their generated assertions must satisfy a structural linkage check. Rebuilding a state projection reads admitted assertions; it does not autonomously replay events and invent another state history.

An ordinary agent may not edit an event-generated assertion independently of the event effect that owns it. Revising the effect regenerates the affected proposal expansion and makes all changes visible. Changing only evidence/labels uses explicitly permitted metadata operations. A deliberate inconsistent outcome can remain as author-approved fictional content with a finding, but malformed or mismatched event-to-assertion linkage is a structural error and cannot be waived.

Event kinds are `occurred`, `planned`, `predicted`, `hypothetical`, `reported`, or another declared descriptive mode. Only an admitted `occurred` event can establish objective state effects by default. A report establishes a report, not the reported occurrence. Changing occurrence mode therefore requires impact review.

Within an event, use explicit phase/step IDs. Evaluate preconditions against the pre-state of the applicable step, then admit that step's effect batch atomically. Independent effects may be unordered. Noncommuting effects on the same resource or exclusive property require an authored order or yield an unresolved-order finding. Database insertion order and UUID ordering never supply fictional order.

### 27.6 Knowledge, messages, memories, and intentions

| Record | Minimum fields | Checks |
|---|---|---|
| Epistemic attitude | holder, proposition, attitude, certainty descriptor, validity, acquisition/basis | Keep `believes`, `suspects`, `rejects`, `remembers`, and authored knowledge distinct. Do not silently promote a belief. |
| Observation | observer, observed subject/event, sensory access, time, interpretation proposition | Presence alone does not establish perception or understanding. |
| Communication | sender, intended/actual recipients, content propositions, channel, send/receipt times, distortions | Knowledge changes need receipt and the declared acquisition/interpretation basis. |
| Memory | holder, represented content, alleged event/source, accessibility, alteration/loss | Remembered content can be false, incomplete, or detached from objective events. |
| Secret/disclosure constraint | proposition or record scope, fictional knowers, reader-disclosure boundaries, concealment | Fictional secrecy and application access grants remain separate. |
| Goal/plan | actor, desired state, prerequisites, intended steps, status | An approved plan does not execute itself or reserve resources automatically. |
| Commitment | parties/roles, obligated action, conditions, deadline, fulfillment/breach/release | Violations are permitted occurrences; prescribed consequences happen only when established. |

The kernel does not assume philosophical factivity, logical omniscience, or closure under every inference for a character. Authors may define a particular knowledge rule, but the engine must not infer that a character knows every logical consequence of everything recorded about them.

### 27.7 Source and narrative-reference contracts

A `SourceVersion` stores a content digest, media type, byte size, origin metadata, import actor/time, and a decoding descriptor. An `Anchor` stores the source version, anchor type, exact range or structural locator, and excerpt digest. Canonical text offsets are UTF-8 byte offsets in the explicitly named decoded-text representation; original source bytes and decoding metadata remain available.

Byte boundaries must align to decoded character boundaries. The desktop translates WebView UTF-16 selection offsets through tested conversion utilities. Normalization for searching never modifies evidence offsets or source hashes. Re-decoding a source with different encoding creates a new text representation and new anchors.

External `Work`, `WorkVersion`, `SceneRef`, and `PassageRef` records store identities, source links, depicted events, viewpoint, narrative position, and narration frame. They do not contain a manuscript-editor workflow. Link relocation is explicit; the universe manager does not watch or rewrite an arbitrary external editor's files by default.

### 27.8 Canonical payload and digest rules

Use one versioned canonical serializer in the service. Reject duplicate object keys, invalid UTF-8, nonfinite numbers, out-of-range primitive encodings, and unknown fields where the contract is closed. Canonicalize object-key order and exact numeric representations; retain authored Unicode string content without identity-changing normalization. Preserve sequence order.

Compute SHA-256 over the canonical serialized payload and its schema discriminator. Hash an approval's complete binding, including universe, continuity, base revision, immutable proposal content, expanded operations, scope, and decision basis. Do not hash only a title, prose rationale, or client-provided digest.

A digest is an integrity/comparison mechanism, not proof of authorship. A caller cannot authorize a write by supplying a digest that happens to match stored data.

### 27.9 Domain-operation catalog

These are the v1 command-compiler families underlying MCP proposal batches. Each operation carries its own closed typed payload and, for replacement, the exact expected prior version. The registry is versioned; no agent can add an executable operation implementation by defining a new universe type.

| Operation family | Required payload / effect | Authority classification |
|---|---|---|
| `create_entity`, `add_name`, `add_type_membership` | Typed entity identity metadata, contextual name, or classification assertion; local-reference mapping for new IDs. | Ordinary detail only where the grant and content boundaries permit. |
| `assert_proposition`, `record_relation` | Typed proposition/value or n-ary roles, polarity, context, validity, persistence, and basis. | Content-dependent; protected properties retain their stronger policy. |
| `end_assertion_at`, `supersede_assertion`, `retract_assertion` | Exact target, expected version, time or replacement as appropriate, rationale/basis. | Historical/fixed/protected changes require matching authority. |
| `record_event`, `revise_event` | Occurrence mode, frame, participants, prerequisites, complete effect specification; deterministic expanded assertion changes. | Event and every effect checked together; no hidden interval rewrite. |
| `add_belief`, `record_observation`, `record_communication`, `record_memory` | Holder/participants, proposition/content, time, source, and attitude/interpretation details. | No automatic objective truth or knowledge acquisition beyond declared semantics. |
| `record_plan`, `record_commitment` | Actors/parties, desired or obligated outcome, conditions, dates, status, basis. | Recording is distinct from execution, fulfillment, or enforcement. |
| `define_type`, `define_property`, `define_relation`, `define_unit`, `define_calendar`, `define_value`, `define_rule` | Create or replace an exact typed definition version with explicit dependencies and executable capability. | Definition editing is separately granted; no schema change can widen its own authority. |
| `set_completeness`, `set_creative_boundary`, `add_exception` | Exact affected scope, membership/rule/boundary, validity, and authorizing basis. | Protected by default. |
| `add_source_anchor`, `record_narrative_reference` | Existing authorized staged source/version, exact locator, context; no arbitrary network/path fetch. | Evidence/reference editing; verified source match is reported separately from truth. |
| `record_issue_decision` | Exact finding fingerprint(s), scope, rationale, and resolution mode. | Proposable by permitted collaborators; effective waiver/approval requires author authority. |
| `tombstone_record`, `merge_entities` | Exact identity/version targets, reference impact, redirect/retention plan. | Privileged and previewed; history is not physically erased. |
| `install_pack`, `upgrade_pack` | Exact pack manifest/dependencies plus expanded definition/record changes. | Author-controlled; executable application plugins are not installed through this path. |

Universe creation, continuity creation/adoption, enrollment/grant administration, backup/restore, and purge are separate typed author service operations. They use the same validation, authority, and receipt infrastructure but are not exposed as unrestricted default MCP mutations.

An identity merge creates revision-scoped identity/redirect decisions while preserving original records and historical references. Undo is a reviewed compensating proposal. Later facts authored against a merged identity may need manual disambiguation; the engine must not guess which pre-merge identity should inherit them.

#### Named-world and narrative operations

Add `create_world`, `rename_world_selector`, `add_world_alias`, `create_work`, `create_saga`, `set_work_binding`, `associate_work_world`, and `set_saga_membership` to the typed operation enum, with schema/permission checks and ordinary immutable proposal expansion. Creation declares a new ID or client-local reference; names never stand in for persisted identity. A world name/alias is checked for normalized collision against reservations when admitted. Rename and tombstone do not reassign the world ID or erase name/history evidence.

`create_entity.world_associations`, when offered as authoring convenience, expands into explicit typed association records in the same immutable proposal; it is not a competing writable field. Changing associations and changing physical location are separate operations. Work-world associations likewise do not establish character travel, actual occurrences, or narrative truth.

New-world creation changes the universe's world catalog and therefore uses no existing-world write envelope. It requires the relevant universe-level grant or author approval. Universe provisioning/renaming itself is an installation-administration operation, outside the default domain MCP tool surface; it does not create a fictional event.

### 27.10 Capability manifest

The service publishes a machine-readable capability registry. Each entry identifies representation support, executable-check support, semantics version, bounds, source-schema version, and relevant tests. Suggested IDs include `assertion.qualified.v1`, `time.exact_interval.v1`, `time.relative_order.v1`, `state.declared_persistence.v1`, `rule.finite_constraints.v1`, `knowledge.explicit_attitudes.v1`, and `continuity.pinned_inheritance.v1`.

Capabilities for descriptive custom calendars, nonstandard geometry, probabilistic distributions, or paradox/loop reasoning must distinguish preserved data from executable interpretation. An unsupported rule requiring such a capability contributes visible unsupported coverage. A newly installed domain pack cannot declare the application capable of evaluating code that has not been implemented.

<a id="section-28"></a>

## 28. Storage implementation specification

**Status:** Proposed physical design. WP05 produces executable migrations from this schema contract and proves them with fixtures. This section deliberately distinguishes source-of-truth tables from indexes and caches.

### 28.1 Schema groups and constraints

| Group | Required columns or keys | Constraints and ownership |
|---|---|---|
| `universes` | universe ID; format/creation metadata | One universe namespace per package, containing all of its worlds and work metadata. Live aliases to the same files cannot create another writer. |
| World record payloads | world record ID; selector name/aliases; setting type; authored metadata | Versioned canonical records; effective existence and names resolve through continuity/revision membership. |
| `world_name_reservations` | universe ID; normalized selector key; world ID; first admitting revision | A key never routes to a different world identity. Reservations are inserted with the admitting commit; index lookup alone never proves current existence/access. |
| World-scope projections | immutable source version; world/reference IDs; role; applicability/time qualifiers | Derived many-to-many indexes; not a required world owner column or an independent state source. |
| Narrative projections | work/saga/version/member IDs; optional world associations; continuity/revision bindings | Rebuildable from universe-owned narrative records. World membership and saga membership are not exclusive. |
| `record_identities` | `(universe_id, record_id)` primary key; immutable kind | Canon identities are inserted only when admitted. Proposal-reserved IDs live outside effective canon membership. |
| `record_versions` | `(universe_id, version_id)` primary key; record ID; schema version; digest; typed payload | Immutable; composite reference must match the same record and universe. |
| `continuities` | universe/continuity ID; immutable branch descriptor; current head | Parent baseline is pinned. Head updates only inside the canon commit transaction. |
| `commits` | universe/revision ID; continuity; optional prior revision; local sequence; principal/basis/digest | Parent chain is acyclic and linear within a continuity. Genesis/branch creation is explicit. |
| `commit_changes` | revision; ordinal; record ID; prior version/state; next version/tombstone | At most one resulting assignment per record per commit after operation compilation. Expected prior state prevents accidental replacement. |
| `head_membership` | universe/continuity/record ID; effective version or tombstone marker | Derived, transactionally maintained, and rebuildable. |
| `snapshot_membership` | snapshot revision plus membership entries/checksum | Optional verified cache. Only written after complete construction; partial snapshots are not readable. |
| `reference_index` | source version; target record/version; role/path; reference semantics | Derived; distinguishes required current dependency from historical evidence reference. |
| Typed projections | assertion subject/predicate/context; role participants; time bounds; rule scopes | Derived from immutable payloads, always constrained by the requested membership map. |
| `source_versions`, `anchors`, `blob_refs` | immutable source/anchor identities; digests; reachability | Source aliases or filesystem names are not blob identity. |
| `proposal_versions` | proposal ID/version; base; expanded operations; reserved-ID map; digest; creator | Immutable content. Separate lifecycle events describe submission/rejection/withdrawal. |
| `approvals` | exact binding; issuer; scope; grant/decision reference; expiry/revocation record | Not writable by ordinary agent proposals. Current validity is checked again at commit. |
| `validation_runs` | input/base/evaluator/definition digests; check results; coverage; limits | Results are immutable evidence of a past run. “Current” is a computed property. |
| `findings`, `resolutions` | rule/evidence/candidate fingerprint; scoped decision | Resolutions cannot suppress changed evidence indiscriminately. |
| `operations`, `receipts` | operation ID; principal/universe/kind/idempotency uniqueness; payload digest; state; result | Mutating outcome and canonical commit receipt share one universe transaction. |
| `dependency_index` | producer result; explicit premise refs; query-scope dependencies | Derived invalidation aid, never sufficient proof of complete impact without parity tests. |
| FTS text/index | version ID; approved searchable fields | Select only versions effective in the requested snapshot and allowed by current grants. |

Use connection-level foreign-key enforcement, appropriate unique constraints, and typed payload validation. The database does not enforce every universe rule. Structural invariants enforced in the service must have negative tests that call the service without the UI.

Never use cascading deletion to erase referenced canon history. A record referenced by old evidence remains readable in that historical frame even if absent from the new head. A current required dependency cannot disappear silently; preview the dependent changes or retain an explicit unresolved/tombstoned reference according to its schema.

### 28.2 Installation state is separate

The installation registry stores universe IDs, current exact selector names and retained aliases, versioned normalization keys, registered package locations, profile identities, current authorization grants and revocation epoch, application settings, and protected references to credentials. It enforces unique universe selectors within the author library. The canonical package identity is its stable universe ID, not its directory or display name. It is not part of a universe's portable export.

A universe commit records the authorization decision ID and sufficient nonsecret audit metadata to explain what authorized it. Restoring an old universe cannot restore revoked installation grants. Grant mutation and the final commit authorization check take the same service-level authorization gate, with a defined lock order: installation authorization gate, then universe writer gate, then database transaction. Do not hold the gate during an author's review or expensive rule evaluation.

Record local administrative decisions durably before reporting them successful. If grant storage cannot persist a revocation, report failure; do not pretend a volatile revocation will survive restart. The daemon is the only writer to installation authority state under the supported application model.

### 28.3 Revision resolution algorithm

For a requested revision, verify universe/continuity membership and current access. Find the nearest verified ancestor snapshot or explicit genesis. Resolve a branch's pinned inherited baseline recursively with cycle/depth guards. Apply committed record assignments in editorial order up to the requested revision, honoring tombstones. Record versions not in this resulting map do not belong to this canon snapshot even if they physically exist in the database.

For current-head reads, use `head_membership` only after checking its revision marker. A head projection for R43 cannot answer a request pinned to R42. For historical reads, cache a membership map keyed by immutable revision and projection-format version, with a configured memory limit. Large maps can be stored in a disposable on-disk cache.

Schema/property/rule references resolve through that same map. Loading today's property definition to interpret yesterday's assertion is a history bug. The payload schema needed to decode stored bytes is independently versioned from the author-defined property's semantics.

Short database read transactions provide a consistent source snapshot while collecting immutable inputs. Close them before long CPU work. If building a large snapshot takes multiple reads, every read targets immutable revision IDs and version IDs; a concurrent head change cannot change the requested data.

### 28.4 Candidate overlay and write-set construction

A proposal compiles into a deterministic map of record changes over a base snapshot. A record created and then amended within one proposal has one final candidate version plus its visible operation history. Conflicting operations on the same record are rejected unless their order and meaning are explicit.

Reserve IDs once when the immutable proposal version is persisted. References among new records use a client-local ID map resolved by the service. Repeated submission with the same idempotency key returns the same mapping. A pure inline validation uses ephemeral local references and cannot create canonical identity rows.

Run structural/reference validation over the complete candidate map, not one operation at a time against only the old head. This allows mutually related records to be added atomically without permitting unresolved canonical references.

Before commit, validate expected prior versions and the continuity head. In v1, any intervening head change requires an explicit rebase. Optimizing this to fine-grained conflict detection is deferred until predicate-range and rule-applicability phantom conflicts have a tested solution.

### 28.5 Query projections and index policy

Start with indexes for effective membership; subject/predicate; role/participant; context/realm; event ordering; rule scope and referenced predicates; source digest; proposal state; and operation idempotency. Add indexes from actual query plans, not speculative indexes for every authored property.

Exact numeric values remain exact strings/rationals in canonical payloads. Any sortable numeric projection must prove equivalent comparisons within its supported range; otherwise perform the bounded exact comparison in Rust. Approximate temporal bounds can narrow candidates, but they cannot establish a definite overlap by themselves.

FTS supplies discovery candidates, not canon membership or exhaustive negative evidence. Escape or parse query syntax through an explicit supported search grammar. No user expression is interpolated into SQL. For restricted views, avoid exposing global hidden-corpus counts or ranking statistics; use authorization-safe candidate scoring and regression tests.

Rebuild projections into a new generation, verify against source payloads and known queries, then atomically activate the generation. An interrupted rebuild leaves the old generation or an explicit rebuilding state, never a partially populated “empty universe.”

### 28.6 Writer, checkpoints, and disk budgets

Use one owned writer connection per universe and a bounded read pool. Run blocking SQLite calls on owned worker threads rather than blocking the async/UI runtime. Serialize checkpoint coordination with writes. Limit busy retries; report storage-busy distinctly from an empty result.

Open-time checks record `sqlite_version`, required compile options, foreign-key state, journal mode, synchronous mode, and schema version. Require the documented WAL-reset patch baseline in §6.2. Test the actual packaged library, not the system command-line SQLite executable. [R10, R12, R13]

Monitor WAL size, available disk space, checkpoint progress, writer queue length, and read-transaction duration. Use bounded passive checkpoint work during normal use; stronger checkpoint/maintenance operations run with an explicit scheduling policy. Do not delete WAL files manually to recover space.

`FULL` durability and directory/file flushes are part of the planned supported-storage contract, not a guarantee against faulty hardware, malicious processes, or a filesystem that does not honor its guarantees. Distinguish process-crash tests from genuine power-loss testing in release evidence.

### 28.7 Blobs, garbage collection, and backups

Write attachments to a service-owned staging location, enforce size/type limits, compute digest, flush content, and atomically place it in the immutable blob store before admitting the database reference. Flush containing-directory metadata using the supported platform path. On a duplicate digest, verify length/content metadata rather than overwriting blindly.

The reachability roots for garbage collection include every retained canon revision, proposal version, source version, active import, in-progress backup/export, and explicit retention pin. Capture a GC generation and use a grace period; recheck roots before deletion. A blob newly referenced after a mark pass must not be swept.

A backup first captures a consistent SQLite snapshot, then derives its blob list from that snapshot. Pin the required blobs until the archive is complete and verified. Check every digest, write the manifest last, and atomically publish the completed backup. Partial backup directories remain clearly incomplete and cannot appear as restore candidates.

A restore validates into a separate directory before replacing the registered project. Detect two live copies with the same universe ID. Offer explicit restore/replace or clone-as-new-universe paths; do not operate them as independent writable replicas with the same identity.

<a id="section-29"></a>

## 29. Service, authorization, and operation state machines

### 29.1 Service startup and ownership

The desktop and MCP adapter discover a per-user runtime endpoint in an owner-only directory. They first attempt a versioned handshake with an existing engine. If none is available, a client acquires the bootstrap lock, checks again, and starts the installed engine by its verified absolute path. Losing the bootstrap race means connecting to the winner, not creating another service.

The engine owns a service lock for its lifetime and registers each open universe's canonical filesystem identity. Resolve path aliases before assigning writer ownership. A PID file is diagnostic metadata, not the lock. Reject symlink/path substitution in runtime/profile locations and report an unsupported or inaccessible location explicitly.

The handshake supplies application IPC major/minor, client build, optional diagnostic client name, credential, and desired capabilities. The response contains engine build, supported contract range, service-instance ID, limits, and authenticated principal. The diagnostic name and `client_kind` never select privileges.

On macOS, the private application transport uses a Unix-domain socket with owner-only access and peer-identity checks. Credentials are generated by author-controlled enrollment, stored using the platform credential facility or protected installation storage, and referenced by a profile ID. Do not put bearer credentials in model-visible tool arguments, source text, exports, logs, or shell arguments. Same-OS-user hostile-process resistance remains outside the guarantee unless stronger isolation is added.

### 29.2 Private IPC framing and client behavior

**Proposed application protocol:** bounded length-prefixed UTF-8 JSON messages over the private socket, with request IDs and a closed request/response schema. A 4-byte network-order length prefix is a framing choice for this application IPC, not a change to MCP stdio framing. The external `universe-mcp` process continues to use the SDK's MCP transport. [R09]

Before allocation, reject frames larger than the negotiated maximum. Parse duplicate keys/depth/typed values strictly. Dispatch requests by a fixed method enum. Never accept a client-supplied SQL statement, Rust type name to instantiate, arbitrary executable command, or filesystem path as a generic application method.

The typed client multiplexes bounded in-flight requests. A disconnected read may be retried against the same immutable revision. A mutation is never retried with a new idempotency key merely because its response was lost. Reconnect, resolve its existing operation/key, then display the actual outcome.

Read subscriptions are optional application notifications, not required MCP features. A notification contains a new revision/operation identifier and minimal permitted metadata; it does not silently refresh a pinned view. Clients recover from notification loss by checking the current head/status explicitly.

### 29.3 Queues, scheduling, and shutdown

Use bounded request queues, one serialized universe writer, and a separate bounded CPU executor for validation. Initial tuning defaults: two active CPU validation jobs globally, at most eight in-flight ordinary requests per principal, and bounded per-universe write admission. These are adjustable engineering budgets, not measured capacity.

Apply fair scheduling so a single agent cannot starve author reads or other clients. Large imports and full-universe validations use jobs with work counters and cooperative cancellation. Every expensive traversal decrements a deterministic fuel budget as well as observing an elapsed-time bound. Do not run long CPU work on a UI event thread or hold database locks while awaiting external input.

A connection closing cancels unneeded ephemeral reads, not an already admitted durable operation. Normal engine shutdown stops accepting work, completes or safely stops queued jobs, resolves in-flight commit transactions, persists receipts, closes stores, and releases locks. Forced termination is covered by crash recovery. An idle exit occurs only when no connected clients or active durable operations remain; its configurable delay has no semantic effect.

### 29.4 Authority matrix

| Operation family | Research | Collaborator | Scoped editor | Author administration |
|---|---|---|---|---|
| Read permitted records and schemas | Yes | Yes | Yes | Yes |
| Validate within permitted evaluation scope | Yes | Yes | Yes | Yes |
| Cancel own eligible read/validation job | Yes | Yes | Yes | Yes |
| Create/revise/withdraw own proposals | No | Yes | Yes | Yes |
| Commit ordinary detail | No | No | Only within exact current grant | Yes, subject to integrity checks |
| Change rules, fixed facts, completeness, identity, or boundaries | No | Proposal only where allowed | Only if explicitly granted; never implicit | Yes, with impact/decision record |
| Approve another principal's protected proposal | No | No | No by default | Yes |
| Grant privileges, enroll profiles, restore, purge | No | No | No | Yes |

A scoped grant binds universe IDs, continuity, optional world-ID scope, operation kinds, entity/predicate/type scopes, protected-area exclusions, approval requirements, limits, expiry, and issuer. A name, a world-filtered UI, or omission of a world argument cannot expand that authority. Changing shared universe definitions or a cross-world event requires authority over the complete actual write footprint. New custom definitions and their claimed categories do not expand a grant by labeling themselves “ordinary detail.” Evaluate actual effects and referenced definitions, not only operation names.

An agent may record an in-world decree saying “the author approves this.” That is content; it is not an application approval. Host-side tool confirmation is an additional user interaction, not a replacement for these grants.

### 29.5 Proposal lifecycle

Persist immutable proposal versions and separate lifecycle events. States are `draft`, `submitted`, `rejected`, `withdrawn`, and `committed`. A revision of a submitted proposal produces a new draft/submitted version; old validation and approvals stay attached to their old version.

Author approval is a separate immutable authorization record. The UI can display “approval current” or “approval stale” beside a submitted proposal. A scoped editor's current grant may supply the required authority instead. Neither route bypasses structural checks or silently accepts an unevaluated hard rule.

Reject/withdraw does not delete evidence or reserved identifiers from the audit trail. A rejected proposal cannot later be committed without a new explicit proposal version and applicable review. A committed proposal cannot be edited; an amendment creates another proposal and canon revision.

Rebase is explicit. Show the old base, new base, intervening changes, and operation conflicts; create a new immutable proposal version and digest. Do not label a proposal “the same approved change” after rewriting its base or expansion.

### 29.6 Durable operation lifecycle and idempotency

Use `queued`, `running`, `awaiting_authority`, `committing`, `succeeded`, `failed`, `cancelled`, and `interrupted` where applicable. A proposal waiting for author review need not occupy a running job; return its ID and requirements. Persist job inputs as exact immutable references rather than retaining an expiring context handle as their only basis.

Mutation admission records the principal, resolved universe ID, operation kind, semantic canonical request digest, and idempotency key. Resolve any world scope into stable IDs before hashing; equivalent retained aliases do not become distinct mutations. Retain the original requested names as audit metadata, not as receipt identity. Uniqueness is enforced for that tuple. Retrying the same key/payload returns the admitted operation or final receipt; a different payload produces `IDEMPOTENCY_KEY_REUSED`.

A successful canonical commit and its receipt are written atomically. “Committing” is not a user-visible guarantee of success. Recovery checks the receipt before deciding whether an interrupted worker requires retry. A new worker must never infer failure merely because its predecessor died.

`universe_get_operation` supports lookup by operation ID **or** the caller's universe/kind/idempotency key. This covers a lost admission response where the caller never learned the operation ID. Old receipts are readable only under current access. Detailed receipts may be pruned under policy, but their idempotency tombstones cannot be reused to create another mutation.

Cancellation is a request. Before the commit point it can stop work without canonical changes. After the transaction commits it returns the committed receipt or “too late to cancel”; it must not suggest the canon was rolled back. Reversal is an ordinary new proposal.

### 29.7 Restricted validation and secret-oracle prevention

A viewpoint filter describes fictional information; a grant describes actual data access. The evaluator must not use privileged facts and then reveal their values indirectly through arbitrary true/false feasibility tests.

For v1, restricted research principals validate only scopes whose required facts/rules can be evaluated and disclosed under their grant. Otherwise return a generic access-limited coverage result, not a secret-dependent success/failure. Determine this from policy/evaluation scope rather than revealing the specific hidden matching record. Avoid exposing hidden names, IDs, result counts, or suppressed finding counts.

Restricted collaborators may submit proposals without learning confidential reasons for every decision. An authorized author can inspect the complete impact. Delegated direct commit requires access to the required evaluation scope or an exact author approval bound to the full check; otherwise it is not available. Do not promise both arbitrary secret-dependent validation and complete secrecy from the same principal.

Tests compare paired universes that differ only in hidden material and exercise search, validation, receipts, caches, errors, and UI notifications. These are concrete disclosure regressions, not a formal claim of eliminating every timing or resource-use side channel.

<a id="section-30"></a>

## 30. Application tool schemas and interaction contracts

### 30.1 Shared response envelope

Every successful domain result contains application contract version, request/operation identifier, resolved universe ID and canonical selector name, safe alias-match metadata, immutable canon frame when relevant, effective world scope, current authorization-scope indicator, typed result, and delivery metadata. Administrative universe names are routing labels; fictional names retain their own versioned context.

Every request contains `universe: string`. Optional `universe_id` is a consistency guard. A command supporting world focus may also contain `world: string` and optional `world_id`; the guard is illegal without the corresponding name. Names resolve exactly according to §36, never from guessed substrings. Nested typed references are checked against that universe.

An envelope distinguishes universe selection, world focus, evaluation/dependency scope, and actual write footprint. These are not one overloaded scope value. Failure responses disclose resolved names/IDs only if current permissions allow it. A missing/inaccessible selector has no fabricated frame, and no hidden target is revealed through mismatch diagnostics.

Evaluation coverage, universe/world completeness, and payload pagination are independent. A paginated report can have complete evaluation but incomplete delivery; a fully delivered report can describe partial evaluation. Validation also reports input coverage, evaluator/rule/definition bindings, run ID, findings, missing definitions, unsupported capabilities, and cross-world scope expansion without leaking inaccessible dependency metadata.

A fictional contradiction is a completed application evaluation with findings, not an MCP protocol failure. A semantic request fingerprint uses resolved IDs, immutable frames, explicit operation content and focus/footprint; mutable display names and alias spelling are audit metadata, not independent mutation identity.

### 30.2 Tool input/output specifications

All fields shown before the first semicolon are required for the selected action unless explicitly labeled optional. `universe` is unconditionally required for every tool; `universe_id` is an optional matching guard in all rows. Conditional fields must be generated and tested from Rust DTOs.

| Tool | Required input and controlled options | Output / side effects |
|---|---|---|
| `universe_describe` | universe; mode summary/capabilities/worlds/definitions; context_id required for revision-bound worlds/definitions; world only for scoped definitions | Describe the selected universe, accessible continuities, worlds, schemas, and limits. Never enumerate other universes. |
| `universe_open_context` | universe; continuity_id; revision selector; represented context; temporal query and reference systems; perspective | Resolve/pin the universe revision and frame. No current/default world is stored. |
| `universe_search` | universe; context_id; query; typed filters; limit/cursor; optional world | Find authorized candidates in the universe or focused world, with applicable shared material and labeled dependencies. |
| `universe_get` | universe; context_id; record_ids; field groups; optional world | Read exact effective records. Explicit IDs inconsistent with world focus receive a scoped result/error, never another identity. |
| `universe_get_state` | universe; context_id; entity_ids; predicate filters; event entry/exit selector when applicable; optional world | Evaluate state within the pinned temporal frame; world focus never erases relevant incoming/outgoing transitions. |
| `universe_get_context` | universe; context_id; focus_ids; purpose; byte budget/cursor; optional world | Assemble research context including applicable universe-wide rules and necessary authorized cross-world dependencies. |
| `universe_validate` | universe; context_id; inline candidate or exact proposal reference; check scope; optional world only for inline candidates | Validate inline candidates with declared focus, or the entire immutable proposal footprint. A proposal cannot be partially validated through a world filter. |
| `universe_propose` | universe; context_id; action create/revise/submit/withdraw; appropriate operations/proposal reference; submission; rationale; idempotency_key; optional world for create/revise only | Create/revise explicit local or cross-world changes. World-local creation requires authored scope/association; the selector never fills missing canon facts. Submit/withdraw use the stored footprint. |
| `universe_get_proposal` | universe; proposal_id/version; cursor; optional view group | Read the exact whole proposal, changed worlds/shared definitions, impact, and authorization requirements. |
| `universe_get_impact` | universe; context_id; proposal reference or changed-record specification; scope/budget; optional world for inline specifications only | Return the complete authorized dependency impact or explicit restricted/partial coverage, not only the selected world. |
| `universe_commit` | universe; submitted proposal_id/version/digest; expected_base_revision; validation_run; idempotency_key | Commit the entire authorized universe changeset atomically. Reject filters and caller-supplied approval flags. |
| `universe_get_operation` | universe; operation_id OR own operation_kind/idempotency_key; cursor | Read/recover the operation or receipt in the supplied universe. An operation ID cannot select another universe. |
| `universe_cancel_operation` | universe; operation_id; idempotency_key | Request eligible cancellation in the named universe; never infer scope from the handle or undo committed canon. |

The name arguments are nonempty strings, not paths, SQL fragments, wildcards, or omission-sensitive defaults. `null` is not an alias for omission. `world_id` without `world` is invalid. A world cannot be resolved outside the explicitly named universe. A selected-world cursor is bound to its world-ID focus, universe, canon frame, query, and authorization epoch.

For `universe_propose`, create/revise may supply `world` as a local **write envelope**, not an implicit fact. Every operation still declares the appropriate scope/association. Submit/withdraw reuse the stored immutable footprint and reject a new world selector. For `universe_validate` and `universe_get_impact`, proposal mode always evaluates the entire stored proposal; optional world focus is only for inline candidate/specification mode. This prevents a caller from narrowing away a conflicting cross-world effect.

Closed schemas reject incompatible/unrelated fields. Examples in this plan are planning fixtures; WP03 generates normative JSON Schema and tests every valid/malformed example. An old call that omits universe fails even when a valid context ID is present. There is no silent v0.3 inference adapter.

### 30.3 Concrete proposal example

The following is a planning example with symbolic IDs. It shows the application arguments, not an entire MCP JSON-RPC message. The named universe, named world, frame, and type must already exist and be accessible.

```json
{
  "universe": "The Ashen Cycle",
  "universe_id": "unv_ashen_cycle",
  "world": "Aster",
  "world_id": "wld_aster",
  "context_id": "ctx_example_main_r42",
  "action": "create",
  "submission": "submitted",
  "rationale": "Propose a tavern in the already defined harbor district.",
  "operations": [
    {
      "kind": "create_entity",
      "client_ref": "new_tavern",
      "type_ids": ["type_tavern"],
      "display_name": "The Lantern House",
      "world_associations": [
        { "world_id": "wld_aster", "role": "setting", "validity": { "kind": "unresolved" } }
      ]
    },
    {
      "kind": "assert_proposition",
      "client_ref": "new_tavern_location",
      "subject": { "local_ref": "new_tavern" },
      "predicate_id": "property_located_in",
      "value": { "kind": "entity_ref", "record_id": "entity_harbor_district" },
      "polarity": "support",
      "applicability": { "kind": "worlds", "world_ids": ["wld_aster"] },
      "validity": { "kind": "unresolved" },
      "basis": { "kind": "proposed_authorial_definition" }
    }
  ],
  "idempotency_key": "example-create-lantern-house-1"
}
```

This stores a proposal, not an automatically valid location at every fictional time. The response provides persistent IDs for the local references, the exact proposal version/digest, and any scope/definition gaps. An agent that needs a scene-specific usable location must supply or propose the relevant validity rather than treating unresolved validity as timeless.

### 30.4 Context and proposal interaction

The author supplies a universe name (or the external host supplies it explicitly on the author’s behalf). The agent calls `universe_describe` for that universe, opens a universe-level frame, discovers named worlds/definitions within it, and retrieves state/rules using explicit per-call world focus when appropriate. It then submits a candidate, inspects validation and impact, and creates or revises a proposal. A canonical addition becomes usable only after the service returns a commit receipt.

After commit R43, the old R42 context remains R42. Return a clearly identified new-revision reference; require the client to open a new context to use it. This prevents later research in the same conversation from silently mixing revisions. Hosts may provide convenience UI, but the server's frame contract is explicit.

`universe_get_proposal` returns both authored and compiled changes. A model must not see only the high-level “record transfer” action while an author approves undisclosed validity rewrites. The approval digest covers the exact expansion.

A world focus is not retained in the context. For example, two `universe_search` calls sharing the same context may explicitly select Aster and Nacre; a third omitting world queries the authorized universe scope. Each still repeats `universe`. A world name in another universe, a mismatched guard, or a context for another universe is rejected before any target lookup or mutation.

### 30.5 Tool output size and model behavior

Never load the entire universe into a tool definition or return every fact by default. Use compact schemas, typed filters, batched lookup, ID references, and pagination. A model receives only operations authorized for its profile where supported, but hidden-tool names alone are not an access-control boundary.

Measure actual schema plus result tokens in each supported host/model configuration. The 24 KiB brief default is an application byte budget, not a guarantee that it fits any specific model's context window. A compatible client can request less. Oversized mandatory context returns explicit continuation and incomplete-delivery status rather than dropping constraints.

No tool requires a hidden internal model, sampling permission, or a special host prompt. Suggested prompts may teach usage, but malformed or overconfident model output cannot alter the server contract.

### 30.6 Integration installation and compatibility record

Generate the MCP configuration from the actual installed executable path and author-created profile. Its shape uses LM Studio's documented local-server configuration mechanism. The exact installation path in examples is not hard-coded as a product requirement. [R01]

```json
{
  "mcpServers": {
    "universe-builder": {
      "command": "/ABSOLUTE/INSTALLED/PATH/universe-mcp",
      "args": ["--profile", "profile_authorized_worlds"]
    }
  }
}
```

The application displays and copies this configuration; it does not silently overwrite the user's host configuration. Any automated merge must preview changes, preserve unrelated servers, create a backup, and require explicit authorization.

For the native LM Studio API route, use a configured local server and the documented setting permitting configured MCP servers. An ephemeral remote-server URL is not a substitute for launching this stdio server. Record the actual API/host version and settings. [R02]

The compatibility artifact records OS and build, app/engine/MCP SDK versions, negotiated protocol, host version, transport, model identifier and quantization, model prompt/tool template, context limit, settings, tested workflow, and pass/failure evidence. Client identifiers and model names are diagnostic labels, not trusted principals.

<a id="section-31"></a>

## 31. Validator and state-evaluation algorithms

### 31.1 Evaluation input and reproducibility

An evaluation input consists of an immutable base frame, a normalized candidate overlay, a requested scope, current permitted evaluation/disclosure scope, exact schema/rule/evaluator versions, and explicit work limits. Resolve all of these before executing checks. Save their digests with the result.

Use deterministic iteration and evidence ordering. When a processing limit stops work, preserve a deterministic continuation position where practical. A repeated run on identical inputs with sufficient identical budgets should produce the same semantic outcomes; wall-clock timings and generated operation IDs are excluded from that equivalence.

Rule compilation performs schema validation, type checking, name-to-ID resolution, dimension checking, dependency extraction, scope validation, and boundedness analysis. Unknown operators are not interpreted as no-ops. Store unsupported rules descriptively and mark them nonexecutable. The first executable derivation language permits acyclic rule dependencies; a cyclic derivation must be rejected for activation or treated as explicitly unsupported, not executed until it happens to stop.

### 31.2 Evidence algebra

For an atomic proposition in a fixed frame, maintain two evidence bits: support `s` and refutation `r`, each with its derivation/source references. Outcomes are supported `(1,0)`, refuted `(0,1)`, conflicting `(1,1)`, or not established `(0,0)`. Access-limited and unsupported evaluation are separate coverage dimensions and must not be disguised as ordinary `(0,0)` universe uncertainty.

For the first declarative Boolean operators, define explicit four-valued evidence propagation:

```text
not(a):       support = a.refutation;       refutation = a.support
all(a, b):    support = a.support AND b.support
              refutation = a.refutation OR b.refutation
any(a, b):    support = a.support OR b.support
              refutation = a.refutation AND b.refutation
```

This is a proposed finite evaluation contract, not a claim that the engine solves every logic. Never apply classical explosion to a conflicting proposition. Test every pair of inputs, including both-supported-and-refuted, for each operator.

Finite quantification requires separate domain completeness. One supported witness can establish existence even if the set is incomplete. Lack of a witness cannot refute existence without an applicable complete domain and completed evaluation. One counterexample can refute a universal rule; proving it requires covering the relevant domain. Empty-domain identities apply only when the domain is explicitly complete and empty.

For numeric ranges, a comparison is definite only when every supported value satisfies it or every value refutes it; otherwise return unresolved evidence. Preserve inclusivity and units. Do not sample an arbitrary point from a range. Unsupported distribution arithmetic returns unsupported coverage.

### 31.3 Rule applicability is not material implication

For each rule, first evaluate scope and applicability. A definitely inapplicable rule is reported as such. An unknown or conflicting applicability condition remains potentially applicable and contributes an indeterminate check. It must not be declared satisfied through a vacuous implication.

For an applicable operational rule, test requirements against the pre-state. Definitely missing/disproved prerequisites conflict; unestablished prerequisites leave the outcome indeterminate. A law's departure is a normative finding, not a failed structural write. A behavioral tendency produces advisory information, not a fabricated psychological requirement.

Evaluate exceptions by exact rule, scope, validity, and authorizing basis. A more permissive exception cannot bypass grant administration. Several incompatible exceptions produce an explicit conflict; the engine does not choose the most convenient one for the proposed action.

### 31.4 State query pipeline

Resolve the snapshot membership and requested temporal frame. Collect applicable assertions by subject/predicate/context, including explicit negative evidence and declared completeness. Evaluate definite and possible temporal applicability. Apply only declared persistence semantics, event-effect linkages, and authorized derivations. Return supported values, refuted values, alternatives, and gaps with their bases.

For `persistent_until_changed`, the initial assertion's start and permitted termination semantics must be established. An unknown start does not become the beginning of the universe. If change events are partially ordered and could yield different current values, return the alternatives instead of selecting the latest database row.

An explicit interval ending at time T ceases to establish its positive assertion at T under the half-open convention. It does not necessarily establish the opposite proposition afterward. A collection declared complete at T may justify a negative conclusion at T; it does not automatically justify that conclusion at T+1.

For event validation, build the candidate pre-state, evaluate all prerequisites, then apply the compiled effect batch to the candidate post-state. Validate simultaneous resource use jointly. Resource conservation is an authored rule or domain-pack rule explicitly installed by the author, not an assumption that every fantasy process obeys ordinary physics.

Travel checks operate on defined paths, access, modes, durations, and capabilities. Not finding a route establishes impossibility only when relevant route/path coverage and rule evaluation are complete. Deliberate navigation can depend on knowledge, guidance, or another authored mechanism; arriving somewhere is not itself proof of prior knowledge.

World-aware state evaluation starts with universe membership and the pinned snapshot, then resolves the optional world focus. Universe-wide applicability is included only where the author actually declared it; a record's storage ownership is not evidence of universal applicability. Relationship/event traversal may expand into other worlds in the same universe under current access. Do not clone a traveling entity, interpret location as exclusive ownership, or discard a departure/arrival outside the display focus. Unsupported cross-world temporal comparison remains indeterminate.

### 31.5 Validation execution pipeline

The service performs these stages in a fixed order, stopping only where further work cannot be meaningfully executed and recording the unexecuted stages:

1. Authenticate and authorize requested input/evaluation scope; enforce input and job limits.
2. Decode typed inputs, verify references, and resolve the immutable base frame.
3. Compile domain operations into a complete candidate overlay, including effect-generated assertions.
4. Enumerate potentially applicable structural definitions, authored rules, completeness, boundaries, and exceptions without search-ranking truncation.
5. Evaluate structure, time/state, capabilities/resources, knowledge, normative/behavioral rules, and relevant external narrative constraints.
6. Compute and evaluate impact on existing material within the declared coverage scope.
7. Determine findings, missing information, unsupported work, and execution/delivery coverage separately.
8. Evaluate current approval/commit requirements without turning permission into semantic truth.
9. Persist the run and input/evaluator bindings; return its evidence or job reference.

The decision to admit a proposal into canon occurs later under §10.4. A validator may finish successfully while finding conflicts. A proposal can be compatible and still require author approval. An author-approved inconsistency remains a reported inconsistency.

### 31.6 Impact analysis

The initial implementation uses conservative impact. Collect changed predicates/entities/rules/scopes, their direct reference dependents, affected query scopes, and transitive derived dependencies up to an explicit bound. If completeness, rule applicability, definitions, or temporal conversions change, broaden to the affected continuity scope rather than assume only old record-reference edges matter.

Reevaluate existing events and assertions that rely on those scopes. Adding a new sibling, route, power, member, or exception can change a prior absence/cardinality conclusion even though no old dependency edge referenced the new record. Record these scope dependencies explicitly.

If the impact set cannot be safely bounded, run a full-scope job or report incomplete impact. Do not silently authorize delegated direct commit where its grant requires complete impact checks. The author may make a specifically bound decision accepting a disclosed incomplete evaluation; that decision does not change coverage to complete.

Only add incremental invalidation optimizations after they match a simpler full reevaluator on generated universes, with randomized insertion order and changes affecting absence-based conclusions. The unoptimized evaluator remains a test oracle for the implemented finite semantics, not for arbitrary fiction.

Impact closure starts from the candidate's entire actual footprint, including world scope, universe-wide definitions, cross-world routes/resources, world associations, and work/version bindings. A world-local edit may have broader dependent effects. Record that broader impact; do not silently widen the mutation authority. An approved local scope cannot authorize a global rule edit merely because it affects a local subject.

### 31.7 Finding identity and presentation

A finding fingerprint includes rule version, candidate digest, relevant fact/source versions, temporal/context scope, and issue category. Separately group related findings for readability. A user's resolution applies to the exact fingerprint/scope or to an explicitly authored general exception; it does not globally suppress future warnings with the same text.

Each finding explains the submitted claim, the applicable constraint, the supporting/refuting evidence, and the specific unknown information. Return permitted source anchors and version IDs. Suggested repairs are proposed options, not silent canon edits. A false-positive report becomes a reproducible fixture before changing evaluator behavior.

<a id="section-32"></a>

## 32. Dioxus desktop implementation specification

### 32.1 Application state ownership

Keep a small application root containing connection status, authenticated author session, open tabs with per-tab universe/continuity/pinned frames and explicit world focus, and notifications. The active tab is presentation state, not an implicit service request target. Each workspace owns its query state and presentation models. Each editable draft is keyed by universe, continuity, base revision, target record, and draft/proposal ID.

Canonical data comes only from `universe-client`. Dioxus signals contain bounded view data, not an independent mutable copy of the universe. Large sets are paged/windowed. Selection keys use stable IDs, never row numbers. When context changes, increment the request generation; an old response cannot replace a newer context's data.

Draft autosave uses a service draft/proposal endpoint. It does not auto-commit canon. Display `unsaved`, `draft saved`, `submitted`, `validation stale`, and `committed` distinctly. On a failed save, preserve the authored input and visible error. Switching universes prompts for unresolved local input rather than silently discarding or copying it to the new universe.

Every async UI operation captures stable universe identity, continuity/revision, explicit world focus, and draft/proposal identity at dispatch. Typed requests always include the resolved universe's selector name plus its ID guard. Switching universe/world views never mutates an already dispatched request or changes the target of a pending commit. Render the captured scope with pending operations and reject late responses for a different view generation. Concurrent tabs may work on different universes without a process-wide active-universe variable.

### 32.2 Required screen contracts

| Screen | Primary elements | Write behavior |
|---|---|---|
| Universe library | Named universe catalog; identity guards; package status; alias/restore conflicts. | Author-controlled creation/rename/registration; no automatic grants or retargeting. |
| Worlds | Named world records; explicit all-content/shared/unassigned views; world scope summary. | Typed world creation/rename/association proposals with uniqueness and footprint checks. |
| Works and sagas | External novels/stories; versions; group memberships/order; many-to-many world associations and canon bindings. | Universe-owned metadata changesets; no manuscript editing or private work canon. |
| Universe dashboard | Project identity; continuity/head; recent decisions; unresolved issues; maintenance status | Initialization and pack installation are explicit author operations. |
| Explorer | Typed filters, contextual-name search, paged results, stable selection | Creating an item opens a draft with visible scope. |
| Entity inspector | Identity/types; facts; relations; time; evidence; issues/history | Each continuity-bearing field edits its assertion, not an unversioned entity column. |
| Qualified-fact editor | Predicate/value, polarity, validity/persistence, context, basis, alternatives | Client shape feedback; service validation remains authoritative. |
| Relationship editor | Named roles with variable cardinality and reference pickers | No forced binary relationships or name-based identity guessing. |
| Timeline/state view | Explicit clock/reference system, event ordering, before/after state, uncertainty | Reordering creates a proposed temporal change; dragging cannot silently set invented dates. |
| Rule/boundary editor | Rule kind, typed expression fields, applicability, exceptions, executable status | Changes carry impact and stronger authority checks. |
| Proposal review | Exact expanded diff; protected changes; evidence; findings; coverage; authority | Approval binds the visible immutable proposal; changed bindings disable stale actions. |
| Sources/evidence | Immutable version selector; safe preview; exact anchor; origin status | Reanchoring is proposed, never automatic source replacement. |
| History/issues | Revision diff, decisions, finding status, scoped resolution | Undo generates a compensating proposal with impact. |
| Profiles/settings | Granted universes/operations, current clients, compatibility, privacy/diagnostics | Privileged credential/grant changes; no secrets in export. |
| Maintenance | Backup/restore, import staging, integrity, projection rebuild, storage status | Explicit maintenance jobs with durable outcomes. |

Universe notes are editable descriptions; manuscript editing remains out of scope. A source preview is read-only evidence unless the author is explicitly replacing the source version.

### 32.3 App-owned control layer

Use Rust/UI source for suitable primitives, wrapped by application-owned components. Start with buttons, labels, badges, tabs, dialogs, selects, inputs, and ordinary paged tables. Add `UniverseSelector`, `WorldSelector`, `NarrativeWorkPicker`, `EntityRefPicker`, `QualifiedValueEditor`, `WorldTimeEditor`, `EvidenceAnchorView`, `ProposalDiff`, `CoverageBadge`, and `PermissionSummary` as domain-specific controls.

Maintain a component provenance manifest: upstream commit/path/digest, license notice, transitive UI dependencies, local patch description, platform assumptions, tests, and update date. Pin the initial Dioxus candidate from the inspected snapshot only after WP01's native check. The source README identifies Rust/UI as copy-in and experimental; do not treat a successful website demo as a native acceptance result. [R16, R17]

Audit `web-sys`, `wasm-bindgen`, direct DOM calls, evaluation bridges, global listeners, resize observers, and portals in selected components. Native Rust code does not inherit browser globals just because the page uses a WebView. Encapsulate platform-specific behavior in reviewed adapters and test it on macOS. [R07]

Universe/world selectors are separate controls. “All universe content” is an explicit view choice, not a fabricated world named “All.” The world picker lists only worlds effective in the selected continuity/revision and allowed by current permissions. The work/saga picker supports multiple world associations without requiring one to be selected. Scope breadcrumbs remain visible in proposal review, history, errors, and recovered-operation receipts.

### 32.4 Interaction and accessibility gates

Every input has a visible name, a precise value state, an associated error, and keyboard access. Unknown/absent/negative values use explicit choices; a cleared field does not become a negative fact. Dates use authored reference systems. Numbers preserve exact values and units.

Dialogs preserve focus, support keyboard dismissal where safe, and restore focus after completion. Long validation jobs announce state changes without stealing focus. Text resizing and reduced motion must retain access to approval controls and evidence. Severity is conveyed with labels and explanation, not color alone.

Use normal paragraph spacing and progressive disclosure. The default explorer is a list/table; no required graph-navigation skill. Place the universe, continuity, revision, and relevant time/perspective in a persistent context bar. Make stale/disconnected views unmistakable without deleting their existing data.

### 32.5 Rendering and native integration gates

Render source text as escaped text or allowlisted inert markup. Never inject source strings into executable JavaScript or raw HTML templates. Prevent source-driven navigation, windows, network subresources, privileged bridge calls, and unrestricted local-file loads. Use plain text/raster fallback for formats that cannot be made inert in the pinned renderer.

Use native file dialogs and clipboard adapters with explicit user actions. The engine receives an authorized staged-source token, not an agent's arbitrary filesystem path. Verify Unicode text-selection offsets and pasted multiline content. Package CSS/icons/assets locally; Tailwind class scanning must include vendored Rust source and all explicit variants.

The compiled package, not the development hot-reload window, must pass these checks. No promise of native widgets, a JavaScript-free renderer, or a complete sandbox follows from choosing Rust/Dioxus. [R07, R15]

<a id="section-33"></a>

## 33. Detailed dependency-ordered implementation backlog

Each package has a concrete exit gate. Subtasks can become issues directly using their stable IDs. The names below describe planned outputs, not commands or files that already exist in an application repository. Do not mark a package complete because a demonstration worked once or a model gave a plausible answer.

### WP01 — Decision baseline, fixtures, and native feasibility

**Dependencies:** None. **Primary area:** architecture, test fixtures, desktop build.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP01.1 | ADRs for scope, Dioxus, shared engine, immutable canon, MCP, authorization, time/uncertainty, SQLite, source ownership. | Each decision references requirements and lists explicit trade-offs/unsupported scope. |
| WP01.2 | Silver-gate logical fixture plus expected outcomes, including independent custody, knowledge, entrance completeness, and boundaries. | Fixture has no unstated exclusivity or knowledge assumptions. |
| WP01.3 | Release-mode Dioxus fixture using selected Rust/UI inputs/select/dialog/table source. | Native launch, keyboard/VoiceOver, bundled styles, file/clipboard adapter, helper execution. |
| WP01.4 | Lockfile/toolchain/component manifest and actual minimum/tested macOS support entry. | A clean build resolves the selected dependencies; exact versions recorded rather than assumed from a docs version label. |
| WP01.5 | Two universes, two worlds in the primary universe, duplicate world names across universes, shared entities, and a cross-world narrative fixture. | V01–V05 and V21–V26 become first-milestone fixtures; no single-world-only feasibility prototype is treated as complete. |

**Exit:** Architecture and fixture contracts are reviewable, and the selected desktop path works in the packaged feasibility fixture. A failed complex component can be replaced with an app-owned primitive without changing the engine design. Do not begin broad UI screen work before this gate.

### WP02 — Pure domain model

**Dependencies:** WP01's model decisions; native packaging can proceed in parallel. **Primary area:** `universe-domain`, `universe-schema`.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP02.1 | Newtyped identities, exact values, version/record references, scopes, temporal expressions, represented contexts. | Valid serialization round trips; cross-universe and wrong-kind references rejected. |
| WP02.2 | Entity/type/property/relation/proposition/assertion/event/rule/provenance/epistemic payloads from §27. | Every family can represent its source example without an untyped semantic escape hatch. |
| WP02.3 | Definition registry, closed payload schemas, canonical serializer/digests, local-reference resolution types. | Duplicate keys, malformed numerics, unknown enums, invalid schema recursion, and silent coercion tests. |
| WP02.4 | Pure reference-universe builders and domain fixtures. | Tests run without a model, WebView, service, or database. |
| WP02.5 | UniverseId/WorldId/WorkId/SagaId, exact selector types, world-applicability alternatives, and multi-world narrative associations. | Namespaces, ownership, location, shared scope, and narrative membership serialize without being collapsed. |

**Exit:** Source distinctions survive serialization, including false versus unspecified, source versus occurrence, role versus officeholder, type versus instance, and editorial versus fictional time. Display text does not determine behavior.

### WP03 — Versioned contracts and typed client

**Dependencies:** WP02. **Primary area:** `universe-protocol`, `universe-client`, `contracts/`.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP03.1 | Command/query DTOs and error/coverage envelope, independent of Dioxus and MCP types. | Schemas and valid/invalid examples generated/tested from the same contract. |
| WP03.2 | Private IPC framing, version handshake, bounded multiplexing, disconnect/reconnect handling. | Oversized/malformed frame rejection; unrelated requests remain available. |
| WP03.3 | Explicit context and operation selectors, cancellation contract, proposal action variants. | No global active-universe state; lookup works when an admission response is lost. |
| WP03.4 | Compatibility fixtures for supported contract versions. | Incompatible major versions fail visibly; unknown semantics are not silently downgraded. |
| WP03.5 | Required universe argument on every generated tool schema; guarded name resolution; conditional world fields and explicit scope envelopes. | Missing-universe cases fail for all tools; world omission, null, guards, and lifecycle action restrictions are tested. |

**Exit:** A mock service and client demonstrate exact serialization, bounded errors, cancellation/status semantics, and response-generation filtering. No actual database behavior is implied yet.

### WP04 — MCP adapter and host interoperability

**Dependencies:** WP03. **Primary area:** `universe-mcp`, host test harness.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP04.1 | `rmcp`-based stdio executable with the tools in §30 and a disposable fixture backend. | Discovery/calls/errors work; stdout contains protocol data only. |
| WP04.2 | Capability/limit presentation and structured/text compatibility behavior. | Identical semantic result in supported host representations; measured token overhead. |
| WP04.3 | LM Studio desktop, configured-MCP API, and independent-client workflows. | Saved test configuration/transcripts with exact host/model/SDK versions and failures. |
| WP04.4 | Installed-path configuration generation and least-privilege profile selection. | Spaces, Unicode, no shell PATH, no source tree, and cold-launch tests. |
| WP04.5 | Two-universe LM Studio/custom-client tool loop with explicit universe repeated on every invocation. | A host context or profile never supplies missing domain scope implicitly; interleaved chats remain isolated. |

**Exit:** Supported hosts can read a fixture, receive a typed error, and create a noncanonical proposal. Record unsupported model/tool-template combinations without weakening validation. Later packages replace the fixture backend, not the tool contract.

### WP05 — SQLite storage and immutable revision kernel

**Dependencies:** WP02. **Primary area:** `universe-store`.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP05.1 | Migration DDL implementing §28, actual-library checks, foreign keys, constraints, connection policy. | Patched SQLite version and required extensions verified in the packaged build. |
| WP05.2 | Immutable versions, commits, expected-version checks, genesis, head membership, exact snapshot reads. | Earlier revision results remain unchanged after later edits. |
| WP05.3 | Typed/reference/search projections with generation-based rebuilding. | Delete/corrupt a projection and reproduce known queries from authoritative payloads. |
| WP05.4 | Store fault hooks for commit phases, disk-full cases, and interrupted snapshot construction. | All-or-none transaction contents; no usable partial snapshot. |
| WP05.5 | One package per universe, many world records, name reservations, world-scope/narrative projections, and universe-wide atomic commits. | Duplicate same-universe world selectors are rejected; cross-world references work; cross-universe references fail. |

**Exit:** Fixture data survives restart, preserves historical definitions, and has a tested reconstruction path. Internal storage test APIs are not exposed as bypasses through the desktop or MCP.

### WP06 — Engine process, credentials, and writer lifecycle

**Dependencies:** WP03, WP05. **Primary area:** `universe-engine`, installation registry.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP06.1 | Bootstrap/service/universe locks, path identity checks, version handshake, startup recovery. | Concurrent cold starts, stale metadata, duplicate paths, incompatible helpers. |
| WP06.2 | Author enrollment, credential/profile storage, authenticated principals, current grant checks. | A claimed administrative client name or author field never escalates authority. |
| WP06.3 | Writer/read/CPU queues, admission limits, cancellation, idle and maintenance shutdown. | A busy agent cannot indefinitely starve ordinary author operations. |
| WP06.4 | Doctor/status output and sanitized local diagnostics. | Actionable errors without source text, credentials, or private-profile leakage. |
| WP06.5 | Installation universe catalog, normalization/alias registry, per-universe writer ownership, world-scoped grants, and fair scheduling. | Renames preserve IDs, other universes remain responsive, and a world-only grant cannot edit shared/global rules. |

**Exit:** Two hosts and the desktop share one controlled engine per installation and one writer per universe. Closing the UI does not lose active operations. No universe access is granted merely by a guessed project path.

### WP07 — Proposal, approval, commit, and receipts

**Dependencies:** WP03, WP05, WP06; final executable-rule admission gate integrates WP08. **Primary area:** `universe-service`.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP07.1 | Domain operation compilation, immutable proposal versions, lifecycle, reserved IDs, explicit rebase. | New-record references resolve atomically; submitted edits invalidate old bindings. |
| WP07.2 | Exact approvals, current scoped grants, protected-change classification, author decisions. | T07–T11; proposal content cannot grant itself application authority. |
| WP07.3 | Commit sequence with short writer/authorization gate, current-head recheck, atomic receipt. | T01–T10; crash/retry produces no duplicate revision or phantom success. |
| WP07.4 | Operation lookup by ID/key, cancellation, interrupted recovery, idempotency tombstones. | Lost-admission and lost-commit-response scenarios recover exact outcomes. |
| WP07.5 | Immutable full world/shared write footprints, resolved-ID digests, cross-world approvals/commits, and scoped receipt recovery. | Cross-world effects commit exactly once as a unit; no world-filtered partial commit or mismatched-universe recovery. |

**Exit:** One successful commit is one atomic, attributable revision under retries and concurrent requests. Before executable validators are integrated, their capabilities remain unavailable; a structural-only prototype is not advertised as continuity validation.

### WP08 — Basic time and declarative checks

**Dependencies:** WP02, WP05. **Primary area:** `universe-rules`.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP08.1 | Exact/half-open/uncertain temporal values and finite ordering checks. | Boundary, missing-endpoint, approximate-overlap, and wrong-calendar tests. |
| WP08.2 | Evidence algebra, exact comparisons, finite membership/cardinality, completeness prerequisites. | Truth-table/property tests; no negation-as-missing-data. |
| WP08.3 | Rule compiler, typed scope/applicability, bounded AST and variable evaluation. | Unsupported operators and exhausted work produce visible coverage results. |
| WP08.4 | Simple scalar, exclusivity, prerequisite, and author-boundary validation stages. | Silver-gate basic conflicts and false-positive controls pass against the pure fixture. |
| WP08.5 | Universe-wide versus world-specific rule applicability, unspecified scope, and explicit independent world clocks. | Local overrides require scoped exceptions; unknown inter-world time conversion stays indeterminate. |

**Exit:** The implemented checks are deterministic and bounded, and cannot report undefined prerequisites as satisfied. New checks integrate into WP07 without changing permission/approval semantics.

### WP09 — Store-backed research and state queries

**Dependencies:** WP03, WP04, WP05, WP06, WP08. **Primary area:** queries, `universe-mcp` adaptation.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP09.1 | Authorized universe/definition discovery and immutable context handles. | No cross-universe or cross-revision leakage; expiry cannot silently select a newer head. |
| WP09.2 | Exact/name/FTS search, typed filtering, stable cursors, batched record reads. | Ambiguous names remain candidates; pagination retains its query/revision/grant binding. |
| WP09.3 | Basic state and evidence retrieval with negatives/completeness/alternatives. | “Empty result,” “denied,” “failed,” and “undefined state” remain distinct. |
| WP09.4 | Budgeted context assembly and authorization/version-aware caching. | Mandatory rule overflow is disclosed; cached author briefs cannot serve a restricted principal. |
| WP09.5 | Universe-required research, selected-world dependency expansion, shared/unassigned inclusion, and scope-bound cursors/caches. | No default world; no cross-universe leakage; world-filtered checks do not omit necessary shared/cross-world constraints. |

**Exit:** MCP and typed client queries return the same effective canon and evidence for an identical authorized frame. Search relevance does not determine validation completeness.

### WP10 — Sources, import/export, backup, and restore

**Dependencies:** WP05, WP07. **Primary area:** source storage, maintenance/CLI.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP10.1 | Immutable blobs, decoded-text versions, byte-accurate anchors, safe source metadata. | Unicode/normalization/encoding/changed-source tests; anchors remain exact. |
| WP10.2 | Logical archive/JSONL/source-text import staging, mapping preview, explicit ID-conflict modes. | Malicious archive and malformed payload tests; no automatic canon from prose. |
| WP10.3 | Complete and filtered logical export with manifests/digests and no installation credentials. | Restore preserves IDs; filtered snapshots declare omissions. |
| WP10.4 | Consistent live backup, reachable-blob pins, restore validation, retention-aware garbage collection. | Backup/write/GC race, interrupted archive, missing asset, and separate-directory restore drills. |
| WP10.5 | Whole-universe backups, dependency-closed partial exports, named restore/clone conflict handling, and explicit v0.3 conversion. | All world/work identities and bindings restore; partial world export is not mislabeled a complete backup. |

**Exit:** Restore reproduces selected current and historical queries plus source anchors. Successful file copy alone does not pass this gate. Recovery exists before substantial author data is entrusted to the application.

### WP11 — First usable Dioxus author workflow

**Dependencies:** WP01, WP03, WP07, WP09; source preview integrates WP10. **Primary area:** `universe-ui`, desktop.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP11.1 | Connection/context shell, explorer, entity inspector, stable paged selection. | U03, U05; stale data cannot replace another universe's view. |
| WP11.2 | Qualified values, fictional-time and relationship editors, explicit draft autosave. | U04; no default-to-zero, absence coercion, or hidden direct canon write. |
| WP11.3 | Exact proposal/effect diff, findings/coverage, approve/reject/commit workflow. | U06, U07; binding changes invalidate stale UI actions. |
| WP11.4 | Keyboard/VoiceOver behavior, safe sources, native adapters, component provenance. | U01–U02, U08–U09 in the packaged fixture and alpha workflow. |
| WP11.5 | Universe library, world focus selector, shared/unassigned views, works/sagas browser, and scope-bound drafts/async requests. | Two open universe tabs cannot cross-save; the complete cross-world footprint is visible before approval. |

**Exit:** Phase 2's author/agent loop works with real storage and authority: define, query, propose, validate, review, commit, re-query, restart. The desktop is not an independent interpretation of universe rules.

### WP12 — Events, knowledge, completeness, and rule kinds

**Dependencies:** WP08, WP10; commit integration uses WP07. **Primary area:** domain evaluators.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP12.1 | Event effect compilation, explicit order, pre/post-state, persistence and time-ended assertions. | S07–S09, S25–S32; mismatched generated effects rejected structurally. |
| WP12.2 | Epistemic attitudes, observation, communications, memory, nested beliefs, knowledge gaps. | S02–S04, S10, S14–S16, S33–S34; no omniscience from presence. |
| WP12.3 | Completeness and creative-boundary intersection, scoped exceptions, norm/tendency distinctions. | S05–S06, S11–S20, S35; no forbidden/impossible conflation. |
| WP12.4 | Capability registry showing executable, descriptive-only, unsupported, and partial semantics. | S40–S45 and unsupported round trips; no hidden fallback to a model. |
| WP12.5 | Cross-world journeys/messages, persistent traveling identities, explicit endpoints, and shared-resource dependencies. | Arrival does not create another character; world A/B knowledge and local time are not inferred from one another. |

**Exit:** The full semantic acceptance suite passes for the declared implemented capabilities. Unsupported complex time/causality is preserved and honestly reported.

### WP13 — Impact, jobs, evidence, and cache correctness

**Dependencies:** WP12. **Primary area:** validation orchestration/performance.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP13.1 | Conservative impact traversal with record and query-scope dependencies. | Adding a fact invalidates prior absence/cardinality conclusions. |
| WP13.2 | Durable validation jobs, budget/cancel behavior, result pagination, resume/restart policy. | Evaluation coverage and delivery coverage remain independent. |
| WP13.3 | Finding fingerprints and scoped resolutions; cache keys include all semantic/access bindings. | Changed facts/rules cannot inherit a stale resolution or privileged result. |
| WP13.4 | Reference-evaluator parity and measured bounded-query profiling. | Property-generated changes and randomized order match full reevaluation wherever completeness is claimed. |
| WP13.5 | Cross-world/shared-rule impact closure and narrative-version invalidation with permission-safe reporting. | A global rule change reaches affected works/worlds; restricted dependencies yield coverage limits, not a false pass. |

**Exit:** “Complete” has executable evidence for the requested check scope. Optimization cannot drop applicable rules or mask incomplete impact. Fine-grained incremental performance is optional; conservative correctness is mandatory.

### WP14 — Continuities, all domain packs, and narrative evidence

**Dependencies:** WP10, WP12, WP13. **Primary area:** branch/schema/pack management.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP14.1 | Pinned branch baselines, explicit local overrides/tombstones, branch diffs and adoption proposals. | Parent changes do not silently alter child canon; historical definitions stay pinned. |
| WP14.2 | Versioned custom types/properties/forms and reviewed pack install/upgrade. | No schema change is needed just to represent another catalog category. |
| WP14.3 | All 19 source-domain fixture pairs in §34.2. | Minimal cases round-trip; misleading cases retain their distinctions. |
| WP14.4 | External work/version/scene/passage, viewpoint, narration time, commitments/reveals. | Reader position does not become fictional time; sources remain evidence rather than manuscript-editor state. |
| WP14.5 | Universe-wide continuity inheritance plus many-to-many worlds/works/sagas and historical selector resolution. | Parent edits do not leak into forks; one story can span worlds and distinct edition bindings remain explicit. |

**Exit:** Broad coverage is data-driven and does not imply universal simulation or evaluation. Release documentation distinguishes representable definitions from executable semantics.

### WP15 — Release hardening and operational readiness

**Dependencies:** WP04, WP06, WP10, WP11, WP13, WP14; all final gates. **Primary area:** packaging, security, performance, operations.

| Subtask | Implementation output | Required evidence |
|---|---|---|
| WP15.1 | Release package, verified helpers, offline resources, update/maintenance protocol, supported OS manifest. | Clean supported Mac, no developer tools, no required outbound requests for universe operations. |
| WP15.2 | Security/fuzz/fault suites across IPC, source previews, imports, permissions, secret-oracle paths. | No known release-blocking bypass or silent false pass within the declared threat model. |
| WP15.3 | Workload benchmarks and resource budgets, cold/warm profiling, diagnostic runbooks. | Measured figures recorded against actual hardware; failures are not relabeled as achieved targets. |
| WP15.4 | Golden upgrade projects, rollback/restore drills, release checklist, SBOM/component provenance. | Native UI/host compatibility, schema/receipt/history preservation, and reproducible core build evidence. |
| WP15.5 | Named-universe scope regression, multi-universe backup/restore and fairness drills, and generated schema audit. | V01–V40 have release evidence; no remaining root-world APIs, silent defaults, or untested migration claims. |

**Exit:** All supported required cases pass; unsupported configurations are labeled; no unresolved critical corruption, authorization, false-validation, or recovery defect is waived for release. An unmet performance target requires explicit scope/target revision and evidence, not a hidden benchmark exception.

### 33.16 Dependency and integration order

Implement WP01's architecture/fixture foundation, then WP02. WP03/WP04 and WP05 can progress in parallel after their inputs are stable. WP06 and WP08 follow storage/contracts; WP07 may build its structural transaction path concurrently but does not pass its executable-rule gate before WP08 integration. WP09 and WP10 then support WP11's first usable loop. WP12–WP14 add semantics and coverage; WP15 integrates the whole release.

Security, diagnostics, negative tests, and recovery are embedded in earlier packages. WP15 verifies them together rather than first introducing them. Do not advertise a fixture adapter, an unvalidated commit prototype, or a visually complete desktop as a product alpha before WP11's end-to-end gate.

### 33.17 Per-change definition of done

A merged change includes the requirement/work-package/test IDs, negative cases, schema/example updates, migration or compatibility effect, safe error behavior, and diagnostic fields. Changes affecting assertions/time/rules run semantic tests; writes run retry/crash tests; rendering runs malicious-preview tests; protocol changes run host/contract tests; dependency changes run provenance/license/native compatibility checks.

Planned repository automation exposes one checked-in entry point for formatting, linting, unit/property tests, contract validation, migration tests, headless integration, native UI checks, host interoperability, package verification, and fixture/benchmark generation. CI must show which expensive/native suites actually ran; a skipped suite is not a pass.

<a id="section-34"></a>

## 34. Expanded acceptance and traceability

The original S01–S45, T01–T35, and U01–U10 cases are retained. The E cases below close implementation gaps made explicit in this revision. D cases cover the entire original domain catalog. Every case is specified, not executed by writing this plan.

### 34.1 Additional cross-cutting cases

| ID | Setup / action | Required outcome |
|---|---|---|
| E01 | End a possession assertion at E20, then query before/after and an older editorial revision. | Earlier possession remains; ending validity is not editorial deletion or proof of its opposite afterward. |
| E02 | Compile an event whose effects alter several assertions; interrupt admission. | Event and all canonical effect assertions are admitted together or none are. |
| E03 | Store a planned event with complete effect specifications. | No objective effect is applied solely because the plan is canon. |
| E04 | Two unordered effects consume the same exclusive resource. | Joint availability/order is checked; insertion order is not invented as fictional order. |
| E05 | An uncertain time interval possibly intersects an exclusivity interval. | Potential overlap is indeterminate unless evidence establishes a definite conflict. |
| E06 | Universal/existential query over an incomplete collection and over a complete empty one. | Correct witness/counterexample/completeness behavior; empty search is not empty reality. |
| E07 | Clear a field, submit false/zero/empty text, and submit an explicit absence separately. | Four distinct meanings remain distinguishable in canon and UI. |
| E08 | Import/export a descriptive rule with an unsupported operator and rich temporal value. | Bytes/meaning survive; no executable pass is claimed. |
| E09 | Rule applicability itself has unknown or conflicting evidence. | Potential applicability stays indeterminate; no vacuous successful check. |
| E10 | A local exception appears to override a stricter ancestor boundary without authority. | No implicit permission widening; exact exception authority is required. |
| E11 | Agent labels a new predicate “ordinary detail” while changing protected capabilities. | Grant evaluation follows actual effects/definitions, not a supplied friendly label. |
| E12 | An event effect and its supposedly generated assertion disagree. | Structural rejection; author waiver cannot admit broken effect linkage. |
| E13 | A local client sends `client_kind=author` with a collaborator credential. | Collaborator authority only; no administrative access. |
| E14 | Paired universes differ only in hidden facts; restricted agent asks distinguishing validation questions. | No secret-dependent yes/no oracle; authorized-scope or generic restricted coverage. |
| E15 | Hidden documents contain search terms matching a restricted query. | No hidden titles/snippets/counts or global ranking metadata disclosed. |
| E16 | Restore a universe backup made before an installation grant was revoked. | Revocation remains current; portable data cannot restore tool authority. |
| E17 | Change a property/rule schema on the parent after a child fork. | Parent and child/historical interpretations use their own pinned definitions. |
| E18 | Interrupt snapshot/projection generation, then restart with a bad checksum. | No partial cache used as canon; verify/rebuild from immutable source. |
| E19 | Backup and GC overlap with a new blob reference and later head edits. | Snapshot-required and newly reachable blobs are retained; completed backup restores. |
| E20 | Open one physical package through distinct aliases or a substituted runtime path. | One writer or safe rejection; no path-based authority bypass. |
| E21 | Register a copied package with the same universe ID as an existing live universe. | Explicit restore/clone decision; not independent writable replicas. |
| E22 | Lose the operation-admission response before learning its operation ID. | Lookup/retry by the original key recovers the existing operation and reserved IDs. |
| E23 | Encounter a future payload schema in an otherwise readable package. | Safe read-only preservation/refusal according to capability; no guessed semantic conversion. |
| E24 | Same finding wording recurs after its evidence or rule changes. | Old resolution does not automatically clear the new fingerprint. |
| E25 | Reorder JSON keys or change an exact proposal field around approval. | Canonical-equivalent content hashes consistently; changed semantic content invalidates approval. |
| E26 | Delete a record from current canon while an old anchor references its prior version. | Historical evidence remains resolvable; current required references are checked explicitly. |
| E27 | Package uses a wrapper crate whose actual bundled SQLite lacks the required WAL patch. | Build/release verification fails based on actual library evidence. |
| E28 | Full evaluation yields more findings than one response page. | Execution can be complete while delivery is paginated; omissions are explicit. |
| E29 | A queued job's original context expires or its owner disconnects; authorization changes before write. | Exact immutable input retained; current authority rechecked; no accidental rebase or stale grant. |
| E30 | Release-mode UI/MCP start offline after build caches and developer tools are removed. | Required assets/helpers are present; no registry/CDN/toolchain download at runtime. |

### 34.2 Domain fixture pairs

Each row defines **two distinct cases**, with explicit IDs: one minimal round-trip/query example and one adversarial semantic example. These implement the source catalog rather than adding compulsory author forms.

| Domain | Minimal fixture | Adversarial fixture |
|---|---|---|
| Reality, cosmology, and time | **D01M:** Two realms with separately defined laws and a crossing condition. | **D01A:** Inhabitants' cosmology conflicts with objective definitions without replacing them. |
| Geography and environment | **D02M:** Overlapping regions, a seasonal river, and a resource deposit. | **D02A:** No coordinate/flow/time value is invented from an unlabeled map image. |
| Life, ecology, and health | **D03M:** Species, population, individual condition, and authored survival requirement. | **D03A:** Typical species trait does not become a universal individual fact. |
| People, minds, and identity | **D04M:** One agent with contextual names, body, office assignment, and capabilities. | **D04A:** Clone/avatar/impersonator with matching appearance remains separately identified. |
| Kinship, households, and populations | **D05M:** Chosen family, multilateral partnership, household, and caregiving relation. | **D05A:** No binary ancestry tree or exclusive partnership constraint is introduced. |
| Culture and everyday life | **D06M:** Community customs, foodway, dress convention, and individual preference. | **D06A:** An individual's departure from a custom is not structural impossibility. |
| Government and political power | **D07M:** State, government, office, tenure, territorial claim, and effective control. | **D07A:** Sovereignty claim and actual control differ without being collapsed. |
| Law, justice, and diplomacy | **D08M:** Jurisdictional law, treaty roles, obligation, and proceeding. | **D08A:** A prohibited action can occur without automatically triggering its prescribed punishment. |
| Organizations and institutions | **D09M:** Institution, branch, memberships, resources, and leadership appointment. | **D09A:** Stated mission and actual practice remain independent assertions. |
| Economy, resources, and work | **D10M:** Currency/unit, inventory, production requirement, shipment, and debt. | **D10A:** Unknown exchange rate is unresolved, not a silently fetched real-world rate. |
| Religion, philosophy, and belief | **D11M:** Doctrine, institution, ritual, believer attitude, and sacred narrative. | **D11A:** An approved belief in a deity does not settle objective existence. |
| Language, knowledge, and communication | **D12M:** Language variant, contextual place name, literacy/fluency, and message. | **D12A:** Sending a readable message does not prove receipt, understanding, or belief. |
| Science, technology, and magic | **D13M:** Technique/device with cost, prerequisite, failure condition, and availability. | **D13A:** Possible in principle differs from usable by this actor at this place/time. |
| Settlements, buildings, and infrastructure | **D14M:** Building, rooms, entrances, occupants, supply source, and service consumer. | **D14A:** Hidden or unrecorded entrance is not impossible without applicable completeness. |
| Transportation, logistics, and security | **D15M:** Vehicle, route, mode, travel interval, capacity, and access condition. | **D15A:** Unknown route/speed does not become definite travel feasibility or impossibility. |
| Objects, art, and records | **D16M:** Work, edition, particular copy, custody, source contents, and authenticity claim. | **D16A:** A forged document's claims do not establish the described occurrence as real. |
| History, events, and processes | **D17M:** Compound event with ordered subevents, changes, causes claimed, and accounts. | **D17A:** Conflicting accounts are not silently reconciled into one fabricated event history. |
| Intentions, knowledge, and disputed information | **D18M:** Goal, plan, commitment, nested belief, observation, and disclosure. | **D18A:** Canonical future plan or prediction does not produce an occurred event. |
| Narrative and authoring records | **D19M:** External work/version/scene/passages with viewpoint and reveal position. | **D19A:** Retrospective narration/reader disclosure is not mistaken for character knowledge then. |

### 34.3 Test harness and release evidence

Use deterministic fixtures and a simple reference evaluator for the implemented finite semantics. Property tests generate alternative insertion orders, temporal bounds, reference graphs, exact quantities, and proposal batches. Persist random seeds for failures. Fuzz parsers, expression compilers, archive import, IPC framing, and safe preview inputs under resource limits.

Crash tests place explicit fault hooks before/after blob flush, rename, transaction begin, record insertion, receipt insertion, database commit, response serialization, and notification publication. Assert database state, receipt identity, and source reachability after restart. Do not test only returned error strings.

Native UI/host tests run on actual supported Mac builds. Browser screenshots and Linux headless tests can supplement them but cannot substitute for native clipboard, VoiceOver, WebView, signing, helper, and cold-launch behavior. Record skipped cases as skipped with a reason.

Store release evidence with test IDs, application/build/SDK versions, fixture revision, host/model configuration, OS/hardware, test commands, outcomes, logs/artifacts, and known limitations. A test catalog listing 198 specified cases is not evidence that 198 tests have run.

### 34.4 Named-universe and multi-world acceptance suite

V01–V40 are **additional specified cases**, not executed results. They complement the earlier isolation/revision tests. Every tool in V06 is parameterized individually, and the group remains one catalog case with per-tool execution evidence. Use at least two universes, duplicate world names across universes, multiple worlds in one universe, shared/unassigned records, and work/saga metadata.

| ID | Scenario | Required result |
|---|---|---|
| V01 | Create two named universes and open both in separate tabs/agent sessions. | Independent stable IDs, packages, canon heads, and authorized results; no process-wide active universe. |
| V02 | Create worlds Aster and Nacre inside The Ashen Cycle. | Both belong to one universe; queries can select either by exact name. |
| V03 | Create Aster in a second universe. | Allowed; world-name resolution remains inside the required universe. |
| V04 | Create duplicate/case-fold-equivalent or normalization-equivalent world selectors in one universe. | Canonical admission rejects the collision; no fuzzy merge or second target under the same selector. |
| V05 | Define a universe with no worlds and add shared definitions/work metadata. | Valid incomplete universe; no placeholder world required or silently created. |
| V06 | Omit universe on each published domain tool while supplying otherwise valid handles/IDs. | Every request fails its schema/service scope gate; no profile/context/UI fallback. |
| V07 | Supply null/blank/wildcard universe or world, or an ID guard without its required name. | Explicit invalid input; never all universes, default world, or inferred scope. |
| V08 | Supply an accessible universe name and another accessible universe ID guard. | Safe mismatch error and no query/write in either target. |
| V09 | Supply universe A with a context, proposal, validation run, record, or operation from B. | No auto-switch; safe namespace mismatch or generic inaccessible result. |
| V10 | Request a world that exists only in another universe or another inaccessible revision. | No cross-universe fallback or hidden candidate disclosure. |
| V11 | Repeat a world-focused query, then omit world with the same universe-level context. | Third request uses authorized universe scope; no remembered world focus. |
| V12 | Query without world when some records are shared, unassigned, or have unknown applicability. | Those records are not lost through a mandatory-world join; uncertainty remains explicit. |
| V13 | Filter to Aster while a relevant universe-wide rule applies. | Rule is included/evaluated; world focus is not a reason to omit it. |
| V14 | Filter to Aster while a portal/resource/route requires Nacre evidence. | Required authorized dependencies expand across worlds with labeled scope; otherwise explicit restricted coverage. |
| V15 | Reuse a world-focused cursor/cache entry under another world or universe. | Rejected or independent keyed entry; no stale cross-scope results. |
| V16 | Move a character and unique object from Aster to Nacre. | Same universe identities; explicit temporal location/effect updates, no duplicate entities. |
| V17 | A cross-world event fails on its destination update after source changes were prepared. | Whole universe changeset rolls back; no half-travel or split canon revisions. |
| V18 | World-A-only editor proposes a shared rule change or effect in world B. | Full footprint detects excess scope; requires different authority, never silently widens the grant. |
| V19 | Create a fact with omitted world selector and no authored applicability. | Universe ownership established, applicability remains unresolved; no fabricated universe-wide truth. |
| V20 | Add a world-specific rule conflicting with an applicable universe-wide rule. | Locality alone does not override it; require compatible authored scope/exception or report conflict. |
| V21 | Associate one novel with Aster and Nacre. | One work with multiple world associations; no duplication or mandatory primary world. |
| V22 | Associate several novels and stories with one universe/world. | Distinct work/version identities share the existing canon as bound. |
| V23 | Create a saga spanning multiple works and worlds, with a work in two groupings. | Typed nonexclusive memberships and authored ordering; no forced tree or independent saga canon. |
| V24 | Bind different editions/versions of a work to different universe continuities/revisions. | Each binding is explicit; reader order/edition is not a fictional event or automatic retcon. |
| V25 | A universe-wide rule edit affects references in multiple worlds and works. | Impact reaches all relevant authorized bindings or declares incomplete coverage; no current-book-only check. |
| V26 | Compare local dates from worlds with no established conversion. | Indeterminate comparison; shared universe revision does not establish simultaneity. |
| V27 | Rename a universe and use its retained old selector on an admitted-operation retry. | Same stable ID/receipt; old name is not rebound and alias spelling cannot duplicate a write. |
| V28 | Rename a world while an earlier canon context remains open. | Historical names/existence resolve at that frame; IDs remain stable and alias reservations cannot target another world. |
| V29 | Use a same-looking but distinct Unicode name or a near spelling. | No fuzzy/confusable auto-routing; preserve names and show authorized explicit identity choices. |
| V30 | Register two live packages with one universe ID, or import a conflicting universe selector. | Explicit restore/clone/rename decision; no independent writers or silent name reassignment. |
| V31 | Switch universe/world tabs while a draft save, validation, or response is in flight. | Captured scope stays fixed; late data cannot overwrite the newly selected view or commit into it. |
| V32 | Back up/restore a universe containing several worlds, cross-world facts, sagas, and receipts. | All referenced IDs, history, associations, and assets recover together; current installation grants remain separate. |
| V33 | Export one world with dependencies on shared entities and another world. | Explicit dependency-complete subset or declared external/missing references; not labeled a whole-universe backup. |
| V34 | Convert a v0.3-style root-world fixture to the universe hierarchy. | Explicit identity/revision mapping and provenance; no automatic assignment of all material to a child world or broader rule scope. |
| V35 | Run long validation in one universe while reading/writing another. | Global bounded fairness and per-universe writer isolation; no unnecessary universe-wide installation lock held for CPU work. |
| V36 | Commit in Aster while a Nacre edit uses the same universe continuity base. | One head advances; stale second base revalidates even though its visible world differs. |
| V37 | Restricted caller probes hidden universe/world names, counts, mismatches, or dependencies. | Generic safe errors/coverage; no hidden-name search, count, or validation oracle. |
| V38 | Call describe without universe or attempt mode all_universes; negotiate MCP/tools-list normally. | Domain request denied; protocol metadata remains usable without exposing canonical data. |
| V39 | Add world filtering to proposal validation, commit, recovery, or cancellation that binds a full object. | Conditional schema rejects it; no partial approval/validation/commit or retargeted job. |
| V40 | Create a canonical reference from universe A to universe B to model a crossover. | Rejected live cross-universe reference; use shared canon within one universe or explicit provenance-preserving import/copy. |


<a id="section-35"></a>

## 35. Operational runbooks and release checklist

### 35.1 Planned diagnostic/maintenance commands

Provide a versioned CLI with `doctor`, `status`, `operation`, `backup`, `restore-check`, `export`, `import-check`, `integrity-check`, `rebuild-projections`, and `maintenance` commands. Exact flags are generated from the same service contracts. Privileged commands require current author authority. No CLI command bypasses the running engine's writer ownership; offline recovery requires an exclusive maintenance lock.

Canonical-data CLI commands also require `--universe` by name and accept world focus only where meaningful. Library-level list/create/register/rename actions are explicit author administration, not unscoped MCP data tools. Command examples and diagnostics must show the selected universe.

These are planned commands, not tools already supplied by this document. The release documentation must include tested examples with actual installed paths and a clear statement of their read/write effects.

### 35.2 Failure runbooks

| Symptom | First diagnostic / safe response | Do not do |
|---|---|---|
| Commit response lost | Query by operation ID or original idempotency key; recover receipt. | Retry with a fresh key before determining the original outcome. |
| Engine unavailable | Check installed helper/profile, handshake version, lock owner, and sanitized logs. | Start an unrelated writer on the same package. |
| Disk full | Stop new mutation admission; preserve drafts and partial import status; free unrelated space or move via controlled maintenance. | Delete WAL files, receipts, or referenced blobs to make room. |
| Projection mismatch | Enter explicit degraded/rebuild state; rebuild a new generation from immutable data. | Treat missing indexed records as an empty universe. |
| Corrupt canonical database | Preserve original files; validate latest backups in another directory; restore only after verification. | “Repair” by deleting failing assertions without an audit trail. |
| Stale approval | Show changed base/proposal/rule/policy binding and require revalidation/review. | Reuse an approval because the proposal title stayed the same. |
| Grant revoked | Deny new affected reads/writes; reevaluate queued work and result disclosure. | Restore an old package to reactivate credentials. |
| Broken source anchor | Show the exact old source version and failed match; create a proposed new anchor. | Attach it to similar text silently. |
| Unsupported rule | Preserve definition and mark affected checks unsupported. | Convert descriptive prose to an executable rule through an invisible model. |
| Failed update/migration | Keep maintenance state; use verified prior package/snapshot according to compatibility rules. | Open a newer schema with an older writer that guesses a downgrade. |
| Host/model malformed calls | Return typed errors and inspect the recorded compatibility configuration. | Coerce guessed names, approvals, dates, or missing fields into canon. |

### 35.3 Release procedure

Freeze contract/record/rule/pack versions and the dependency/component lock manifest. Build and verify headless binaries and the desktop from the recorded toolchain. Run schema/example validation, semantic/property/fuzz regression, storage/recovery/migration tests, security tests, and benchmark tiers. Then run packaged native UI and all advertised host/model routes on the supported macOS matrix.

Inspect dependency and component provenance, licensing notices, included resources, and runtime network behavior. Sign/package the app and all helpers under the release process. Test installation, migration with active-client draining, closed-UI MCP startup, and explicit update rollback/recovery. Publishing/build-network steps are separate from offline universe operations.

Publish the compatibility/capability manifest, supported storage locations, actual performance measurements, known unsupported semantics, and recovery instructions. Ship only after all required gates are evidenced. Keep a golden universe and restore archive for each supported product release.

The release contract audit additionally checks that every published domain MCP tool has required `universe`, that all old root-level `world_*` tool names are absent from the current registry, that world selectors are conditional rather than universally required, and that no context/lifecycle example silently infers a universe. Run the two-universe/multi-world fixture in the packaged desktop and every advertised host route. Run V01–V40 and archive outcomes separately from this document’s structural checks.

### 35.4 Open implementation verifications—not unresolved product scope

| Verification | Resolution owner / gate | Default until verified |
|---|---|---|
| Exact compatible Dioxus/CLI/Tailwind/Rust/UI dependency set | WP01 native feasibility | Inspected 0.7.9 snapshot is a candidate, not a guaranteed build. |
| `rmcp` lifecycle compatibility with chosen LM Studio routes | WP04 host tests | No claim of support for an untested combination. |
| Supported macOS minimum and accessibility/native adapter behavior | WP01 and WP15 | Publish only actual tested OS support. |
| Bundled SQLite patch/extension state | WP05 and WP15 | Reject release if the actual library does not meet the patch/capability gate. |
| Performance and local-model resource coexistence | WP13 and WP15 | Report targets as targets; retain bounded jobs and resource admission. |
| Sanitized preview isolation in the pinned WebView | WP11 and WP15 | Plain-text or reviewed raster fallback for unsafe formats. |
| Code-signing/helper/update behavior on clean machines | WP15 | Release blocked until install and recovery paths are demonstrated. |

These checks do not reopen the agreed product scope or defer architectural thinking. They identify facts that require a real build, supported hardware, or a host integration run rather than another speculative decision.

<a id="section-36"></a>

## 36. Named universes, worlds, narratives, and scope migration

**Established requirement / High confidence:** The product is Universe Builder. It must support multiple universes identified by name, multiple named worlds within a universe, and novels/stories/sagas taking place within that universe. Domain tools always require explicit universe specification; world specification is optional where appropriate. The mechanisms below are proposed implementation contracts, not existing code or tested behavior.

### 36.1 Hierarchy and ownership

A **universe** is the outer application namespace for canon, revisions, permissions, packages, sources, and records. A **world** is an identifiable setting record within it. A **realm** is an authored physical/metaphysical domain; it may intersect, contain, or relate to worlds without being forced into an exclusive tree. A **work** identifies an external novel, story, or other narrative. A **saga/series** groups works with typed membership and ordering.

The installation library can manage many universes. Each universe can contain many worlds, and can also contain shared entities, rules, astronomical space, and records not assigned to a world. Nothing must be assigned to a fake “global world.” A newly created universe can have no worlds or works yet. Optional world information remains optional data, not an invalid incomplete project.

Every canonical record belongs to exactly one universe. Worlds and works are not independent copies of canon. A character traveling between Aster and Nacre keeps one identity; a source describing both worlds is one source with appropriate evidence anchors; a shared organization can operate in both without duplication. Location, origin, membership, relevance, and rule applicability remain different typed relationships.

Separate project universes do not share live canonical references or editorial heads. A story requiring shared cross-world canon should place those worlds in one universe. A fictional multiverse can therefore live within one application universe. Importing an entity from a separate universe creates explicitly mapped destination identity and provenance, not a hidden cross-database foreign key. No cross-universe atomic canon commit is offered.

### 36.2 Selector names, stable IDs, and uniqueness

Names are the required human interface; stable IDs are the internal identity. The top-level common fields are `universe: string` and optional `universe_id` consistency guard. World-capable commands may additionally accept `world: string` and optional `world_id` guard. A guard must match the resolved named target; it is not an alternative selection path. Missing/blank/null universe is invalid even with a valid context, proposal, receipt, or record ID.

**Proposed normalization policy:** Preserve the author’s exact display spelling. Compute a separate lookup key using a pinned Unicode version: trim surrounding whitespace, normalize to NFC, apply full case folding, then normalize to NFC again. Preserve internal whitespace and punctuation rather than silently collapsing them. Reject empty keys, wildcard sentinels, control characters, line breaks, and unsafe directional-control characters. Set documented length limits and test them without truncation. The starting maximum is 160 Unicode scalar values and 640 UTF-8 bytes; these are policy limits to implement, not current platform constraints.

Canonical and active-alias keys are unique for universe selectors within the installation library. World selector keys are unique to world identity within one universe; a world named Aster in another universe is unrelated and permitted. Entity names such as character names remain governed by their contextual naming rules and need not be unique. The universe/world routing rule does not introduce global uniqueness for every noun.

Fuzzy matches, substrings, visual confusables, and file/directory names never determine routing. Suggestions may be returned only for explicitly permitted discovery and may not expose hidden candidates. A generic `NOT_FOUND_OR_NOT_ACCESSIBLE` result is preferable to revealing that an inaccessible universe exists. Use stable IDs visibly in disambiguation when the author is authorized to inspect both targets.

A universe selector is administrative project metadata, not necessarily an in-fiction cosmological name. The installation catalog is its routing authority. Package exports retain identity and export-time label, while import registration resolves local name conflicts explicitly. Renaming that administrative label is audited but does not manufacture a fictional event or change universe identity.

A world’s selector label/aliases are versioned on its canonical World record. Two parallel worlds both called Earth in fiction can use distinct administrative selectors such as Earth Prime and Earth Mirror while retaining the same contextual in-fiction name. In-fiction names in other languages or eras remain separate contextual assertions. Resolve effective world names and existence using the requested continuity/revision and current access. Persist a universe-wide reservation from each admitted normalized world selector to its stable WorldId, preventing the old name from later naming a different world. The reservation is not, by itself, proof that the world exists in the current snapshot or is accessible.

### 36.3 Rename, alias, and admission behavior

Universe renames retain the previous routing name as a same-ID alias by default. World renames retain the previous label as an authored alias in the new record version; older revisions retain their original payload. Previously admitted selector keys are not reassigned to other identities. Removing an alias, when explicitly supported, leaves a reservation/tombstone rather than allowing silent reuse. Restore/clone workflows explicitly resolve conflicts. This trades a little name-reuse flexibility for protection against stale agent requests targeting a different setting.

Uncommitted proposals can request names but do not monopolize canonical name reservations. The commit gate checks normalized uniqueness and inserts new reservations atomically with the admitted world definition. Two competing proposals can both exist; only a compatible, current proposal can commit. A conflict returns a named-scope result, not a fuzzy entity merge.

A world record removed from the current continuity remains identifiable in historical frames. Its tombstone never moves related entities into another world or removes them from the universe. Query existence and applicability at the requested snapshot. A branch can retain an old world name, but cannot reuse that key for a different world identity merely because another branch renamed it.

Idempotency admission hashes resolved UniverseId/WorldId and immutable semantic input, not the spelling of a retained alias. Retrying an already admitted request via an equivalent alias resolves to its original receipt. Conflicting ID guards fail before execution. Receipt recovery still requires the explicit universe argument and current authorization.

### 36.4 Request resolution algorithm

1. Authenticate the principal and validate the closed tool schema. Reject absent or malformed `universe` before any context/record lookup.
2. Resolve the normalized universe name/active alias through the authorized installation catalog. Do not infer existence from another supplied ID or search unrelated universes.
3. Check optional `universe_id` and current universe access. Emit safe mismatch diagnostics only where doing so discloses no restricted target.
4. Resolve the immutable context or lifecycle object **inside that universe**. Check every continuity, revision, proposal, validation, cursor, record, and operation binding against the selected namespace. A mismatch never changes the selected universe.
5. On commands supporting `world`, resolve its exact effective name/alias in that universe’s pinned canon frame. Check the optional WorldId guard, existence, and current access. Otherwise reject an unsupported world field or use no individual-world narrowing.
6. Compile per-call read focus or local write envelope as appropriate. Expand evaluation dependencies according to actual authored applicability and access. A display focus never becomes a complete-validation boundary automatically.
7. Execute using stable identities. Echo permitted universe/world names, stable IDs, resolved frame, focus/dependency coverage, and any full write footprint in the result.

Context handles contain no remembered world. The UI can remember a world choice for a tab, but it must serialize that choice on each appropriate request. External clients may do the same. Tool calls lacking `world` remain universe-scope calls regardless of a prior request’s focus.

### 36.5 Omitted world versus selected world

| Request form | Read behavior | Mutation behavior |
|---|---|---|
| `universe` only | Query within the authorized selected universe/frame, including shared and unassigned records. No universal-completeness claim is implied. | Propose explicitly scoped operations anywhere within the caller’s grant. Omission does not make their facts universe-wide. |
| `universe` plus `world` | Focus relevant records on that named world; include applicable shared rules and necessary authorized cross-world dependencies. | For create/revise proposal actions, restrict the requested write envelope to that world; every scope/association is still explicit in the operations. |
| Lifecycle reference plus `universe` | Inspect the referenced immutable proposal/job/receipt as a whole under current permissions. | Validate/commit/cancel the bound object, not a filtered fragment; inappropriate world fields are rejected. |

For exact record lookups, a selected-world request must not silently drop an explicit target that does not fit the focus. Return a safe per-record scope mismatch or labeled required dependency according to the declared query contract. For search, show scope/relevance categories so shared records are not mislabeled as local ones.

Rule/assertion applicability uses a tagged structure such as universe-wide, explicit world-set, conditional, or unspecified. Universe ownership alone establishes none of those truth conditions. An unspecified scope that matters to validation yields a gap, rather than a universal rule or an excluded irrelevant record. “All universe content” in the UI is a selection state, not a database world named All.

### 36.6 Cross-world rules, authority, and transactions

Enumerate applicable universe-wide rules, selected-world rules, scoped exceptions, and dependencies required by the candidate. A world-specific rule does not automatically override a universe-wide rule merely by being more specific. Exceptions or applicability exclusions must be explicit authorial definitions. Laws/norms and physical requirements retain their different semantics.

Compute the **actual write footprint** from compiled operations: changed records, affected-world applicability, universe-shared definitions, identity effects, and cross-world event outputs. Compare it with both the requested local write envelope and the current authorization grant. Do not infer footprint from an operation’s display title or the UI’s current world.

A world-A-only editor can propose changes with permitted A-specific effects but cannot redefine a shared property, rename a protected universe entity globally, create another world, or alter B’s state through a supposedly local action. The service returns an explicit scope/approval requirement. A world-local new entity still receives a universe identity; its creation and associations are explicit and bounded, not evidence that the editor may alter all universe records.

For travel or other multi-world changes, omit the single-world selector, declare all endpoints/effects in the proposal, validate the complete footprint, and obtain the required cross-world authority. The event, ending state, beginning state, resource changes, and any asserted information effects commit together under one universe continuity head. A failure or timeout cannot leave a departure committed without its paired admitted effects. Effects are not automatically invented merely because travel occurred.

One revision head per universe continuity is deliberately conservative: concurrent edits on different worlds can still produce a stale-base conflict. They share canon and potentially rules/dependencies. Future granular concurrency requires separate correctness evidence and does not belong in this naming revision.

### 36.7 Works, sagas, and canon bindings

Store a narrative work once in its universe, with its kind, labels, description, external document/source references, and version records. Store saga/series membership separately with role/order metadata rather than requiring one parent. World associations are zero-to-many and may carry scene/period/relevance qualifiers. A work can span Aster and Nacre; multiple novels and stories can share those same world records.

Each work version identifies its continuity and canon-revision basis, or explicitly remains unbound/under review. Being included in a saga does not select an alternate continuity or give that work a private head. A work intentionally depicting several continuities declares segment/scene-level bindings instead of merging their contradictory facts. A cross-universe anthology is external library metadata unless its works are explicitly imported into a shared project universe; do not quietly relax the canonical reference boundary.

Preserve separate reader order, narration time, depicted event time, and local world time. Scene/arc/world associations do not themselves establish occurrences, travel, knowledge, or physical location. No manuscript-writing UI or internal model hosting is introduced.

Changing a shared universe definition must discover dependent work/version/scene anchors across all affected worlds, using their recorded canon bindings. A historical pinned edition is not silently rewritten; flag relevant review/impact against the proposed newer canon while retaining its earlier evidence. A filter for one novel cannot certify every other work in its saga.

### 36.8 Tool argument examples

These symbolic examples illustrate application arguments, not production-generated schemas or executed calls. Names/IDs/contexts below must already exist and be authorized.

`universe_search` — universe scope, including shared and unassigned content:

```json
{
  "universe": "The Ashen Cycle",
  "universe_id": "unv_ashen_cycle",
  "context_id": "ctx_ashen_main_r42",
  "query": "charged seal",
  "limit": 25
}
```

`universe_search` — one named world, using the same universe-level frame:

```json
{
  "universe": "The Ashen Cycle",
  "universe_id": "unv_ashen_cycle",
  "world": "Aster",
  "world_id": "wld_aster",
  "context_id": "ctx_ashen_main_r42",
  "query": "charged seal",
  "limit": 25
}
```

`universe_get_operation` — recover a lost response without letting an operation ID select its own universe:

```json
{
  "universe": "The Ashen Cycle",
  "universe_id": "unv_ashen_cycle",
  "operation_kind": "commit",
  "idempotency_key": "transfer-seal-to-nacre-1"
}
```

In the last example, adding a `world` filter is invalid; the receipt describes the entire admitted operation. The original full proposal can name both Aster and Nacre. Every operation in it belongs to The Ashen Cycle.

### 36.9 Storage, export, migration, and compatibility

The installation catalog identifies universes by stable ID plus unique name/aliases and package location. Each registered universe has one canonical package/database containing its world records, shared definitions, narrative metadata, continuities, sources, and operation receipts. Per-universe writers permit independent universes to progress while global queues bound CPU/memory use. There is no global transaction across separate universe packages.

Whole-universe backup/restore preserves all world IDs, cross-world links, work/saga associations, source anchors, and historical revision bindings. A selected-world export computes its dependency closure over shared definitions and other-world endpoints, or explicitly records unresolved/external dependencies. It must disclose its partial nature and never masquerade as a full backup. Access grants and installation credentials remain outside exports. Name conflicts on import require an explicit registration/clone decision; filenames never replace universe identity.

**Compatibility status:** No deployed v0.3 implementation or database has been demonstrated. The following is a conditional conversion requirement for any prototype fixtures/data that need preserving, not a claim that a production migration exists or has run.

Map the former root WorldId to the destination UniverseId explicitly, preserving the old identifier in migration provenance. Keep other record identities where structurally valid and record all namespace/reference translations. Do not blindly replace text inside source documents or fabricate a child world for every old record. Where the old package genuinely represents one physical world, the author may approve creation of a named World record and explicit applicability/association mapping; otherwise retain universe-owned/unassigned material and scoped uncertainty.

Do not broaden formerly local rules into universal ones without review. Map source revisions/continuities and retain original payloads/digests as provenance; where serialization changes, recompute destination digests and record the source-to-destination mapping rather than claiming cryptographic equivalence. Verify historical query/evidence behavior at mapped revisions and preserve unresolved mapping issues. Keep untouched backups before any conversion.

Rename binaries/modules/tool prefixes from root-level `world-*`/`world_*` to `universe-*`/`universe_*`, with the desktop product labeled Universe Builder. Because this is a planning revision, no legacy tool names are required by default. If an explicit legacy adapter is ever offered, it must require universe and reject ambiguous calls; it may not infer universe from a former context-only request. Version the application/schema contract when published clients actually exist.

### 36.10 Scope completion gate

WP01–WP15 contain direct subtasks for this model; V01–V40 specify the additional acceptance cases. The first usable milestone must already manage multiple named universes, multiple named worlds in one universe, explicit universe on all tools, and a multi-world narrative/character fixture. These are not postponed until a later database redesign.

Evidence must cover schema rejection, name/ID resolution, cross-universe isolation, world omission, dependency expansion, atomic cross-world effects, world-limited authority, narrative bindings, rename retries, historical names, UI tab isolation, and whole-universe restore. Document checks performed while revising this plan are not application integration or semantic test results.

<a id="section-37"></a>

## 37. Sources and verification notes

### Supplied basis

**[S0]** `Pasted text.txt`, supplied in this conversation. SHA-256: `128d845be08e6926a23ec0afe86b306bdfb2bde178c09ffacb16fb69134b337c`.

The original file includes an earlier combined writing/local-model application idea. The user’s subsequent explicit clarifications control this plan: universe management, exposed via MCP; writing and model operation remain outside the application. The earlier source’s top-level “world” is now the application universe, with actual worlds nested within it. The entity/fact/state model and its distinctions remain the source basis.

**[S1]** `World_Management_MCP_Implementation_Plan_v0.2_Dioxus.md`, supplied prior plan. SHA-256: `9ed0689b203ff4bc9977a5766b4981b8c58a7e7aa9b784b7aa3da4d56aaf5e79`. Its architecture, original work-package IDs, domain coverage, and S/T/U acceptance identifiers are consolidated here. Clarifications and newly proposed implementation details are listed in C01–C10 and §§27–35.

**[S2]** `World_Management_Full_Implementation_Plan_v0.3.md`, supplied prior consolidated plan. SHA-256: `bf0c05ec006f6721dc5d6925473727eeee0fe9b8af7f101f50800c0446a437e0`. Its implementation details, 15 work packages, and 158 S/T/U/E/D acceptance cases are retained with the universe namespace correction; new decisions are C11–C17 and §36, and new acceptance cases are V01–V40.

**[S3]** Explicit user requirement in this conversation on September 20, 2026: “This design must account for multiple worlds, identified by name. In fact, we need to switch nomenclature to universe builder. One or more novels/stories/sagas may take place in a universe and a universe can contain multiple worlds. So the tools must require specification of universe and may include specification of world along with whatever other params are appropriate per command.” This instruction overrides the earlier root-world nomenclature. Name matching, storage grouping, alias reservations, per-call omission semantics, and migration mechanics are proposed engineering consequences, not quotations from the original brief.

### Official external documentation and repository evidence

The v0.3 source plan reports that R01, the MCP-via-API page in R02, R03, the SDK catalog in R04, R06–R07, the stdio page in R09, R10–R13, R15, and the pinned README/manifest in R16–R17 were reopened on September 20, 2026 during that earlier revision. These technical sources have **not** been reopened or independently reverified for v0.4; their observations are retained as attributed source-plan material, not fresh research. R05, R08, R14, R18–R19, the ordinary function-tool page in R02, and the HTTP transport page are retained as earlier source notes, not presented as newly reverified. The source observations about installation-page drift and demo numeric parsing are retained from v0.2, not independently reproduced in v0.3. Framework/component claims below are source observations; architecture choices and acceptance targets remain our design.

**[R01] LM Studio — Use MCP Servers.** Documents local/remote MCP host configuration and warns about context overhead.  
`https://lmstudio.ai/docs/app/mcp`

**[R02] LM Studio — Using MCP via API; Tool Use.** Documents configured MCP integrations, required settings, and the external function-execution loop for ordinary tool calls.  
`https://lmstudio.ai/docs/developer/core/mcp`  
`https://lmstudio.ai/docs/developer/openai-compat/tools`

**[R03] MCP — Tools, specification 2026-07-28.** Tool schemas, structured content, annotations, state handles, and error reporting.  
`https://modelcontextprotocol.io/specification/2026-07-28/server/tools`

**[R04] MCP — Official SDKs and Rust SDK.** Current SDK availability and documented protocol compatibility; exact release must be pinned/tested during implementation.  
`https://modelcontextprotocol.io/docs/2026-07-28/sdk`  
`https://github.com/modelcontextprotocol/rust-sdk`

**[R05] MCP — Versioning and Compatibility.** Current/older lifecycle differences and interoperability requirements.  
`https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning`

**[R06] Dioxus 0.7 — Building User Interfaces.** Rust/RSX UI, HTML/CSS, reactivity, and platform-renderer support.  
`https://dioxuslabs.com/learn/0.7/essentials/ui/`

**[R07] Dioxus 0.7 — Desktop.** System WebView/Wry, native Rust execution, browser API distinctions, and JavaScript bridge. This documents mechanisms, not a complete application sandbox.  
`https://dioxuslabs.com/learn/0.7/guides/platforms/desktop/`

**[R08] Dioxus 0.7 — Publishing.** Desktop bundling and local asset inclusion; native package behavior must be tested.  
`https://dioxuslabs.com/learn/0.7/guides/deploy/`

**[R09] MCP — Transports: stdio and Streamable HTTP.** Transport framing, security requirements, and compatibility behavior.  
`https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio`  
`https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http`

**[R10] SQLite — Write-Ahead Logging.** Reader/writer behavior, one-writer constraint, filesystem restrictions, checkpointing, durability settings, and the WAL-reset defect. The page states that 3.51.3 and later include the fix, with named backports 3.44.6 and 3.50.7. This is a source-backed minimum patch gate, not a claim that any SQLite build was tested for this application.  
`https://sqlite.org/wal.html`

**[R11] SQLite — Online Backup API.** Consistent snapshot backup mechanics.  
`https://sqlite.org/backup.html`

**[R12] SQLite — Foreign Key Support.** Connection-level enforcement configuration.  
`https://sqlite.org/foreignkeys.html`

**[R13] SQLite — FTS5 Extension.** Built-in full-text indexing capabilities.  
`https://sqlite.org/fts5.html`

**[R14] MCP — Security Best Practices.** Application/transport threat boundaries and authorization concerns.  
`https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices`

**[R15] Dioxus 0.7 — Bundle Config.** Extra-binary, resource, and macOS signing/entitlement fields. Not proof of a completed signed/notarized multi-binary release.  
`https://dioxuslabs.com/learn/0.7/guides/deploy/config/`

**[R16] rust-ui/ui — README.** Dioxus 0.7, Tailwind v4, source-copy distribution, experimental status, independent project, MIT license identification, and Node/pnpm development prerequisites.  
`https://github.com/rust-ui/ui`
`https://github.com/rust-ui/ui/blob/10dfc3511d03644dce1d05715d384a97c41662e1/README.md`

**[R17] rust-ui/ui — pinned Cargo manifest and commit metadata.** Reviewed commit `10dfc3511d03644dce1d05715d384a97c41662e1`, dated September 18, 2026; root manifest pins `dioxus`/`dioxus-html` to `=0.7.9`. Maintainer explanation of a 0.7.10 desktop publication issue is attributed, not reproduced.  
`https://github.com/rust-ui/ui/blob/10dfc3511d03644dce1d05715d384a97c41662e1/Cargo.toml`
`https://github.com/rust-ui/ui/commit/10dfc3511d03644dce1d05715d384a97c41662e1`

**[R18] Rust/UI — Installation.** Retrieved page describes Leptos and future Dioxus support, contrary to the current repository's Dioxus instructions. This discrepancy is recorded rather than treated as resolved.  
`https://rust-ui.com/docs/components/installation`

**[R19] Rust/UI — Data Grid.** Dioxus grid demo and source; demo numeric setters use default values after parse failure. Only presentation patterns are candidates for reuse; domain conversion behavior is not adopted.  
`https://rust-ui.com/docs/components/data-grid`

External documentation confirms the available interfaces and constraints. It does not prove the proposed application works, meets its latency budgets, or has passed these tests. All architecture, rule semantics, limits, and milestone choices above are the proposed design unless identified as an established requirement.
