//! Freeze event expansion into the exact proposal reviewed by the author.
use std::collections::BTreeMap;
use universe_domain::{ids::*, records::*};
use universe_store::kernel::Assignment;
fn invalid(message: &str) -> anyhow::Error {
    universe_protocol::ProtocolError::invalid_argument("event", message).into()
}
pub fn recompile(
    u: &UniverseId,
    base: &[RecordVersion],
    changes: &mut Vec<Assignment>,
) -> anyhow::Result<()> {
    let mut candidate: BTreeMap<_, _> = base
        .iter()
        .map(|r| (r.identity.record_id.clone(), r.clone()))
        .collect();
    for change in changes.iter() {
        if candidate.get(&change.record_id).is_some_and(
            |r| matches!(&r.payload,Payload::Assertion(a) if a.established_by.is_some()),
        ) || change.next.as_ref().is_some_and(
            |r| matches!(&r.payload,Payload::Assertion(a) if a.established_by.is_some()),
        ) {
            return Err(invalid(
                "generated assertions can only change through their event",
            ));
        }
        if let Some(next) = &change.next {
            candidate.insert(change.record_id.clone(), next.clone());
        } else {
            candidate.remove(&change.record_id);
        }
    }
    for row in candidate.values() {
        if let Payload::Assertion(a) = &row.payload {
            if let universe_domain::scope::EvidenceBasis::InstanceInitialization { start, .. } = &a.basis {
                if changes.iter().any(|change|change.record_id==start.record && change.next.is_none()) {
                    return Err(invalid("surviving initialization requires its occurred start; its once-only receipt is retained"));
                }
            }
        }
    }
    let mut expected =
        universe_rules::events::expand(&candidate.values().cloned().collect::<Vec<_>>())
            .map_err(|e| invalid(&e))?;
    for old in base {
        if matches!(&old.payload,Payload::Assertion(a) if a.established_by.is_some()) {
            let next = expected
                .remove(&old.identity.record_id)
                .map(Payload::Assertion);
            if next.as_ref() == Some(&old.payload) {
                continue;
            }
            changes.push(Assignment {
                record_id: old.identity.record_id.clone(),
                expected: Some(old.record_version_id.clone()),
                next: next
                    .map(|p| {
                        RecordVersion::build(
                            RecordVersionId::generate(&mut rand::rng()),
                            old.identity.clone(),
                            p,
                        )
                    })
                    .transpose()?,
            });
        }
    }
    for (id, a) in expected {
        if candidate.contains_key(&id) {
            return Err(invalid(
                "generated effect identity collides with an existing record",
            ));
        }
        changes.push(Assignment {
            record_id: id.clone(),
            expected: None,
            next: Some(RecordVersion::build(
                RecordVersionId::generate(&mut rand::rng()),
                RecordIdentity::new(u.clone(), id, RecordKind::Assertion),
                Payload::Assertion(a),
            )?),
        });
    }
    Ok(())
}
