//! State queries and action validation share the same possession semantics.
use universe_domain::{frame::FrameTime, ids::*, records::RecordVersion, value::RecordRef};
use universe_protocol::{response::DerivedFact, ProtocolError};
pub fn derive(
    records: &[RecordVersion],
    subjects: &[RecordId],
    predicates: &[RecordId],
    context: &RecordRef,
    time: &FrameTime,
    world: Option<&WorldId>,
) -> anyhow::Result<Vec<DerivedFact>> {
    let facts = universe_rules::powers::derive(records, subjects, predicates, context, time, world)
        .map_err(|message| ProtocolError::EvaluationLimitReached { message })?;
    Ok(facts
        .into_iter()
        .map(|f| DerivedFact {
            subject: f.subject,
            predicate: f.predicate,
            value: f.value,
            evidence: f.evidence,
            rule: f.rule,
        })
        .collect())
}
