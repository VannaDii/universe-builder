# Independent D03/D08 design preparation review

October 2, 2026. Independent reviewing agent, explicitly delegated by Vanna. No design approval, runtime implementation or runtime qualification. Only new independent-review/oracle/calculation files were written; producer files were not edited and no commit was made.

## Freeze and method

I read the remediation plan D03/D08/shared lifecycle/compatibility requirements and current owning sources before reading producer artifacts. My independent oracle was then written and frozen as `independent-oracle.md`, SHA-256 **3c52d79b87ecda9efce52cf1d4b5592078a471268ce9c99522199d68663ba2ba**. Subsequent comparisons did not change that file. Sources inspected include `workflow.rs` freeze/check/approve/commit/source verification, request/response/wire closed DTOs, domain canonical serializer and source/anchor/work/edition records, and kernel immutable workflow storage.

After freezing I read the producer decision, oracle, examples, review, additional fixtures and verifier. `independent-calculation.py` neither imports nor invokes producer verification. It independently implements canonical encoding for these fixtures' strings/integers/arrays/objects and writes `independent-calculation-results.json`. Its six digest calculations agree with the supplied example fields where corresponding fields exist:

| Preimage | Independently calculated SHA-256 |
|---|---|
| Miniature candidate | 3ef0b94746f89e6eb53f24f372a89fa24ba3186499ce0e721aaab311f8160e55 |
| Production-shaped tuple | 91eaafdc0921b147d93f9cd83e071af43e73a9be58e84adc5419280fc5aa85ad |
| Assessment | cf147089d651894030e61895720f2faf29067a21995b3797b6b674b56e6ae22e |
| Execution fixture | 7e66a076b150a9df49e0b2776a44758be5340c779ee8cdf1b3187ee99513619b |
| Inventory | c3f71a820591606018d1b4cfe538c41d80b0dca8e5a1518ebd458280cbc8c808 |
| Final validation | b90fa2b366734d2fdb0cc8c014baf302f080fc6abdf1daad6bf92cc3a87b945d |

Source A is independently 47 UTF-8 bytes and B 49. Their full quoted utterance ends are 34 and 36, quote starts 11, and waiting starts 35 and 37. Supplied inventory offsets agree. Curly-quote interiors cannot decode as standalone UTF-8.

## Actionable findings

**R1 — Link the real candidate shape to the assessment chain (preparation blocker).** The production-shaped tuple's C is 91ea…85ad, while assessment/selection/execution/final binding all use miniature C=3ef0…0e55. The marking is honest, but two disconnected arithmetic examples do not establish concrete proposal-bound payload proof. Add a complete same-C production-shaped candidate → assessment → selected generation → execution → final binding chain. A no-change proposal using exact unchanged records is sufficient for hash-shape evidence; supply its resolved snapshot/dependency identities rather than claiming runtime admission. Retain miniature example if useful. No engine changes are needed to close this preparation gap.

**R2 — Execution preimage differs from owning typed serialization (preparation blocker).** `response.rs::Validation` omits operation_id when None and opposing_evidence when empty. examples.json execution_core contains operation_id:null and opposing_evidence:[], and the proposed execution digest hashes that JSON directly. The supplied arithmetic is internally correct, but current workflow hashing a typed Validation would serialize a different preimage. Define the execution-core canonical preimage using the owning serializer, remove omitted fields in the example, regenerate final hash, and independently compare. Distinguish closed input acceptance from canonical output serialization; null and absence are distinct canonical objects.

**R3 — Close inventory/unknown consistency invariants (contract specificity blocker).** Empty inventory is restricted to no_material_claims, but the reverse restriction is unstated: nonempty inventory with no_material_claims can satisfy the written consistent conclusion criteria. Position says unknown does not imply consistent, but the formal conclusion predicate only rejects unresolved entries or mappings; a mapping with unknown material reader/narration position, occurrence or modality and judgment=supported can still pass that predicate. Explicitly require declaration/inventory agreement in both directions. For material unknown fields require linked unresolved disposition and prevent consistent conclusion; for an irrelevant position use not_applicable or an explicitly attributable materiality disposition. Add negative controls for these exact bodies. These are omissions in a pending contract, not proof of a flaw in approved runtime design.

**R4 — Public surface ambiguity (clarification required before readiness).** The remediation plan keeps thirteen public tools, while the proposal names three new universe_attach/select/get_assessment routes without saying whether these are native/internal routes or extra public MCP tools. Specify their mapping into the existing review tool's closed variants (if that is intended), or put an explicit public-tool-count change in Vanna's decision. Do not implicitly add tools during implementation.

**R5 — Stale-result final-binding semantics need a precise boundary (minor).** The normal contract says completed proposal validation can bind a negative result, while stale_result_fragment always has null final_binding_digest. Distinguish a stale/cancelled run (null, nonauthoritative) from a fresh record-only validation performed after an unusable attachment is detected. The latter can preserve raw-record admission under existing rules only if exact selected identity/generation/unavailable status is bound and private recheck agrees. Document that distinction; avoid either silently blocking raw archives or silently reusing an earlier binding.

## Independent judgments for all proposed fixtures

These are contract/gold judgments. No row claims a runtime route was executed. “Agree” means the expected outcome matches my frozen oracle, subject to the findings above.

| ID | Independent judgment |
|---|---|
| O01 | Agree: archive remains valid; complete checks certify structured scope only. |
| O02 | Agree conditionally: declared passage consistency; exact record/context meanings must be supplied, not inferred from IDs. |
| O03 | Agree: reported quotation does not establish objective door state. |
| O04 | Agree: changed closed/open quotation is not an unchanged mapping. |
| O05 | Agree: missing waiting fails this gold recall; internal accounting can still pass. |
| O06 | Agree: active unchanged evidence needs no duplicate canonical operation. |
| O07 | Agree: uncovered declared item forbids consistent conclusion. |
| O08 | Agree: counterfactual possibility cannot establish occurrence. |
| O09 | Agree: unresolved speaker stays unresolved. |
| O10 | Agree: same label does not establish referent identity. |
| O11 | Agree: context/world/time/occurrence changes alter applicability. |
| O12 | Agree: historical A remains inspectable; B/current continuation needs fresh exact binding. |
| O13 | Agree: altered bytes under immutable identity are integrity failure. |
| O14 | Agree: mid-character boundary rejects independently of supplied hash. |
| O15 | Agree: excerpt identity proves bytes, not entailment. |
| O16 | Agree: changed candidate/head/definition/version invalidates reuse. |
| O17 | Agree: adding attachment invalidates previous absence-bound approval. |
| O18 | Agree: equally positive replacement still requires fresh validation/authority. |
| O19 | Agree: withdrawal retains history and invalidates previous live binding. |
| O20 | Agree: one CAS winner; second cannot publish same expected generation. |
| O21 | Agree: exact authorized retry recovers response without new generation. |
| O22 | Agree: modified retry rejects. |
| O23 | Agree: service-authenticated identity overrides claimed author. |
| O24 | Agree: hidden dependency must not reveal identity/count/verdict/fingerprint. |
| O25 | Agree: current revocation denies access/commit despite historical approval. |
| O26 | Agree: positive interpretation does not waive engine admission. |
| O27 | Agree: existing admissible Partial author path survives; delegation requires Complete. |
| O28 | Agree: ordinary delegated record commit can survive unresolved prose; host assessed-consistent selection cannot. |
| O29 | Agree: restricted result supplies no usable approval evidence. |
| O30 | Agree: closed legacy types require explicit coordinated version boundary. |
| O31 | Agree: retained legacy evidence is unavailable_legacy, not retrospectively assessed. |
| O32 | Agree: candidate→assessment DAG excludes back edges; self-digest fields must reject structurally. Hash mutation alone is not a runtime rejection proof. |
| O33 | Agree: object ordering is canonical; arrays remain ordered. |
| O34 | Agree: generation/head/current authority must compare atomically through publication. |
| O35 | Agree: earlier relevant retcon invalidates current reuse; historical edition survives. |
| O36 | Agree: pinned delivery/pagination differs from semantic execution/assessment. Future complete-review enforcement must be demonstrated separately. |
| O37 | Agree: empty inventory on this gold fails material recall. See R3 for structural declaration predicate. |
| O38 | Agree: failed/cancelled checks cannot authorize; restart/idempotency must recover exact identities. |
| O39 | Agree: explicit restricted wrapper omits required legacy input_digest rather than fabricating hidden fingerprint. Outer envelope/cursor/error paths also need future confidentiality proof. |
| O40 | Agree: complete query has absent assessment and null final binding; no proposal authority. |
| O41 | Agree: range containment/source lookup and reciprocal links must reject exact malformed cases. |
| O42 | Agree: optional author-frame fields affect C; every assessment VersionRef explicitly names universe. |

## Authority, visibility, history and compatibility assessment

The attachment body excludes its identity/digest; C excludes the attachment; final binding includes selection identity/generation and execution. This is a sound acyclic dependency direction. Existing Checked evidence plus exact author approval/current delegation remains authoritative. The document correctly preserves Partial author admission, Complete delegation, protected/shared limits, current revocation and unchanged head; it does not grant assessor authority. Insertion-only kernel workflow keys plus generation-keyed history is compatible with current storage, with new atomic latest-generation and commit publication comparisons explicitly still required.

Historical editions are correctly separated from active prerequisites. Merely discovering newer B elsewhere does not erase A's evidence; choosing B or changing current snapshot requires a fresh assessment. Source version/bytes/ranges and work edition need owning-record resolution in future implementation, not only digest arithmetic. Missing retained bytes cannot be silently replaced by latest content.

The evaluated and query examples carry the required tags, and restricted_result exactly matches its closed restricted shape. Scope redaction includes digests/counts/stale reasons and full dependency intersection; future tests must cover outer Envelope frame/world/cursor metadata, errors, idempotency recovery and private recheck delivery. Protocol 3 coordination is correctly distinguished from capability advertisement. Legacy bytes/hashes/receipts remain historical and cannot authorize new semantics. The producer review's correction of its oracle's misleading storage sentence is supported by actual workflow_put source.

## Readiness verdict

**Not ready to present as a completed design-preparation package yet:** resolve R1–R4 and clarify R5, then re-run independent arithmetic/comparison without changing either frozen oracle. The core proposed direction matches D03/D08 and preserves existing authority. This review is not design approval. All 42 expected design fixture judgments are independently endorsed subject to the listed contract omissions; none is engine/MCP/model/native/restart qualification. After preparation corrections, Vanna's decision remains required before affected implementation.

## Re-review of preparation corrections

The preceding findings and initially blocked readiness verdict are retained as the first review, not silently rewritten. After the producer addressed them, I read the corrected decision/examples/additional controls and independently recalculated with `independent-recalculation.py`. Initial independent-calculation-results.json is preserved. The same frozen independent oracle hash remains unchanged.

| Finding | Corrected evidence and independent disposition |
|---|---|
| R1 | Resolved for design preparation: a nonexecuted synthetic AddSourceAnchor production tuple has its actual Assignment/RecordVersion/payload hash and shared footprint; production_bound_example binds exactly the same C throughout assessment, selection, execution and final result. The synthetic snapshot still assumes named unchanged records; the explicit no-runtime-admission limitation is appropriate. |
| R2 | Resolved: typed execution omits None operation_id and empty opposing_evidence. Independent calculation proves retaining null/[] changes the hash. Nullable new attachment fields explicitly remain null, so serializer rules are no longer ambiguous. |
| R3 | Resolved: no_material_claims now requires empty inventory/mappings/unresolved and converse nonempty inventory requires material_inventory_declared. Material unknown fields require unresolved mapping and reciprocal disposition; irrelevant positions use not_applicable. |
| R4 | Resolved: existing universe_propose action variants attach_assessment/select_assessment and universe_get_proposal assessment view preserve thirteen public tool names. Native internal route names are distinguished. |
| R5 | Resolved: a discarded stale/cancelled run has null V. A fresh record-only run can bind exact current selection/generation and unusable assessment_state; source integrity errors still cannot use this fallback. Final binding now commits to the exact authorized assessment_state, and private recheck must agree. |

Corrected production chain independently agrees:

| Preimage | SHA-256 |
|---|---|
| C, actual-shaped synthetic tuple | 3e1e2d20a62236d6f049d14f81f6fc2e9806bd6558d1d56ae1b8b4cc08a80a17 |
| A, production-bound assessment | ef444e6ff178b540ef9bc566734efd582f5dda05c31824bf6eee404ba431d098 |
| Typed execution core | 916d8fd6ac24129d806c9ba86c069bba9bab876894f1f53b09a782c7a2d44d1c |
| V, production-bound final validation | 5e126acba489a37e7cf9d3c24dc72b3dbfd82e04e483405c34e895ff56b2f78b |
| anchor:v1 payload discriminator/hash | 0d58c60cd994dd40a56d8333074873e3cf756d830a96ead84b446496e7467ce6 |
| Fresh record-only V | d037b288a6577a37a23bbdcd2e5207ba47f72064b9274f8e7918f5751a2ea8c3 |

The separate miniature remains correctly identified as a different C; its existence is not a failed link in the new production_bound_example. Independent checks compare production C across body/proposal/execution, A across envelope/selection, execution preimage/hash, response assessment/submitted scope against binding, selection generation/reference, anchor payload discriminator, and fresh record-only V/state/scope. These checks do not execute Rust DTO admission or proposed service endpoints.

| New control | Independent judgment |
|---|---|
| O43 | Agree: declaration/inventory mismatch rejects in both directions; no-material declaration is still assessor claim. |
| O44 | Agree: material unknown with supported judgment/no disposition cannot yield consistent; explicit unresolved accounting required. |
| O45 | Agree, independently calculated: absent optional fields and explicit null/[] serialize to different hashes; owning typed output is the preimage. |
| O46 | Agree, independently calculated: actual-shaped anchor Proposal/Assignment/Footprint C connects to A and V; prospective variants preserve the public catalog. No runtime admission inferred. |
| O47 | Agree, independently calculated: discarded run cannot authorize; fresh record-only run binds current selection and unusable state. Source integrity protection remains authoritative. |

**Updated readiness verdict: ready for Vanna's D03/D08 design decision, within the stated design-preparation scope.** All five initial preparation findings are resolved in the reviewed artifacts. All 47 fixture expectations are independently judged; original O01–O42 judgments remain unchanged. There is no independent runtime, external-host, MCP/native, accessibility, retcon/restart or release qualification, and no design approval is granted by this review. Future implementation must exercise the recorded fixtures and owning-source authority/visibility/CAS guarantees before claiming those behaviors work.

Historical proof hygiene: `independent-initial-input.json` reconstructs the exact initial digest preimages from the retained initial evidence, plus unchanged source strings and the wrapper fields actually inspected. It is explicitly a reconstructed reviewer-input subset, not an alleged full original producer snapshot. The initial calculation now reads that fixed snapshot and compares regenerated output byte-for-byte to retained initial results, refusing overwrite on mismatch. Re-running it reproduced the initial results unchanged (SHA-256 1562f63ee1e4854bb2659f1460404b135b6a017dba5f1fc48472097fedfde823). The separate corrected calculation still reads current examples and passed again. Neither frozen oracle nor initial judgments changed.
