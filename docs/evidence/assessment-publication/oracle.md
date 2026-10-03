# Independent publication oracle

Frozen before generating the publication MCP transcript. The separate Python
auditor imports no producer or Rust helpers. It independently reconstructs
canonical UTF-8 bytes, source/body hashes, final validation digests and exact
approval hashes from raw SQLite rows. Its expectations follow the approved
D03/D08 lifecycle: rejected stale/unapproved/revoked requests preserve all rows;
successful commits append exactly one canonical commit/receipt; idempotent retries
append nothing; replacement, withdrawal and identity reselection change generation;
restart preserves receipts, historical attachments and validation bytes exactly.

The transcript uses actual stdio MCP for validation and commit, and the existing
private author approval command. Deterministic concurrency and transaction
rollback are separate Rust proofs, not inferred from stdio timing. This is an
independent calculator/process audit, not a second human or model review.
