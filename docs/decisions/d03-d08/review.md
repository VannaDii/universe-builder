# D03/D08 compatibility, authority and fixture comparison

Prepared October 2, 2026. Status: source-based review and calculation complete; separate reviewing-agent judgment requires the user's explicit delegation authorization. This is a same-author review, not an independent person/agent endorsement. Design remains pending Vanna; no implementation.

## Frozen oracle and corrections

The requirement oracle was frozen at SHA-256 `3ead237bf50ef60413a9d62ef0505daf57961168b2bfbf5d74de02f711e77107` before the payload/lifecycle document. O01–O38 remain unchanged. Two preparation corrections are retained:

1. The first hand-counted UTF-8 range calculation expected lengths 45/32; the independent encoder/decoder comparison failed. Counting the prefix's 11 ASCII bytes, opening quote's 3 bytes, quoted text's 17 bytes and closing quote's 3 bytes yields end 34. Space then waiting gives [35,47). Actual source has 47 bytes. Gold inventory meaning stayed unchanged; verifier literal offsets corrected to [0,34), [11,34), [35,47). No failed attempt represented as a pass.
2. The initial oracle's storage commentary incorrectly inferred workflow_put was an upsert. Direct inspection of `universe-store/src/kernel.rs:499` establishes it rejects differing values for an existing key (`immutable workflow key conflict`) and accepts identical retries. The proposal now reuses that invariant and adds generation-keyed history and atomic latest-generation comparison. Oracle O17–O22/O34 remain correct; its last paragraph's storage sentence is superseded here. This is a source-inspection correction, not a design flaw in the approved workflow or a reason to change architecture.

## Owning-source review

| Concern | Current source evidence | Proposed disposition / acceptance control |
|---|---|---|
| Freeze and digest | `workflow.rs:1755–1855` freezes compiled assignments and generated versions; C hashes Proposal with empty digest plus changes/footprint. Proposal later submission/withdrawal increments version. | Attachment after Submitted only; separate body/selection. Never add unhashed public fields casually to the entire Proposal serialization. O11/O16/O32. |
| Hash authority | `domain/src/canonical.rs` describes serializer and explicitly says digests do not authorize authorship. `PayloadDigest::compute` differs from workflow hash. | Explicit domain separators for new workflow hashes; preserve owning C rules. Authenticated principal bound by service, tool labels declared only. O23/O32/O33. |
| Stored immutability | `kernel.rs::workflow_put` transaction rejects changed existing key. | Reuse immutable keys; atomic latest generation check needed for replacement race and commit publication. No claim current store has mutable pointer CAS. O17–O22/O34/O38. |
| Exact source bytes | `workflow.rs::verify_sources` checks import metadata receipt, digest/size/UTF-8 representation; exact ByteRange excerpt. `provenance.rs` checks links name anchors. | Reuse staging, verify exact sources and ranges; external semantic conclusion remains external. O03/O04/O12–O15. |
| Work editions and references | `records.rs::SourceVersion`, `Anchor`, `WorkVersion`, `SceneRef`; `value.rs::VersionRef`; CalendarId maps to matching record body. | Bind edition VersionRef and explicit passage range. No mutable work/version labels or implicit newest version. O10–O12/O35. |
| Existing approval | `workflow.rs::approve` at 1123 checks author/latest/submitted/admissible/head/exact evaluator; full Checked hash stored in approval. | Extend Checked final binding, not author power. Changed selection forces fresh run/approval; Partial can still be exact author-approved if admissible. O17–O19/O26/O27. |
| Delegation and private commit | Commit at 2130 onward checks current grants/protected/shared footprint, Complete for delegation, exact approval when required, current head, private full-scope candidate recheck and authority lock. | Preserve these tests; include assessment exact applicability and generation in locked publication. No positive-assessment override. O25–O29/O34. |
| Scope | `workflow.rs::proposal`, visibility closure, restricted ValidationTask response; private commit recheck deliberately undisclosed. | Full source/dependency visibility intersection and redaction of metadata, not just text. Do not return bound verdict or counts for hidden dependency. O24/O29. |
| Typed results | `response.rs::Coverage` has complete/partial/unsupported/restricted/failed; `Envelope::Delivery` is distinct. Closed Validation lacks submitted source inventory. | Keep execution enum, use explicit v3 wrapper with scope/assessment and separate delivery. O01/O28/O36/O37. |
| Wire compatibility | `protocol/src/lib.rs` version 2; `request.rs`, `response.rs`, `wire.rs` closed DTOs/duplicate rejection and 1 MiB limit. `xtask::schemas` writes tools/examples. | Coordinated protocol 3, no silent old-client field stripping or imported authority. Versioned historical read adapter, hashes retained. O30/O31. |
| Native/MCP | `ui/src/author.rs` prints Coverage and approves exact run; `mcp/src/instructions.rs` distinguishes source-byte verification from semantic prose validation. | Display all three axes and complete inventory review; invalidate approval UI on generation change, update host selection wording. O01/O03/O15/O36. |

## Oracle-to-contract comparison

| Gold rows | Judgment | Contract location |
|---|---|---|
| O01–O07, O37 | Source archive stays valid; material inventory omission can fail gold while passing internal accounting. Unchanged state references need no duplicate canon assertion. | Typed inventory/mappings; result axes; host requirement. |
| O08–O11 | Modality, attribution, time, referent and context are separate bound fields; unknown remains unresolved. | ClaimMapping tagged semantics and judgment. |
| O12–O16, O35 | Old edition integrity survives; current reuse becomes stale on relevant selection/snapshot changes. Corrupted bytes reject. | Exact binding, lifecycle invalidation. |
| O17–O22, O34/O38 | Every selection transition is exact; immutable bodies and replay safety; race/failed run cannot publish. | Selection generation CAS, idempotency and locked commit. |
| O23–O29 | Digest/verdict grants no authority. Partial author route preserved; complete delegated route preserved; hidden scope never disclosed. | Assessor identity, visibility, authority matrix. |
| O30/O31 | Protocol 2 cannot accept changed closed shapes; old evidence not retrospectively assessed. | Version 3 boundary and historical adapter. |
| O32/O33 | Acyclic hashes with explicit preimages; object ordering neutral, sequence ordering bound. | Digest DAG and independent arithmetic proof. |
| O36 | Pagination not semantic coverage; full unpaged core and pinned pages. | Response wrapper/delivery and approval review requirement. |

No oracle verdict was changed to fit the proposal. The storage commentary correction is explicit above. Unknown materiality and unsupported semantics remain declared limitations; no serializer success can establish semantic recall. The golden corpus is small and deliberately synthetic; future host qualification needs held-out narration/paraphrase/referent variants and a separate reviewer.

## Binding proof results and limits

`python3 docs/decisions/d03-d08/verify_bindings.py` passes **36** assertions. Every digest preimage is serialized once by Python JSON and independently by a handwritten encoder; OpenSSL SHA-256 agrees with hashlib. Includes exact production-shaped no-change Proposal tuple (not a live service run), miniature source candidate/assessment/final-validation bindings, unchanged dependencies, changed sources/versions/editions/mapping/assessor/inventory, replacement/withdrawal/generation, UTF-8 boundaries and self-reference controls. The checked-in `proof-results.json` retains canonical preimages, hashes and mutations. This verifier implements arithmetic for design examples only, not proposed attachment routes, assessment semantic validation or authority admission.

No engine build/test, production workflow fixture, MCP/native interaction, model qualification, accessibility run, restart recovery or deployment was performed for this docs-only decision task. Those remain future implementation acceptance work. Separate-review readiness is not claimed in this file until independently judged evidence exists or Vanna explicitly accepts the calculation-only scope.

## Completion-audit additions

O39–O42 and concrete evaluated/query/stale/inconsistent/restricted examples now cover response-shape and range/link-accounting details. The evaluated response has an explicit kind; restricted responses omit the entire mandatory-digest Validation core. Query/failed runs have no final authority binding. The verifier independently checks exact nondisclosure keys, query nonauthority, reciprocal mapping links, source range containment, B offsets and changes to optional readerScene/personalSequence in the production-shaped candidate tuple. All original 38 gold judgments and their frozen hash remain unchanged. These refinements close draft specificity gaps; separate reviewing-agent judgment is still pending authorization.
