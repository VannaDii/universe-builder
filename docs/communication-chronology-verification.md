# Goal 39 — Authored communication chronology

October 7, 2026. This goal authorizes the bounded K2 lane proposed in
[Goal 34](decisions/goal-34-factual-constraints.md). It does not authorize
knowledge acquisition, global cardinality, clock conversion, or generic causality.

## Authored contract

Existing Rule records optionally carry a closed `channelChronology` object:

```json
{"channel":"letter","forwardOnly":true,"minimumDelay":"2","maximumDelay":"10"}
```

The capability is `communications.chronology.v1`. Supported contracts are
executable `physical_constraint` rules with `always_block`, explicit
`universe_wide` applicability, `unspecified` validity, empty subject/target
filters, literal-true expression, and only this capability. The expression is
a carrier; it is not evaluated as a separate pass that can bypass chronology.
Unsupported contract shape or inconsistent/non-integer bounds fails validation.
Existing rule records omit the optional field and retain their canonical bytes.
The typed relational catalog, source-contract snapshot, DDL and public contracts
are updated in place for the single unreleased model; there is no opaque body
fallback, alternate software schema, or migration of live packages.

Delay is the signed receipt coordinate minus send coordinate, in that
message's clock ticks. Minimum and maximum are optional inclusive signed i128
integer bounds. Forward-only independently requires delay >= 0; simultaneous
receipt is legal when its authored bounds permit zero. `forwardOnly: false`
explicitly permits negative delay, subject to its signed bounds. For example
`minimumDelay: "-10", maximumDelay: "-2"` permits receipt 2–10 ticks before send.
Matching channel names are exact and case sensitive. Multiple contracts for one
channel all apply; neither latest rule nor record order wins.

At least one authored contract activates candidate-wide chronology admission.
With no contract the lane is inactive, preserving existing factual admission
without certifying chronology. Once active, a missing channel identity/rule,
absent receipt, receipt with no actual recipient, nonexact/unsupported coordinates,
unmapped clocks or overflowing delay yields NotEstablished/Unsupported findings,
partial coverage, and refused admission. Exact same-calendar integer coordinates
alone are comparable. Cross-calendar conversion expressions are not executed.
Sender, intended recipients and actual recipients remain distinct entity references;
an actual recipient need not be intended and can also be the sender. All actual
recipients share this record's authored receipt time. No recipient, delivery,
knowledge, or conversion is synthesized.

Validation rechecks the complete candidate, including untouched communications
when a rule changes. Findings bind communication and matching rule versions;
uncovered messages bind their communication version. The existing validation
fingerprint binds the base frame, proposal digest, evaluator, outcome and evidence.
Ordinary approval cannot waive an unresolved or refuted contract. Correction uses
existing exact-version tombstone and authored replacement operations; old messages,
old findings and pinned factual revisions remain immutable. Evaluator identity is
`finite-policy-v12-communication-chronology`.

## Reproduction

Use the existing Python proof environment with `jsonschema==4.25.1`:

```sh
cargo build --locked -p universe-cli -p universe-engine -p universe-mcp -p xtask
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/communication_chronology_pilot.py \
  --output /tmp/goal39-chronology-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/audit_communication_chronology.py \
  /tmp/goal39-chronology-RUN-ID
PYTHONPATH=scripts /tmp/ub-goal34-venv/bin/python scripts/test_communication_chronology_audit.py \
  --evidence /tmp/goal39-chronology-RUN-ID
RUST_TEST_THREADS=2 cargo run --locked -p xtask -- check
```

The public driver uses real stdio MCP proposals, validation, commit refusal,
approved publication, immutable record reads and context opens. Authenticated
author review/approval uses the existing CLI. All installations are disposable.
A SQLite backup and raw wire transcript are retained before credential cleanup.
The independent auditor imports neither driver nor evaluator: it reconstructs
candidate/historical membership from typed SQL, calculates signed delay with
Python arbitrary precision integers, compares every finding and fingerprint,
and binds approvals, commits, refused head/count movement, actual MCP reads and
restart to their wire/storage evidence. Its expected case inventory is authored
separately. Forgery controls exercise audit rejection, not engine admission.

## Scope limits

No new native UI controls or native/VoiceOver qualification; the contract is
available through the existing public factual rule workflow. No live author data,
installed development bundle replacement, package conversion, model host,
production deployment, hosted CI or release acceptance was performed. Different
receipt times per recipient require separate authored communication records.
General paradox solving, arbitrary date formats, approximate/relative clock
arithmetic, clock conversions and justified knowledge remain outside this proof.
The opt-out regression is deliberately not a chronology certificate. Adding a
contract may require simultaneous correction of legacy unruled/unreceived facts.
Existing unchanged packages under the previous typed DDL have not been migrated
or qualified against this revised unreleased model.

## Execution record

The first fresh driver run stopped while storing its new rule because the
relational catalog had not yet been refreshed. It did not reach the chronology
proof inventory. The mapping was repaired. Two further driver attempts exposed an identity already reserved by a rejected proposal and an incorrect assertion about the helper's structured error shape. The driver now uses fresh identities and checks the actual error code/field. The full proof was rerun in a new installation; no oracle expectation was relaxed to obtain a pass.


Final execution: `/tmp/goal39-chronology-r4/` passed **24 cases, 222 actual MCP
calls, 11 reviewed publications and 35 independently reconstructed validations**.
Legal authored delivery, forward min/max boundaries, simultaneous receipt,
permitted negative delay, rejected forward reversal and both signed-bound
violations are covered. Missing rules/identity, unreceived/intended-only messages,
unmapped/unknown clocks and arithmetic overflow remain unresolved. Sender,
intended and actual-recipient distinctions and conjunctive rules are retained.
Three malformed delay contracts were refused through actual validation calls.
Rule activation rechecked and rejected a previously admitted reversed message;
an atomic authored correction enabled activation. Five historical reads and the
corrected message's version/digest/payload survived one forced engine restart;
a fresh reversed candidate still rejected after restart.

A separate agent reviewed the implementation and independently authored the
oracle/auditor. Six numerical suites, one authentic saved-evidence control and
seven deliberate forgeries passed (14 tests). The audit recomputes every finding,
its fingerprint, coverage and admission from candidate history rather than
trusting the driver's classifications. No remaining audit findings were reported.

Final `xtask check` passed formatting, workspace/all-target strict Clippy,
**398 Rust tests**, doc tests and generated-schema freshness. Two opt-in workloads
remain ignored: the release workload and overlapping-history retrieval benchmark.
The ordinary 10,050-record import/backup/restore/restart test passed. An earlier
workspace run overlapped relational regeneration and rejected the independently
seeded large archive's schema; the final coherent rebuild and complete shared
gate passed without weakening archive checks. Closed contracts passed 26 schemas,
13 valid and 91 invalid examples; five existing action-contract regressions
passed. Independent stdio MCP smoke passed 13-tool discovery, 91 malformed
mutations, Unicode/isolation/output contracts, denial, retry/receipt recovery,
adapter restart and both negotiated protocol versions.

The implementation and public driver/auditor are committed as
`34028150c54fec65f5bbf37696e01946b7be576c`.
[Machine-readable proof metadata](communication-chronology-proof-results.json)
records exact evidence and helper hashes, test counts and cleanup. Raw report,
wire transcript and typed backup are local disposable proof artifacts, not a
portable committed evidence bundle. Reproduce with the commands above.

Report SHA-256:
`cfa45bb23dcecf4180f64f3120c7296ec9876b9a9dde51765f3d90767e3c4914`.
Wire SHA-256:
`59afe63939ebe065da5645d2e0a41dfe6e5e6a96c12d255cccd48ed3fb4399cb`.
Typed package SHA-256:
`dcd941b99a7e05a7bb2ad1f1d4f187a01cf8e609a5647e4ba18c1fc186b5f484`.
The pilot engine was stopped and its installation/profiles removed; the retained
package backup contains disposable fictional facts and workflow evidence.

Working wall time through final verification: **23 minutes 15 seconds**, from
October 7, 2026 11:22:53 PDT (18:22:53 UTC) to 11:46:08 PDT (18:46:08 UTC).
This includes build/test waits, failed attempts, repair and independent audit.
Final proof-document commit and completion reporting follow in the same session.
