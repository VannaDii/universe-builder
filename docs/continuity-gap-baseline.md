# Reproducible continuity-gap baseline

The maintained pilot preserves the original thirteen probes: G01–G11 and the two working controls, C01 (`correct_phase_action_blocks`) and C02 (`different_single_property_values_block`). It uses the existing `PilotSession`, schema validators and stdio MCP client. Product code, existing helpers and existing baseline tests are unchanged by this work. No domain or workflow extension is approved here.

The qualified proof bundle is [October 2 run 7](evidence/continuity-gap-2026-10-02-run7/README.md). Its comparison must say `passed`, both independent audits must say `passed`, and all six audit tests must pass. Each audit entry and the evidence index link the individual gap to actual transcript lines, exact proposals, approvals, resulting records and commit receipts. Evidence remains in the project's existing `docs/evidence` workflow, which is ignored by Git; preserve the whole directory when sharing or archiving proofs.

## Reproduction

Use a Python environment with the project's existing `jsonschema` dependency. The qualified run used Python 3.14.7 and `jsonschema==4.25.1`; the full runtime, compiler, source hashes and executable hashes are in the build identity. If an environment is needed:

```sh
python3 -m venv /tmp/ub-gap-validation
/tmp/ub-gap-validation/bin/python -m pip install jsonschema==4.25.1
/tmp/ub-gap-validation/bin/python scripts/continuity_gap_pilot.py \
  --output docs/evidence/continuity-gap-new-run
```

Choose a new output directory for each attempt. The runner refuses to overwrite prior evidence. It builds the three existing executables from the current working tree with the locked dependency graph, records source and binary hashes, then checks those hashes again before declaring success. A Git commit ID alone is insufficient because the current tree has unrelated uncommitted work.

The two installations use separate fresh directories, authors, enrolled agents, universe identities and databases. Only synthetic disposable data receives approval. Both engines are stopped and installations removed after snapshots are retained. Short temporary paths avoid macOS Unix socket path limits. No installed user package or profile is accessed.

To repeat the independent audit without a live engine:

```sh
python3 scripts/audit_continuity_gap.py docs/evidence/continuity-gap-new-run/run-a
python3 scripts/audit_continuity_gap.py docs/evidence/continuity-gap-new-run/run-b
python3 scripts/test_continuity_gap_pilot.py \
  --evidence docs/evidence/continuity-gap-new-run/run-a -v
```

The auditor and its tests require only Python's standard library. The runner invokes both audits and the negative checks automatically.

## Maintained inputs and proof boundaries

- [Continuity oracle](../scripts/continuity_gap/oracle.json) states the intended synthetic continuity behavior and each gap's classification. These expectations are separate from engine findings and do not assert that every gap is a defect in an existing engine contract.
- [Frozen observed baseline](../scripts/continuity_gap/baseline.json) records historical engine behavior and normalized actual request stimuli. A changed stimulus or changed observed behavior fails qualification. Preserve any failure rather than rewriting expectations to match it.
- [Cases](../scripts/continuity_gap/cases.py) preserve the original operation payloads and execution order. The historical [script and report](evidence/continuity-gap-original-2026-10-02/manifest.json) were copied from the temporary originals without modification; their original build identity was not recorded.
- [Runner](../scripts/continuity_gap_pilot.py) orchestrates the existing persistent helpers and records actual sent/received JSON-RPC envelopes, including initialization, notifications, tool errors and the connection after restart. It also records private author CLI requests and outputs separately.
- [Independent auditor](../scripts/audit_continuity_gap.py) imports neither the runner nor pilot helpers. It reads the wire transcript and a read-only SQLite snapshot, checking stored proposals, validations, approvals, approved assignments, kernel inputs and receipts, final membership, restart reads and the exact source/anchor bytes. This is an independent program audit, not an external human review.
- [Audit tests](../scripts/test_continuity_gap_pilot.py) check valid evidence and reject five deliberately corrupted temporary copies: wire requests, approvals, kernel receipts, resulting head membership and source text. They do not modify baseline tests or saved proof packages.

The first phase preserves the original 42 public MCP calls, including the seed and source publication. Eleven gap validations complete with zero findings and receive approval. C01 returns `INVALID_ARGUMENT` for `event.action.requirements`; because it has no validation run, approval is explicitly not attempted. C02 reports one `conflicting` finding and its approval is denied. Neither rejected candidate becomes canonical.

Only after all baseline observations are recorded does the persistence phase revise the ten remaining gap proposals, using the existing public revision route with their unchanged operations and reserved record identities. Each revised proposal is validated, checked for complete impact, tested for missing-approval rejection, reviewed, exactly approved, committed and retried. G11 already has its source receipt from the original sequence. Baseline and persistence proposal versions, validation runs and approvals remain distinct in the evidence. Persistence-phase results are not substituted for the baseline observations.

Each installation therefore records 114 public MCP calls, 12 successful MCP receipts (seed plus eleven gaps), 13 kernel receipts (including universe creation), and 14 revisions (including empty genesis). The engine is killed and restarted through the existing helper before the final reads. The storage audit proves that committed records match approved assignments and that retry receipts identify the same revisions.

Equivalence compares observed results, unchanged stimuli and canonical payloads. Only generated identities, record-version metadata and source import timestamps are normalized, after exact intra-installation bindings are checked. Fixed record identities, story times, owners, predicates, roles, actions, effects, evidence polarity, quotes and values remain comparable. Raw identities, digests, timestamps and receipts are retained in each proof bundle. `evidence-manifest.json` hashes every saved proof file.

This baseline reproduces the eleven gaps; it does not remediate them or qualify the proposed broader legal/unresolved corpus. Prose interpretation remains an authored assessment. Expected continuity, byte verification, engine validation, author approval and canonical publication remain separate results.

## Retained attempts

Run 1 stopped at installation startup because the default macOS temporary path exceeded the engine socket path limit. Run 2 reproduced all baseline observations, then the persistence replay correctly rejected identities already reserved by earlier proposals; the pilot now uses the existing revise route. Runs 3 and 4 retained completed installation evidence while audit checks were corrected for append-only receipt reconstruction, creation/genesis counts, schema defaults and volatile source import metadata. Run 5 passed both installations and the independent audits. Run 6 includes the negative checks automatically and supplies the per-case evidence index. Run 7 qualifies the final source after whitespace cleanup and opens saved database snapshots as immutable files so audits do not create transient SQLite sidecars. Earlier attempts are retained, not relabeled as passing runs.
