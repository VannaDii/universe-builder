# Goal 40 — Declared knowledge acquisition

October 7, 2026. Goal 40 authorizes the bounded K1 communication-receipt lane
proposed in [Goal 34](decisions/goal-34-factual-constraints.md). It reuses
[Goal 39 chronology](communication-chronology-verification.md) and the existing
four-valued proposition evaluator. Observation acquisition, automatic understanding,
clock conversion and scoped global cardinality are outside this goal.

## Authored contract

An executable, universe-wide `physical_constraint` Rule with `always_block`,
unspecified validity, empty predicate/subject filters, literal true, and only
`knowledge.acquisition.v1` carries an explicit context policy:

```json
{"knowledgePolicy":{"context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"mode":"justified"}}
```

The other mode is `author_established`. Policies apply to propositions in that
exact represented context. Multiple matching policies are conjunctive. A policy
cannot share a Rule with a channel chronology contract or silently use generic
expression evaluation as a bypass. Unsupported policy shapes fail validation.

A `knows` attitude carries an optional, closed `acquisition` declaration:

```json
{"truthContext":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"exact","calendar":"cal_000000000000000000000001","value":"7"},"basis":{"kind":"communication_receipt","communication":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000030"},"interpretation":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000020"}}}
```

Truth context must match the proposition and the policy. Acquisition time and the
attitude's onset must be exact integer coordinates in the same authored calendar;
onset is an exact Instant or the exact start of CalendarInterval. Acquisition must
be at or before onset, and receipt at or before acquisition. Equality is legal.
Unknown, legacy unclocked or unmapped time remains unresolved. Every receipt basis
requires an actual holder recipient, an authored interpretation naming the exact
known proposition, that proposition in message content, and undistorted content.
Receipt alone does not infer interpretation. Distortion stays unresolved in this
slice; its interpreted transformed content requires a separately approved lane.
The message must pass all matching authored Goal 39 channel contracts, including
explicit reverse-time channels; missing chronology contracts remain unresolved.

Justified mode evaluates the proposition's particular claim in the declared truth
context at acquisition time through the existing scoped truth evaluator. An
optional `world` reference selects the exact world for truth evaluation; its
absence considers universe-wide evidence only. No realm is guessed. Unsupported
quantification, uncertain applicable evidence and unknown truth remain unresolved.
Refutation or conflicting truth refuses knowledge. Supporting proposition evidence
must exist; mentioning a proposition does not assert it. Ending truth later does
not erase knowledge of the fact at its earlier acquisition coordinate.

Author-established mode requires `basis: {"kind":"author_established"}` in the
acquisition plus the attitude's existing attributable `author_decision` evidence
basis. It does not require receipt or supported truth; it certifies an explicit
author establishment, not a justified acquisition chain. Existing authenticated
publication authority still applies. A direct basis under justified mode, or a
receipt basis under direct mode, is rejected. Belief, suspicion, rejection and
memory stay separate; this validator never promotes them to knowledge.

An absent declaration retains legacy canonical bytes. Legacy knowledge in a context
with no matching policy remains readable/admissible without certification. Under a
matching policy, absent acquisition stays unresolved. A newly declared acquisition
with no matching policy also stays unresolved. A policy in another context does
not impose meaning on unrelated legacy attitudes.

Shared admission reassesses the complete candidate, including unchanged knowledge,
so truth/message/policy corrections cannot leave an old successful dependent
validation authorizing publication. Findings bind exact rule, attitude, proposition,
context, communication, chronology and truth evidence versions. The existing
fingerprint also binds the base frame, proposal digest and evaluator identity
`finite-policy-v13-knowledge-acquisition`. No ordinary approval waives unresolved
or refuted acquisition. Exact-version historical adoption enters this same gate.
Historical revisions, old payloads and old validation evidence remain immutable.

The canonical model, public schema and fixed-column relational catalog/DDL are
updated in place for the unreleased model. There is no alternate storage schema,
opaque body fallback or migration of installed packages.

## Reproduction

```sh
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp -p xtask
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/knowledge_acquisition_pilot.py --output /tmp/goal40-knowledge-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/audit_knowledge_acquisition.py /tmp/goal40-knowledge-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/test_knowledge_acquisition_audit.py --evidence /tmp/goal40-knowledge-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/communication_chronology_pilot.py --output /tmp/goal40-chronology-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/audit_communication_chronology.py /tmp/goal40-chronology-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/test_communication_chronology_audit.py --evidence /tmp/goal40-chronology-RUN-ID
RUST_TEST_THREADS=2 cargo run --locked -p xtask -- check
```

The Python environment uses `jsonschema==4.25.1`. Both public drivers use real
stdio MCP proposals, validation/refusal, reviewed approval/publication, immutable
reads and a forced engine restart. Authenticated author review/approval uses the
existing CLI. Disposable installations/profiles are removed and engines stopped;
fictional typed backups, raw wire and reports are retained locally for audit.

The separate Python oracle imports neither driver nor Rust evaluator. It decodes
normalized SQL, verifies canonical hashes, reconstructs all candidate and historical
memberships, independently calculates the bounded truth/order cases, and checks
findings, fingerprints, approvals, commit disposition, actual MCP reads and restart.
Its independent truth oracle deliberately supports only the exact instance,
universe-wide boolean fixture; general evaluator semantics remain covered by the
workspace suite. This oracle was authored in this session by the implementing
agent; there was no separate human or agent review. Forgery controls test evidence
audit rejection, not additional engine admission cases.

## Limits

No observation/sensory acquisition, automatic understanding, nested attitude
inference, memory accessibility/decay, prose entailment or clock conversion.
No new native controls or native/VoiceOver interaction qualification. The public
factual workflow exposes the typed declarations; existing native attitude editing
does not supply these new fields. No live author data, installed bundle replacement,
package migration, deployment, hosted CI, signed release or clean-machine acceptance.
The requested correction proof exercises truth facts; communications are checked
as dependencies, but this goal does not claim a separately executed communication
retcon proof. Raw local proof artifacts are reproducible evidence, not a committed
portable evidence bundle.

## Execution record

The final fresh Goal 40 run passed **26 cases, 207 actual MCP calls, six reviewed
publications and 32 independently reconstructed validations**. It covers valid
interpreted receipt, knowledge before receipt/onset, wrong actual recipient/content,
missing interpretation, distorted content, unknown/refuted/conflicting truth,
false belief, missing declarations, unknown/unmapped acquisition clocks, direct
establishment under its explicit policy, and incompatible bases under either mode.

Correcting truth at acquisition invalidated unchanged dependent knowledge. Ending
truth later retained supported acquisition history. Correcting the truth onset
required an atomic correction of the dependent claim to belief. Restoring the
original knowledge through historical adoption was still refused against corrected
truth. Three original record payloads/digests and the corrected current state survived
a forced restart; fresh policy and corrected-truth checks still refused admission.

The required Goal 39 regression passed **24 cases, 222 MCP calls, 11 reviewed
publications and 35 independently reconstructed validations**, plus its 14
numerical/audit controls. Goal 40's authentic saved-evidence control and six
intentional forgeries passed (seven tests). Four Rust regressions cover policy
context isolation, absent policy, unsupported policy shape and exact clock ordering.

`xtask check` passed formatting, workspace tests, doc tests and schema freshness:
**402 Rust tests passed; two existing opt-in workloads remain ignored**. The ordinary
10,050-record import/backup/restore/restart test passed. Final strict workspace/all-target
Clippy passed after the last code changes. Closed contracts passed 26 schemas,
13 valid and 91 invalid examples, six source-assessment and five action-contract
tests. The existing stdio MCP smoke passed discovery, malformed mutation rejection,
Unicode/isolation/output contracts, denial, retry/receipt recovery, adapter restart
and both protocol versions.

One initial driver run stopped on an incorrect SQL lookup column after its first
14 cases; the identity lookup was fixed without changing semantic expectations.
The first audit-forgery test invocation expected the wrong exception class; the
auditor correctly rejected each forgery, and the harness was corrected to expect
its existing RuntimeError. A preliminary successful run preceded the added
historical-adoption/clock/restart cases. Only final evidence directories are retained;
failed and superseded knowledge runs were removed. No portable raw evidence copy
or extra committed validation report was created.

[Compact proof metadata](knowledge-acquisition-proof-results.json) records final
local evidence paths, report/wire/package and helper hashes, cleanup and limits.

Working wall time through final verification: **27 minutes 13 seconds**, from
October 7, 2026 11:47:50 PDT (18:47:50 UTC) to 12:15:03 PDT (19:15:03 UTC).
This includes implementation, builds, failed attempts, repair, proof and test waits.
Final commit and completion reporting follow in this session.
