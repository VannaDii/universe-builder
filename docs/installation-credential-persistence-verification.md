# Goal 24: relational installation and credential persistence

October 4, 2026. Completed locally against disposable installations. Live
installation conversion remains Goal 27; no live installation was opened or
converted, and no release was deployed.

## Implementation

The registry initializes directly from the approved
`docs/decisions/relational-storage/installation.sql`. Grant flags, scope states,
expiry, delegation and shared-write permission are scalar columns. World,
entity, predicate and continuity lists are ordered child rows. Grant replacement,
withdrawal and purge update children and authority audit records transactionally.
Reporting reconstructs the existing public grant contract without persisted JSON.
List order and duplicate identities survive; `all` and `listed` with zero children
remain distinct. Existing admission rules still reject new empty grant boundaries.
Expiry remains the exact decimal representation of the existing unsigned seconds.

Both client authentication and service enrollment use the shared credential
reader/writer and the approved `credential.sql`. Each `profiles/{profile}.sqlite`
contains one exact profile identity and credential. The file is private (0600),
its directory is private (0700), and the reader checks ownership, links, mode and
identity. Enrollment durably commits the private credential before publishing its
unchanged SHA-256 hash. Credential values are never debug-formatted in proofs.
The obsolete JSON profile-file contract was removed.

Existing legacy installation databases are rejected with an explicit Goal 27
conversion message. The regression test verifies their database bytes remain
unchanged; no automatic migration or compatibility reader was added.

## Executed qualification

All checks below passed on this host:

- `cargo test -p universe-service -p universe-client -p universe-store`: 144 tests
  passed; the existing standard-workload test remained ignored. Includes real
  Unix-socket client/service authentication, reviewed commits, current grants,
  world restrictions, protected/shared-write denial, queued stale-authority and
  grant-ABA rejection, delegation expiry and revocation, restart, backup and export.
- `cargo test --locked -p universe-service --test installation`: all four tests
  passed after the final scope controls were added. Actual client requests deny
  entity, predicate and continuity write boundaries independently; grants,
  profile IDs, exact credentials and reports survive restart. An authenticated
  connection loses access after expiry or revocation; revoked credentials remain
  rejected after reopening installation authority.
- `cargo test --locked -p universe-store credentials::tests`: exact synthetic
  Unicode/whitespace credentials survive, overwrite is refused, and wrong
  identity, symlink, public file mode and public directory mode are rejected.
- The real-client installation test executes
  `scripts/verify_installation_relational.py` in a separate Python process. Its
  read-only SQLite connections compare the actual installation and credential
  schemas against the approved SQL, check integrity/foreign keys, ordered lists,
  exact credential/hash matches and private modes. It checks the actual logical
  export, universe database files and Profiles/Doctor/Status reports for credential
  or hash leakage. Inspection prints neither credentials nor hashes.
- `cargo build -p universe-cli -p universe-mcp -p universe-engine`: passed.
- `/tmp/universe-goal24-verification/bin/python scripts/installation_smoke.py`:
  passed with pinned `jsonschema==4.25.1`. Six simultaneous CLI cold starts share
  one service; independent stdio MCP performs proposal, validation, approval and
  commit; malformed/forged handshake, revocation, SIGKILL stale-socket recovery
  and durable heads pass. Its stale entity fixture was updated to the current
  classification contract, and its credential reader now queries private SQLite.
- `cargo clippy --locked -p universe-store -p universe-service -p universe-client
  -p universe-protocol -p universe-cli -p universe-mcp -p universe-engine
  --all-targets -- -D warnings`: passed. Final installation-test additions also
  passed `cargo clippy --locked -p universe-service --test installation -- -D warnings`.
- `cargo fmt --all -- --check` and `git diff --check`: passed.

The first integration-inspector attempt incorrectly treated the current JSONL
logical export as SQLite; the inspector was corrected to inspect the actual
format. The first smoke attempts encountered a missing Python dependency and
an obsolete entity fixture; both were corrected before the successful run.
No export-format conversion was introduced by this goal.

Working time began at 09:21:40 PDT; implementation and final checks completed at
09:31:00 PDT (9 minutes 20 seconds). Documentation and commit preparation follow
that interval; the final response reports total elapsed working time.
