//! Mandatory owner-bound action attributes; labels and optional prerequisites
//! cannot change an action definition's requirements. Historical actionless
//! events remain readable, but every new or revised event must name an action.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    expr::{Expr, Operand},
    frame::{EventTimeSide, FrameTime},
    ids::*,
    records::*,
    scope::*,
    value::RecordRef,
    Frame,
};
use universe_protocol::ProtocolError;

fn invalid(field: &str, message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument(field, message).into()
}

pub fn validate(
    records: &[RecordVersion],
    changed: &BTreeSet<RecordId>,
    frame: &Frame,
) -> anyhow::Result<()> {
    let by_id: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let index = universe_rules::EvaluationIndex::new(records);
    let mut remaining = 1_000_000usize;
    let mut charge = |cost: usize| -> anyhow::Result<()> {
        remaining =
            remaining
                .checked_sub(cost)
                .ok_or_else(|| ProtocolError::EvaluationLimitReached {
                    message: "Action attribute evaluation exceeded its work budget".into(),
                })?;
        Ok(())
    };
    charge(records.len())?;
    for record in records {
        charge(1)?;
        let Payload::Event(event) = &record.payload else {
            continue;
        };
        let Some(action_ref) = &event.action else {
            if changed.contains(&record.identity.record_id) {
                return Err(invalid(
                    "event.action",
                    "new or revised events must name a declared action",
                ));
            }
            continue;
        };
        let Some(Payload::ActionDefinition(action)) = by_id
            .get(&action_ref.record)
            .filter(|r| action_ref.universe.as_ref() == Some(&r.identity.universe_id))
            .map(|r| &r.payload)
        else {
            return Err(invalid(
                "event.action",
                "action must reference a declared action definition",
            ));
        };
        let mut event_frame = frame.clone();
        event_frame.time = FrameTime::AtEvent {
            event: RecordRef::new(frame.universe.clone(), record.identity.record_id.clone()),
            side: EventTimeSide::Before,
        };
        event_frame.context = event
            .effects
            .first()
            .map_or_else(|| action.scope.context.clone(), |e| e.scope.context.clone());
        if event_frame.context != action.scope.context
            || !matches!(&action.scope.applicability, Applicability::UniverseWide)
                && !matches!(&action.scope.applicability, Applicability::Worlds { world_ids } if !event.worlds.is_empty() && event.worlds.iter().all(|w| world_ids.contains(w)))
        {
            return Err(invalid(
                "event.action",
                "event must stay within its action's declared context/world scope",
            ));
        }
        for requirement in &action.requirements {
            let participants: Vec<_> = event
                .participants
                .iter()
                .filter(|p| p.role == requirement.role)
                .collect();
            charge(event.participants.len())?;
            if participants.len() != 1
                || !by_id
                    .get(&participants[0].record.record)
                    .is_some_and(|r| matches!(r.payload, Payload::Entity(_)))
            {
                return Err(invalid(
                    "event.action.requirements",
                    "each required role must identify exactly one owning entity",
                ));
            }
        }
        if event.occurrence != OccurrenceMode::Occurred {
            continue;
        }
        if !matches!(action.validity, Validity::Unspecified)
            && universe_rules::events::applies(&action.validity, &event_frame.time, records)
                != Some(true)
        {
            return Err(invalid(
                "event.action",
                "action is not explicitly active before this event",
            ));
        }
        let worlds: Vec<Vec<RecordId>> = if event.worlds.is_empty() {
            vec![vec![]]
        } else {
            event
                .worlds
                .iter()
                .map(|w| RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)).map(|r| vec![r]))
                .collect::<Result<_, _>>()?
        };
        for requirement in &action.requirements {
            let owner = &event
                .participants
                .iter()
                .find(|p| p.role == requirement.role)
                .unwrap()
                .record;
            let Some(Payload::Property(property)) =
                by_id.get(&requirement.predicate.record).map(|r| &r.payload)
            else {
                return Err(invalid(
                    "event.action.requirements",
                    "required attribute property is unavailable",
                ));
            };
            let expression = Expr::Claim {
                subject: Operand::Record {
                    record: owner.clone(),
                },
                predicate: format!("{}:{}", property.namespace, property.key),
                roles: vec![],
                value: Some(Operand::Value {
                    value: requirement.value.clone(),
                }),
                polarity: Polarity::Support,
                context: None,
            };
            for world in &worlds {
                charge(if index.has_powers() {
                    records.len()
                } else {
                    index
                        .claim(
                            owner,
                            &format!("{}:{}", property.namespace, property.key),
                            &event_frame.context,
                        )
                        .len()
                })?;
                let (evidence, complete) = universe_rules::basic::evaluate(
                    &expression,
                    &universe_rules::EvaluationContext {
                        frame: Some(&event_frame),
                        base_snapshot: records,
                        candidate_changes: vec![],
                        index: Some(&index),
                        world_scope: Some(world.clone()),
                    },
                );
                if !complete || evidence.outcome() != universe_rules::EvidenceOutcome::Supported {
                    return Err(invalid("event.action.requirements", "owning entity's required attribute is missing, muted, conflicting, expired or unsupported before the event"));
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    fn id(n: usize) -> String {
        format!("rec_{n:024x}")
    }
    fn rr(n: usize) -> Value {
        json!({"universe":"unv_000000000000000000000001","record":id(n)})
    }
    fn record(n: usize, payload: Value) -> RecordVersion {
        let p: Payload = serde_json::from_value(payload).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(
                UniverseId::parse("unv_000000000000000000000001").unwrap(),
                RecordId::parse(&id(n)).unwrap(),
                p.kind(),
            ),
            p,
        )
        .unwrap()
    }
    fn fixture() -> (Vec<RecordVersion>, Frame) {
        let scope = json!({"context":rr(10),"applicability":{"kind":"universe_wide"}});
        let rows = vec![
            record(
                1,
                json!({"record_kind":"entity","names":[],"types":[],"worldAssociations":[],"labels":{},"metadata":{}}),
            ),
            record(
                2,
                json!({"record_kind":"property","namespace":"test","key":"charged","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
            ),
            record(
                3,
                json!({"record_kind":"proposition","subject":rr(1),"predicate":rr(2),"value":{"kind":"boolean","value":true},"context":rr(10),"quantification":"particular"}),
            ),
            record(
                4,
                json!({"record_kind":"assertion","proposition":rr(3),"polarity":"support","scope":scope,"validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000009","start":{"kind":"exact","value":"10"},"end":{"kind":"unbounded"}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Explicit attribute"}}),
            ),
            record(
                5,
                json!({"record_kind":"action_definition","namespace":"test","key":"charged_action","labels":{},"requirements":[{"role":"actor","predicate":rr(2),"value":{"kind":"boolean","value":true}}],"scope":scope,"validity":{"kind":"unspecified"}}),
            ),
            record(
                6,
                json!({"record_kind":"event","occurrence":"occurred","action":rr(5),"time":{"kind":"exact","calendar":"cal_000000000000000000000009","value":"11"},"participants":[{"record":rr(1),"role":"actor"}],"labels":{},"effects":[],"preconditions":[]}),
            ),
        ];
        let frame=serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(10),"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
        (rows, frame)
    }
    fn changed() -> BTreeSet<RecordId> {
        BTreeSet::from([RecordId::parse(&id(6)).unwrap()])
    }
    #[test]
    fn historical_actionless_events_decode_unchanged_but_cannot_be_created_or_revised() {
        let (mut rows, frame) = fixture();
        if let Payload::Event(e) = &mut rows[5].payload {
            e.action = None;
        }
        let encoded = serde_json::to_value(&rows[5].payload).unwrap();
        assert!(encoded.get("action").is_none());
        assert!(validate(&rows, &BTreeSet::new(), &frame).is_ok());
        assert!(validate(&rows, &changed(), &frame)
            .unwrap_err()
            .to_string()
            .contains("event.action"));
    }
    #[test]
    fn missing_ambiguous_and_nonentity_owners_cannot_satisfy_requirements() {
        for variant in 0..3 {
            let (mut rows, frame) = fixture();
            if let Payload::Event(e) = &mut rows[5].payload {
                match variant {
                    0 => e.participants.clear(),
                    1 => e.participants.push(e.participants[0].clone()),
                    _ => e.participants[0].record = serde_json::from_value(rr(2)).unwrap(),
                }
            }
            assert!(validate(&rows, &changed(), &frame)
                .unwrap_err()
                .to_string()
                .contains("event.action.requirements"));
        }
    }
    #[test]
    fn unknown_attributes_and_invalid_action_references_do_not_authorize_use() {
        let (rows, frame) = fixture();
        assert!(validate(&rows, &changed(), &frame).is_ok());
        let mut unknown = rows.clone();
        if let Payload::Assertion(a) = &mut unknown[3].payload {
            a.validity = Validity::Unknown;
        }
        assert!(validate(&unknown, &changed(), &frame).is_err());
        let mut alternatives = rows.clone();
        if let Payload::Assertion(a) = &mut alternatives[3].payload {
            a.alternatives = vec![universe_domain::value::Value::bool_(false)];
        }
        assert!(validate(&alternatives, &changed(), &frame).is_err());
        let mut undeclared = rows.clone();
        undeclared.remove(3); // proposition alone is not a fact
        assert!(validate(&undeclared, &changed(), &frame).is_err());
        let mut wrong = rows;
        if let Payload::Event(e) = &mut wrong[5].payload {
            e.action = Some(serde_json::from_value(rr(1)).unwrap());
        }
        assert!(validate(&wrong, &changed(), &frame)
            .unwrap_err()
            .to_string()
            .contains("event.action"));
    }
    #[test]
    fn action_context_world_and_validity_never_widen() {
        for variant in 0..3 {
            let (mut rows, frame) = fixture();
            if let Payload::ActionDefinition(a) = &mut rows[4].payload {
                match variant {
                    0 => {
                        a.scope.applicability = Applicability::Worlds {
                            world_ids: vec![WorldId::parse("wld_000000000000000000000020").unwrap()],
                        }
                    }
                    1 => a.validity = Validity::Unknown,
                    _ => {}
                }
            }
            if variant == 2 {
                if let Payload::Assertion(a) = &mut rows[3].payload {
                    a.scope.context = serde_json::from_value(rr(11)).unwrap();
                }
            }
            assert!(validate(&rows, &changed(), &frame).is_err());
        }
    }
    #[test]
    fn an_event_cannot_self_grant_its_pre_event_attribute() {
        let (mut rows, frame) = fixture();
        if let Payload::Assertion(a) = &mut rows[3].payload {
            if let Validity::CalendarInterval { start, .. } = &mut a.validity {
                *start = universe_domain::temporal::TemporalBound::Exact { value: "11".into() };
            }
        }
        assert!(validate(&rows, &changed(), &frame).is_err());
    }
    #[test]
    fn g02_capability_uses_exact_pre_event_interval_boundaries() {
        let (mut rows, frame) = fixture();
        if let Payload::Assertion(a) = &mut rows[3].payload {
            if let Validity::CalendarInterval { end, .. } = &mut a.validity {
                *end = universe_domain::temporal::TemporalBound::Exact { value: "20".into() };
            }
        }
        // Immediately before the ending boundary the capability still holds;
        // immediately before its starting boundary it has not yet begun.
        for (tick, allowed) in [(10, false), (11, true), (20, true), (21, false)] {
            if let Payload::Event(e) = &mut rows[5].payload {
                e.time = serde_json::from_value(json!({"kind":"exact","calendar":"cal_000000000000000000000009","value":tick.to_string()})).unwrap();
            }
            assert_eq!(
                validate(&rows, &changed(), &frame).is_ok(),
                allowed,
                "{tick}"
            );
        }
    }
    #[test]
    fn g02_earlier_incapacity_revalidates_unchanged_dependent_action() {
        let (mut rows, frame) = fixture();
        assert!(validate(&rows, &BTreeSet::new(), &frame).is_ok());
        if let Payload::Assertion(a) = &mut rows[3].payload {
            if let Validity::CalendarInterval { end, .. } = &mut a.validity {
                *end = universe_domain::temporal::TemporalBound::Exact { value: "10".into() };
            }
        }
        // Only evidence changes; the existing event must still be checked.
        let changed_evidence = BTreeSet::from([RecordId::parse(&id(4)).unwrap()]);
        assert!(validate(&rows, &changed_evidence, &frame)
            .unwrap_err()
            .to_string()
            .contains("event.action.requirements"));
    }
    #[test]
    fn g02_patient_incapacity_does_not_apply_to_the_capable_actor() {
        let (mut rows, frame) = fixture();
        rows.push(record(7, json!({"record_kind":"entity","names":[],"types":[],"worldAssociations":[],"labels":{},"metadata":{}})));
        if let Payload::Event(e) = &mut rows[5].payload {
            e.participants
                .push(serde_json::from_value(json!({"record":rr(7),"role":"patient"})).unwrap());
        }
        assert!(validate(&rows, &changed(), &frame).is_ok());
        // Swapping the patient into the required actor role cannot borrow the
        // original actor's capability, even though that entity is present.
        if let Payload::Event(e) = &mut rows[5].payload {
            e.participants[0].role = "patient".into();
            e.participants[1].role = "actor".into();
        }
        assert!(validate(&rows, &changed(), &frame).is_err());
    }
}
