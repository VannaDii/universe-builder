# Independent assessment MCP audit

Oracle frozen by the independent reviewer before inspecting producer pilot or transcript.
Source: approved `docs/decisions/d03-d08-source-assessments.md`, attachment lifecycle,
acyclic binding and visibility sections. Scope: this goal's write actions only.

| ID | Required observed result |
| --- | --- |
| A01 | Real MCP `tools/call` sends both actions through `universe_propose`; `tools/list` preserves the thirteen existing public names. |
| A02 | First valid authenticated attachment returns generation 1 and a selected service-assigned identity/digest; immutable stored body hashes independently to that digest. |
| A03 | Replacement attachment returns generation 2, a distinct identity, and preserves the first attachment and generation history. |
| A04 | Selection of an existing exact attachment changes generation once; null selection withdraws selection without deleting evidence/history. |
| A05 | Identical retries recover the exact original result with no workflow changes, including after later selection movement. |
| A06 | Same idempotency key with differing body, expected generation or selected reference rejects and leaves all workflow rows unchanged. |
| A07 | Impersonated assessor rejects without any workflow write. Identity is bound to authenticated profile through existing principal conversion, not tool labels. |
| A08 | Stale expected generations reject without any workflow write. Fresh no-change selection rejects without fabricating a generation. |
| A09 | Current propose permission, proposal owner/author boundary and full source/dependency visibility are enforced. Denials disclose no selected identity/digest, counts, body or generation. |
| A10 | Every assessment call preserves frozen proposal bytes, version, operations and digest, canonical continuity head, commits and head membership. |
| A11 | Success persists envelope, selection history and idempotency receipt atomically; failure/retry preserves complete workflow state. Attachment body digest uses independent canonical encoding and SHA-256. |
| A12 | Focused service tests directly cover the routes; no assessment retrieval, validation integration or new public tool is added by this goal. |

This oracle requires independently inspecting raw request/response envelopes and stored
state snapshots; producer summary booleans alone are insufficient. It does not claim
native UI qualification, semantic interpretation, validation binding or release acceptance.

## Final audit

**PASS for A01–A12, scoped to this goal.** Independently ran
`python3 scripts/audit_assessment_mcp.py` against the final draft transcript.
The read-only verifier imports no producer script or owning Rust serializer. It
uses a separate recursive canonical encoder and Python SHA-256 to recompute
raw workflow payload hashes, exact request receipt fingerprints, assessment
body digests, source byte digests, sizes, version identity and UTF-8 boundaries.

Observed 24 actual stdio MCP assessment calls. Attachment, replacement,
reselection and withdrawal produced generations 1, 2, 3 and 4. Replacement
created a distinct immutable identity; prior bodies/history remained byte
identical. Six identical retries recovered their original generation/identity,
including after replacement, withdrawal and service restart. Thirteen ordinary
negative controls and the source visibility denial failed with no workflow
changes. The controls cover impersonation, stale attachment/selection,
body/generation/reference retry mismatch, no-change, required explicit null,
closed body fields, wrong owner, revoked propose permission and source scope.

The source visibility control first retrieved the caller's own world-scoped
proposal successfully with the same grant, then denied an attachment referring
to retained source outside that grant. It therefore exercises source access
separately from ordinary proposal access and propose permission. Permission,
ownership, impersonation and source denials returned exactly
`{"code":"NOT_FOUND_OR_NOT_ACCESSIBLE","message":"resource"}`.

For every call the verifier compared all raw canonical tables, including
continuity heads, commits, record versions, membership and canonical receipts.
No assessment call moved canon. It independently checked 440 existing workflow
row observations for preservation. Every frozen proposal row was identical
before/after; successful writes added exactly the selection/receipt and, for
attachment, one immutable envelope. Every failure/retry preserved the entire
workflow snapshot. The separate record-only setup commit precedes the source
scope case and is not attributed to an assessment call.

Reviewed the public request variants, untagged closed result DTO, independent
workflow dispatch, fixture rejection, immutable service/CAS path and updated
MCP instructions. They preserve the thirteen public tool names and do not add
assessment retrieval or validation integration. No actionable implementation
bug or design flaw was identified. Independently executed the focused public
service test `public_actions_preserve_frozen_proposal_and_recover_selection_retries`:
**1 passed, 0 failed**. An initial exact-name command matched zero tests; the
correct filtered command above executed the intended test.

Transcript SHA-256:
`5e180cd86b8a57cbbb8cdc83f1801928c58a59de6396d8f9ebf861ea00af8839`.
Any transcript change requires rerunning the verifier and updating this digest.
