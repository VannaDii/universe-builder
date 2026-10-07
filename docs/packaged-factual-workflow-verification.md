# Goal 38 — Fresh installed development package factual workflow

October 6, 2026 (America/Los_Angeles). The final development package was built
from clean `main` at `2219ddd26fe888694713e601874639038ff2514b` using the existing
`xtask package-fixture` command. No packaging or product integration defect was
demonstrated. This goal adds a reproducible installed-package proof, a prefix
option in the independent Python MCP client for `multiverse-mcp serve`, and a CI
step. It does not change product admission or architecture. Hosted CI has not
been executed in this session.

The [runner](../scripts/packaged_factual_workflow.py) copies the complete app to
an owned temporary `Applications with spaces` directory, creates a public
launcher symlink, and runs from outside the source checkout. All product process
launches must resolve inside the copied bundle; a Python execution guard rejects
other product executable paths, source-checkout working directories, checkout
PATH entries, and desktop launches. The final run records 75 product launches.
Nine post-start/status observations independently check that the running owned
engine's command names the copied installed helper. MCP processes force
`/usr/bin:/bin`; the outer qualification tooling also permits the Rust toolchain
directory for build metadata. Python readers, schemas, expected tables and source
hash collection remain source-based qualification tooling, not product runtime
dependencies. This proves a fresh installation on this host, not a clean machine.

## Executed proof

| Requirement | Observed result |
| --- | --- |
| Package inspection | Local-development channel, `release_accepted: false`, clean source revision, 393 recorded components, component hash and all four helper hashes match. Every copied bundle file retains its original hash throughout the proof. |
| Enrollment/authentication | Fresh author initialization, separately enrolled agent, current grants, denial before granting access, exact author approval requirement, forged/incompatible handshake rejection and revoked-profile denial. Six simultaneous cold clients converge on one owned service. No existing installation is opened. |
| MCP discovery | Real initialize and tools/list discover all 13 tools. Compiled tool schemas and output envelopes are validated by the independent client. The factual author session goes through installed public `admin` and `serve`; additional enrolled/restricted clients use the installed MCP helper. |
| Effective retrieval | Field kit definition exposes four initial units without making them instance stock. Reviewed initialization supplies exactly four units with its receipt and provenance. Missing instance state remains explicit before initialization. A pinned earlier context retains the earlier facts; a North-only reader retains restricted coverage and cannot see the South-only attribute. |
| Reviewed publication | Nine canonical publications bind the captured private review, exact candidate/version/digest, validation run, author approval and commit receipt. Commit before exact approval rejects. The separately authored factual table checks 65 delivered versions, ten canonical snapshots and eleven state queries. |
| Resource gate and acceptance | Three unresolved candidates reject ordinary approval/commit without changing canonical authority. Exact unexplained stock of two is explicitly accepted; changing it to three needs a different independently reconstructed fingerprint and fresh acceptance. An enrolled client copying the author principal cannot mint creative authority. Acceptance preserves the unexplained arrival; it supplies no invented cause. |
| Stale authority | Reusing old validation/approval yields `APPROVAL_STALE`; a mismatched old commit key rejects. A previous accepted claim cannot authorize the changed claim. Denials preserve canonical counts/head. Revocation invalidates the old enrolled credential. |
| Receipts/restart | Three forced engine restarts preserve current and historical facts, rejection, initialization provenance and publication receipts. A delivered commit response is deliberately discarded before restart and recovered by its original key. All nine exact commit retries return their original receipts after the final restart. |
| Independent history inspection | The existing resource auditor compares raw JSON-RPC delivery against the separately authored expected table and reconstructs immutable typed SQLite history without the Rust writer/evaluator or head-membership cache. Stored publication and initialization receipts match delivered evidence. Integrity check is `ok`; foreign-key check returns no violations. |
| Auditor controls | All 18 tests pass, including the authentic retained database/wire control and coherent forgeries of counts, acceptance authority, policy, debit, historical state, provenance, recovered receipt, stale context and restricted coverage. Independence means separate expected facts and reader/calculator, not another human or model review. |

The final installed proof takes **28.322 seconds**, including its 18 auditor
controls. Package build and shared workspace checks are separate from that time.
The [committed result metadata](packaged-factual-proof-results.json) includes all
bundle file/helper hashes, oracle identity, audit counts, local evidence hashes
and measured timing. Raw synthetic report, wire, package database and audit log
remain in `/tmp/goal38-final-proof`; installations, credentials and copied app are
removed. Those temporary files are local evidence, not a portable committed
proof bundle. Reproduce them when absent.

Report SHA-256:
`c89e372123223e08e5d8975057b2d0ebb9c182adf21a29d69d681cbf49db5671`.
Retained synthetic package SHA-256:
`cd2421cea11768465b3386487b486aaf1a596c4ef641a7bb591f6def55c4f31c`.

## Reproduction and boundaries

```sh
cargo run --locked -p xtask -- package-fixture
uv run --with jsonschema==4.25.1 python scripts/packaged_factual_workflow.py \
  --bundle 'target/fixture/Universe Builder Fixture.app' \
  --output /tmp/fresh-packaged-factual-proof
RUST_TEST_THREADS=2 cargo run --locked -p xtask -- check
uv run --with jsonschema==4.25.1 python scripts/validate_contracts.py
uv run --with jsonschema==4.25.1 python -m unittest discover -s scripts -p 'test_distribution.py' -v
```

The output directory must be new. The runner itself executes the independent
resource auditor and its 18 controls. The [expected table](../fixtures/resource-resolution/expected.json)
supplies expected facts only to the auditor; the workflow driver hashes it but
does not use its contents to construct facts.
The development bundle's existing ad-hoc sealing is a build/runtime prerequisite,
not Developer ID, notarization or signing acceptance. Execution is local arm64
on macOS 27.0.1 with Rust 1.92.0; no broader OS/architecture certification follows.
Live author data, native interaction/VoiceOver, external model interpretation,
host integration, signing acceptance, deployment and distribution acceptance are
outside this goal. Receipt interruption follows delivered response; network or
packet-loss behavior is not established.

Automatic MCP startup created six disposable GitHub/Sonar containers with
generated names. Launcher working directories, read-only project mounts and the
idle other chat for this project established ownership; this proof used neither
server. The initial four were stopped and automatically removed. Automatic startup
created two more for this project before completion; those were also stopped
and removed, then verified absent.
Other projects' containers were preserved. The automatic launcher cannot yet
provide compliant project names and shared HTTP reuse; no supervisor, new server,
software installation or system-permission change was introduced to work around it.

## Final gates and working time

The final shared workspace check passed formatting, strict workspace/all-target
Clippy, **398 Rust tests**, doc tests and generated-schema freshness. Two existing
opt-in workloads remain ignored: the standard release workload and Goal 36
overlapping-history benchmark. The ordinary 10,000-entity import/backup/restore/
restart regression passed. Contract validation passed 26 schemas, 13 valid
examples and 91 malformed examples; five distribution formula unit tests passed.
These unit tests do not establish distribution installation or acceptance.

Working wall time through final verification: **9 minutes 37 seconds**,
from October 6, 2026 at 18:34:17 PDT
to 18:43:54 PDT. This includes package build and executed test waits.
Final documentation commit and completion-report bookkeeping follow in this
session. The goal completion report includes that additional working time.
