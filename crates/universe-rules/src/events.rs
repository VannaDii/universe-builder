//! Deterministic event expansion and event-boundary queries. No wall clock.
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    frame::{EventTimeSide, FrameTime},
    ids::*,
    records::*,
    scope::*,
    temporal::*,
    value::RecordRef,
};
pub const EXPANSION: &str = "events-v1";
pub fn exact(time: &TemporalExpression) -> Result<(&CalendarId, i128), String> {
    if let TemporalExpression::Exact { calendar, value } = time {
        let n = value
            .parse::<i128>()
            .map_err(|_| "Event time needs an exact integer coordinate")?;
        if n == i128::MIN || n == i128::MAX {
            return Err("Event coordinate outside supported bounds".into());
        }
        Ok((calendar, n))
    } else {
        Err("Event effects require an exact named-calendar time".into())
    }
}
pub fn effect_id(event: &RecordId, slot: &str) -> RecordId {
    let hash = Sha256::digest(format!("{EXPANSION}:{event}:{slot}").as_bytes());
    RecordId::parse(&format!("rec_{}", hex::encode(hash)[..24].to_owned()))
        .expect("digest identity")
}
pub fn applies(validity: &Validity, time: &FrameTime, records: &[RecordVersion]) -> Option<bool> {
    let FrameTime::AtEvent { event, side } = time else {
        return crate::time::applies(validity, time);
    };
    let e = records.iter().find(|r| {
        r.identity.record_id == event.record
            && event.universe.as_ref() == Some(&r.identity.universe_id)
    })?;
    let Payload::Event(e) = &e.payload else {
        return None;
    };
    if e.occurrence != OccurrenceMode::Occurred {
        return None;
    }
    let (calendar, t) = exact(&e.time).ok()?;
    if *side == EventTimeSide::After {
        return crate::time::applies(
            validity,
            &FrameTime::At {
                time: e.time.clone(),
            },
        );
    }
    match validity {
        Validity::CalendarInterval {
            calendar: c,
            start,
            end,
        } if c == calendar => {
            let start = match start {
                TemporalBound::Unbounded => true,
                TemporalBound::Exact { value } => value.parse::<i128>().ok()? < t,
                _ => return None,
            };
            let end = match end {
                TemporalBound::Unbounded => true,
                TemporalBound::Exact { value } => t <= value.parse::<i128>().ok()?,
                _ => return None,
            };
            Some(start && end)
        }
        Validity::Instant { at } => {
            let (c, _) = exact(at).ok()?;
            if c != calendar {
                None
            } else {
                Some(false)
            }
        }
        _ => None,
    }
}
/// Expand all occurred events, including automatic ends of superseded generated
/// values. Non-event evidence is never silently edited or overridden.
pub fn expand(records: &[RecordVersion]) -> Result<BTreeMap<RecordId, Assertion>, String> {
    let map: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let mut events = Vec::new();
    let mut preconditions = 0usize;
    let mut effect_count = 0usize;
    let mut remaining = 1_000_000usize;
    for r in records {
        if let Payload::Event(e) = &r.payload {
            preconditions += e.preconditions.len();
            effect_count += e.effects.len();
            if preconditions > 1000
                || effect_count > 10_000
                || e.effects.len() > 100
                || e.preconditions.len() > 100
            {
                return Err("Event work budget exceeded".into());
            }
            if e.occurrence != OccurrenceMode::Occurred {
                continue;
            }
            let (c, t) = exact(&e.time)?;
            if e.expansion_version.as_deref() != Some(EXPANSION) {
                return Err("Event expansion version is missing or unsupported".into());
            }
            events.push((c.clone(), t, r, e));
        }
    }
    if events.len() > 1000 {
        return Err("Event work budget exceeded".into());
    }
    events.sort_by(|a, b| {
        (&a.0, a.1, &a.2.identity.record_id).cmp(&(&b.0, b.1, &b.2.identity.record_id))
    });
    let mut out: BTreeMap<RecordId, Assertion> = BTreeMap::new();
    let mut groups: BTreeMap<String, Vec<(i128, RecordId, RecordId, Polarity)>> = BTreeMap::new();
    for (calendar, t, r, e) in events {
        let mut slots = BTreeSet::new();
        let mut orders = BTreeSet::new();
        let mut effects: Vec<_> = e.effects.iter().collect();
        effects.sort_by_key(|x| x.order);
        for effect in effects {
            if effect.slot.trim().is_empty()
                || effect.slot.len() > 120
                || !slots.insert(&effect.slot)
                || !orders.insert(effect.order)
            {
                return Err("Event slots and effect orders must be explicit and unique".into());
            }
            let Some(prop) = map.get(&effect.proposition.record) else {
                return Err("Event proposition unavailable".into());
            };
            let Payload::Proposition(p) = &prop.payload else {
                return Err("Event effect target must be a proposition".into());
            };
            if effect.scope.context != p.context {
                return Err("Event effect context differs from proposition".into());
            }
            if !matches!(
                effect.scope.applicability,
                Applicability::UniverseWide | Applicability::Worlds { .. }
            ) {
                return Err("Event effect scope must be explicit".into());
            }
            let Validity::CalendarInterval {
                calendar: c,
                start: TemporalBound::Exact { value },
                end,
            } = &effect.validity
            else {
                return Err("Effects require a half-open named-calendar interval".into());
            };
            if c != &calendar || value.parse::<i128>().ok() != Some(t) {
                return Err("Effect must start at its event's exact time and calendar".into());
            }
            match end {
                TemporalBound::Unbounded => {}
                TemporalBound::Exact { value }
                    if value.parse::<i128>().ok().is_some_and(|n| n > t) => {}
                _ => {
                    return Err(
                        "Effect end must be exact and later, or explicitly unbounded".into(),
                    )
                }
            }
            let single=map.get(&p.predicate.record).is_some_and(|d|matches!(&d.payload,Payload::Property(d) if d.multiplicity==Multiplicity::Single));
            let key = serde_json::to_string(&(&calendar, &p.subject, &p.predicate, &effect.scope))
                .map_err(|e| e.to_string())?;
            let id = effect_id(&r.identity.record_id, &effect.slot);
            let previous = groups.entry(key).or_default();
            for (old_time, old_id, old_prop, polarity) in previous.iter() {
                remaining = remaining
                    .checked_sub(1)
                    .ok_or("Event expansion work budget exhausted")?;
                if map
                    .get(old_prop)
                    .is_some_and(|old| matches!(&old.payload,Payload::Proposition(old) if old==p))
                    || (single
                        && *polarity == Polarity::Support
                        && effect.polarity == Polarity::Support)
                {
                    if *old_time == t
                        && out
                            .get(old_id)
                            .and_then(|a| a.established_by.as_ref())
                            .is_none_or(|source| source.event.record != r.identity.record_id)
                    {
                        return Err("Noncommuting effects at the same time need distinct authored times; no record-ID ordering is inferred".into());
                    }
                    if let Some(a) = out.get_mut(old_id) {
                        if let Validity::CalendarInterval { end, .. } = &mut a.validity {
                            if matches!(end, TemporalBound::Unbounded)
                                || matches!(end,TemporalBound::Exact{value} if value.parse::<i128>().ok().is_some_and(|n|n>t))
                            {
                                *end = TemporalBound::Exact {
                                    value: t.to_string(),
                                };
                            }
                        }
                    }
                }
            }
            previous.push((
                t,
                id.clone(),
                effect.proposition.record.clone(),
                effect.polarity,
            ));
            out.insert(
                id,
                Assertion {
                    attribute_mode: universe_domain::records::AttributeMode::Instance,
                    proposition: effect.proposition.clone(),
                    polarity: effect.polarity,
                    scope: effect.scope.clone(),
                    validity: effect.validity.clone(),
                    persistence: PersistenceSemantics::ExplicitInterval,
                    precision: Precision::Exact,
                    alternatives: vec![],
                    basis: EvidenceBasis::AuthorDecision {
                        note: format!(
                            "Compiled event {} slot {}",
                            r.identity.record_id, effect.slot
                        ),
                    },
                    established_by: Some(EventEffectRef {
                        event: RecordRef::new(
                            r.identity.universe_id.clone(),
                            r.identity.record_id.clone(),
                        ),
                        slot: effect.slot.clone(),
                    }),
                },
            );
        }
    }
    Ok(out)
}
pub fn verify(records: &[RecordVersion]) -> Result<(), String> {
    let mut expected = expand(records)?;
    for r in records {
        if let Payload::Assertion(a) = &r.payload {
            if a.established_by.is_some()
                && expected.remove(&r.identity.record_id).as_ref() != Some(a)
            {
                return Err("Generated effect assertion does not match its event".into());
            }
        }
    }
    if !expected.is_empty() {
        return Err("Event is missing a compiled effect assertion".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn fixture() -> Vec<RecordVersion> {
        let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
        let id = |n| RecordId::parse(&format!("rec_{n:024x}")).unwrap();
        let rr = |n| RecordRef::new(u.clone(), id(n));
        let build = |n, payload: Payload| {
            RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                RecordIdentity::new(u.clone(), id(n), payload.kind()),
                payload,
            )
            .unwrap()
        };
        let proposition = Payload::Proposition(Proposition {
            subject: rr(1),
            predicate: rr(2),
            roles: vec![],
            value: Some(universe_domain::Value::Boolean { value: true }),
            quantification: Quantification::Particular,
            context: rr(3),
        });
        let event = |n, time, polarity| {
            build(n,Payload::Event(serde_json::from_value(json!({"occurrence":"occurred","time":{"kind":"exact","calendar":"cal_000000000000000000000001","value":format!("{time}")},"participants":[],"labels":{},"expansionVersion":EXPANSION,"effects":[{"slot":"active","proposition":rr(4),"polarity":polarity,"scope":{"applicability":{"kind":"universe_wide"},"context":rr(3)},"validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"exact","value":format!("{time}")},"end":{"kind":"unbounded"}},"order":0}]})).unwrap()))
        };
        vec![
            build(4, proposition),
            event(5, 10, "support"),
            event(6, 20, "refutation"),
        ]
    }
    #[test]
    fn order_independent_recompilation_and_forged_effect_rejection() {
        let records = fixture();
        let expected = expand(&records).unwrap();
        for permutation in [
            [0, 1, 2],
            [0, 2, 1],
            [1, 0, 2],
            [1, 2, 0],
            [2, 0, 1],
            [2, 1, 0],
        ] {
            let shuffled: Vec<_> = permutation
                .into_iter()
                .map(|i| records[i].clone())
                .collect();
            assert_eq!(expand(&shuffled).unwrap(), expected);
        }
        let mut complete = records.clone();
        for (index, (id, assertion)) in expected.iter().enumerate() {
            complete.push(
                RecordVersion::build(
                    RecordVersionId::parse(&format!("ver_{:024x}", 20 + index)).unwrap(),
                    RecordIdentity::new(
                        records[0].identity.universe_id.clone(),
                        id.clone(),
                        RecordKind::Assertion,
                    ),
                    Payload::Assertion(assertion.clone()),
                )
                .unwrap(),
            );
        }
        assert!(verify(&complete).is_ok());
        if let Payload::Assertion(a) = &mut complete.last_mut().unwrap().payload {
            a.polarity = if a.polarity == Polarity::Support {
                Polarity::Refutation
            } else {
                Polarity::Support
            };
        }
        assert!(verify(&complete).is_err());
        assert!(verify(&records).is_err());
    }
    #[test]
    fn atomic_event_uses_explicit_effect_order_without_exposing_intermediate_state() {
        let mut records = fixture();
        records.pop();
        let event_id = records[1].identity.record_id.clone();
        let Payload::Event(e) = &mut records[1].payload else {
            panic!()
        };
        let mut last = e.effects[0].clone();
        last.slot = "final".into();
        last.order = 9;
        last.polarity = Polarity::Refutation;
        e.effects.push(last);
        // Array position is not an ordering authority.
        e.effects.reverse();
        let result = expand(&records).unwrap();
        let at = FrameTime::At {
            time: e_time(&records[1]),
        };
        assert_eq!(
            applies(
                &result[&effect_id(&event_id, "active")].validity,
                &at,
                &records
            ),
            Some(false)
        );
        assert_eq!(
            applies(
                &result[&effect_id(&event_id, "final")].validity,
                &at,
                &records
            ),
            Some(true)
        );
        records.reverse();
        assert_eq!(expand(&records).unwrap(), result);
    }
    fn e_time(record: &RecordVersion) -> TemporalExpression {
        let Payload::Event(e) = &record.payload else {
            panic!()
        };
        e.time.clone()
    }
    #[test]
    fn same_time_noncommuting_events_fail_and_predicted_events_have_no_effect() {
        let mut records = fixture();
        if let Payload::Event(e) = &mut records[2].payload {
            e.time = TemporalExpression::Exact {
                calendar: CalendarId::parse("cal_000000000000000000000001").unwrap(),
                value: "10".into(),
            };
            if let Validity::CalendarInterval { start, .. } = &mut e.effects[0].validity {
                *start = TemporalBound::Exact { value: "10".into() };
            }
        }
        assert!(expand(&records).unwrap_err().contains("Noncommuting"));
        if let Payload::Event(e) = &mut records[2].payload {
            e.occurrence = OccurrenceMode::Predicted;
        }
        assert_eq!(expand(&records).unwrap().len(), 1);
    }
}
