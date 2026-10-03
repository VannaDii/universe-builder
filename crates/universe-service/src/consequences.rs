//! Match authored effects; never synthesize a missing obligation or post-value.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    consequences::*,
    expr::{Expr, Operand},
    frame::{EventTimeSide, FrameTime},
    ids::*,
    records::*,
    scope::*,
    temporal::{TemporalBound, TemporalExpression},
    value::{RecordRef, Value},
    Frame,
};
use universe_protocol::ProtocolError;

fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("event.action.effects", message).into()
}
fn owner<'a>(
    event: &'a Event,
    role: &str,
    records: &BTreeMap<&RecordId, &RecordVersion>,
) -> anyhow::Result<&'a RecordRef> {
    let mut matches = event.participants.iter().filter(|p| p.role == role);
    let p = matches
        .next()
        .ok_or_else(|| invalid("effect role has no owner"))?;
    if matches.next().is_some()
        || !records.get(&p.record.record).is_some_and(|r| {
            p.record.universe.as_ref() == Some(&r.identity.universe_id)
                && matches!(r.payload, Payload::Entity(_))
        })
    {
        return Err(invalid(
            "effect role must identify exactly one owning entity",
        ));
    }
    Ok(&p.record)
}

/// Resolve stock only from explicit direct/generated assertions. Possession powers
/// and unasserted propositions cannot establish a spendable balance.
fn magnitude(value: &Value, unit: &Option<UnitId>) -> anyhow::Result<i128> {
    let value = match (value, unit) {
        (Value::Integer { .. }, None) => value,
        (
            Value::Quantity {
                value,
                unit: actual,
            },
            Some(expected),
        ) if actual == expected => value,
        _ => {
            return Err(invalid(
                "resource requires an integer in the exact declared unit",
            ))
        }
    };
    let Value::Integer { digits } = value else {
        return Err(invalid(
            "resource magnitude must be an exact bounded integer",
        ));
    };
    digits
        .parse()
        .map_err(|_| invalid("resource magnitude outside supported integer bounds"))
}

#[allow(clippy::too_many_arguments)]
fn transition(
    records: &[RecordVersion],
    by_id: &BTreeMap<&RecordId, &RecordVersion>,
    event: &Event,
    slot: &EffectSlot,
    frame: &Frame,
    worlds: &[Vec<RecordId>],
    charge: &mut impl FnMut(usize) -> anyhow::Result<()>,
) -> anyhow::Result<()> {
    let EffectChange::Delta {
        delta,
        minimum,
        maximum,
        unit,
    } = &slot.change
    else {
        return Ok(());
    };
    let target = owner(event, &slot.target.role, by_id)?;
    let effect = event
        .effects
        .iter()
        .find(|e| e.slot == slot.slot)
        .ok_or_else(|| invalid("missing resource effect"))?;
    let Some(Payload::Proposition(post)) =
        by_id.get(&effect.proposition.record).map(|r| &r.payload)
    else {
        return Err(invalid("resource post-value unavailable"));
    };
    if effect.polarity != Polarity::Support {
        return Err(invalid(
            "resource effects must support the proposed balance",
        ));
    }
    let proposed = magnitude(
        post.value
            .as_ref()
            .ok_or_else(|| invalid("resource post-value missing"))?,
        unit,
    )?;
    for world in worlds {
        let mut supported = BTreeSet::new();
        let mut refuted = BTreeSet::new();
        charge(records.len())?;
        for record in records {
            let Payload::Assertion(a) = &record.payload else {
                continue;
            };
            let Some(Payload::Proposition(p)) =
                by_id.get(&a.proposition.record).map(|r| &r.payload)
            else {
                continue;
            };
            if &p.subject != target
                || p.predicate != slot.target.predicate
                || p.context != frame.context
                || a.scope.context != frame.context
                || !p.roles.is_empty()
                || p.quantification != Quantification::Particular
            {
                continue;
            }
            let applies = match &a.scope.applicability {
                Applicability::UniverseWide => true,
                Applicability::Worlds { world_ids } => world_ids.iter().any(|w| {
                    world
                        .iter()
                        .any(|r| r.as_str().strip_prefix("rec_") == w.as_str().strip_prefix("wld_"))
                }),
                _ => return Err(invalid("resource scope unresolved")),
            };
            if !applies {
                continue;
            }
            match universe_rules::events::applies(&a.validity, &frame.time, records) {
                Some(false) => continue,
                None => return Err(invalid("resource pre-event time evidence unresolved")),
                Some(true) => {}
            }
            if a.scope.realm.is_some()
                || a.precision != Precision::Exact
                || !a.alternatives.is_empty()
            {
                return Err(invalid(
                    "resource pre-event evidence is uncertain or nonobjective",
                ));
            }
            let n = magnitude(
                p.value
                    .as_ref()
                    .ok_or_else(|| invalid("resource pre-value missing"))?,
                unit,
            )?;
            match a.polarity {
                Polarity::Support => {
                    supported.insert(n);
                }
                Polarity::Refutation => {
                    refuted.insert(n);
                }
            }
        }
        if supported.len() != 1 || !supported.is_disjoint(&refuted) {
            return Err(invalid(
                "resource pre-event balance missing, conflicting or ambiguous",
            ));
        }
        let before = *supported.first().expect("one supported balance");
        if before < minimum.get() || before > maximum.get() {
            return Err(invalid(
                "resource pre-event balance outside declared bounds",
            ));
        }
        let after = before
            .checked_add(delta.get())
            .ok_or_else(|| invalid("resource arithmetic overflow"))?;
        if after < minimum.get() || after > maximum.get() {
            return Err(invalid(
                "resource transition underflow or overflow of declared bounds",
            ));
        }
        if proposed != after {
            return Err(invalid(
                "resource post-value does not equal pre-value plus declared change",
            ));
        }
    }
    Ok(())
}

pub fn validate(
    records: &[RecordVersion],
    base: &[RecordVersion],
    changed: &BTreeSet<RecordId>,
    frame: &Frame,
) -> anyhow::Result<Vec<String>> {
    let by_id: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let index = universe_rules::EvaluationIndex::new(records);
    let mut remaining = 1_000_000usize;
    let mut charge = |cost| -> anyhow::Result<()> {
        remaining =
            remaining
                .checked_sub(cost)
                .ok_or_else(|| ProtocolError::EvaluationLimitReached {
                    message: "Consequence evaluation exceeded its work budget".into(),
                })?;
        Ok(())
    };
    let mut exclusions = Vec::new();
    for record in records {
        charge(1)?;
        if let Payload::ActionDefinition(action) = &record.payload {
            if changed.contains(&record.identity.record_id) && action.consequence_contract.is_none()
            {
                return Err(invalid(
                    "new or revised actions must declare a consequence contract",
                ));
            }
        }
        let Payload::Event(event) = &record.payload else {
            continue;
        };
        let action = event
            .action
            .as_ref()
            .and_then(|a| by_id.get(&a.record))
            .and_then(|r| match &r.payload {
                Payload::ActionDefinition(a) => Some(a),
                _ => None,
            });
        let Some((action, contract)) =
            action.and_then(|a| a.consequence_contract.as_ref().map(|c| (a, c)))
        else {
            if changed.contains(&record.identity.record_id) {
                return Err(invalid(
                    "new or revised events require a contract-bearing action",
                ));
            }
            exclusions.push(format!(
                "event:{}: historical undeclared consequences excluded",
                record.identity.record_id
            ));
            continue;
        };
        contract.validate().map_err(|e| invalid(&e))?;
        if action.scope.realm.is_some()
            || event.worlds.iter().collect::<BTreeSet<_>>().len() != event.worlds.len()
        {
            return Err(invalid(
                "contract execution requires realm-free scope and unique worlds",
            ));
        }
        let mut worlds = event.worlds.clone();
        worlds.sort();
        let scope = Scope {
            context: action.scope.context.clone(),
            applicability: if worlds.is_empty() {
                Applicability::UniverseWide
            } else {
                Applicability::Worlds {
                    world_ids: worlds.clone(),
                }
            },
            realm: None,
        };
        let mut event_frame = frame.clone();
        event_frame.context = scope.context.clone();
        event_frame.time = FrameTime::AtEvent {
            event: RecordRef::new(frame.universe.clone(), record.identity.record_id.clone()),
            side: EventTimeSide::Before,
        };
        let world_queries: Vec<Vec<RecordId>> = if worlds.is_empty() {
            vec![vec![]]
        } else {
            worlds
                .iter()
                .map(|w| {
                    RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)).map(|id| vec![id])
                })
                .collect::<Result<_, _>>()?
        };
        let mut targets = BTreeSet::new();
        for slot in &contract.slots {
            charge(event.participants.len())?;
            let target = owner(event, &slot.target.role, &by_id)?;
            if !targets.insert((target, &slot.target.predicate)) {
                return Err(invalid("effect slots resolve to the same owner/property"));
            }
            if let EffectCondition::AttributeEquals { role, .. } = &slot.condition {
                owner(event, role, &by_id)?;
            }
        }
        let mut seen = BTreeSet::new();
        for effect in &event.effects {
            let slot = contract
                .slots
                .iter()
                .find(|s| s.slot == effect.slot)
                .ok_or_else(|| invalid("effect slot is not permitted by the action"))?;
            if !seen.insert(&effect.slot) {
                return Err(invalid("duplicate effect slot"));
            }
            let target = owner(event, &slot.target.role, &by_id)?;
            let Some(Payload::Proposition(prop)) =
                by_id.get(&effect.proposition.record).map(|r| &r.payload)
            else {
                return Err(invalid("effect proposition is unavailable"));
            };
            let mut actual_scope = effect.scope.clone();
            if let Applicability::Worlds { world_ids } = &mut actual_scope.applicability {
                if world_ids.iter().collect::<BTreeSet<_>>().len() != world_ids.len() {
                    return Err(invalid("duplicate effect worlds"));
                }
                world_ids.sort();
            }
            if actual_scope != scope
                || prop.context != scope.context
                || &prop.subject != target
                || prop.predicate != slot.target.predicate
                || !prop.roles.is_empty()
                || prop.quantification != Quantification::Particular
                || effect.order != usize::from(slot.order)
            {
                return Err(invalid("effect must match declared owner, predicate, order, context and full event scope"));
            }
            if let EffectChange::Set { polarity, value } = &slot.change {
                if effect.polarity != *polarity || prop.value.as_ref() != Some(value) {
                    return Err(invalid(
                        "effect polarity/value does not match declared assignment",
                    ));
                }
            }
            let TemporalExpression::Exact {
                calendar,
                value: time,
            } = &event.time
            else {
                return Err(invalid(
                    "effect requires an exact named-calendar event time",
                ));
            };
            let tick = time
                .parse::<i128>()
                .map_err(|_| invalid("invalid event coordinate"))?;
            let end = match &slot.lifetime {
                EffectLifetime::UntilChanged {} => TemporalBound::Unbounded,
                EffectLifetime::Ticks { count } => TemporalBound::Exact {
                    value: tick
                        .checked_add(count.get())
                        .filter(|v| *v != i128::MAX && *v != i128::MIN)
                        .ok_or_else(|| invalid("effect lifetime overflow"))?
                        .to_string(),
                },
            };
            let expected = Validity::CalendarInterval {
                calendar: calendar.clone(),
                start: TemporalBound::Exact {
                    value: tick.to_string(),
                },
                end,
            };
            if effect.validity != expected {
                return Err(invalid("effect lifetime must match the declared interval"));
            }
        }
        if event.occurrence != OccurrenceMode::Occurred {
            continue;
        }
        for slot in &contract.slots {
            let present = seen.contains(&slot.slot);
            let mut enabled = true;
            if let EffectCondition::AttributeEquals {
                role,
                predicate,
                value,
            } = &slot.condition
            {
                let subject = owner(event, role, &by_id)?;
                let Some(Payload::Property(property)) =
                    by_id.get(&predicate.record).map(|r| &r.payload)
                else {
                    return Err(invalid("condition property unavailable"));
                };
                let mut values = vec![value.clone()];
                for r in records {
                    charge(1)?;
                    let v = match &r.payload {
                        Payload::Proposition(p)
                            if p.predicate == *predicate && p.context == scope.context =>
                        {
                            p.value.as_ref()
                        }
                        Payload::ItemPower(p) if p.power_predicate == *predicate => Some(&p.value),
                        _ => None,
                    };
                    if let Some(v) = v {
                        if !values.contains(v) {
                            values.push(v.clone());
                        }
                    }
                }
                let mut truths = Vec::new();
                for world in &world_queries {
                    let mut supported = Vec::new();
                    let mut refuted_expected = false;
                    for v in &values {
                        charge(records.len())?;
                        let expr = Expr::Claim {
                            subject: Operand::Record {
                                record: subject.clone(),
                            },
                            predicate: format!("{}:{}", property.namespace, property.key),
                            roles: vec![],
                            value: Some(Operand::Value { value: v.clone() }),
                            polarity: Polarity::Support,
                            context: None,
                        };
                        let (evidence, complete) = universe_rules::basic::evaluate(
                            &expr,
                            &universe_rules::EvaluationContext {
                                frame: Some(&event_frame),
                                base_snapshot: records,
                                candidate_changes: vec![],
                                index: Some(&index),
                                world_scope: Some(world.clone()),
                            },
                        );
                        if !complete
                            || evidence.outcome() == universe_rules::EvidenceOutcome::Conflicting
                        {
                            return Err(invalid("effect condition unresolved: incomplete or conflicting pre-event evidence"));
                        }
                        match evidence.outcome() {
                            universe_rules::EvidenceOutcome::Supported => supported.push(v),
                            universe_rules::EvidenceOutcome::Refuted if v == value => {
                                refuted_expected = true
                            }
                            _ => {}
                        }
                    }
                    let single = property.multiplicity == Multiplicity::Single;
                    if single && supported.len() > 1 {
                        return Err(invalid(
                            "effect condition unresolved: incompatible pre-event values",
                        ));
                    }
                    let truth = if supported.contains(&value) {
                        true
                    } else if refuted_expected || single && supported.len() == 1 {
                        false
                    } else {
                        return Err(invalid(
                            "effect condition unresolved: no established pre-event truth",
                        ));
                    };
                    truths.push(truth);
                }
                if present && truths.iter().any(|t| !t) {
                    return Err(invalid(
                        "effect supplied for a false condition in an event world",
                    ));
                }
                enabled = truths.iter().any(|t| *t);
            }
            if (!enabled && present)
                || (enabled && slot.presence == EffectPresence::Required && !present)
            {
                return Err(invalid(
                    "missing mandatory effect or effect supplied for a false condition",
                ));
            }
            if enabled
                && (present || slot.presence == EffectPresence::Required)
                && matches!(slot.change, EffectChange::Delta { .. })
            {
                transition(
                    records,
                    &by_id,
                    event,
                    slot,
                    &event_frame,
                    &world_queries,
                    &mut charge,
                )?;
            }
        }
    }
    // A removal cannot evade enforcement by leaving untouched bound events.
    for old in base {
        if matches!(&old.payload, Payload::ActionDefinition(a) if a.consequence_contract.is_some()) && by_id.get(&old.identity.record_id).is_some_and(|r| matches!(&r.payload, Payload::ActionDefinition(a) if a.consequence_contract.is_none())) {
            return Err(invalid("a contracted action cannot discard its contract"));
        }
    }
    Ok(exclusions)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    #[test]
    fn independent_expected_effect_fixtures() {
        fixtures(include_str!(
            "../../../fixtures/action-effects/expected.json"
        ));
    }
    #[test]
    fn independent_resource_transition_fixtures() {
        fixtures(include_str!(
            "../../../fixtures/resource-transitions/expected.json"
        ));
    }
    fn fixtures(raw: &str) {
        let fixture: Value = serde_json::from_str(raw).unwrap();
        for case in fixture["cases"].as_array().unwrap() {
            let mut payloads = fixture["records"].as_array().unwrap().clone();
            for m in case["mutations"].as_array().unwrap() {
                let mut node = &mut payloads[m["record"].as_u64().unwrap() as usize - 1];
                let path: Vec<_> = m["path"].as_str().unwrap().split('.').collect();
                for key in &path[..path.len() - 1] {
                    node = if node.is_array() {
                        &mut node[key.parse::<usize>().unwrap()]
                    } else {
                        &mut node[*key]
                    };
                }
                let key = path[path.len() - 1];
                if m["value"].is_null() {
                    node.as_object_mut().unwrap().remove(key);
                } else {
                    node[key] = m["value"].clone();
                }
            }
            if let Some(extra) = case["extraRecords"].as_array() {
                payloads.extend(extra.iter().cloned());
            }
            let universe = UniverseId::parse("unv_000000000000000000000001").unwrap();
            let rows: Vec<_> = payloads
                .into_iter()
                .enumerate()
                .map(|(i, p)| {
                    let payload: Payload = serde_json::from_value(p).unwrap();
                    RecordVersion::build(
                        RecordVersionId::parse(&format!("ver_{:024x}", i + 1)).unwrap(),
                        RecordIdentity::new(
                            universe.clone(),
                            RecordId::parse(&format!("rec_{:024x}", i + 1)).unwrap(),
                            payload.kind(),
                        ),
                        payload,
                    )
                    .unwrap()
                })
                .collect();
            let frame: Frame = serde_json::from_value(json!({"universe":universe,"continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":universe,"record":"rec_00000000000000000000000a"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
            let changed = case["changed"]
                .as_array()
                .unwrap()
                .iter()
                .map(|n| RecordId::parse(&format!("rec_{:024x}", n.as_u64().unwrap())).unwrap())
                .collect();
            let result = validate(&rows, &[], &changed, &frame);
            assert_eq!(
                result.is_ok(),
                case["allowed"].as_bool().unwrap(),
                "{}: {:?}",
                case["id"],
                result
            );
            if case["id"] == "historical_contractless" {
                assert_eq!(result.unwrap().len(), 1);
            }
        }
    }
}
