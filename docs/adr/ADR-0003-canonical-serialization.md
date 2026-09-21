# ADR-0003: Canonical serialization, digests, and the tagged-enum encoding rule

**Status:** Accepted
**Date:** 2026-07-22
**Work package:** WP02.3

## Context

Spec §27.8 requires **one versioned canonical serializer**: reject duplicate
object keys, invalid UTF-8, nonfinite numbers, and unknown fields for closed
contracts; canonicalize object-key order and exact numeric representation;
preserve authored Unicode without identity-changing normalization; preserve
sequence order. And: SHA-256 over the canonical serialized payload **and its
schema discriminator**.

## Decision

### 1. One manual `Canonical` implementation is the source of truth

Every domain type implements `Canonical::to_canonical() -> CanonicalValue`.
Serde is a *bridge*: types also derive `Serialize`/`Deserialize` so the same
value can travel over the wire and into diagnostics, with the **invariant**
that the serde shape and the manual canonical shape agree (duplicate-key and
round-trip tests enforce this). The canonical form is defined by the manual
impl, not by serde's emission.

- `CanonicalValue` is a strict closed value type: object keys are sorted,
  strings keep raw UTF-8 (minimal escapes only, no NFKC or other
  identity-changing normalization), numeric tokens are exact decimal strings
  with leading zeros preserved (`"007"` stays `007`), arrays keep order.
- The strict canonical *parser* rejects duplicate keys, trailing data,
  nonfinite numbers, and invalid UTF-8 before any value is accepted.
- The raw-string lexer copies full UTF-8 characters, never per-byte
  reinterpretation (a Latin-1-per-byte bug was caught in review).

### 2. Digests

- `payload_digest` = SHA-256 over the canonical bytes **plus the schema
  discriminator** (`record_kind` + schema version), so a payload under two
  kinds cannot share a digest.
- `hash_canonical` (the `Hash` impl) writes a **u32 length prefix** (via
  `Hasher::write_u32`) followed by the canonical bytes. This is a deliberate
  length-extension guard, not an optimization: `Hash` in Rust 1.92 has no
  `write_str`, and a bare byte stream would let `("ab", "c")` collide with
  `("abc", "")` for any combiner.

### 3. The `record_kind` discriminator on `Payload`

Several payload structs carry their **own** `kind` field (work, rule,
represented context). An internally tagged enum using `kind` as the
discriminator would emit a duplicate key — the strict parser rejects it, so
such a shape is unrepresentable. The `Payload` enum therefore tags on
`record_kind` (§27.1 contract naming) while nested payload fields keep their
authorial `kind`. This is covered by
`payload_tag_record_kind_coexists_with_payload_kind_fields`.

### 4. Struct variants, never newtype variants, for tagged recursive enums

serde's internally-tagged representation serializes a **newtype** variant's
content by *wrapping* the content's serializer in a `TaggedSerializer` per
variant arm (serde_derive `src/ser.rs`). When the wrapped content is
recursive (e.g. `Expr::Not(Expr)`), every derive-level monomorphization adds
a further wrapper layer and rustc's type-system recursion limit is exceeded —
`cargo check` passes but `cargo build`/`cargo test` fail deep in
serialization codegen.

**Rule:** any `#[serde(tag = …)]` enum whose variant content is (transitively
) recursive in the same type must use **struct variants**
(`Not { expr: Box<Expr> }`), which serialize the tag as an ordinary object
field and do not wrap the content type. Applied to `Expr`
(`Lit`/`Not`/`All`/`Any`), `Operand` (`Record`/`Value`), and `Value`
(`EntityRef`/`RecordRef`/`PropositionRef`/`Temporal`/`Spatial`), with field
names matching the manual canonical keys so the serde≡canonical invariant
holds. Non-recursive enums (e.g. `Payload` arms, whose content is a non
self-recursive record struct) may keep newtype variants.

**Trade-off:** struct variants are marginously chattier on the wire
(`{"kind":"not","expr":…}` vs. a wrapped form). That cost is irrelevant next
to the alternative — no serde representation at all for recursive tagged
enums — and it is *the* representation the manual canonical impl already uses.

### 5. Set normalization

`Value::Set` canonicalizes by **sorting items by their canonical byte
encoding** (spec §27.2: arrays representing sets are normalized by stable
identity). Sequences keep authored order. The sort is a pure function of
canonical bytes, so identity is stable across processes and languages, and
`sequence_order_and_set_normalization_are_distinct` pins the two apart.

## Consequences

- Canonical bytes are a cross-process, cross-language identity: the store
  (WP05), the MCP adapter (WP04), and the desktop (WP11) all consume the same
  bytes; none may re-serialize through serde for identity purposes.
- Any new closed contract must (a) implement `Canonical` manually, (b) keep
  its serde derive shape identical to the manual keys, (c) add a duplicate-key
  + strict round-trip test, and (d) if it is a tagged recursive enum, use
  struct variants.
- Changing canonical byte layout is a schema-version bump (§14.5), never a
  silent re-encode.
