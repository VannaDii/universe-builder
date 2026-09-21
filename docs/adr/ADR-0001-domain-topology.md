# ADR-0001: Domain topology — universe/world scope, in-domain expression AST, body-remapped definition IDs

**Status:** Accepted
**Date:** 2026-07-22
**Work package:** WP01.1 (decision baseline) / WP02

## Context

`universe-domain` must encode the spec's identity and scope model (spec §27.1,
§36.1, §5.6) plus the rule expression language (§9.3–9.5, §27.10). Three
consequential choices were required while implementing the pure domain model:

1. How universe/world/work/saga ownership is represented.
2. Where the rule expression AST lives.
3. How definition-family IDs (calendar, unit, value definition, proposition,
   rule, exception, anchor) relate to `RecordId`.

## Decision

### 1. Universe is the namespace; world/work/saga are universe-owned records

`WorldId`, `WorkId`, `SagaId`, and `ContinuityId` are typed newtypes but are
**not** second namespaces. A `World` record is a canonical record inside the
universe selected by `UniverseId`; world *focus* is a per-command scope
selector, and `Applicability` (universe-wide vs. named worlds vs. conditional)
is explicit data on assertions/rules. A world selector does not silently
establish applicability (I26; spec §36.5). There is no implicit "current
world" anywhere in the domain types.

### 2. The expression AST is a domain type, not a rules-crate type

`Expr`/`Operand`/`Quantifier`/`Comparator` (with `rule-expr-v1` language
version) live in `universe-domain`. Consequences:

- `universe-rules` (WP08.3) is a pure compiler/evaluator *over* domain types;
  it cannot drift into a parallel, incompatible AST.
- One canonical serializer (ADR-0003) covers rule expressions, so a rule
  payload's canonical bytes are stable across crates.
- Domain values referenced by expressions (`Value`, `RecordRef`, temporal and
  spatial expressions) are the exact types the rest of the model uses, so
  "definition vs. instance" and "value vs. reference" distinctions cannot be
  silently flattened.

**Trade-off accepted:** the domain crate now contains executable-language
types. That is deliberate — the spec's single-serializer requirement (§27.8)
and the no-untyped-escape-hatch requirement (WP02 exit) both pull in the same
direction. The domain crate still has no transport/database/service
dependencies (spec §3.4).

### 3. Definition-family IDs use body-preserving prefix remapping

Seven definition families have their own prefixed ID newtypes
(`cal_`, `unit_`, `vdef_`, `prop_`, `rule_`, `exc_`, `anch_`), each with a
24-hex opaque body. `from_id(RecordId) -> Option<Self>` and
`to_record_id() -> RecordId` are implemented via a shared `remap_id_body`
macro: take the 24-hex body of one family's ID, keep it byte-identical, and
re-prefix it with the other family's prefix.

**Alternatives rejected:**

- *Free-form definition IDs* — loses the 24-hex parseable body and the
  cross-family identity link; breaks "identity and kind are immutable" (§27.1)
  for definition records.
- *Separate `RecordId` + `RecordKind` pair everywhere* — matches the wire
  contract but forces every in-domain reference to carry a redundant kind and
  invites kind/body mismatches. The typed IDs make mismatches unrepresentable.
- *The previous session's `from_id` definition* (require the source `RecordId`
  to already carry the target prefix) — can never succeed, since record IDs
  start `rec_`; replaced.

## Consequences

- A definition record's `RecordId` and its family ID always share a body;
  validation can reject mismatches structurally.
- The remap is lossless and deterministic in both directions, which keeps
  canonical digests stable (the digest hashes the family-prefixed ID form in
  the payload; the `RecordId` view is a projection).
- New definition families must add both prefixes to `remap_id_body` at
  definition time, not later.

## Unsupported scope (WP01.1 requirement)

- Cross-universe definition references are rejected at the domain level; the
  service layer adds the grant check (WP06/WP07).
- The expression AST is *descriptive* in this crate: it serializes, validates
  structurally, and canonicalizes. Executable evaluation is WP08's job; the
  capability registry (`capabilities::*`) is what publishes what is
  executable.
