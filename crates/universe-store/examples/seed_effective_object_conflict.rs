//! Test-only inconsistent historical specimen for readback qualification.
//! Public admission must continue to reject this competing scalar value.
use universe_domain::{ids::*, records::*, scope::Polarity};
use universe_store::kernel::{Assignment, CommitInput, Kernel};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    let path = std::path::Path::new(&args[1]);
    assert!(
        path.components().any(|p| p
            .as_os_str()
            .to_string_lossy()
            .starts_with("effective-object-")),
        "disposable effective-object installation required"
    );
    let mut kernel = Kernel::open(path)?;
    let continuity = ContinuityId::parse(&args[2])?;
    let principal = PrincipalId::parse(&args[3])?;
    let payloads: Vec<Payload> = serde_json::from_slice(&std::fs::read(&args[4])?)?;
    assert_eq!(payloads.len(), 2);
    assert!(
        matches!(&payloads[0], Payload::Proposition(p) if p.subject.record.as_str() == "rec_000000000000000000030d42" && p.predicate.record.as_str() == "rec_000000000000000000030d4a")
    );
    assert!(
        matches!(&payloads[1], Payload::Assertion(a) if a.attribute_mode == AttributeMode::Shared && a.polarity == Polarity::Support && a.proposition.record.as_str() == "rec_000000000000000000030d65")
    );
    let changes = payloads
        .into_iter()
        .enumerate()
        .map(|(i, payload)| {
            let record_id = RecordId::parse(&format!("rec_{:024x}", 200037 + i))?;
            let version = RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{:024x}", 900001 + i))?,
                RecordIdentity::new(kernel.universe().clone(), record_id.clone(), payload.kind()),
                payload,
            )?;
            Ok(Assignment {
                record_id,
                expected: None,
                next: Some(version),
            })
        })
        .collect::<Result<Vec<_>, universe_domain::DomainError>>()?;
    let input = CommitInput {
        universe: kernel.universe().clone(),
        continuity: continuity.clone(),
        expected_head: kernel.head(&continuity)?,
        principal,
        decision: "disposable inconsistent historical retrieval specimen".into(),
        reason: "competing inherited scalar value readback, not admission".into(),
        idempotency_key: "effective-object-history-seed".into(),
        changes,
    };
    println!("{}", kernel.commit(&input)?);
    Ok(())
}
