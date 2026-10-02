# ADR-0004: Closed contracts and disposable feasibility runtime

Status: Implemented within the user-approved WP01–WP04 feasibility scope, 2026-09-24.

## Decision

Application contract version 1 uses a tagged `Request` with `tool` and typed `args`. MCP exposes the arguments directly. Arguments use snake_case; existing domain payloads retain their documented camelCase fields. Each of the 13 tools has an independently generated input and output schema. Action/mode variants close the field sets: a submit, withdraw, commit, receipt lookup, or proposal-bound validation cannot accept a new world filter. The inline/proposal `mode` and operation `lookup` discriminators make the spec's alternatives explicit.

Required scope has no default. Optional selectors reject explicit null; ID guards require names. Typed ID deserialization enforces the same prefix and lowercase-hex shape as its schema. Nested domain records reject unknown fields. Every successful result has version, request ID, resolved universe, frame where applicable, world focus, authorization disclosure, delivery metadata, and a typed result. Error results retain the existing error taxonomy. Schema generation and an independent Draft 2020-12 validator check positive and negative examples.

Private IPC uses a big-endian length-delimited JSON frame, a version/mode handshake, 1 MiB frame limit, at most 16 in-flight requests per connection, and correlated request IDs. Client reads and writes progress independently. Handshake, admission, and response waiting are bounded by the configured deadline. Dropped/timed-out requests send cancellation where possible; callers recover mutations with the original idempotency key. No mutation is automatically resubmitted with a new key. The fixture server permits 16 local connections and 8,192 unique request IDs per connection; it closes an exhausted connection. Contexts and proposal receipts have finite fixture capacities.

MCP remains an rmcp stdio adapter. Its inbound line decoder applies the same byte and duplicate-key checks before dispatch. Structured results and text fallbacks contain the same data. Fixture semantic errors are tool-visible errors. Standard JSON Unicode escapes are accepted on the wire; canonical-input parsing is not used as a wire decoder. Proposal hashes use the canonical serializer and resolved world IDs. Exact retries precede admission limits, and stale mutations cannot replace an existing proposal version. Selected-world proposals require a proven local write footprint; complex footprints remain unsupported in the fixture. No diagnostic output is written to MCP stdout.

## Feasibility boundary

The engine's `--fixture` flag is mandatory. It uses in-memory, bounded state and cannot open a real universe database or commit canon. A private socket directory, socket mode, and same-user peer check isolate the local fixture; these are not a substitute for the production credential/profile model. Contexts, proposals, and receipts are lost on engine exit. Recovery is tested across disconnected clients within the same fixture engine lifetime, not across engine restart.

Two named universes, duplicate world names across universes, shared character/work associations, and unassigned records exist from the first fixture. Display labels are not a substitute for structured assertions. Unsupported semantic operations return explicit errors. The core Boolean evaluator implements the spec's evidence algebra, preserves compilation scope/executability, and does not mark unsupported operators complete.

The native feasibility controls are app-owned Dioxus/HTML primitives; no Rust/UI source was copied. This uses the WP01 fallback to app-owned primitives rather than claiming an unreviewed upstream component integration. CSS is embedded, system fonts are used, and no remote assets are required. The proposal dialog uses native modal focus handling with a fixed, app-owned DOM bridge; authored text is never executable JavaScript or HTML. Clipboard writing uses the OS utility with literal stdin, and source selection does not import files.

The desktop launches its bundled helper by absolute path in a newly created private directory. Because Dioxus can exit the process without Rust destructors, an inherited stdin pipe also ties the disposable helper's lifetime to its parent. This fixture lifetime is intentionally different from WP06's persistent production engine, which must survive desktop closure.

## Remaining gates and tradeoffs

Host interoperability and native accessibility are evidence gates, not consequences of compilation. LM Studio desktop testing is blocked while Bionic runs; the user explicitly chose to keep Bionic open. No host configuration was changed. The full generated catalog is large; its measured schema size is recorded in the verification report. Host-specific token cost and tool-template behavior remain unverified.

Production authentication, immutable canon storage, crash-durable receipts, grant checks, full rule compilation/evaluation, revision-aware search, and release signing/notarization remain later work. No storage migration or production compatibility claim is made by this feasibility increment.
