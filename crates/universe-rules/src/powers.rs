//! Possession effects retain their rule and complete positive evidence chain.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    frame::FrameTime,
    ids::*,
    records::*,
    scope::*,
    value::{RecordRef, Value},
};
/// A derived grant with its complete canonical evidence chain. Never persisted
/// as an independent assertion and never detached from the owning entity.
#[derive(Debug, Clone)]
pub struct PowerFact {
    pub subject: RecordRef,
    pub predicate: RecordRef,
    pub value: Value,
    pub evidence: Vec<RecordVersionId>,
    pub rule: RecordId,
}
pub fn derive(
    records: &[RecordVersion],
    subjects: &[RecordId],
    predicates: &[RecordId],
    context: &RecordRef,
    time: &FrameTime,
    world: Option<&WorldId>,
) -> Result<Vec<PowerFact>, String> {
    if matches!(time, FrameTime::Timeless) {
        return Ok(vec![]);
    }
    let mut remaining = 1_000_000usize;
    let mut charge = |cost: usize| -> Result<(), String> {
        remaining = remaining.checked_sub(cost).ok_or_else(|| {
            "Possession-effect work budget exhausted; narrow the requested state.".to_string()
        })?;
        Ok(())
    };
    charge(records.len())?;
    let mut propositions = BTreeMap::<(&RecordId, &RecordId), Vec<&RecordVersion>>::new();
    let mut equivalent = BTreeMap::<&str, Vec<&RecordId>>::new();
    let mut assertions = BTreeMap::<&RecordId, Vec<&RecordVersion>>::new();
    for r in records {
        match &r.payload {
            Payload::Proposition(p) => {
                propositions
                    .entry((&p.subject.record, &p.predicate.record))
                    .or_default()
                    .push(r);
                equivalent
                    .entry(r.payload_digest.as_str())
                    .or_default()
                    .push(&r.identity.record_id);
            }
            Payload::Assertion(a) => assertions.entry(&a.proposition.record).or_default().push(r),
            _ => {}
        }
    }
    // Event-boundary evaluation only needs the named event, resolved once.
    let event_records: Vec<_> = if let FrameTime::AtEvent { event, .. } = time {
        records
            .iter()
            .filter(|r| r.identity.record_id == event.record)
            .cloned()
            .collect()
    } else {
        vec![]
    };
    let active = |validity: &Validity| crate::events::applies(validity, time, &event_records);
    let mut out = Vec::new();
    let mut recipients = BTreeMap::<RecordId, BTreeSet<RecordRef>>::new();
    let mut uncertain = BTreeSet::new();
    for rule in records {
        charge(1)?;
        let Payload::ItemPower(power) = &rule.payload else {
            continue;
        };
        if power.scope.realm.is_some()
            || &power.scope.context != context
            || (!predicates.is_empty() && !predicates.contains(&power.power_predicate.record))
        {
            continue;
        }
        let applies = match &power.scope.applicability {
            Applicability::UniverseWide => true,
            Applicability::Worlds { world_ids } => world.is_some_and(|w| world_ids.contains(w)),
            _ => false,
        };
        if !applies || active(&power.validity) != Some(true) {
            continue;
        }
        let mut seen = BTreeSet::new();
        for prop in propositions
            .get(&(&power.item.record, &power.holder_predicate.record))
            .into_iter()
            .flatten()
        {
            charge(1)?;
            let Payload::Proposition(p) = &prop.payload else {
                continue;
            };
            if p.subject != power.item
                || p.predicate != power.holder_predicate
                || &p.context != context
                || !seen.insert(&prop.payload_digest)
            {
                continue;
            }
            let Some(Value::EntityRef { record: holder }) = &p.value else {
                continue;
            };
            let mut chain = Vec::new();
            let mut refuted = false;
            for id in equivalent
                .get(prop.payload_digest.as_str())
                .into_iter()
                .flatten()
            {
                for r in assertions.get(id).into_iter().flatten() {
                    charge(1)?;
                    let Payload::Assertion(a) = &r.payload else {
                        continue;
                    };
                    let scoped = a.scope.context == *context
                        && a.scope.realm.is_none()
                        && match &a.scope.applicability {
                            Applicability::UniverseWide => true,
                            Applicability::Worlds { world_ids } => {
                                world.is_some_and(|w| world_ids.contains(w))
                            }
                            _ => false,
                        };
                    if !scoped {
                        continue;
                    }
                    let applies = active(&a.validity);
                    if a.polarity == Polarity::Support
                        && applies != Some(false)
                        && (a.precision != Precision::Exact
                            || !a.alternatives.is_empty()
                            || applies.is_none())
                    {
                        uncertain.insert(rule.identity.record_id.clone());
                    }
                    if a.polarity == Polarity::Refutation && applies != Some(false) {
                        refuted = true;
                    }
                    if a.polarity == Polarity::Support
                        && a.precision == Precision::Exact
                        && a.alternatives.is_empty()
                        && applies == Some(true)
                    {
                        chain.push(r.record_version_id.clone());
                    }
                }
            }
            if refuted || chain.is_empty() {
                continue;
            }
            recipients
                .entry(rule.identity.record_id.clone())
                .or_default()
                .insert(holder.clone());
            if !subjects.contains(&holder.record) {
                continue;
            }
            // An explicit suspension on the recipient overrides an indirect
            // grant. Unknown suspension timing cannot authorize use. Absence
            // alone never means muted, and muting another owner has no effect.
            let mut muted = false;
            for prop in propositions
                .get(&(&holder.record, &power.power_predicate.record))
                .into_iter()
                .flatten()
            {
                charge(1)?;
                let Payload::Proposition(p) = &prop.payload else {
                    continue;
                };
                if p.subject != *holder || p.context != *context {
                    continue;
                }
                for assertion in assertions
                    .get(&prop.identity.record_id)
                    .into_iter()
                    .flatten()
                {
                    charge(1)?;
                    let Payload::Assertion(a) = &assertion.payload else {
                        continue;
                    };
                    let scoped = a.scope.context == *context
                        && a.scope.realm.is_none()
                        && match &a.scope.applicability {
                            Applicability::UniverseWide => true,
                            Applicability::Worlds { world_ids } => {
                                world.is_some_and(|w| world_ids.contains(w))
                            }
                            _ => false,
                        };
                    let denies = a.polarity == Polarity::Refutation
                        && p.value.as_ref() == Some(&power.value)
                        || a.polarity == Polarity::Support
                            && matches!(
                                (&power.value, &p.value),
                                (
                                    Value::Boolean { value: true },
                                    Some(Value::Boolean { value: false })
                                )
                            );
                    if scoped && denies && active(&a.validity) != Some(false) {
                        muted = true;
                    }
                }
            }
            if muted {
                continue;
            }
            chain.push(prop.record_version_id.clone());
            chain.push(rule.record_version_id.clone());
            chain.sort();
            chain.dedup();
            if !out
                .iter()
                .any(|f: &PowerFact| f.subject == *holder && f.rule == rule.identity.record_id)
            {
                out.push(PowerFact {
                    subject: holder.clone(),
                    predicate: power.power_predicate.clone(),
                    value: power.value.clone(),
                    evidence: chain,
                    rule: rule.identity.record_id.clone(),
                });
            }
        }
    }
    // A single-valued custody property cannot confer the same item's power on
    // two competing holders. Retain unknown/conflicting custody as unresolved.
    out.retain(|f| {
        !uncertain.contains(&f.rule)
            && recipients
                .get(&f.rule)
                .is_some_and(|holders| holders.len() == 1)
    });
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value as Json};
    fn id(n: usize) -> String {
        format!("rec_{n:024x}")
    }
    fn rr(n: usize) -> Json {
        json!({"universe":"unv_000000000000000000000001","record":id(n)})
    }
    fn scope() -> Json {
        json!({"context":rr(10),"applicability":{"kind":"universe_wide"}})
    }
    fn interval(start: i32, end: Option<i32>) -> Json {
        json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000009","start":{"kind":"exact","value":start.to_string()},"end":end.map_or(json!({"kind":"unbounded"}),|v| json!({"kind":"exact","value":v.to_string()}))})
    }
    fn record(n: usize, payload: Json) -> RecordVersion {
        let payload: Payload = serde_json::from_value(payload).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(
                UniverseId::parse("unv_000000000000000000000001").unwrap(),
                RecordId::parse(&id(n)).unwrap(),
                payload.kind(),
            ),
            payload,
        )
        .unwrap()
    }
    fn assertion(n: usize, proposition: usize, polarity: &str, validity: Json) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(proposition),"polarity":polarity,"scope":scope(),"validity":validity,"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Power regression"}}),
        )
    }
    fn custody(n: usize, owner: usize) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"proposition","subject":rr(3),"predicate":rr(4),"value":{"kind":"entity_ref","ref":rr(owner)},"context":rr(10),"quantification":"particular"}),
        )
    }
    fn fixture() -> Vec<RecordVersion> {
        vec![
            record(
                5,
                json!({"record_kind":"property","namespace":"phase","key":"wall_phase","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
            ),
            record(
                6,
                json!({"record_kind":"item_power","item":rr(3),"holderPredicate":rr(4),"powerPredicate":rr(5),"value":{"kind":"boolean","value":true},"scope":scope(),"validity":interval(10,None)}),
            ),
            custody(7, 1),
            assertion(8, 7, "support", interval(10, None)),
        ]
    }
    fn facts(
        records: &[RecordVersion],
        owner: usize,
        day: i32,
        world: Option<&WorldId>,
    ) -> Vec<PowerFact> {
        derive(records, &[RecordId::parse(&id(owner)).unwrap()], &[], &serde_json::from_value(rr(10)).unwrap(), &FrameTime::At { time: serde_json::from_value(json!({"kind":"exact","calendar":"cal_000000000000000000000009","value":day.to_string()})).unwrap() }, world).unwrap()
    }
    #[test]
    fn only_actual_recipient_and_complete_evidence_chain() {
        let rows = fixture();
        let found = facts(&rows, 1, 11, None);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].evidence.len(), 3);
        assert!(facts(&rows, 2, 11, None).is_empty());
        assert!(facts(&rows, 3, 11, None).is_empty()); // item does not gain holder's grant
    }
    #[test]
    fn conflicts_and_unknown_custody_block_even_when_other_holder_not_requested() {
        let mut rows = fixture();
        rows.push(custody(11, 2));
        rows.push(assertion(12, 11, "support", interval(10, None)));
        assert!(facts(&rows, 1, 11, None).is_empty());
        assert!(facts(&rows, 2, 11, None).is_empty());
        rows.pop();
        rows.push(assertion(12, 11, "support", json!({"kind":"unknown"})));
        assert!(facts(&rows, 1, 11, None).is_empty());
    }
    #[test]
    fn explicit_transfer_and_expiry_do_not_leak_prior_owner_attributes() {
        let mut rows = fixture();
        rows[3] = assertion(8, 7, "support", interval(10, Some(12)));
        rows.push(custody(11, 2));
        rows.push(assertion(12, 11, "support", interval(12, Some(15))));
        assert_eq!(facts(&rows, 1, 11, None).len(), 1);
        assert!(facts(&rows, 1, 12, None).is_empty());
        assert_eq!(facts(&rows, 2, 12, None).len(), 1);
        assert!(facts(&rows, 2, 15, None).is_empty());
    }
    #[test]
    fn explicit_owner_muting_restoration_and_other_owner_isolation() {
        let mut rows = fixture();
        rows.push(record(11,json!({"record_kind":"proposition","subject":rr(1),"predicate":rr(5),"value":{"kind":"boolean","value":true},"context":rr(10),"quantification":"particular"})));
        rows.push(assertion(12, 11, "refutation", interval(12, Some(14))));
        assert_eq!(facts(&rows, 1, 11, None).len(), 1);
        assert!(facts(&rows, 1, 12, None).is_empty());
        assert_eq!(facts(&rows, 1, 14, None).len(), 1);
        if let Payload::Proposition(p) = &mut rows[4].payload {
            p.subject = serde_json::from_value(rr(2)).unwrap();
        }
        assert_eq!(facts(&rows, 1, 12, None).len(), 1);
    }
    #[test]
    fn world_scoped_grant_never_widens_and_accepts_universe_wide_custody() {
        let mut rows = fixture();
        let world = WorldId::parse("wld_000000000000000000000020").unwrap();
        if let Payload::ItemPower(p) = &mut rows[1].payload {
            p.scope.applicability = Applicability::Worlds {
                world_ids: vec![world.clone()],
            };
        }
        assert!(facts(&rows, 1, 11, None).is_empty());
        assert_eq!(facts(&rows, 1, 11, Some(&world)).len(), 1);
        let other = WorldId::parse("wld_000000000000000000000021").unwrap();
        assert!(facts(&rows, 1, 11, Some(&other)).is_empty());
    }
}
