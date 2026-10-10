//! Thin ordinary writing adapters; canonical operations and evaluators stay authoritative.
use super::writing::{plain_time, plain_value};
use super::*;
use std::collections::BTreeMap;
use universe_domain::{scope::*, temporal::TemporalExpression, value::Value as DomainValue};
use universe_protocol::writing::*;

pub(super) fn plain_action(
    a: &ActionDefinition,
    name: &impl Fn(&RecordId) -> Option<String>,
) -> Value {
    let requirements:Vec<_>=a.requirements.iter().map(|r|json!({"role":r.role,"property":name(&r.predicate.record),"value":plain_value(&r.value,name)})).collect();
    let effects:Vec<_>=a.consequence_contract.iter().flat_map(|c|&c.slots).map(|s|{
                    use universe_domain::consequences::*;
                    let change=match &s.change{EffectChange::Set{polarity,value}=>json!({"kind":"set","value":plain_value(value,name),"negated":*polarity==Polarity::Refutation}),EffectChange::Delta{delta,minimum,maximum,unit}=>json!({"kind":"delta","amount":delta.get(),"minimum":minimum.get(),"maximum":maximum.get(),"unit":unit.as_ref().and_then(|u|u.to_record_id().ok()).and_then(|id|name(&id))})};
                    let condition=match &s.condition{EffectCondition::Always{}=>Value::Null,EffectCondition::AttributeEquals{role,predicate,value}=>json!({"role":role,"property":name(&predicate.record),"value":plain_value(value,name)})};
                    let lifetime=match &s.lifetime {EffectLifetime::UntilChanged{}=>json!({"kind":"until_changed"}),EffectLifetime::Ticks{count}=>json!({"kind":"ticks","count":count.get()})};
                    json!({"role":s.target.role,"property":name(&s.target.predicate.record),"change":change,"condition":condition,"optional":s.presence==EffectPresence::Optional,"lifetime":lifetime})}).collect();
    json!({"name":a.key,"requirements":requirements,"effects":effects,"scope":match &a.scope.applicability { Applicability::UniverseWide=>json!("universe"),Applicability::Worlds{world_ids}=>json!({"worlds":world_ids.iter().map(|id|RecordId::parse(&id.as_str().replacen("wld_","rec_",1)).ok().and_then(|id|name(&id))).collect::<Vec<_>>()}),_=>json!("unresolved") },"time":plain_time(&json!(a.validity),name),"contract_declared":a.consequence_contract.is_some()})
}

pub(super) fn authored_fact<'a>(
    rows: &'a [RecordVersion],
    handle: &str,
) -> anyhow::Result<(&'a RecordVersion, &'a Assertion)> {
    let row = rows
        .iter()
        .find(|r| r.record_version_id.as_str() == handle)
        .ok_or_else(|| {
            anyhow::anyhow!("Retrieve the current pinned authored fact handle before editing it")
        })?;
    let Payload::Assertion(assertion) = &row.payload else {
        anyhow::bail!("Correction handle is not an authored assertion")
    };
    if assertion.established_by.is_some() {
        anyhow::bail!(
            "Generated event facts cannot be corrected directly; correct the authored cause"
        )
    }
    Ok((row, assertion))
}

fn reference(u: &UniverseId, id: &RecordId) -> RecordRef {
    RecordRef::new(u.clone(), id.clone())
}
pub(super) fn object(records: &[RecordVersion], name: &str, frame: &Frame) -> Option<RecordId> {
    let ids: BTreeSet<_> = records
        .iter()
        .filter_map(|r| match &r.payload {
            Payload::Entity(e)
                if e.labels.values().any(|n| n == name)
                    || e.names.iter().any(|n| {
                        n.text == name
                            && universe_rules::events::applies(&n.validity, &frame.time, records)
                                != Some(false)
                    }) =>
            {
                Some(r.identity.record_id.clone())
            }
            _ => None,
        })
        .collect();
    (ids.len() == 1).then(|| ids.into_iter().next().unwrap())
}
pub(super) fn claim(
    u: &UniverseId,
    records: &[RecordVersion],
    frame: &Frame,
    input: &WritingClaim,
) -> anyhow::Result<Proposition> {
    let subject = object(records, &input.subject, frame).ok_or_else(|| {
        anyhow::anyhow!("Which exact object is '{}' in this claim?", input.subject)
    })?;
    let properties: Vec<_> = records
        .iter()
        .filter_map(|r| match &r.payload {
            Payload::Property(p)
                if p.key == input.property || p.labels.values().any(|n| n == &input.property) =>
            {
                Some((r, p))
            }
            _ => None,
        })
        .collect();
    let [(r, p)] = properties.as_slice() else {
        anyhow::bail!(
            "Which authored property is '{}' in this claim?",
            input.property
        )
    };
    let value = fact_value(u, records, frame, &input.value)?;
    // The canonical compiler validates actual value shape, units and references.
    let _ = p;
    Ok(serde_json::from_value(
        json!({"subject":reference(u,&subject),"predicate":reference(u,&r.identity.record_id),"value":value,"context":frame.context,"quantification":"particular"}),
    )?)
}
pub(super) fn fact_value(
    u: &UniverseId,
    records: &[RecordVersion],
    frame: &Frame,
    input: &FactValue,
) -> anyhow::Result<DomainValue> {
    Ok(match input {
        FactValue::Text(v) => DomainValue::Text { text: v.clone() },
        FactValue::Boolean(v) => DomainValue::Boolean { value: *v },
        FactValue::Number(v) if !v.to_string().chars().any(|c| matches!(c, '.' | 'e' | 'E')) => {
            DomainValue::Integer {
                digits: v.to_string(),
            }
        }
        FactValue::Number(v) => DomainValue::Decimal {
            digits: v.to_string(),
        },
        FactValue::Quantity { amount, unit } => DomainValue::Quantity {
            value: Box::new(fact_value(
                u,
                records,
                frame,
                &FactValue::Number(amount.clone()),
            )?),
            unit: super::writing_units::unit(records, unit)?,
        },
        FactValue::Object { object: name } => DomainValue::EntityRef {
            record: reference(
                u,
                &object(records, name, frame)
                    .ok_or_else(|| anyhow::anyhow!("Which exact object is '{name}'?"))?,
            ),
        },
    })
}
pub(super) fn time(
    frame: &Frame,
    records: &[RecordVersion],
    tick: &Option<String>,
) -> anyhow::Result<TemporalExpression> {
    if let FrameTime::At {
        time: TemporalExpression::Exact { calendar, value },
    } = &frame.time
    {
        return Ok(TemporalExpression::Exact {
            calendar: calendar.clone(),
            value: tick.as_ref().unwrap_or(value).clone(),
        });
    }
    if matches!(frame.time, FrameTime::Timeless) {
        if let Some(value) = tick {
            let context = records.iter().find(|r| {
                r.identity.record_id == frame.context.record
                    && frame.context.resolve_namespace(&frame.universe).is_ok()
            });
            if let Some(Payload::RepresentedContext(context)) = context.map(|r| &r.payload) {
                if let Some(clock) = &context.chronology {
                    return Ok(TemporalExpression::Exact {
                        calendar: clock.calendar.clone(),
                        value: value.clone(),
                    });
                }
            }
        }
    }
    anyhow::bail!(
        "What exact authored calendar/story time applies to this action or communication?"
    )
}

pub(super) fn define(
    operations: &mut Vec<Value>,
    u: &UniverseId,
    p: &Proposition,
    records: &[RecordVersion],
) -> RecordRef {
    if let Some(r) = records
        .iter()
        .find(|r| matches!(&r.payload,Payload::Proposition(existing) if existing==p))
    {
        return reference(u, &r.identity.record_id);
    }
    let id = RecordId::generate(&mut rand::rng());
    operations.push(json!({"kind":"define_proposition","client_ref":id,"record":p}));
    reference(u, &id)
}
pub(super) fn candidate_records(
    u: &UniverseId,
    ctx: &Context,
    base: &[RecordVersion],
    operations: &[Value],
) -> anyhow::Result<Vec<RecordVersion>> {
    let ops: Vec<DomainOperation> = serde_json::from_value(json!(operations))?;
    let changes = operations::compile(u, &ctx.frame.revision, base, &ops)?;
    let mut rows: BTreeMap<_, _> = base
        .iter()
        .cloned()
        .map(|r| (r.identity.record_id.clone(), r))
        .collect();
    for a in changes {
        if let Some(next) = a.next {
            rows.insert(a.record_id, next);
        } else {
            rows.remove(&a.record_id);
        }
    }
    Ok(rows.into_values().collect())
}
impl Workflow<'_> {
    pub(super) fn writing_aliases(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        base: &[RecordVersion],
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        let mut targets = BTreeSet::new();
        for alias in &input.aliases {
            let build = || -> anyhow::Result<Option<Value>> {
                if alias.text.trim().is_empty() {
                    anyhow::bail!("Supply the author's explicit nonempty alias text.")
                }
                let id = object(base, &alias.object, &ctx.frame).ok_or_else(|| {
                    anyhow::anyhow!("Which exact existing identity is '{}' ?", alias.object)
                })?;
                let original = base
                    .iter()
                    .find(|r| r.identity.record_id == id)
                    .ok_or_else(denied)?;
                let Payload::Entity(e) = &original.payload else {
                    return Err(denied());
                };
                let validity = match (&alias.at_tick, &alias.lifetime) {
                    (None, None) => Validity::Unspecified,
                    (Some(_), None) => super::writing_contracts::validity(
                        &time(&ctx.frame, base, &alias.at_tick)?,
                        &FactLifetime::Unspecified,
                    )?,
                    (_, Some(lifetime)) => super::writing_contracts::validity(
                        &time(&ctx.frame, base, &alias.at_tick)?,
                        lifetime,
                    )?,
                };
                let name = ContextualName {
                    text: alias.text.clone(),
                    language: alias.language.clone(),
                    community: alias.community.clone(),
                    role: alias.role.clone(),
                    validity,
                };
                if e.names.contains(&name) {
                    return Ok(None);
                }
                Ok(Some(
                    json!({"kind":"add_name","record":{"universe":self.kernel.universe(),"record":id},"expected_version":original.record_version_id,"name":name}),
                ))
            };
            match build() {
                Ok(None) => result
                    .unchanged
                    .push(format!("Existing alias: {} — {}", alias.object, alias.text)),
                Ok(Some(op)) => {
                    if !targets.insert(op["record"]["record"].to_string()) {
                        result.clarifications.push("Add only one new alias per identity per delta; existing aliases stay unchanged.".into());
                        continue;
                    }
                    ops.push(op);
                    result.additions.push(format!(
                        "Explicit alias: {} — {}; no knowledge or communication inferred.",
                        alias.object, alias.text
                    ));
                }
                Err(error) => result.clarifications.push(error.to_string()),
            }
        }
        Ok(())
    }
    pub(super) fn connected_writing(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        base: &[RecordVersion],
        operations: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        if input.events.is_empty()
            && input.messages.is_empty()
            && input.attitudes.is_empty()
            && input.corrections.is_empty()
            && input.fact_endings.is_empty()
            && input.fact_withdrawals.is_empty()
        {
            return Ok(());
        }
        let u = self.kernel.universe();
        let mut rows = candidate_records(u, ctx, base, operations)?;
        let mut messages = BTreeMap::new();
        for message in &input.messages {
            let built = (|| -> anyhow::Result<_> {
                if messages.contains_key(&message.label) || message.label.trim().is_empty() {
                    anyhow::bail!(
                        "Communication labels must identify separate depicted messages uniquely"
                    )
                }
                let resolve = |name: &str| {
                    object(&rows, name, &ctx.frame)
                        .map(|id| reference(u, &id))
                        .ok_or_else(|| {
                            anyhow::anyhow!("Which exact communication participant is '{name}'?")
                        })
                };
                let sender = resolve(&message.from)?;
                let intended_recipients = message
                    .to
                    .iter()
                    .map(|n| resolve(n))
                    .collect::<anyhow::Result<Vec<_>>>()?;
                let actual_recipients = message
                    .received_by
                    .iter()
                    .map(|n| resolve(n))
                    .collect::<anyhow::Result<Vec<_>>>()?;
                if message
                    .understood_by
                    .iter()
                    .any(|n| !message.received_by.contains(n))
                {
                    anyhow::bail!("Who actually received the communication they understood?")
                }
                let proposition = claim(u, &rows, &ctx.frame, &message.claim)?;
                let prop = define(operations, u, &proposition, &rows);
                let sent_at = time(&ctx.frame, &rows, &message.sent_tick)?;
                let received_at = if actual_recipients.is_empty() {
                    None
                } else {
                    Some(time(&ctx.frame, &rows, &message.received_tick)?)
                };
                let id = RecordId::generate(&mut rand::rng());
                let record = Communication {
                    sender,
                    intended_recipients,
                    actual_recipients,
                    content: vec![prop.clone()],
                    channel: message.channel.clone(),
                    sent_at,
                    received_at,
                    distorted: message.distorted,
                };
                Ok((id, record, prop))
            })();
            match built {
                Ok((id, record, prop)) => {
                    operations.push(
                        json!({"kind":"record_communication","client_ref":id,"record":record}),
                    );
                    messages.insert(
                        message.label.clone(),
                        (id, prop, message.understood_by.clone()),
                    );
                    result.additions.push(format!(
                        "Communication '{}' from {} (content is not objective truth)",
                        message.label, message.from
                    ));
                    rows = candidate_records(u, ctx, base, operations)?;
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for attitude in &input.attitudes {
            let built = (|| -> anyhow::Result<_> {
                let holder = object(&rows, &attitude.holder, &ctx.frame)
                    .map(|id| reference(u, &id))
                    .ok_or_else(|| {
                        anyhow::anyhow!("Which exact attitude holder is '{}' ?", attitude.holder)
                    })?;
                let proposition = claim(u, &rows, &ctx.frame, &attitude.claim)?;
                let prop = define(operations, u, &proposition, &rows);
                let at = time(&ctx.frame, &rows, &attitude.at_tick)?;
                let kind: EpistemicAttitudeKind = serde_json::from_value(json!(attitude.attitude))?;
                let acquisition = if kind == EpistemicAttitudeKind::Knows {
                    let policies: Vec<_> = rows
                        .iter()
                        .filter_map(|r| match &r.payload {
                            Payload::Rule(rule) => rule
                                .knowledge_policy
                                .as_ref()
                                .filter(|p| p.context == ctx.frame.context),
                            _ => None,
                        })
                        .collect();
                    if policies.len() != 1 || policies[0].mode != KnowledgeMode::Justified {
                        anyhow::bail!("Knowledge requires the authored justified acquisition policy; author-established knowledge needs a separate explicit author decision")
                    }
                    let label = attitude.message.as_ref().ok_or_else(|| {
                        anyhow::anyhow!(
                            "Which actual interpreted communication establishes {}'s knowledge?",
                            attitude.holder
                        )
                    })?;
                    let (id, interpreted) = if let Some((id, p, understood)) = messages.get(label) {
                        if !understood.contains(&attitude.holder) || p != &prop {
                            anyhow::bail!(
                                "What claim did {} actually understand from this communication?",
                                attitude.holder
                            )
                        }
                        (id.clone(), p.clone())
                    } else {
                        let row=rows.iter().find(|r|r.identity.record_id.as_str()==label).ok_or_else(||anyhow::anyhow!("Retrieve the actual communication handle before claiming knowledge"))?;
                        let Payload::Communication(c) = &row.payload else {
                            anyhow::bail!("Knowledge receipt handle is not a communication")
                        };
                        if !c.content.contains(&prop) {
                            anyhow::bail!(
                                "The claimed interpretation differs from the communication content"
                            )
                        }
                        // An explicit attitude submitted by the caller declares interpretation;
                        // recipient, chronology and truth are still evaluated by the engine.
                        (row.identity.record_id.clone(), prop.clone())
                    };
                    Some(KnowledgeAcquisition {
                        truth_context: ctx.frame.context.clone(),
                        time: at.clone(),
                        world: None,
                        basis: KnowledgeBasis::CommunicationReceipt {
                            communication: reference(u, &id),
                            interpretation: Some(interpreted),
                        },
                    })
                } else {
                    None
                };
                Ok(EpistemicAttitude {
                    acquisition,
                    holder,
                    proposition: prop,
                    attitude: kind,
                    certainty: None,
                    validity: match (&attitude.lifetime, &at) {
                        (FactLifetime::Unspecified, _) => Validity::Instant { at: at.clone() },
                        (lifetime, TemporalExpression::Exact { calendar, value }) => {
                            Validity::CalendarInterval {
                                calendar: calendar.clone(),
                                start: universe_domain::temporal::TemporalBound::Exact {
                                    value: value.clone(),
                                },
                                end: match lifetime {
                                    FactLifetime::Until { end_tick } => {
                                        universe_domain::temporal::TemporalBound::Exact {
                                            value: end_tick.clone(),
                                        }
                                    }
                                    _ => universe_domain::temporal::TemporalBound::Unbounded,
                                },
                            }
                        }
                        _ => anyhow::bail!("What exact attitude lifetime applies?"),
                    },
                    basis: EvidenceBasis::ImportedClaim,
                })
            })();
            match built {
                Ok(record) => {
                    operations.push(json!({"kind":"add_belief","client_ref":RecordId::generate(&mut rand::rng()),"record":record}));
                    result.additions.push(format!(
                        "{}: {:?} (distinct from objective truth)",
                        attitude.holder, attitude.attitude
                    ));
                    rows = candidate_records(u, ctx, base, operations)?;
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        let mut edited_facts = BTreeSet::new();
        for correction in &input.corrections {
            let built = (|| -> anyhow::Result<_> {
                if correction.reason.trim().is_empty() {
                    anyhow::bail!("A factual correction requires the author's stated reason")
                }
                let (row, old) = authored_fact(base, &correction.fact_handle)?;
                if !edited_facts.insert(row.identity.record_id.clone()) {
                    anyhow::bail!("Submit only one correction, ending or withdrawal for each authored fact in a delta.")
                }
                let Some(Payload::Proposition(p)) = base
                    .iter()
                    .find(|r| r.identity.record_id == old.proposition.record)
                    .map(|r| &r.payload)
                else {
                    anyhow::bail!("Retrieve the original correction proposition")
                };
                let mut p = p.clone();
                p.value = Some(fact_value(u, &rows, &ctx.frame, &correction.value)?);
                let prop = define(operations, u, &p, &rows);
                let mut replacement = old.clone();
                replacement.proposition = prop;
                replacement.basis = EvidenceBasis::ImportedClaim;
                Ok(
                    json!({"kind":"supersede_assertion","record":reference(u,&row.identity.record_id),"expected_version":row.record_version_id,"replacement":replacement,"rationale":correction.reason}),
                )
            })();
            match built {
                Ok(op) => {
                    operations.push(op);
                    result.additions.push(format!(
                        "Correction to authored fact {} (original scope/time preserved)",
                        correction.fact_handle
                    ));
                    rows = candidate_records(u, ctx, base, operations)?;
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for (handle, reason, end_tick) in input
            .fact_endings
            .iter()
            .map(|e| (&e.fact_handle, &e.reason, Some(&e.end_tick)))
            .chain(
                input
                    .fact_withdrawals
                    .iter()
                    .map(|w| (&w.fact_handle, &w.reason, None)),
            )
        {
            let built = (|| -> anyhow::Result<Value> {
                if reason.trim().is_empty() {
                    anyhow::bail!("Explain the author's fact ending or withdrawal.")
                }
                let (row, assertion) = authored_fact(base, handle)?;
                if !edited_facts.insert(row.identity.record_id.clone()) {
                    anyhow::bail!("Submit only one correction, ending or withdrawal for each authored fact in a delta.")
                }
                if let Some(tick) = end_tick {
                    let Validity::CalendarInterval { calendar, .. } = &assertion.validity else {
                        anyhow::bail!("Ending requires an authored calendar interval; use withdrawal or explicit historical correction for other validity.")
                    };
                    Ok(
                        json!({"kind":"end_assertion_at","record":reference(u,&row.identity.record_id),"expected_version":row.record_version_id,"at":{"kind":"exact","calendar":calendar,"value":tick},"basis":{"kind":"imported_claim"}}),
                    )
                } else {
                    Ok(
                        json!({"kind":"retract_assertion","record":reference(u,&row.identity.record_id),"expected_version":row.record_version_id,"rationale":reason}),
                    )
                }
            })();
            match built {
                Ok(op) => {
                    operations.push(op);
                    result.additions.push(if let Some(tick) = end_tick { format!("Authored fact ends at {tick}: {reason}") } else { format!("Authored fact support withdrawn, without asserting its opposite: {reason}") });
                    rows = candidate_records(u, ctx, base, operations)?;
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for event in &input.events {
            let built = (|| -> anyhow::Result<_> {
                let matches: Vec<_> = rows
                    .iter()
                    .filter_map(|r| match &r.payload {
                        Payload::ActionDefinition(a)
                            if a.key == event.action
                                || a.labels.values().any(|n| n == &event.action) =>
                        {
                            Some((r, a))
                        }
                        _ => None,
                    })
                    .collect();
                let [(action_row, action)] = matches.as_slice() else {
                    let choices:Vec<_>=rows.iter().filter_map(|r|if let Payload::ActionDefinition(a)=&r.payload { if a.scope.context==ctx.frame.context { Some(json!({"name":a.key,"roles":a.requirements.iter().map(|r|r.role.clone()).chain(a.consequence_contract.iter().flat_map(|c|c.slots.iter().map(|s|s.target.role.clone()))).collect::<BTreeSet<_>>()})) }else{None} }else{None}).collect();
                    anyhow::bail!("Which existing authored action contract is '{}' ? Visible authored choices: {}",event.action,json!(choices))
                };
                if action.scope.context != ctx.frame.context || action.scope.realm.is_some() {
                    anyhow::bail!("Action contract does not apply to this represented context")
                }
                let participants = event
                    .participants
                    .iter()
                    .map(|(role, name)| {
                        object(&rows, name, &ctx.frame)
                            .map(|id| EventParticipant {
                                record: reference(u, &id),
                                role: role.clone(),
                            })
                            .ok_or_else(|| {
                                anyhow::anyhow!(
                                    "Which exact object fills action role '{role}' as '{name}'?"
                                )
                            })
                    })
                    .collect::<anyhow::Result<Vec<_>>>()?;
                let worlds = if let Some(world) = &event.world {
                    let ids: Vec<_> = rows
                        .iter()
                        .filter_map(|r| match &r.payload {
                            Payload::World(w) if w.selector == *world => {
                                Some(universe_store::kernel::record_world(&r.identity.record_id))
                            }
                            _ => None,
                        })
                        .collect();
                    if ids.len() != 1 {
                        anyhow::bail!("Which accessible authored world is '{world}'?")
                    }
                    ids
                } else {
                    match &action.scope.applicability {
                        Applicability::UniverseWide => vec![],
                        Applicability::Worlds { world_ids } if world_ids.len() == 1 => {
                            world_ids.clone()
                        }
                        _ => anyhow::bail!("Which authored world does this action occur in?"),
                    }
                };
                let id = RecordId::generate(&mut rand::rng());
                let mut record = Event {
                    occurrence: OccurrenceMode::Occurred,
                    action: Some(reference(u, &action_row.identity.record_id)),
                    worlds,
                    region: None,
                    time: time(&ctx.frame, &rows, &event.at_tick)?,
                    sequence: None,
                    occurrence_id: None,
                    participants,
                    preconditions: vec![],
                    effects: vec![],
                    labels: BTreeMap::new(),
                    expansion_version: None,
                };
                let action = (*action).clone();
                for requirement in &event.requires_knowledge {
                    let holder = object(&rows, &requirement.holder, &ctx.frame)
                        .map(|id| reference(u, &id))
                        .ok_or_else(|| {
                            anyhow::anyhow!(
                                "Which exact knowledge holder is '{}' ?",
                                requirement.holder
                            )
                        })?;
                    let p = claim(u, &rows, &ctx.frame, &requirement.claim)?;
                    let prop = define(operations, u, &p, &rows);
                    record.preconditions.push(serde_json::from_value(json!({"kind":"attitude","holder":holder,"proposition":prop,"attitude":"knows"}))?);
                }
                let effects =
                    crate::consequences::author_effects(&rows, &id, &record, &action, &ctx.frame)?;
                Ok((id, record, effects))
            })();
            match built {
                Ok((id, mut record, effects)) => {
                    for (p, proposition, effect) in effects {
                        operations.push(json!({"kind":"define_proposition","client_ref":p,"record":proposition}));
                        record.effects.push(effect)
                    }
                    operations.push(json!({"kind":"record_event","client_ref":id,"record":record}));
                    result.additions.push(format!(
                        "Occurred action: {} (authored contract consequences)",
                        event.action
                    ));
                    // Reuse existing event expansion so another event in this passage
                    // sees actual generated balances rather than caller arithmetic.
                    rows = candidate_records(u, ctx, base, operations)?;
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
    pub(super) fn read_writing_contracts(&mut self, input: ReadContracts) -> anyhow::Result<Value> {
        let ctx = self.context(&input.context_id)?;
        let args = json!(input);
        let all = self
            .kernel
            .records(&ctx.frame.continuity, &ctx.frame.revision)?;
        let ids = self
            .visible_ids(&all)?
            .intersection(&perspective_ids(&all, &ctx.frame)?)
            .cloned()
            .collect::<BTreeSet<_>>();
        let rows: Vec<_> = all
            .into_iter()
            .filter(|r| ids.contains(&r.identity.record_id))
            .collect();
        let name = |id: &RecordId| {
            rows.iter()
                .find(|r| &r.identity.record_id == id)
                .and_then(|r| match &r.payload {
                    Payload::Entity(e) => e
                        .labels
                        .values()
                        .next()
                        .cloned()
                        .or_else(|| e.names.first().map(|n| n.text.clone())),
                    Payload::Property(p) => Some(p.key.clone()),
                    Payload::Relation(r) => Some(r.key.clone()),
                    Payload::EntityType(t) => Some(t.name.clone()),
                    Payload::Realm(r) => r.labels.values().next().cloned(),
                    Payload::Unit(u) => Some(u.key.clone()),
                    Payload::World(w) => Some(w.selector.clone()),
                    Payload::Calendar(c) => Some(c.key.clone()),
                    _ => None,
                })
        };
        let mut actions = vec![];
        let mut policies = vec![];
        let mut channels = vec![];
        let mut messages = vec![];
        let mut attitudes = vec![];
        let mut constraints = vec![];
        let mut exhaustive_sets = vec![];
        let mut relations = vec![];
        let mut relation_limits = vec![];
        let mut relationships = vec![];
        let mut item_powers = vec![];
        let mut properties = vec![];
        let units:Vec<_>=rows.iter().filter_map(|r|if let Payload::Unit(u)=&r.payload {Some(json!({"name":u.key,"symbol":u.symbol,"dimension":u.dimension,"conversion_declared":u.base.is_some() || u.scale_to_base.is_some(),"time":plain_time(&json!(u.validity),&name)}))}else{None}).collect();
        for row in &rows {
            match &row.payload{
            Payload::ActionDefinition(a)if a.scope.context==ctx.frame.context&&(input.action_names.is_empty()||input.action_names.iter().any(|n|n==&a.key||a.labels.values().any(|v|v==n)))=>{
                actions.push(plain_action(a, &name));
            },Payload::Rule(r)=>{
            if let Some(c)=&r.relation_cardinality {if c.scope.context==ctx.frame.context {relation_limits.push(json!({"name":r.key,"relation":name(&c.relation.record),"grouping":c.grouping,"counted_role":c.counted_role,"maximum":c.maximum,"scope":plain_scope(&c.scope,&name),"time":plain_time(&json!(c.validity),&name),"time_applicable":universe_rules::events::applies(&c.validity,&ctx.frame.time,&rows),"policy":"always_block","limitation":"Distinct authored participants across overlapping relation occurrences; no inferred minimum/exclusivity, conversion or ordinary exception."}));}}
            if super::writing_contracts::supported_policy(r) {
                let target=r.target_predicates.first().and_then(|key|rows.iter().find_map(|row|if let Payload::Property(p)=&row.payload { (format!("{}:{}",p.namespace,p.key)==*key).then(||p.key.clone()) }else{None}));
                let scope=match &r.applicability {Applicability::UniverseWide=>json!("universe"),Applicability::Worlds{world_ids}=>json!({"worlds":world_ids.iter().filter_map(|w|RecordId::parse(&w.as_str().replacen("wld_","rec_",1)).ok().and_then(|id|name(&id))).collect::<Vec<_>>()}),_=>json!("unresolved")};
                if r.capabilities==["resources.accounting.v1"] {
                    constraints.push(json!({"name":r.key,"kind":"resource_accounting","property":target,"scope":scope,"time":plain_time(&json!(r.validity),&name),"limitation":"Exact interval stock; acceptance retains unexplained arrival and needs a separate real author decision."}));
                } else if let universe_domain::expr::Expr::NoOpposingEvidence{subject:universe_domain::expr::Operand::Record{record},..}=&r.expression {
                    constraints.push(json!({"name":r.key,"kind":"no_opposing_evidence","property":target,"object":name(&record.record),"scope":scope,"time":plain_time(&json!(r.validity),&name)}));
                }
            }
if let Some(p)=&r.knowledge_policy{if p.context==ctx.frame.context{policies.push(json!({"name":r.key,"mode":p.mode,"limitation":if p.mode==KnowledgeMode::AuthorEstablished{"Use the separate private establish_knowledge author action with selected claim, time, lifetime and rationale, followed by exact approval; source text or ordinary approval cannot manufacture it."}else{"Requires actual receipt, explicit interpretation, authored channel chronology, and objective truth."}}))}}
            if let Some(c)=&r.channel_chronology{channels.push(json!({"name":r.key,"channel":c.channel,"forward_only":c.forward_only,"minimum_delay":c.minimum_delay,"maximum_delay":c.maximum_delay}))}},
            Payload::Property(p) if matches!(ctx.frame.perspective,Perspective::Author)=>properties.push(json!({"name":p.key,"single_value":p.multiplicity==Multiplicity::Single,"persistence":match p.persistence {PersistenceSemantics::PersistentUntilChanged=>"until_changed",PersistenceSemantics::ExplicitInterval=>"explicit_interval",PersistenceSemantics::Unspecified=>"unspecified",PersistenceSemantics::InstantaneousObservation=>"instantaneous_observation",PersistenceSemantics::ConditionDependent=>"condition_dependent"},"value_type":if matches!(p.value,ValueShape::EntityRef{..}){json!("object")}else{serde_json::to_value(&p.value)?["kind"].clone()},"unit":match &p.value {ValueShape::Quantity{unit}=>unit.to_record_id().ok().and_then(|id|name(&id)),_=>None},"limitation":"Multiplicity/persistence revisions require private contract review; value type, units and other metadata stay unchanged. Existing facts retain their explicit validity and persistence."})),
            Payload::ItemPower(p) if matches!(ctx.frame.perspective,Perspective::Author) && p.scope.context==ctx.frame.context => {
                item_powers.push(json!({"grant_handle":row.record_version_id,"item":name(&p.item.record),"holder_property":name(&p.holder_predicate.record),"ability_property":name(&p.power_predicate.record),"value":plain_value(&p.value,&name),"scope":plain_scope(&p.scope,&name),"time":plain_time(&json!(p.validity),&name),"time_applicable":universe_rules::events::applies(&p.validity,&ctx.frame.time,&rows),"limitation":"Declaration only; the ability applies to the holder only while explicit holder-property evidence and this declaration both apply. Ownership relations do not establish possession."}));
            },
            Payload::Relation(d)=>relations.push(json!({"name":d.key,"roles":d.roles.iter().map(|role|json!({"name":role.name,"multiple":role.multiplicity==Multiplicity::Multiple,"ordered":role.ordered,"participant_types":role.participant_types.iter().map(&name).collect::<Vec<_>>()})).collect::<Vec<_>>() })),
            Payload::Assertion(a) if matches!(ctx.frame.perspective,Perspective::Author) && a.scope.context==ctx.frame.context && universe_rules::events::applies(&a.validity,&ctx.frame.time,&rows)!=Some(false)=>{
                if let Some(p)=rows.iter().find_map(|r|if r.identity.record_id==a.proposition.record{if let Payload::Proposition(p)=&r.payload {Some(p)}else{None}}else{None}) {
                    if rows.iter().any(|r|r.identity.record_id==p.predicate.record&&matches!(r.payload,Payload::Relation(_))){
                        relationships.push(json!({"relationship_handle":super::writing_relations::correctable(a).then_some(&row.record_version_id),"relation":name(&p.predicate.record),"subject":name(&p.subject.record),"participants":p.roles.iter().map(|role|json!({"role":role.role,"object":name(&role.participant.record)})).collect::<Vec<_>>(),"polarity":a.polarity,"scope":plain_scope(&a.scope,&name),"time":plain_time(&json!(a.validity),&name),"time_applicable":universe_rules::events::applies(&a.validity,&ctx.frame.time,&rows),"limitation":"Authored assertion; cross-occurrence limits are checked by the engine, not inferred from these declarations."}));
                    }
                }
            },
            Payload::Completeness(c) if c.scope.context==ctx.frame.context => {
                let property=rows.iter().find_map(|r|if let Payload::Property(p)=&r.payload {(format!("{}:{}",p.namespace,p.key)==c.predicate).then(||p.key.clone())}else{None});
                let scope=match &c.scope.applicability {Applicability::UniverseWide=>json!("universe"),Applicability::Worlds{world_ids}=>json!({"worlds":world_ids.iter().filter_map(|w|RecordId::parse(&w.as_str().replacen("wld_","rec_",1)).ok().and_then(|id|name(&id))).collect::<Vec<_>>()}),_=>json!("unresolved")};
                exhaustive_sets.push(json!({"subject":name(&c.subject.record),"property":property,"members":c.members.iter().map(|m|name(&m.record)).collect::<Vec<_>>(),"kind":match &c.completeness{CompletenessKind::ObjectiveReality=>"objective",CompletenessKind::ObserverKnown{..}=>"observer_known"},"scope":scope,"time":plain_time(&json!(c.validity),&name),"time_applicable":universe_rules::events::applies(&c.validity,&ctx.frame.time,&rows)}));
            },
            Payload::EpistemicAttitude(a) => {
                let p=rows.iter().find(|r|r.identity.record_id==a.proposition.record).and_then(|r|if let Payload::Proposition(p)=&r.payload{Some(p)}else{None});
                attitudes.push(json!({"holder":name(&a.holder.record),"attitude":a.attitude,"claim":p.map(|p|json!({"subject":name(&p.subject.record),"property":name(&p.predicate.record),"value":p.value.as_ref().and_then(|v|plain_value(v,&name))})),"time":plain_time(&json!(a.validity),&name),"applicable":universe_rules::events::applies(&a.validity,&ctx.frame.time,&rows),"message_handle":a.acquisition.as_ref().and_then(|a|if let KnowledgeBasis::CommunicationReceipt{communication,..}=&a.basis{Some(communication.record.clone())}else{None}),"limitation":"Attributed attitude; knowledge eligibility remains subject to existing truth/acquisition evaluator."}));
            },
            Payload::Communication(c)=>messages.push(json!({"message_handle":row.identity.record_id,"from":name(&c.sender.record),"received_by":c.actual_recipients.iter().filter_map(|r|name(&r.record)).collect::<Vec<_>>(),"sent_at":plain_time(&json!(c.sent_at),&name),"received_at":c.received_at.as_ref().map(|t|plain_time(&json!(t),&name)),"distorted":c.distorted,"claims":c.content.iter().filter_map(|p|rows.iter().find(|r|r.identity.record_id==p.record)).filter_map(|r|if let Payload::Proposition(p)=&r.payload{Some(json!({"subject":name(&p.subject.record),"property":name(&p.predicate.record),"value":p.value.as_ref().and_then(|v|plain_value(v,&name))}))}else{None}).collect::<Vec<_>>()})),_=>()
        }
        }
        self.wrap(&args,Some(ctx.frame.clone()),None,true,None,json!({"actions":actions,"units":units,"knowledge_policies":policies,"channels":channels,"communications":messages,"attitudes":attitudes,"constraints":constraints,"exhaustive_sets":exhaustive_sets,"relations":relations,"relation_limits":relation_limits,"relationships":relationships,"item_powers":item_powers,"properties":properties,"coverage":if self.scope.is_some() || !matches!(ctx.frame.perspective,Perspective::Author){"restricted"}else{"bounded"},"limitation":"Visible pinned authored declarations; absent contracts are unknown. Effects are computed and checked by the engine. Interpretation alone does not establish knowledge."}))
    }
}

pub(super) fn plain_scope(
    scope: &universe_domain::scope::Scope,
    name: &impl Fn(&RecordId) -> Option<String>,
) -> Value {
    let applicability = match &scope.applicability {
        Applicability::UniverseWide => json!("universe"),
        Applicability::Worlds { world_ids } => {
            json!({"worlds":world_ids.iter().map(|w|RecordId::parse(&w.as_str().replacen("wld_","rec_",1)).ok().and_then(|id|name(&id))).collect::<Vec<_>>()})
        }
        _ => json!("unresolved"),
    };
    match &scope.realm {
        Some(realm) => json!({"applicability":applicability,"realm":name(&realm.record)}),
        None => applicability,
    }
}
