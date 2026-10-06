# Goal 36 retrieval measurements

Run the targeted measurements with:

```sh
cargo test -p universe-service snapshot_index_matches_complete_ancestor_reference_and_reports_cost -- --nocapture
cargo test -p universe-service indexed_context_assembly_matches_full_scan_with_overlapping_history -- --nocapture
cargo test -p universe-rules indexed_event_time_lookup_matches_linear_reference -- --nocapture
```

These tests use debug builds and one timed sample per path. Results below are
local observations, not release-mode or SLA claims.

| Path | Workload | Reference | Indexed | Observation |
| --- | --- | ---: | ---: | --- |
| Ancestor resolution and type match | 576 records, depth 384, 192 subjects | 321 ms | 82 ms | About 3.9x faster |
| Applicable-rule subject targeting | Same 576-record snapshot | 161 ms | 42 ms | About 3.8x faster |
| Temporal event lookup | 4,099 records, 256 event-relative lookups, target event at end | 9.6 ms | 0.067 ms | About 143x faster |
| Context assembly | 14,407 records, 64 subjects, 48 overlapping facts per subject | 405 ms | 315 ms | About 1.3x faster |
| Impact projection | Same 14,407-record snapshot, 12,348 visible records | 16 ms | 15 ms | Small change; one full pass instead of three |

Context and impact projections compare serialized complete outputs against the
previous full-scan implementations. The restricted context case also compares
outputs with the restricted-evidence marker enabled. Ancestor, applicable-rule,
and temporal measurements compare exact tri-state results and ancestry content.
Snapshot isolation is exercised against kernel-loaded revisions: a two-commit
ancestry change followed by 64 unrelated commits, for 66 commits total. The
historical and latest snapshots are retrieved independently, then indexed
assembly is compared to the full scan at each pinned revision. This revision
test uses a small record set; it is not a production revision-graph benchmark.

The context workload models overlapping time intervals, a large current record
snapshot, restricted visibility, and unrelated retained definitions. It does
not yet represent many database commits or a production-size revision graph.
The event workload stresses locating one late event record; ordinary absolute
time checks do not need this record lookup. All timings are single local debug
samples and will vary with machine load. No optimization is justified yet for
impact beyond reducing its projection from three record passes to one. Goal 36
still requires larger historical-revision and end-to-end impact workloads,
permission/conflict/unknown parity across the full query surface, and final
scoped commits.
