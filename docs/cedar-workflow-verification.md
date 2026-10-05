# Goal 32: complete Cedar workflow

October 4, 2026 (America/Los_Angeles). Qualification uses one owned disposable
installation, actual stdio MCP calls, and the existing authenticated private author
review/approval path. The [driver](../scripts/cedar_workflow_pilot.py) does not read
expected facts to construct proposals. The separately authored
[expected table](../fixtures/cedar-workflow/expected.json) is consumed by the
[auditor](../scripts/audit_cedar_workflow.py).

| Requirement | Executed evidence |
| --- | --- |
| Minimal Tree | A standalone `introduce_definition` publication contains no entity, property, unit or action. No missing values are supplied. |
| Existence/location/time | A stable North-tree identity is classified Tree. Explicit existence and physical-location assertions start at calendar coordinate 0 in Grove. Its world association remains distinct from the physical location, “North bank of the grove.” A query at -1 returns neither assertion and reports incomplete instance state; absence is not a refutation of existence. |
| Shared capability/local hazard | Tree owns `grows: true`; North tree owns “Broken upper branch.” Effective retrieval retains different subjects, assertion modes, exact provenance and world scope. It never promotes either source into the other category. |
| Cedar refinement | Introducing Cedar and refining North tree in the same proposal preserves its identity, names, world associations and metadata. Ancestry is Cedar → Tree. |
| Effective description/unknowns | Actual state and context deliveries expose the classification, shared capability and local hazard. Height and unit definitions are absent at this stage. Later, the exact authored growth action requires `grows`, `adequate_water`, and `growing_season`. The latter two are missing; these are authored obligations, not biological defaults. |
| Authored height change | A 30-foot assertion is valid on [0,10). An explicitly authored event at 10 declares a required +1-foot height change and a 31-foot post-value. Queries at 5 and 15 return 30 and 31 respectively, with event-slot provenance on the later assertion. The query at 1000 still returns 31; time passage does not infer another change. |
| Legal/conflicting/unresolved | Ten reviewed publications succeed. Opposing shared growth values and overlapping unequal heights return complete conflicting findings. Missing water rejects the growth event; after the author supplies water, the missing season is identified. Water later retains unknown validity and unresolved precision; the growth event rejects with incomplete evidence. All six rejected cases leave canonical counts and head unchanged; commit attempts are denied. |
| Earlier correction/downstream impact | Replacing the earlier height with 29 while retaining the 31-foot successor rejects: the declared +1 delta requires 30. Actual impact retrieval includes the event, whose old/new records are fetched and inspected. The complete correction changes the earlier assertion and the downstream event/post-proposition together. Current queries return 29 then 30; historical queries retain 30 then 31. |
| Revision pinning/restart | The approved correction survives a forced engine termination before commit. Exact commit retries return the same receipt before/after another forced restart. A retained pre-correction context still returns the old frame and facts. Explicit historical/current state and canonical snapshots remain equal across restarts. |

The demonstrated product defect was an undifferentiated action-requirement error:
the author could not tell whether water or season needed clarification. Admission
now names the failed predicate, owning role/entity and event, together with the
evidence outcome and completeness. The same supported-only admission semantics
remain in force. A focused Rust assertion and the actual missing-water,
missing-season and unresolved-water MCP cases verify the diagnostic. The shared
independent snapshot helper also now closes read-only SQLite connections; Python
3.14 exposed unclosed-connection warnings during audit.

## Independent proof and falsification

Nine canonical snapshots are independently reconstructed from retained typed
SQLite columns/children and ordered commit changes. The reader validates integrity,
foreign keys, immutable payload digests and historical membership without using the
Rust writer/evaluator or cached head membership. Every reconstructed record matches
received MCP delivery. The audit checks 38 delivered versions, all 14 state queries,
their exact revision/time/world, property ownership, quantity/unit, validity,
applicability, event linkage, requirement lists, and separate evidence categories.
All ten publication receipts are also checked directly in the retained database.
Successful author approvals are bound to captured private command results and exact
validation runs. Rejected candidates leave workflow evidence; they are not canon.

The 12 [audit tests](../scripts/test_cedar_workflow_audit.py) contain an authentic
database/wire control and eleven coherent report/wire forgeries with recalculated
payload digests. They change post-height, refinement identity, shared/instance
ownership, physical location, growth obligations, unknown-water precision,
historical height, downstream correction, event provenance, or retained-context
revision. Each fails. Forgery tests deliberately bypass database comparison to
test the independent factual oracle itself; the normal audit always reconstructs
the database. Independence means separately authored expectations and a separate
reader/algorithm, not a second human or model review. No subagents were used.

The [proof summary](cedar-workflow-proof-results.json) records final executed gates,
artifact SHA-256 hashes, binary identity and actual working time. CI runs the MCP
driver, database/wire auditor and falsification controls together.

## Reproduce and limits

```sh
cargo build --locked -p universe-engine -p universe-cli -p universe-mcp
uv run --with jsonschema==4.25.1 python scripts/cedar_workflow_pilot.py --output /tmp/cedar-workflow-proof/actual.json
python3 scripts/audit_cedar_workflow.py /tmp/cedar-workflow-proof/actual.json
python3 scripts/test_cedar_workflow_audit.py --evidence /tmp/cedar-workflow-proof/actual.json -v
RUST_TEST_THREADS=1 cargo run --locked -p xtask -- check
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
```

Raw report, JSON-RPC transcript, and a credential-free synthetic package database
remain under `/tmp/cedar-workflow-proof/actual.{json,jsonl,sqlite}`. The driver
stops its owned engine and removes the disposable installation and credentials.
The database is retained as proof, not imported as author data.

Impact remains the existing conservative full-universe closure; inclusion does
not claim an exact causal dependency graph. The downstream relationship is proved
by the authored delta contract, rejected partial correction, and inspected event
versions. Effective-object coverage concerns visible authored evidence; it does
not certify physical completeness. Missing height/unit is demonstrated by absent
authored records, while growth obligations are delivered in action requirements
and identified on attempted admission. No generic automatic missing-property
checklist was added.

No biological simulation, inferred growth, automatic physical transformation,
model prose interpretation, native UI/VoiceOver, hosted CI, deployment or release
qualification is claimed. Existing bounded quantity/delta and correction semantics
were used without a design change. Early harness attempts assumed all conflicts
were protocol errors and reused a reserved identity from a rejected proposal;
the harness was corrected to preserve complete conflict findings and distinct
frozen proposal identities.
