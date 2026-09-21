# Universe Builder — Implementation Status

Source of truth: `Universe_Builder_Full_Implementation_Plan_v0.4.md`
(spec commit `c287a1b`). Decisions: `docs/adr/`. This file is updated at
every committed increment and never lags the tree.

## Overall state

**In progress — WP02 (pure domain model).** The `universe-domain` crate is
implemented and verified. All other crates are honest, compiling
placeholders. Nothing here is a demonstration being reported as finished.

## Crate status

| Crate | Status | Spec area |
|---|---|---|
| `universe-domain` | **Implemented.** 10 modules; 35 tests passing; `fmt` + `clippy --all-targets` clean. | WP02.1, WP02.2, and the WP02.3 canonical-serializer core |
| `universe-schema` | Placeholder | WP02.3 (definition registry, closed payload schemas, schema recursion checks) |
| `universe-rules` | Placeholder | WP08 (rule compiler/evaluation) |
| `universe-protocol` | Placeholder | WP03.1 |
| `universe-client` | Placeholder | WP03.2–03.5 |
| `universe-store` | Placeholder | WP05 |
| `universe-service` | Placeholder | WP07 |
| `universe-engine` | Placeholder | WP06 |
| `universe-mcp` | Placeholder | WP04 |
| `universe-cli` | Placeholder | WP10 (maintenance/import/export) |
| `universe-ui` | Placeholder | WP11 |
| `apps/desktop` | Placeholder | WP01.3 / WP11 |
| `xtask` | Minimal (`help` only) | §33.17 automation entry point |

## What `universe-domain` contains

- Newtyped IDs for all §27.1 families; definition families (`cal_`, `unit_`,
  `vdef_`, `prop_`, `rule_`, `exc_`, `anch_`) with body-preserving
  `RecordId` remapping (ADR-0001).
- Exact values, precision alternatives, temporal/spatial expressions,
  scopes, validity/persistence, represented contexts, frames, and the full
  closed `Payload` set with the `record_kind` discriminator (ADR-0003).
- One versioned canonical serializer: strict parser, sorted keys, raw UTF-8,
  exact numeric tokens, set normalization, SHA-256 digests with schema
  discriminator, length-prefixed `Hash` (ADR-0003).
- The `rule-expr-v1` expression AST (in-domain per ADR-0001) with structural
  validation.
- Capability identifiers and `SCHEMA_VERSION` / `CONTRACT_VERSION`.

## WP01 status (honest accounting)

- **WP01.1:** the three *consequential* ADRs are written (topology, stack,
  canonical). The remaining WP01.1 topics (shared engine, authorization,
  immutable canon, MCP, time/uncertainty, SQLite, source ownership) will get
  ADRs at the point each owning work package lands, so each ADR cites a
  verified implementation rather than a plan.
- **WP01.2 / WP01.5 (silver-gate and two-universe/multi-world fixtures):**
  not yet written. Planned as `fixtures/` after the core crate chain lands
  (domain → schema → rules → protocol → client → store → service → engine →
  mcp → cli).
- **WP01.3 (native Dioxus feasibility fixture):** not yet run; desktop is a
  placeholder.
- **WP01.4:** done — exact `=` pins, committed `Cargo.lock`,
  `rust-toolchain.toml` (1.92.0).
- Deviation from §26/§33.16 ordering (WP01–WP04 + fixtures first): we are
  landing WP02's remaining pieces (`universe-schema`) before WP03/WP04 and
  before the silver-gate fixtures, because the domain model is the substrate
  every later crate and fixture consumes. The fixture contracts themselves
  are unaffected; they will be written against the same §36/V-cases text.

## Verification

Current tree (this commit): `cargo fmt --check`, `cargo clippy --workspace
--all-targets` (zero warnings), `cargo check --workspace`, and
`cargo test -p universe-domain` (35/35) all pass.

## Environment note (developers)

This machine has no accepted Xcode.app license. Use
`export DEVELOPER_DIR=/Library/Developer/CommandLineTools` before cargo
commands, or run `sudo xcodebuild -license` once.

## Next increment (planned, dependency order per §33.16)

1. `universe-schema` — WP02.3: definition registry, closed payload schema
   validation (duplicate keys, unknown enums, schema recursion, silent
   coercion tests), digest wiring. Closes WP02.
2. `universe-rules` — WP08.1/08.3 structural compiler over the domain AST.
3. `universe-protocol` + `universe-client` — WP03.
4. `universe-store` — WP05 (SQLite 3.51.3 bundled, §28 DDL).
5. `universe-service`, `universe-engine`, `universe-mcp`, `universe-cli`.
6. `fixtures/` — silver-gate S01–S10 and §36 two-universe/multi-world
   fixtures ("The Ashen Cycle", "The Glass Archive").
7. `universe-ui` + `apps/desktop` — WP11.

Each step commits with an updated section of this file.

## Change log

| Date | Change |
|---|---|
| 2026-07-22 | Spec committed (`c287a1b`). Workspace skeleton, pinned dependencies, `universe-domain` implemented and green (35 tests). ADRs 0001–0003, this file. |
