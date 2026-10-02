# G05 validation and public workflow qualification

October 2, 2026. This integrates the [approved D01/G05 recommendation](g05-opposing-evidence.md) into validation and admission. It qualifies the structured public workflow; **G05 remains open for later prose and integrated-story qualification**. Other gaps, new public tools, and native interaction qualification are outside this goal.

## Implemented behavior

Candidate validation runs the approved comparison kernel over the complete structurally checked, event-expanded active snapshot. A separate optional `opposing_evidence` collection preserves definite and unresolved pairs, original assertion/proposition identities and versions, separate polarity chains, pinned dependency references, scope/intersection, closed uncertainty reason codes, coverage, and a candidate/frame/evaluator/policy-bound fingerprint. Automatic diagnostics alone do not deny admission; unresolved comparisons make coverage partial. Existing scalar and completeness denials remain separate.

`NoOpposingEvidence { subject, predicate, context }` uses the same kernel, exact resolved meaning, and four-valued evidence implementation. Its result describes absence of an opposing pair in the inspected candidate, rather than fictional truth. The existing rule policies decide admission; complete cell coverage and exact accepted exceptions are required for waiver. Unqualified consistency rules inspect dated evidence across its finite temporal partition, including both polarities and exception boundaries. The partition follows expression operands rather than target hints, submitted time, or unrelated contexts/clocks. Candidate-wide policy checks do not disappear because an unrelated proposal has a narrower footprint. Static explicit contexts also bind exception coverage; a context that cannot be resolved for a waiver is not guessed.

The evaluator binding is now `finite-policy-v4-opposing-evidence`. Both approval and commit reject reusable validation from another evaluator, and commit checks the approval's evaluator binding. Stored validation, approval, operation and commit history is retained. The closed IPC/envelope contract advances from 1 to 2; older IPC clients fail the existing version handshake. Public MCP tool count remains thirteen and generated closed schemas include the additive diagnostic and expression. Records containing the new expression use payload v2; unchanged historical records retain v1 and their original digests. Kernel admission, reads and logical archive validation accept supported versions without rewriting history. Existing native validation rendering already displays the complete result; no native interaction acceptance is claimed.

## Reproducible proof

Run the maintained pilot in its G05 mode, with saved binaries from the pre-G05 evaluator:

```sh
uv run --with jsonschema python scripts/continuity_gap_pilot.py --g05 \
  --old-bin-dir /absolute/path/to/pre-g05-binaries \
  --output docs/evidence/g05-public-YYYY-MM-DD-runN
```

Only disposable synthetic installations receive automatic author approvals. Operations and commits use the actual MCP executable and closed schemas; the existing private author CLI supplies exact approvals and source-independent review. The upgrade case first creates and approves a queued validation using the real pre-G05 evaluator, stops that engine, opens the same installation with the new engine, and exercises stale approval/commit rejection followed by fresh validation, approval, commit and restart.

The independent audit imports neither the runner nor the detector. It compares actual JSON-RPC requests/responses with recorded observations, reconstructs candidate/revision state from SQLite history, checks original polarity/target/dependency bindings and independently calculates half-open intersections, verifies exact approvals and canonical commit inputs against kernel receipts and SQL changes, confirms blocked attempts have no receipt or head movement, and compares restart/history reads. A frozen policy oracle in the audit is independent of the runner's observations. Tamper tests alter copies of wire requests, approvals, kernel receipts, head membership and historical versions; each must fail audit. This is independent program/storage verification, not external human review.

The final proof is [`g05-public-2026-10-02-run8`](../evidence/g05-public-2026-10-02-run8/comparison.json), with committed [results and artifact hashes](g05-public-workflow-results.json).

- Rust: **251 passed, 0 failed, 1 ignored** across domain, rules, protocol, service and store, including the focused indexed/reference metacondition regression. The existing ignored performance workload remains outside this goal.
- Contracts: **26 closed schemas, 13 valid examples and 91 invalid examples passed**; regenerated schemas match source.
- MCP: **25 policy/control/correction cases per fresh installation**, with equivalent independently audited semantics. Each run includes both failure mechanisms, report-only publication, all six policies, installed-policy denial, adjacency/world/context isolation, restricted delivery, standalone-decision and partial/full-exception checks, correction, continuation, stale-head rejection, restart and historical reads. Actual call and receipt counts are in the committed results.
- Upgrade: **real v3 → v4 persisted-validation/approval rejection passed**, head unchanged; fresh validation committed and restart retained the entity; historical queued-validation operation remained readable.
- Independent audit: **all three runs passed; six tamper tests passed**, including five deliberate corruptions rejected by the audit.
- Targeted formatting and staged whitespace checks passed. Earlier incomplete/failed pilot attempts remain local as attempted work, not acceptance evidence.

## Commit and checkout boundary

The goal began in a checkout with extensive pre-existing modified and untracked implementation. The goal commit captures its integration owners, maintained G05 pilot/audit, generated tool contract and this note. For tracked domain files, only the G05 changes are staged; prior domain changes remain in the working tree. Previously untracked integration-owner files necessarily enter the commit as complete files and include their prior implementation. Other pre-existing work remains uncommitted. This commit is qualified in this checkout and is **not claimed to build independently from a clean historical HEAD**. The proof's build identity hashes the exact complete source and executables used, including those pre-existing dependencies. Large disposable evidence artifacts stay in the existing ignored `docs/evidence` directory.
