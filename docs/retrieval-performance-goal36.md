# Goal 36 retrieval measurements

Run the targeted measurements with:

```sh
cargo test -p universe-service snapshot_index_matches_complete_ancestor_reference_and_reports_cost -- --nocapture
cargo test -p universe-service indexed_context_assembly_matches_full_scan_with_overlapping_history -- --ignored --nocapture
cargo test -p universe-service indexed_retrieval_stays_pinned_to_store_historical_revisions -- --nocapture
cargo test -p universe-rules indexed_event_time_lookup_matches_linear_reference -- --nocapture
```

These tests use debug builds and one timed sample per path. Results below are
local observations, not release-mode or SLA claims.

| Path | Workload | Reference | Indexed | Observation |
| --- | --- | ---: | ---: | --- |
| Ancestor resolution and type match | 576 records, depth 384, 192 subjects | 321 ms | 82 ms | About 3.9x faster |
| Applicable-rule subject targeting | Same 576-record snapshot | 161 ms | 42 ms | About 3.8x faster |
| Temporal event lookup | 4,099 records, 256 event-relative lookups, target event at end | 9.6 ms | 0.067 ms | About 143x faster |
| Context assembly | 4,745 records, 64 subjects, 32 overlapping facts each, 111 commits | 149 ms | 95 ms | About 1.6x faster |
| End-to-end impact request | 73 records, 66 historical commits | n/a | 13 ms | Output equals full reference projection |
| End-to-end impact limit | 4,745 records, 111 commits, 65,536-byte budget | n/a | 1,411 ms | Explicit budget error; no partial result |

Context assembly compares serialized complete outputs against the full-scan
reference implementation. The restricted context case also compares outputs
with the restricted-evidence marker enabled. Ancestor, applicable-rule, and
temporal measurements compare exact tri-state results and ancestry content.
Snapshot isolation is exercised against kernel-loaded revisions: a two-commit
ancestry change followed by 64 unrelated commits, for 66 commits total. The
historical and latest snapshots are retrieved independently, then indexed
assembly is compared to the full scan at each pinned revision. The explicit
context workload seeds overlapping evidence and unrelated definitions in 47
batches, appends 64 further revisions, reads the latest of 111 committed
revisions and compares reference/indexed context assembly. The inline impact
request is timed end-to-end and its result is checked against the original
three-pass projection formula. At 4,745 records, the same request computes the
impact set but exceeds the protocol's maximum 65,536-byte budget and returns the
documented evaluation-limit error; it does not emit a partial result.
Seeding and latest-snapshot load took 120 seconds in the observed run. A
separate end-to-end inline impact request at the latest of 66 revisions matched
the full projection reference and took 13 ms on its 73-record fixture.

The context workload exercises a moderate record set and revision depth; its
two-minute setup makes it opt-in. It is not a production-scale revision-graph
benchmark. The event workload stresses locating one late event record; ordinary
absolute time checks do not need this record lookup. All timings are single
local debug samples and will vary with machine load. No impact optimization was
retained because the measured projection difference was within timer resolution.
The large end-to-end impact path is bounded by the protocol's 65,536-byte
impact budget; its 1.4-second measurement ends with the expected limit error,
not a complete large response. The 73-record successful request does not
establish a large-universe latency bound. The 111-commit workload is a local
debug stress case, not a production-scale revision graph or an SLA. Broad permission,
conflict, and unknown parity continues to be covered by focused cases, but
production-scale combinations and a release-mode rerun remain outstanding.
