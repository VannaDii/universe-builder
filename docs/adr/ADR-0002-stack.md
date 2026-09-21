# ADR-0002: Technology stack and pinned dependency set

**Status:** Accepted
**Date:** 2026-07-22
**Work package:** WP01.1 / WP01.4

## Context

The spec (§3, §28, §30) fixes the architecture (Rust workspace, SQLite
storage, MCP server, Dioxus desktop) but not exact versions. WP01.4 requires
that a clean build resolves the *selected* dependencies and that exact
versions be recorded rather than assumed from a docs version label.

## Decision

Exact-pinned (`=`) workspace dependency set, committed `Cargo.lock`, and a
pinned toolchain:

| Component | Version | Rationale |
|---|---|---|
| Rust toolchain | `1.92.0` via `rust-toolchain.toml` | Pins rustc, rustfmt, clippy so `fmt --check` / `clippy` are reproducible. |
| `serde` / `serde_json` | `=1.0.228` / `=1.0.145` | serde_json features `preserve_order` + `arbitrary_precision` so canonical numeric tokens (including leading zeros) survive round trips (ADR-0003). |
| `rmcp` | `=3.4.0` (server, macros, schemars, transport-io) | The current MCP SDK for the tool surface in spec §30; the MCP protocol version it implements is a release-time check, not a domain contract. |
| `rusqlite` | `=0.40.2` (bundled, functions) | `bundled` compiles a known SQLite source into the binary. Verified build resolves to **SQLite 3.51.3** — the actual library version, not a docs label (WP01.4). Removes system-SQLite drift across macOS installs. |
| `sha2` | `=0.10.9` | `dioxus-router-macro 0.7.9` requires `sha2 ^0.10.9`; the workspace is a single resolver, so the whole tree is pinned to the version the UI stack demands. |
| `dioxus` | `=0.7.9` (desktop, router) + `dioxus-hooks` / `dioxus-signals` `=0.7.9` | Current desktop Dioxus line for the author UI (WP11). |
| `tokio` | `=1.48.0` (full) | Async runtime for the engine/IPC/MCP processes. |
| `schemars` | `=1.2.1` (derive) | JSON-Schema emission for contract tooling and MCP schemas. |
| Others | `thiserror =2.0.16`, `hex =0.4.3`, `rand =0.9.2`, `dirs =6.0.0`, `chrono =0.4.42` (clock only), `unicode-normalization =0.1.22`, `tracing =0.1.41`, `tracing-subscriber =0.3.20`, `anyhow =1.0.100`, `tokio-util =0.7.16`, `futures =0.3.31`, `clap =4.5.51` | Conventional choices; none adds a new runtime surface beyond the crates above. |

## Consequences

- `Cargo.lock` is a tracked artifact; any dependency drift is a reviewable,
  explicit change (spec §33.17: dependency changes run provenance checks).
- The `sha2` bump is forced by the UI stack, not chosen by the storage stack —
  recorded here so a future reader does not "fix" it back to 0.10.8.
- Bundled SQLite costs build time and a native-compile step; in exchange the
  storage layer never depends on whatever SQLite a user happens to have.

## Trade-offs / unsupported scope

- **rmcp maturity:** the SDK is young. We pin exactly and treat the MCP
  *protocol* version as a compatibility fixture (WP03.4/WP04) rather than a
  domain promise; if rmcp lags a needed host capability, the adapter grows a
  tested shim instead of the domain changing.
- **Dioxus desktop on macOS** is the primary target; other platforms are
  explicitly out of scope until WP15's OS manifest.
- **Bundled SQLite features:** only `functions` is enabled; FTS5 availability
  is verified at build time in WP05.1 and gated by capability, not assumed.
- The Xcode license quirk in the dev environment (`DEVELOPER_DIR=
  /Library/Developer/CommandLineTools` required for cargo on this machine) is
  an environment note, not a stack decision.
