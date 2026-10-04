# Canonical-family qualification — Goal 25

October 4, 2026. All 38 canonical families have supported public workflow,
independent relational reconstruction and historical/restart evidence. The
inventory is the owning `RecordKind` enum, reconciled with the fixed `Payload`
codec catalog and prior proofs; adding a catalog entry alone does not count as
qualification. The [machine-readable matrix](canonical-families-coverage.json)
links every family to its exact proof set and publication keys.

The new disposable pilot observes 33 families, including all previously
uncovered families and repeated source/editorial coverage. The five others
(`entity_type`, `unit`, `action_definition`, `event`, `assertion`) retain the
existing normalized-foundation and real MCP resource/owner/history proofs.
Those prior MCP transcripts were not rerun for this goal; the current full
workspace gate reran their Rust foundation, rule, action, event and persistence
regressions. Existing semantic outcomes remain unchanged.

## Evidence and independence

[Proof results](canonical-families-proof-results.json) pin the final evidence
hashes. Raw stdio MCP transcript, private staging/author reviews/approval,
read-only SQLite backup, frozen input, build identity, auditor output and gate
log are retained locally under `docs/evidence/canonical-families-complete/`. Each pilot
installation was disposable, its owned engine was stopped, and its temporary
profile credentials were removed with the installation. Credentials and
handshakes are never included in evidence.

`scripts/canonical_families_pilot.py` executes seven reviewed publications,
239 MCP calls, 27 invalid/unauthorized candidates, eight snapshot readbacks and
two SIGKILL/recovery cycles. Before/after engine service identities establish
both restarts. Commit retries return exact prior receipts. Every publication
first attempts a commit without approval, obtains private author approval of
the exact candidate/validation and then commits through MCP.

`scripts/audit_canonical_families.py` imports only the separately implemented
read-only SQL decoder, not the Rust writer, evaluator or pilot. It reconstructs
all 70 canonical versions and 200 workflow bodies, verifies original hashes,
and independently replays immutable commit changes. Every full historical MCP
snapshot must equal that revision's reconstructed membership and occur in the
wire transcript under that exact revision. Every reviewed assignment and
public commit receipt is bound to its stored version and wire evidence.

Exact UTF-8 (decomposed/composed accents, emoji, CRLF, tabs and excerpt byte
ranges), PNG original bytes across two media chunks, dimensions, original name,
duplicate ordered image references/captions, intended/actual recipients and
communication content remain intact. The original external image is deleted
before correction/restart; final author preview and independent original-byte
reconstruction still succeed. A frozen pre-storage media checksum prevents a
changed report from becoming the byte oracle.

Appearance wording, work edition bindings and saga order are corrected by
existing public operations. Old editions remain immutable and scene/passage
pins still target the exact original work-version row after replacement.
Public historical adoption re-admits original bodies under new immutable
versions while original/corrected revisions remain readable after restart.
The rule is left at its original version so its exception's exact rule pin
remains valid. Belief, observation, communication, memory, fictional secrecy,
plans and breached commitments produce no objective assertions or occurred
events; the actual MCP state query also returns no assertions.

Invalid candidates cover dangling references across goal, commitment,
observation, saga, scene, work source, pack, exception, completeness, boundary
and memory; cross-universe communication; wrong holder/property/work/anchor/
image/edition kinds; wrong source/edition pins; nonexistent work revisions and
continuities; missing communication receipt time; forged excerpts/imported
media; split UTF-8 ranges; and agent-origin issue decisions. A failed validation
cannot be forced into publication using a prior approval/run. Canonical
versions, commits, changes, head membership and receipts stay unchanged. A
syntactically admitted rejected candidate may legitimately retain its typed
proposal/validation workflow evidence. Unenrolled, world-restricted and revoked
profiles cannot disclose shared source/media/secret/communication records;
failures retain the established generic denial or disconnected response.

Nine auditor tests include the untouched evidence and eight adversarial
mutations: communication content, historical revision, edition pin, authority
counts, denial content, missing public wire readbacks, source bytes and media
chunk deletion. All pass; the eight corruptions are rejected.

## Inventory matrix

`G25` means the new public observations plus independent SQL/history/wire audit
and two restart cycles. `foundation` means the frozen normalized kernel proof;
`MCP resources/owners/history` identifies prior actual public workflow audits.
The matrix's physical table names come from the current fixed catalog.

| Family | Typed body | Prior evidence | Public/history proof | Unresolved limitation |
|---|---|---|---|---|
| `entity` | `r_payload_v0` | foundation; MCP resources, owners, history | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `appearance` | `r_payload_v1` | codec only; kernel media tests | [G25](canonical-families-proof-results.json) · pinned-editorial-commit, corrections-commit, historical-adoption-commit | — |
| `image_asset` | `r_payload_v2` | codec only; kernel media tests | [G25](canonical-families-proof-results.json) · image-commit, historical-adoption-commit | — |
| `world` | `r_payload_v3` | foundation; MCP resources, history | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `realm` | `r_payload_v4` | codec only | [G25](canonical-families-proof-results.json) · historical-adoption-commit | Creation absent; seeded original → public adoption. |
| `work` | `r_payload_v5` | codec only; MCP history | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `work_version` | `r_payload_v6` | codec only; MCP history | [G25](canonical-families-proof-results.json) · families-commit, corrections-commit, historical-adoption-commit | — |
| `scene_ref` | `r_payload_v7` | codec only; MCP history | [G25](canonical-families-proof-results.json) · pinned-editorial-commit, historical-adoption-commit | — |
| `passage_ref` | `r_payload_v8` | codec only | [G25](canonical-families-proof-results.json) · pinned-editorial-commit, historical-adoption-commit | — |
| `saga` | `r_payload_v9` | codec only | [G25](canonical-families-proof-results.json) · families-commit, corrections-commit, historical-adoption-commit | — |
| `entity_type` | `r_payload_v10` | foundation; MCP history | [rules/events](normalized-rules-events-proof-results.json) · history | — |
| `property` | `r_payload_v11` | foundation; MCP resources, owners, history | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `relation` | `r_payload_v12` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `unit` | `r_payload_v13` | foundation; MCP resources | [rules/events](normalized-rules-events-proof-results.json) · resources | — |
| `calendar` | `r_payload_v14` | foundation; MCP resources, owners, history | [G25](canonical-families-proof-results.json) · public readback | — |
| `value_definition` | `r_payload_v15` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `domain_pack` | `r_payload_v16` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `proposition` | `r_payload_v17` | foundation; MCP resources, owners, history | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `assertion` | `r_payload_v18` | foundation; MCP resources, owners, history | [rules/events](normalized-rules-events-proof-results.json) · resources, owners, history | — |
| `represented_context` | `r_payload_v19` | foundation; MCP resources, owners, history | [G25](canonical-families-proof-results.json) · public readback | — |
| `completeness` | `r_payload_v20` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `boundary` | `r_payload_v21` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `rule` | `r_payload_v22` | codec only | [G25](canonical-families-proof-results.json) · families-commit | — |
| `exception` | `r_payload_v23` | codec only | [G25](canonical-families-proof-results.json) · pinned-editorial-commit, historical-adoption-commit | — |
| `event` | `r_payload_v24` | codec only; MCP resources, owners, history | [rules/events](normalized-rules-events-proof-results.json) · resources, owners, history | — |
| `item_power` | `r_payload_v25` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `action_definition` | `r_payload_v26` | codec only; MCP resources, owners, history | [rules/events](normalized-rules-events-proof-results.json) · resources, owners, history | — |
| `epistemic_attitude` | `r_payload_v27` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `observation` | `r_payload_v28` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `communication` | `r_payload_v29` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `memory` | `r_payload_v30` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `secret` | `r_payload_v31` | codec only | [G25](canonical-families-proof-results.json) · historical-adoption-commit | Creation absent; seeded original → public adoption. |
| `goal` | `r_payload_v32` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `commitment` | `r_payload_v33` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |
| `source` | `r_payload_v34` | foundation | [G25](canonical-families-proof-results.json) · exact-source-source-commit, historical-adoption-commit | — |
| `source_version` | `r_payload_v35` | foundation | [G25](canonical-families-proof-results.json) · exact-source-source-commit, historical-adoption-commit | — |
| `anchor` | `r_payload_v36` | foundation | [G25](canonical-families-proof-results.json) · anchor-commit, historical-adoption-commit | — |
| `issue_decision` | `r_payload_v37` | codec only | [G25](canonical-families-proof-results.json) · families-commit, historical-adoption-commit | — |

## Demonstrated repairs and executed gates

A real MCP control exposed acceptance of a work binding to a nonexistent
revision. Kernel admission now requires every bound or segmented edition
reference to resolve in its declared continuity and universe. Editorial
scene/passage pins also require a `WorkVersion` target, in addition to the
existing exact record/version identity check. These checks run in preview,
publication, historical reads and recovery. They reuse typed storage and do
not add operators, inference, new record families or new story semantics.

The focused kernel regression rejects missing revisions, mismatched
continuities, a segment containing a bad revision and a pinned target of the
wrong kind. Preview/commit rejection leaves all typed tables, canonical history
and receipts unchanged. Valid bound/unbound edits and a pin to the historical
edition remain valid after restart.

Passed `cargo run --locked -p xtask -- check`: formatting, workspace Clippy
with warnings denied, 341 tests, zero failures, documentation tests and generated
contract freshness. One pre-existing release-mode workload test remains ignored;
this is not a workload qualification. The real MCP pilot, separate SQL auditor,
nine auditor tests, Python compilation and `git diff --check` also pass.

## Limits and reproduction

Realm and Secret have no public creation operation. Their original disposable
rows are seeded through the existing typed Kernel by the test-only
`seed_family_history` example; their qualified public write route is exact
historical adoption. Their original/adopted bodies, permission boundaries and
restart history pass the same independent proof. This does not claim a public
creation API, add one, or treat fictional secrecy as an application grant.

Native UI/VoiceOver, live author-package conversion, installation/export
cutover, broader epistemic/causal inference and general simulation remain
outside this record-family qualification. Those existing limits do not become
new acceptance requirements or inferred story semantics.

Use a Python environment containing the existing `jsonschema` test dependency:

```sh
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp
cargo build --locked -p universe-store --example seed_family_history
python scripts/canonical_families_pilot.py --output /tmp/universe-family-proof
python scripts/audit_canonical_families.py /tmp/universe-family-proof
python scripts/test_canonical_families_audit.py --evidence /tmp/universe-family-proof -v
cargo run --locked -p xtask -- check
git diff --check
```

The output directory must be new. Only the explicitly owned disposable
installation is staged, approved, killed, restarted or shut down. SQL audits
open evidence read-only; adversarial tests mutate separately copied temporary
packages, never the original evidence. No live installation, Docker container,
external service, migration or deployment was used.

Active working time through final verification: 31 minutes 44 seconds; commits and completion report follow in the same continuous session.
