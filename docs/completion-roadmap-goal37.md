# Goal 37 — Current completion and remaining roadmap

October 6, 2026 (America/Los_Angeles). Audited checkout: `main` at `8847ead`,
initially clean. Goal 35 landed through `94472d8`, `bb5cafb`, `5c5dcea`,
`32ae2bb` and `b89fb39`; Goal 36 follows through `982fd61`, `4016e6e` and
`8847ead`. This reconciliation changes guidance and documentation, not admission
semantics. The normative scope is the [factual universe roadmap](factual-universe-realignment-plan.md).
The [original continuity gaps and R01–R14](continuity-gap-remediation-plan.md)
remain traceable below; their superseded prose-certification requirements are not
silently reinstated.

“Verified” means the named bounded behavior has an executed proof, not that an
entire scenario, arbitrary manuscript or release is qualified. “Bounded” identifies
implemented representation/checks with an explicit remaining limit. “Decision”
means semantic implementation awaits explicit approval. “External” means execution
or acceptance remains separately authorized. Multiple statuses can apply to one
roadmap area. Proof pages link executable drivers, independent expected tables,
auditors and committed result metadata where available. Ignored `docs/evidence`
and `/tmp` artifacts are local evidence, not portable committed proof bundles;
reproduce them with the linked commands when unavailable. Historical test counts
and timings describe their original runs. The checks below describe this audit.

## Current matrix

| Roadmap or original scenario | Status | Demonstrated behavior and concrete proof | Remaining boundary or action |
| --- | --- | --- | --- |
| A — Normative relational model | Verified | One-parent definitions, incremental identity/classification, typed values/references/scope/time and mapped application persistence: [schema package and independent proofs](decisions/relational-storage/verification.md), [foundation](normalized-foundation-verification.md). | Single unreleased normative model; no alternate active serialized authority. Historical design findings describe the starting point. |
| B — Canonical families | Verified / Bounded | [All 38 family coverage entries](canonical-families-verification.md), including typed history, source/media, references and restart; [rules/actions/events reconstruction](normalized-rules-events-verification.md). | Realm and Secret lack public creation operations; their public historical adoption proof starts with disposable Kernel-seeded records. Representation does not establish realm-dependent evaluation. |
| C — Workflow and installation | Verified | [Frozen proposals/validation/approval/receipts](relational-workflow-verification.md), [relational grants/private credentials](installation-credential-persistence-verification.md), [assessment publication bindings](assessment-publication-verification.md). | Assessments remain optional attributed declarations. Grants and exact approval/delegation still control publication; source review is not a factual prerequisite. |
| D — Conversion, archives and recovery | Verified / External | [Offline conversion](operator-conversion-readiness.md) preserves supported histories/provenance and rejects unsupported inputs; [relational archive/restore](relational-archive-verification.md) covers hostile schemas, interruption, source/media and historical authority isolation. | No live data was converted. Inventory, supported-input verification, catalog/credential cutover and recovery choice require operator authorization; installation conversion targets are not self-contained backups. |
| E — Definitions and authoring | Verified / Bounded | [Ancestor applicability](ancestor-applicability-verification.md), [effective objects](effective-object-verification.md), [incremental operations](incremental-authoring-verification.md), [once-only initialization](instance-initialization-verification.md). | Unknown/conflicting applicability remains explicit. Refinement accepts resolved descendants; unrelated classification correction remains an explicit authored edit. Effective-object and incremental-operation native use is unqualified. |
| F — Cedar | Verified | [Independent Cedar table/MCP/history proof](cedar-workflow-verification.md): minimal Tree, local hazard/shared capability, stable Cedar refinement, authored height delta, missing water/season, correction, historical pinning and restart. | No inferred growth or biology. Impact inclusion is conservative dependency coverage, not a natural-language causality certificate. |
| F — Pistol | Verified / Bounded | [Pistol proof](pistol-workflow-verification.md): independent balances, owner transfer, exhaustion, reload debit, world/subtype controls and retcon/restart. [Opt-in resource resolution](resource-resolution-verification.md) closes the demonstrated unexplained-increase path under its policy. | Original admitted direct increase is retained as an opt-out regression. First observation is an authored baseline; integer/exact-unit stock and realm-free supported scopes only. Exact creative acceptance preserves an unexplained arrival. |
| G — Remaining factual enforcement | Decision | [Goal 34 current-build probes, corrections and restart](decisions/goal-34-factual-constraints.md) establish the absence of K1–K3 policies. Its auditor checks structural/wire consistency, not independently recomputed semantics. | K1 justified knowledge, K2 channel chronology and K3 scoped cross-instance cardinality remain proposals. No extension is approved by this reconciliation. |
| H — External writer protocol (Goal 35) | Verified / External | [Integrated actual MCP workflow and 18 audit controls](resource-resolution-verification.md#goal-35-external-writer-workflow--october-6-2026): setup, unknowns, reviewed start, pinned stale context, restricted reader, clarification/acceptance, fresh canon and recovered receipt. | Scripted caller; receipt loss occurs after delivered response, not packet loss. External model interpretation and intended host remain unqualified. |
| H — Measured retrieval (Goal 36) | Verified / Bounded | [Reference parity and historical isolation](retrieval-performance-goal36.md) for ancestry, rule targeting, event-time lookup and context; end-to-end impact equals complete projection. | Local debug samples; 4,745-record impact hits the 65,536-byte response bound. No production-scale graph, release-mode SLA or narrowed impact claim. Optimize further only after a measured need. |
| G01 — Action classification | Bounded / External | [Owning-action proof and retained model failures](novel-authoring-readiness.md#wall-traversal-and-declared-powers-october-2-verification), [declared effects](declared-action-effects-verification.md). Submitted action requirements enforce exact owners. | External AI/author must classify prose correctly. A mislabeled declaration does not become a full prose check. |
| G02 — Incapable actor acts | Verified / Bounded | [G02 independent MCP proof](g02-action-applicability-verification.md): legal/illegal owner/pre-event cases and earlier incapacity correction; [Pistol holder controls](pistol-workflow-verification.md). | Enforce authored attributes/capability requirements; no default physical feasibility. |
| G03 — Unlimited resources | Verified / Bounded | [Exact transition proofs](resource-transition-verification.md), [cumulative proof](cumulative-resource-verification.md), [opt-in factual accounting](resource-resolution-verification.md). | Exact supported stock and time, finite work budgets, explicit policy and author resolutions; no universal conservation law. |
| G04 — Unrelated grant | Verified / Bounded | [Required/permitted effect-slot proof](declared-action-effects-verification.md) checks role, recipient, condition, time and scope; undeclared effects reject. | Authored causal contracts only; arbitrary causality is not inferred. |
| G05 — Opposing evidence | Verified / Bounded | [Comparison kernel](decisions/g05-detector-verification.md), [public policy/correction/history proof](decisions/g05-public-workflow-verification.md) and [current inherited conflicts](ancestor-applicability-verification.md). | Report opposing chains without truth promotion; policies decide admission, unresolved comparisons stay partial. Earlier prose/integrated-story completion wording is historical under the replaced boundary. |
| G06 — Impossible knowledge | Bounded / Decision | [Explicit attitude/context cases](../crates/universe-rules/tests/semantic_acceptance.rs), [Goal 34 knowledge probes](decisions/goal-34-factual-constraints.md). Belief, presence and communication do not automatically become knowledge. | `Knows` matches authored attitude; truth/basis/acquisition-chain enforcement awaits K1. An explicit admitted attitude is not a justified-knowledge certificate. |
| G07 — Communication chronology | Bounded / Decision | [Family reference/receipt-time validation](canonical-families-verification.md), [forward/reversed/unreceived probes](decisions/goal-34-factual-constraints.md). | Current admission does not enforce sent-before-received or per-channel latency. K2 must define forward/reverse-time and cross-clock rules. |
| G08 — Global cardinality | Bounded / Decision | [Finite collection cardinality implementation](../crates/universe-rules/src/basic.rs), [local roles and current relation probes](decisions/goal-34-factual-constraints.md). | Finite explicitly supplied collection counts and per-instance roles do not aggregate distinct participants across dynamic relation instances. K3 awaits approval. |
| G09 — Appearance mismatch | Bounded / External | [Appearance/history/media regressions](semantic-release-verification.md#additional-semantic-and-durability-evidence), [family source/media audit](canonical-families-verification.md). Accepted typed attributes use factual checks. | Appearance text/images are authored references; no automatic image/prose consistency or attribute extraction. |
| G10 — Citation interpretation | Verified / Bounded | [Exact source/anchor and passage audit](chapter-retcon-verification.md), [assessment source/version bindings](assessment-publication-verification.md). | Byte identity and attributable assessment do not prove entailment; external interpretation still needs review. |
| G11 — Source-only contradiction | Verified / Bounded | [Explicit input/assessment state and atomic binding](validation-binding-verification.md), [selected assessment publication](assessment-publication-verification.md). | Source-only archival publication is legitimate. Its receipt does not certify manuscript continuity or silently add facts; ordinary factual proposals need no assessment. |
| R01 — Flashbacks/retrospective narration | Bounded | [S01–S10 time/context fixture](semantic-release-verification.md#bounded-silver-gate-scenarios), [chapter perspective/history proof](chapter-retcon-verification.md). Narration time is distinct from acting-character story time. | Does not infer acquisition links or interpret nonlinear prose generally; K1 applies only if approved. |
| R02 — Lies/dreams/embedded stories | Bounded | [S14/S15 account isolation and S16/S33/S34 nonpromotion](../crates/universe-rules/tests/semantic_acceptance.rs), [occurred-only effects](declared-action-effects-verification.md). | Context and occurrence mode must be explicitly submitted; external AI identifies figurative/unreliable accounts. |
| R03 — Aliases/disguises/twins/pronouns | Bounded / External | [Identity-preserving rename/refinement](instance-initialization-verification.md), [contextual names/collisions](../crates/universe-service/tests/support/completion.rs). | Stable IDs separate owners. No general pronoun/disguise resolution proof; ambiguous references require external clarification. |
| R04 — Body swaps/possession/clones | Bounded / Decision | [Possession-owner controls](g02-action-applicability-verification.md), [explicit identity/memory family round trip](canonical-families-verification.md). | Body/mind ownership, clone copying and shapeshift transfer have no generic policy. Record explicit authored facts; additional semantics require a separate decision, not automatic K1 approval. |
| R05 — Amnesia/implanted memory | Bounded / Decision | [Memory/attitude persistence](canonical-families-verification.md), [belief nonpromotion](../crates/universe-rules/tests/semantic_acceptance.rs). | Generic accessibility transitions, restoration and memory-dependent action policy are not qualified; false remembered content is not an occurred event. |
| R06 — Loops/time travel/dilation | Bounded / Decision | [Reviewed story-clock operations and independent-calendar cases](authoring-verification.md), [exact temporal controls](../crates/universe-rules/tests/semantic_acceptance.rs). | No generic loop reset/carryover, clock conversion or paradox solver. K2 does not implicitly authorize them. |
| R07 — Travel/pursuit/simultaneous scenes | Bounded | [Atomic cross-world travel with stable identities](../crates/universe-service/tests/support/completion.rs), [simultaneous resource hazards](cumulative-resource-verification.md). | Travel duration, route/access and multiple bodies require explicit authored conditions; no geometry or default speed. |
| R08 — Injury/healing/aging/gradual processes | Bounded | [Incapacity/retcon cases](g02-action-applicability-verification.md), [Cedar explicit height/time controls](cedar-workflow-verification.md). | No unauthored biological rates, elapsed-time growth or decay. Broader schedules need explicit facts/contracts and relevant qualification. |
| R09 — Conditional artifacts/nested possession | Bounded | [Possession powers/timers and exact owner requirements](semantic-release-verification.md#implemented-behavior), [G02 scoped controls](g02-action-applicability-verification.md). | Custody alone is not wear/touch/access; nested reachability or proximity is not inferred. No comprehensive locked-container simulation proof. |
| R10 — Only/never/everyone/last | Bounded / Decision | [S11–S13 completeness/expiry, finite quantifiers](../crates/universe-rules/tests/semantic_acceptance.rs), [objective membership controls](semantic-release-verification.md). | Discovery is not completeness. Broader open-world inference and dynamic global counting remain outside current checks; K3 only if approved. |
| R11 — Retcons/delayed consequences | Verified / Bounded | [Cedar downstream arithmetic correction](cedar-workflow-verification.md), [Pistol history](pistol-workflow-verification.md), [chapter/source/edition correction](chapter-retcon-verification.md), [stale approval bindings](validation-binding-verification.md). | Only represented links/constraints are deterministic; natural-language dependencies can be absent. Conservative impact does not extract them. |
| R12 — Mysteries/delayed reveals | Bounded / External | [Exact edition/scene disclosure and restricted dependency checks](../crates/universe-service/tests/support/audit.rs), [character/reader chapter views](chapter-retcon-verification.md). | Reader context requires explicit disclosures; indirect spoilers/dialogue implications and actual host delivery are not comprehensively qualified. |
| R13 — Promises/betrayal/succession/arcs | Bounded / Decision | [Goal/commitment families](canonical-families-verification.md), [advisory norms/tendencies](../crates/universe-service/tests/support/completion.rs). | Representation does not enforce fulfillment, succession counts or judge arcs; K3 and any fulfillment policy need explicit author decisions. |
| R14 — Metaphor/ellipsis/implied action | Bounded / External | [Retained chapter producer failures and narrow accepted source audit](chapter-retcon-verification.md), [external writer instructions](ai-authoring-workflow.md). | No unrestricted implication extraction. External writer/author maps claims or preserves uncertainty; model self-review is not full qualification. |
| Native interaction/VoiceOver | External | [Earlier native loop and recorded pause](authoring-verification.md#native-evidence-and-limits); current forms have headless compilation/service evidence. | User pause remains in force. Resume only when authorized; effective-object/incremental controls still lack current interaction proof. |
| Intended model host | External | [Separate local MLX results and failures](novel-authoring-readiness.md), [Goal 35 protocol boundary](resource-resolution-verification.md#goal-35-external-writer-workflow--october-6-2026). | LM Studio remains restricted while Bionic stays open; no host activation or model substitution here. Agree intended host/model and authorize testing first. |
| Live migration/cutover | External | [Supported offline operator proof and explicit exclusions](operator-conversion-readiness.md). | Inventory actual inputs, preserve originals and verify private targets before authorized cutover. No production migration claim. |
| Distribution and environment acceptance | External | [Sealed development package and facilitated gates](semantic-release-verification.md#facilitated-final-testing), [release runbook](release-runbook.md). | Hosted CI execution, clean-machine/offline, supported-OS, signing/notarization and release acceptance remain unverified here. No configured remote in this checkout; no publication performed. |

## Reconciliation repairs

- Current entry points now use the factual roadmap and link this matrix; dated
  milestone proof counts remain historical evidence.
- Goal 33's old open-decision wording now points to its approved opt-in accounting
  resolution. No typed observation/correction schema was introduced; the original
  Pistol behavior remains an opt-out control.
- MCP initialization guidance, its existing audit assertion and both writer-facing documents now use
  `resource:<proposition record ID>`, matching
  [`resources::check_claim`](../crates/universe-service/src/resources.rs).
  The predicate/property selects the policy; the acceptance scope identifies the
  particular proposition. This is a guidance repair, not a semantic change.
- The authoring baseline no longer presents implemented event/state work as
  absent. Overall partial coverage and pending inference remain explicit.
- Existing knowledge and basic capability descriptions now state their observed
  limits: no justified acquisition/truth check, dynamic relation aggregation or
  channel chronology enforcement. Capability IDs and statuses are unchanged.

## Smallest remaining execution sequence

1. **Decide the next authorized lane.** K1–K3 in the [Goal 34 package](decisions/goal-34-factual-constraints.md)
   remain unapproved; choose any contract individually, with its authoring tradeoff.
   Defer contracts not needed by the intended factual workflow. R04–R06/R13
   extensions are not silently bundled with those choices.
2. **Implement only an approved bounded contract if selected.** Reuse current
   facts, rules and publication machinery where sufficient. Prove legal, illegal
   and unresolved public admission plus correction, historical reads and restart;
   preserve existing no-invention, authority and independent oracles. K2 precedes
   receipt-based K1 acquisition qualification if that acquisition basis is chosen.
   K3 is independent. No work is required merely to fill a goal count.
3. **Resume external factual-workflow qualification only when authorized.** Use
   the intended host/model and current native controls, with factual mapping scored
   separately from engine admission and retained failures. Cover unknowns,
   clarification, exact approval, receipt recovery and continued fresh canon.
   Keep native/VoiceOver and host results separate; neither substitutes for the other.
4. **Authorize operator/release actions when needed.** Inventory live conversion
   inputs and qualify a private target before any cutover. Run the existing hosted,
   clean-machine/offline, OS and distribution gates against the exact release
   candidate before publication. Migration is unnecessary when no legacy data
   needs conversion. Choose its recovery/cutover separately from release approval.

These are dependency conditions, not a revised total goal count or new acceptance
requirements. Further retrieval optimization has no required next step without a
measured bottleneck; the existing impact budget and debug-only measurements stay
visible. No arbitrary prose certification, simulator, separate state ledger or
background service is needed to complete the factual boundary.

## Goal 37 checks

No native window, model host or live author installation was opened. The audit
did not explicitly launch Docker, but a subsequent inventory found automatically
launched MCP containers; the cleanup correction below records that omission. Fresh
protocol pilots used owned disposable installations and report stopped engines
and removed installations. The final shared gate passed against the repaired source.

The first resource audit attempt rejected the obsolete expected instruction
`resource:<predicate record ID>`. Its existing guidance assertion was corrected
to the proposition ID used by enforcement, then the same independent factual
expected table and all 18 controls were rerun successfully. No factual oracle or
admission expectation was changed to obtain that result.


Fresh checks in this goal:

- Closed-contract validation: 26 schemas, 13 valid and 91 invalid fixtures passed.
- Independent stdio MCP smoke: 13 tools, 91 malformed mutations, output schemas,
  Unicode, isolation, retry/receipt recovery and both negotiated protocol versions
  passed against rebuilt debug helpers.
- Persistent installation smoke: concurrent startup, exact review/approval/commit,
  current grants/revocation, operation recovery, forced termination and durable
  heads passed against rebuilt helpers.
- Goal 35 integrated rerun: 268 MCP calls, nine publications, ten snapshots,
  three forced restarts and independent acceptance/history reconstruction passed;
  all 18 authentic/forgery controls passed. Actual initialization delivered the
  corrected proposition-bound guidance. Local raw report, wire and typed package:
  `/tmp/goal37-resource-resolution.{json,jsonl,sqlite}`.
- Goal 34 rerun: nine current-policy admissions, three correction publications,
  pinned historical/current readback and restart passed the structural/wire audit;
  forged admission and historical payload were rejected. This verifies the
  documented enforcement limits, not K1–K3 semantics. Local evidence directory:
  `/tmp/goal37-factual-constraints/`.
- Matrix inventory and links: A–H, G01–G11 and R01–R14 each present; every local
  matrix target and referenced heading resolves. Scoped whitespace check passed.

Fresh resource report SHA-256:
`15f284448c4885f0ead1698ad01f020b93150056b1c9c57cac1d0847cbbfad1a`.
Fresh factual-probe report SHA-256:
`e3a03366ee9aa8a403cb0289316df2a55ebde0746b924bdf60d4594e5adec95e`.
These hashes identify the retained disposable proof reports; their installations
and credentials were removed. Source/model/native/release guarantees are not
inferred from those synthetic runs.

Final shared gate: `RUST_TEST_THREADS=2 cargo run --locked -p xtask -- check`
passed formatting, workspace/all-target strict Clippy, 398 Rust tests, doc tests
and generated-schema freshness. Two opt-in workloads were ignored: the standard
release workload and Goal 36 overlapping-history benchmark. The ordinary
10,000-entity import/backup/restore/restart regression passed. An earlier shared
run also passed; the final run includes both repaired source descriptions.

Working wall time through final verification: 9 minutes 54 seconds,
from October 6, 2026 at 18:10:35 PDT to 2026-10-07 01:20:29 UTC
(October 6 locally). This includes executed build/test waits. Final commit and
completion-report bookkeeping follow in the same session. No remote publication
or release acceptance is claimed.


## Docker lifecycle correction — October 6, 2026

The original claim that no container was opened omitted automatic MCP startup.
After the author requested cleanup, inventory and launcher-process working
folders identified three Sonar containers mounted read-only to this project and
three GitHub stdio containers launched from this project's working folder.
The other loaded project chats were idle; this cleanup required neither server.
All six used generated names and automatic removal, with no persistent volumes
or writable project mounts. They were stopped and automatically removed:
`b84712572845`, `621a3b55d7d2`, `a519903c4713`, `28173226aaf8`,
`69f49e834898`, `290f651793e5`.

A fresh inventory verified all six absent and no remaining project-mounted or
project-named containers. No project files, volumes or other projects' containers
were deleted by this cleanup. Automatic per-chat stdio startup remains a launcher
configuration limitation: compliant project naming and shared HTTP reuse have
not been implemented by this cleanup. The earlier factual/host test results are
unchanged; the inaccurate container-lifecycle claim is corrected here.
