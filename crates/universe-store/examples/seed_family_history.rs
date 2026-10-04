//! Test-only bootstrap for the two families without public creation operations.
//! Opens only the explicit disposable package supplied by the qualification pilot.
use universe_domain::{ids::*, records::*};
use universe_store::kernel::{Assignment, CommitInput, Kernel};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    let mut kernel = Kernel::open(std::path::Path::new(&args[1]))?;
    let continuity = ContinuityId::parse(&args[2])?;
    let principal = PrincipalId::parse(&args[3])?;
    let records: Vec<RecordVersion> = serde_json::from_slice(&std::fs::read(&args[4])?)?;
    assert!(records
        .iter()
        .all(|r| matches!(r.payload, Payload::Realm(_) | Payload::Secret(_))));
    let input = CommitInput {
        universe: records[0].identity.universe_id.clone(),
        continuity: continuity.clone(),
        expected_head: kernel.head(&continuity)?,
        principal,
        decision: "disposable qualification seed".into(),
        reason: "existing families without creation operations".into(),
        idempotency_key: "family-seed".into(),
        changes: records
            .into_iter()
            .map(|r| Assignment {
                record_id: r.identity.record_id.clone(),
                expected: None,
                next: Some(r),
            })
            .collect(),
    };
    println!("{}", kernel.commit(&input)?);
    Ok(())
}
