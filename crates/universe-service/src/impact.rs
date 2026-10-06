use std::collections::BTreeSet;
use universe_domain::{ids::*, records::RecordVersion};
use universe_protocol::response::{Coverage, Impact};

/// Build the conservative impact payload from the exact visibility-filtered
/// snapshot supplied by the caller. Hidden records still downgrade coverage.
pub(crate) fn assemble(records: &[RecordVersion], visible: &BTreeSet<RecordId>) -> Impact {
    let mut ids = BTreeSet::new();
    let mut worlds = BTreeSet::new();
    let mut restricted = false;
    for record in records {
        if !visible.contains(&record.identity.record_id) {
            restricted = true;
            continue;
        }
        ids.insert(record.identity.record_id.clone());
        worlds.extend(crate::operations::worlds(record));
    }
    Impact {
        records: ids.into_iter().collect(),
        coverage: if restricted {
            Coverage::Restricted
        } else {
            Coverage::Complete
        },
        world_ids: worlds.into_iter().collect(),
    }
}

#[cfg(test)]
pub(crate) fn assemble_reference(
    records: &[RecordVersion],
    visible: &BTreeSet<RecordId>,
) -> Impact {
    let restricted = records
        .iter()
        .any(|r| !visible.contains(&r.identity.record_id));
    let ids: BTreeSet<_> = records
        .iter()
        .filter(|r| visible.contains(&r.identity.record_id))
        .map(|r| r.identity.record_id.clone())
        .collect();
    let worlds: BTreeSet<_> = records
        .iter()
        .filter(|r| visible.contains(&r.identity.record_id))
        .flat_map(crate::operations::worlds)
        .collect();
    Impact {
        records: ids.into_iter().collect(),
        coverage: if restricted {
            Coverage::Restricted
        } else {
            Coverage::Complete
        },
        world_ids: worlds.into_iter().collect(),
    }
}
