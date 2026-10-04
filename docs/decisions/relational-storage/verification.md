# Decision-package verification

Executed October 3, 2026 (America/Los_Angeles). Results apply to the disposable proposal prototypes only. All SQLite databases/backups/archives were created inside automatically cleaned temporary directories. No installed package, profile credential, grant or production database was read or modified.

## Executed proofs

| Proof | Result |
|---|---|
| Source-family inventory | All 38 canonical record families, 50 operation variants and 45 distinct persisted source table families mapped; no source-table omissions. |
| Complete DDL installation | typed, kernel, workflow, semantic, legacy-v0 and export SQL batches load together; installation and per-profile credential schemas load separately. |
| Current Rust domain → typed rows → independent reconstruction | 72 specimens, including all 38 payload families, every Value/Expr variant, legacy multiple parents/memberships, exact digits and Unicode. Actual current domain serde/canonical output supplies the pre-storage oracle; a separate read-only decoder verifies every canonical byte string and prefixed digest. |
| Closed variants/workflow envelopes | 506 additional union/operation/workflow specimens reconstruct exactly against pre-storage fixtures. 14 concrete workflow envelopes also bind their exact reconstructed bodies to their retained workflow digests. These are structural storage proofs, not evaluator or permission-admission proofs. |
| Cedar/Pistol typed-version reconstruction | 50 canonical historical/proposed version bodies and identities/digests match the frozen semantic oracle. Four revision memberships replay through commit_changes and match head/snapshot rows/checksum. A v2 header retains the actual v1/v1 digest recipe. |
| Cedar definitions | Tree → Cedar → Western red cedar; identity retained through refinement. Shared grows and instance hazard are distinct. Height remains absent before t1, then 30.00 with the authored foot unit. World-A subtype applicability excludes that definition in world B. Cross-world height evidence is excluded. |
| Pistol instances | A's explicitly authored balances are 7 → 6 → 0 → 2; B remains 3 at every time. Rename/refinement preserve A's identity and create no refill/start receipt. Initial-value definitions stay separate from current balance; one explicit initialization receipt remains one. These are authored state fixtures, not simulated firing/replenishment. |
| Conflict/unknown/legacy | Opposing inherited grows values both remain; no precedence picks a winner. Unspecified shared applicability remains unresolved. Both legacy memberships are retained with legacy_ambiguous status and no selected classification. Typed query projections agree with canonical bodies. |
| Snapshot/receipt/reservation | Exact reconstructed membership/checksum, retry tuple/input digest/revision and reserved world identity. Synthetic commit attribution/digest columns are carried as fixture evidence; production commit-input digest validation is not claimed. |
| Backup/reopen | SQLite backup independently reconstructs to the same aggregate result as the original. |
| Typed logical export | 828 trusted-schema rows copied into a separate SQLite archive; an independently calculated typed-row-stream checksum and manifest verify. Cedar/Pistol versions, history, membership and receipt reverify from the export. Installation profiles/grants/credentials are absent. The prototype demonstrates same-universe complete-history export, not filtered clone/remapping or operator import approval. |
| Fault/tamper controls | Missing required value, invalid discriminator, missing FK, workflow deletion and typed-body update reject. An injected prepublication failure leaves no published row. Deliberate backup corruption after disabling its immutability trigger is independently rejected; the verifier does not silently rehash it. |
| Installation round trip | Synthetic profiles/role/revocation and scoped grant columns/ordered limits are preserved. All versus listed-empty remains distinct. Original audit sequence 17 remains. No real credential used. |
| Stored-metadata audit | 871 table definitions inspected in the main prototype. No authoritative application BLOB/REAL columns; BLOBs are limited to actual source/media content. Source UTF-8 bytes, length and SHA-256 independently match. |
| Existing domain regression suite | `cargo test -q -p universe-domain`: 39 passed, zero failed. |
| Local syntax/patch checks | Python files compile; added Rust probe compiles and is formatted; staged patch whitespace check passes. |

Machine-readable evidence: [proof-results.json](proof-results.json), [inventory-results.json](inventory-results.json). The former includes an aggregate reconstruction digest and archive checksum; the latter pins the inspected source files with SHA-256. [canonical-oracle.json](canonical-oracle.json) captures actual Rust domain serialization before relational writes. [semantic-oracle.json](semantic-oracle.json) includes the independently specified expected ancestry/balances/conflict/unknown outcomes. These JSON files are test/reference artifacts, not prototype application payload authority.

Independence here means a separate process and algorithm: the reader imports neither `build_schema.py` nor the relational writer and uses direct read-only SQLite queries, the public physical mapping catalog and frozen pre-storage expectations. Cedar/Pistol expected state tables are written before the readback checks. This is not a second human/agent design review. No subagents were used.

## Reproduction

From the repository root:

```sh
cargo run -q -p universe-domain --example relational_decision_probe > /tmp/universe-relational-contracts.json
cmp /tmp/universe-relational-contracts.json docs/decisions/relational-storage/domain-contracts.json
python3 docs/decisions/relational-storage/prototype.py
python3 docs/decisions/relational-storage/audit_inventory.py
cargo test -q -p universe-domain
```

The first command refreshes a temporary source-schema probe; `cmp` verifies the checked-in domain schema snapshot. Prototype outputs regenerate review artifacts and use only disposable database paths. Reproduction does not call current service tools or migrate a package. No new runtime dependency is needed for these proofs: Python standard library, existing Rust workspace and SQLite suffice.

## Failed attempts and scope limits

Initial prototype runs exposed reference-alias and tuple schema handling, SQLite constraint ordering, a row-ID/field-ID collision and incorrectly spelled fixture scope/unit/validity fields. The mappings and fixture grammar were corrected against the owning source contracts; expected ancestry, identity and balance outcomes were retained. Subsequent complete runs passed. Corrupted payload and interrupted-publication attempts remain intentionally failed controls, recorded in proof-results.json.

The optional existing `scripts/validate_contracts.py` check could not run: `jsonschema` is absent from both the host and bundled Python environments. No software was installed. Its public contract files were not modified; this is not represented as a passed check.

Not established here: arbitrary live-package migration, raw-editor draft encoding recipes, ambiguous scaffold-era side-body decoding, credential authentication/cutover, current-grant revocation/CAS under concurrency, production commit authorization, full MCP admission, retcon/evaluator effects, filtered clones, host/native behavior or approval of v3 semantics. Those remain later implementation/qualification gates under the reviewed design. Unknown legacy formats and nonreconstructable drafts block conversion with originals retained; the package does not claim universal conversion readiness.
