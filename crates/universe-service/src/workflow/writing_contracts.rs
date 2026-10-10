//! Finite plain contract declarations over existing protected operations/evaluators.
use super::*;
use std::collections::BTreeMap;
use universe_protocol::writing::*;

fn property<'a>(
    rows: &'a [RecordVersion],
    name: &str,
) -> anyhow::Result<(&'a RecordVersion, &'a PropertyDef)> {
    let found: Vec<_> = rows
        .iter()
        .filter_map(|r| match &r.payload {
            Payload::Property(p) if p.key == name || p.labels.values().any(|v| v == name) => {
                Some((r, p))
            }
            _ => None,
        })
        .collect();
    match found.as_slice() {
        [p] => Ok(*p),
        _ => anyhow::bail!("Which exact authored property is '{name}'?"),
    }
}
pub(super) fn applicability(
    w: &Workflow<'_>,
    text: &str,
    rows: &[RecordVersion],
) -> anyhow::Result<Applicability> {
    match text {
        "universe" => Ok(Applicability::UniverseWide),
        "unspecified" => Ok(Applicability::Unspecified),
        name => Ok(Applicability::Worlds {
            world_ids: vec![w.focus(&json!({"world":name}), rows)?.ok_or_else(denied)?],
        }),
    }
}
fn integer(
    n: &serde_json::Number,
) -> anyhow::Result<universe_domain::consequences::ConsequenceInteger> {
    Ok(serde_json::from_value(json!(n.to_string()))?)
}
fn role_value(
    u: &UniverseId,
    rows: &[RecordVersion],
    frame: &Frame,
    r: &RoleValue,
) -> anyhow::Result<Value> {
    let (p, _) = property(rows, &r.property)?;
    Ok(
        json!({"role":r.role,"predicate":{"universe":u,"record":p.identity.record_id},"value":super::writing_connected::fact_value(u,rows,frame,&r.value)?}),
    )
}
impl Workflow<'_> {
    pub(super) fn writing_properties(
        &self,
        input: &CheckChanges,
        rows: &[RecordVersion],
        properties: &mut BTreeMap<String, (RecordId, PropertyDef)>,
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        for d in &input.properties {
            if d.name.trim().is_empty() {
                return Err(ProtocolError::invalid_argument(
                    "properties.name",
                    "nonempty property name required",
                )
                .into());
            }
            if d.unit.is_some() && !matches!(d.value_type, PlainPropertyType::Quantity) {
                result.clarifications.push(format!(
                    "Property '{}' supplies a unit without explicitly declaring quantity values.",
                    d.name
                ));
                continue;
            }
            let shape = match d.value_type {
                PlainPropertyType::Text => json!({"kind":"text"}),
                PlainPropertyType::Boolean => json!({"kind":"boolean"}),
                PlainPropertyType::Integer => json!({"kind":"integer"}),
                PlainPropertyType::Decimal => json!({"kind":"decimal"}),
                PlainPropertyType::Object => json!({"kind":"entity_ref","subject_types":[]}),
                PlainPropertyType::Quantity => {
                    let unit = match d
                        .unit
                        .as_ref()
                        .ok_or_else(|| {
                            anyhow::anyhow!(
                                "What authored unit applies to quantity property '{}' ?",
                                d.name
                            )
                        })
                        .and_then(|name| super::writing_units::unit(rows, name))
                    {
                        Ok(unit) => unit,
                        Err(e) => {
                            result.clarifications.push(e.to_string());
                            continue;
                        }
                    };
                    json!({"kind":"quantity","unit":unit})
                }
            };
            let persistence = match d.persistence {
                PlainPersistence::Unspecified => "unspecified",
                PlainPersistence::UntilChanged => "persistent_until_changed",
                PlainPersistence::ExplicitInterval => "explicit_interval",
            };
            let definition: PropertyDef = serde_json::from_value(
                json!({"namespace":"authoring","key":d.name,"labels":{},"subjectTypes":[],"value":shape,"multiplicity":if d.single_value{"single"}else{"multiple"},"persistence":persistence,"exclusive":false,"symmetric":false,"transitive":false}),
            )?;
            let found: Vec<_> = rows
                .iter()
                .filter_map(|r| match &r.payload {
                    Payload::Property(p)
                        if p.key == d.name || p.labels.values().any(|v| v == &d.name) =>
                    {
                        Some((r.identity.record_id.clone(), p.clone()))
                    }
                    _ => None,
                })
                .collect();
            if d.introduce && found.is_empty() && !properties.contains_key(&d.name) {
                let id = RecordId::generate(&mut rand::rng());
                ops.push(json!({"kind":"define_property","client_ref":id,"record":definition}));
                properties.insert(d.name.clone(), (id, definition));
                result.additions.push(format!(
                    "New property: {} ({} values)",
                    d.name,
                    if d.single_value { "single" } else { "multiple" }
                ));
            } else if !d.introduce
                && found.len() == 1
                && found[0].1.value == definition.value
                && found[0].1.multiplicity == definition.multiplicity
                && found[0].1.persistence == definition.persistence
            {
                properties.insert(d.name.clone(), found[0].clone());
                result
                    .unchanged
                    .push(format!("Property definition: {}", d.name));
            } else {
                result.clarifications.push(format!("Resolve property '{}' or explicitly revise its existing definition; this declaration cannot duplicate or change it.",d.name));
            }
        }
        for patch in &input.property_corrections {
            let build = || -> anyhow::Result<(Value, RecordId, PropertyDef)> {
                if patch.reason.trim().is_empty()
                    || (patch.single_value.is_none() && patch.persistence.is_none())
                {
                    anyhow::bail!("Specify the property settings to correct and a reason; omitted settings stay unchanged.");
                }
                let (original, definition) = property(rows, &patch.name)?;
                let mut replacement = definition.clone();
                if let Some(single) = patch.single_value {
                    replacement.multiplicity = if single {
                        Multiplicity::Single
                    } else {
                        Multiplicity::Multiple
                    };
                }
                if let Some(persistence) = &patch.persistence {
                    replacement.persistence = match persistence {
                        PlainPersistence::Unspecified => {
                            universe_domain::scope::PersistenceSemantics::Unspecified
                        }
                        PlainPersistence::UntilChanged => {
                            universe_domain::scope::PersistenceSemantics::PersistentUntilChanged
                        }
                        PlainPersistence::ExplicitInterval => {
                            universe_domain::scope::PersistenceSemantics::ExplicitInterval
                        }
                    };
                }
                Ok((
                    json!({"kind":"revise_definition","record":{"universe":self.kernel.universe(),"record":original.identity.record_id},"expected_version":original.record_version_id,"replacement":Payload::Property(replacement.clone())}),
                    original.identity.record_id.clone(),
                    replacement,
                ))
            };
            match build() {
                Ok((operation, id, definition)) => {
                    for name in std::iter::once(&definition.key).chain(definition.labels.values()) {
                        properties.insert(name.clone(), (id.clone(), definition.clone()));
                    }
                    properties.insert(patch.name.clone(), (id, definition));
                    ops.push(operation);
                    result.additions.push(format!(
                        "Property rule correction: {} — {}",
                        patch.name, patch.reason
                    ));
                }
                Err(error) => result.clarifications.push(error.to_string()),
            }
        }
        Ok(())
    }
    pub(super) fn writing_contracts(
        &self,
        input: &CheckChanges,
        ctx: &Context,
        base: &[RecordVersion],
        ops: &mut Vec<Value>,
        result: &mut WritingCheck,
    ) -> anyhow::Result<()> {
        if input.actions.is_empty()
            && input.constraints.is_empty()
            && input.action_corrections.is_empty()
            && input.definition_corrections.is_empty()
            && input.knowledge_policies.is_empty()
            && input.exhaustive_sets.is_empty()
            && input.item_powers.is_empty()
            && input.item_power_corrections.is_empty()
        {
            return Ok(());
        }
        let rows =
            super::writing_connected::candidate_records(self.kernel.universe(), ctx, base, ops)?;
        let u = self.kernel.universe();
        let mut edited = std::collections::BTreeSet::new();
        for patch in &input.item_power_corrections {
            let build = || -> anyhow::Result<Value> {
                let original = rows.iter().find(|r| r.record_version_id.as_str()==patch.grant_handle && matches!(&r.payload,Payload::ItemPower(p) if p.scope.context==ctx.frame.context)).ok_or_else(||anyhow::anyhow!("Retrieve the current pinned author-visible grant handle before correcting it"))?;
                let Payload::ItemPower(old) = &original.payload else {
                    unreachable!()
                };
                if patch.reason.trim().is_empty()
                    || (patch.value.is_none()
                        && patch.scope.is_none()
                        && patch.at_tick.is_none()
                        && patch.lifetime.is_none()
                        && patch.end_tick.is_none())
                {
                    anyhow::bail!(
                        "Choose grant fields to change and explain the author correction"
                    );
                }
                if patch.end_tick.is_some() && (patch.at_tick.is_some() || patch.lifetime.is_some())
                {
                    anyhow::bail!("Choose an explicit ending or a validity correction, not both");
                }
                let mut replacement = old.clone();
                if let Some(v) = &patch.value {
                    replacement.value =
                        super::writing_connected::fact_value(u, &rows, &ctx.frame, v)?;
                }
                if let Some(scope) = &patch.scope {
                    replacement.scope.applicability = applicability(self, scope, &rows)?;
                }
                if patch.at_tick.is_some() || patch.lifetime.is_some() {
                    use universe_domain::{
                        scope::Validity,
                        temporal::{TemporalBound, TemporalExpression},
                    };
                    let (calendar,start,end)=match &old.validity {
                        Validity::CalendarInterval{calendar,start,end}=>(calendar.clone(),start.clone(),Some(end.clone())),
                        Validity::Instant{at:TemporalExpression::Exact{calendar,value}}=>(calendar.clone(),TemporalBound::Exact{value:value.clone()},None),
                        _=>anyhow::bail!("This grant has no supported exact authored calendar validity; use advanced authoring"),
                    };
                    let start = patch
                        .at_tick
                        .as_ref()
                        .map(|value| TemporalBound::Exact {
                            value: value.clone(),
                        })
                        .unwrap_or(start);
                    replacement.validity = if let Some(lifetime) = &patch.lifetime {
                        let TemporalBound::Exact { value } = start else {
                            anyhow::bail!("Supply an explicit start for this unresolved grant")
                        };
                        validity(&TemporalExpression::Exact { calendar, value }, lifetime)?
                    } else if let Some(end) = end {
                        Validity::CalendarInterval {
                            calendar,
                            start,
                            end,
                        }
                    } else {
                        let TemporalBound::Exact { value } = start else {
                            unreachable!()
                        };
                        Validity::Instant {
                            at: TemporalExpression::Exact { calendar, value },
                        }
                    };
                }
                if let Some(end_tick) = &patch.end_tick {
                    use universe_domain::{scope::Validity, temporal::TemporalBound};
                    let Validity::CalendarInterval { start, end, .. } = &mut replacement.validity
                    else {
                        anyhow::bail!("Ending requires an existing authored calendar interval")
                    };
                    let coordinate = end_tick.parse::<i128>()?;
                    if matches!(start,TemporalBound::Exact{value} if coordinate<=value.parse::<i128>().unwrap_or(i128::MAX))
                        || matches!(end,TemporalBound::Exact{value} if coordinate>value.parse::<i128>().unwrap_or(i128::MIN))
                    {
                        anyhow::bail!(
                            "End the grant after its start and no later than its authored end"
                        );
                    }
                    *end = TemporalBound::Exact {
                        value: end_tick.clone(),
                    };
                }
                Ok(
                    json!({"kind":"revise_item_power","record":{"universe":u,"record":original.identity.record_id},"expected_version":original.record_version_id,"replacement":replacement,"rationale":patch.reason}),
                )
            };
            if !edited.insert(&patch.grant_handle) {
                result
                    .clarifications
                    .push("Correct each grant once in a delta".into());
                continue;
            }
            match build() {
                Ok(op) => {
                    ops.push(op);
                    result.additions.push(format!(
                        "Item-power correction: {}; private contract review required",
                        patch.reason
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for power in &input.item_powers {
            let build = || -> anyhow::Result<Value> {
                let item = super::writing_connected::object(&rows, &power.item, &ctx.frame)
                    .ok_or_else(|| {
                        anyhow::anyhow!("Which exact authored item is '{}' ?", power.item)
                    })?;
                let (holder, definition) = property(&rows, &power.holder_property)?;
                if !matches!(definition.value, ValueShape::EntityRef { .. })
                    || definition.multiplicity != Multiplicity::Single
                {
                    anyhow::bail!("Possession requires an explicitly authored single-valued object holder property on the item; ownership relations are not possession evidence.");
                }
                let (ability, _) = property(&rows, &power.ability_property)?;
                let time = super::writing_connected::time(&ctx.frame, &rows, &power.at_tick)?;
                let scope = applicability(self, &power.scope, &rows)?;
                if matches!(scope, Applicability::Unspecified) {
                    anyhow::bail!("Which authored world or universe scope applies to this possession-dependent ability?");
                }
                Ok(
                    json!({"kind":"define_item_power","client_ref":RecordId::generate(&mut rand::rng()),"record":{"item":{"universe":u,"record":item},"holderPredicate":{"universe":u,"record":holder.identity.record_id},"powerPredicate":{"universe":u,"record":ability.identity.record_id},"value":super::writing_connected::fact_value(u,&rows,&ctx.frame,&power.value)?,"scope":{"context":ctx.frame.context,"applicability":scope},"validity":validity(&time,&power.lifetime)?}}),
                )
            };
            match build() {
                Ok(operation) => {
                    ops.push(operation);
                    result.additions.push(format!("Possession-dependent ability: {} grants {}; requires private contract review.", power.item, power.ability_property));
                }
                Err(error) => result.clarifications.push(error.to_string()),
            }
        }
        for boundary in &input.exhaustive_sets {
            let build = || -> anyhow::Result<Value> {
                let subject =
                    super::writing_connected::object(&rows, &boundary.subject, &ctx.frame)
                        .ok_or_else(|| {
                            anyhow::anyhow!(
                                "Which exact authored object is '{}'?",
                                boundary.subject
                            )
                        })?;
                let (_, property) = property(&rows, &boundary.property)?;
                if !matches!(property.value, ValueShape::EntityRef { .. }) {
                    anyhow::bail!("Exhaustive sets require an authored object-valued property.");
                }
                if boundary.scope == "unspecified" {
                    anyhow::bail!(
                        "Which authored world or universe scope applies to this exhaustive set?"
                    );
                }
                let members = boundary
                    .members
                    .iter()
                    .map(|member| {
                        super::writing_connected::object(&rows, member, &ctx.frame)
                            .map(|record| json!({"universe":u,"record":record}))
                            .ok_or_else(|| {
                                anyhow::anyhow!("Which exact authored member is '{member}'?")
                            })
                    })
                    .collect::<anyhow::Result<Vec<_>>>()?;
                let time = super::writing_connected::time(&ctx.frame, &rows, &boundary.at_tick)?;
                Ok(
                    json!({"kind":"set_completeness","client_ref":RecordId::generate(&mut rand::rng()),"record":{
                        "subject":{"universe":u,"record":subject},
                        "predicate":format!("{}:{}",property.namespace,property.key),"members":members,
                        "completeness":"objective_reality", "scope":{"context":ctx.frame.context,"applicability":applicability(self,&boundary.scope,&rows)?},
                        "validity":validity(&time,&boundary.lifetime)?
                    }}),
                )
            };
            match build() {
                Ok(operation) => {
                    ops.push(operation);
                    result.additions.push(format!("Authored exhaustive set: {} — {}; {} members; requires private contract review.",boundary.subject,boundary.property,boundary.members.len()));
                }
                Err(error) => result.clarifications.push(error.to_string()),
            }
        }
        let mut names = BTreeSet::new();
        for a in &input.actions {
            let mut build = || -> anyhow::Result<Value> {
                if !a.introduce || a.name.trim().is_empty() || !names.insert(("action",a.name.clone())) || rows.iter().any(|r|matches!(&r.payload,Payload::ActionDefinition(d)if d.key==a.name||d.labels.values().any(|v|v==&a.name))) {anyhow::bail!("Explicitly introduce a uniquely named action; existing contracts require an explicit definition revision.");}
                let requirements: Vec<_> = a
                    .requirements
                    .iter()
                    .map(|r| role_value(u, &rows, &ctx.frame, r))
                    .collect::<Result<_, _>>()?;
                let mut slots = vec![];
                for (position, e) in a.effects.iter().enumerate() {
                    let (p, d) = property(&rows, &e.property)?;
                    let change = match &e.change {
                        WritingEffectChange::Delta {
                            amount,
                            minimum,
                            maximum,
                            unit,
                        } => {
                            let bound_unit=match &d.value {
                                ValueShape::Integer if unit.is_none()=>None,
                                ValueShape::Quantity{unit:expected}=> {
                                    let actual=super::writing_units::unit(&rows,unit.as_ref().ok_or_else(||anyhow::anyhow!("Specify the quantity delta's authored unit."))?)?;
                                    if &actual!=expected {anyhow::bail!("Quantity delta unit does not match its authored property; no conversion is inferred.");}
                                    Some(actual)
                                },
                                _=>anyhow::bail!("Delta effects require integer magnitudes with the exact authored property unit; no conversion or rounding."),
                            };
                            json!({"kind":"delta","delta":integer(amount)?,"minimum":integer(minimum)?,"maximum":integer(maximum)?,"unit":bound_unit})
                        }
                        WritingEffectChange::Set { value, negated } => {
                            json!({"kind":"set","value":super::writing_connected::fact_value(u,&rows,&ctx.frame,value)?,"polarity":if *negated{"refutation"}else{"support"}})
                        }
                    };
                    let condition = if let Some(c) = &e.condition {
                        let mut c = role_value(u, &rows, &ctx.frame, c)?;
                        c["kind"] = json!("attribute_equals");
                        c
                    } else {
                        json!({"kind":"always"})
                    };
                    let lifetime = match &e.lifetime {
                        WritingEffectLifetime::UntilChanged => json!({"kind":"until_changed"}),
                        WritingEffectLifetime::Ticks { count } => {
                            json!({"kind":"ticks","count":integer(count)?})
                        }
                    };
                    slots.push(json!({"slot":format!("effect_{}",position+1),"order":position,"presence":if e.optional{"optional"}else{"required"},"target":{"role":e.role,"predicate":{"universe":u,"record":p.identity.record_id}},"condition":condition,"change":change,"lifetime":lifetime}));
                }
                let validity =
                    if a.at_tick.is_some() || !matches!(a.lifetime, FactLifetime::Unspecified) {
                        let t = super::writing_connected::time(&ctx.frame, &rows, &a.at_tick)?;
                        validity(&t, &a.lifetime)?
                    } else {
                        universe_domain::scope::Validity::Unspecified
                    };
                Ok(
                    json!({"kind":"define_action","client_ref":RecordId::generate(&mut rand::rng()),"record":{"namespace":"authoring","key":a.name,"labels":{},"requirements":requirements,"consequenceContract":{"kind":"action_consequences","slots":slots},"scope":{"context":ctx.frame.context,"applicability":applicability(self,&a.scope,&rows)?},"validity":validity}}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    result
                        .additions
                        .push(format!("New action contract: {}", a.name));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        // Reuse the finite declaration compiler only for explicitly replaced fields.
        for patch in &input.action_corrections {
            let build = || -> anyhow::Result<Value> {
                if patch.reason.trim().is_empty() {
                    anyhow::bail!("Give the reason for this action correction.");
                }
                if patch.requirements.is_none()
                    && patch.effects.is_none()
                    && patch.scope.is_none()
                    && patch.at_tick.is_none()
                    && patch.lifetime.is_none()
                {
                    anyhow::bail!(
                        "Specify the action fields to correct; omitted fields stay unchanged."
                    );
                }
                let found: Vec<_> = base
                    .iter()
                    .filter_map(|r| match &r.payload {
                        Payload::ActionDefinition(a)
                            if a.key == patch.name
                                || a.labels.values().any(|n| n == &patch.name) =>
                        {
                            Some((r, a))
                        }
                        _ => None,
                    })
                    .collect();
                let [(original, action)] = found.as_slice() else {
                    anyhow::bail!("Which exact authored action is '{}' ?", patch.name);
                };
                if patch.at_tick.is_some() != patch.lifetime.is_some() {
                    anyhow::bail!("An action validity correction requires an explicit tick and lifetime together.");
                }
                if patch.effects.is_some() && action.consequence_contract.is_none() {
                    anyhow::bail!("Legacy action without a declared consequence contract requires advanced review.");
                }
                if patch.effects.is_some()
                    && action.consequence_contract.as_ref().is_some_and(|c| {
                        c.slots.iter().enumerate().any(|(i, s)| {
                            s.slot != format!("effect_{}", i + 1) || usize::from(s.order) != i
                        })
                    })
                {
                    anyhow::bail!("Editing legacy effect slots/order requires advanced contract review; no authored slot metadata is discarded.");
                }
                let mut declaration = input.clone();
                declaration.actions = vec![WritingAction {
                    name: patch.name.clone(),
                    introduce: true,
                    requirements: patch.requirements.clone().unwrap_or_default(),
                    effects: patch.effects.clone().unwrap_or_default(),
                    scope: patch.scope.clone().unwrap_or_else(|| "unspecified".into()),
                    at_tick: patch.at_tick.clone(),
                    lifetime: patch.lifetime.clone().unwrap_or(FactLifetime::Unspecified),
                }];
                declaration.constraints.clear();
                declaration.knowledge_policies.clear();
                declaration.action_corrections.clear();
                declaration.definition_corrections.clear();
                declaration.property_corrections.clear();
                declaration.item_powers.clear();
                declaration.item_power_corrections.clear();
                let mut generated = vec![];
                let mut feedback = result.clone();
                feedback.clarifications.clear();
                let other: Vec<_> = rows
                    .iter()
                    .filter(|r| r.identity.record_id != original.identity.record_id)
                    .cloned()
                    .collect();
                self.writing_contracts(&declaration, ctx, &other, &mut generated, &mut feedback)?;
                if !feedback.clarifications.is_empty() {
                    anyhow::bail!("{}", feedback.clarifications.join(" "));
                }
                let mut replacement = serde_json::to_value(action)?;
                let built = &generated[0]["record"];
                if patch.requirements.is_some() {
                    replacement["requirements"] = built["requirements"].clone();
                }
                if patch.effects.is_some() {
                    replacement["consequenceContract"] = built["consequenceContract"].clone();
                }
                if patch.scope.is_some() {
                    replacement["scope"]["applicability"] = built["scope"]["applicability"].clone();
                }
                if patch.at_tick.is_some() {
                    replacement["validity"] = built["validity"].clone();
                }
                replacement["record_kind"] = json!("action_definition");
                Ok(
                    json!({"kind":"revise_definition","record":{"universe":u,"record":original.identity.record_id},"expected_version":original.record_version_id,"replacement":replacement}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    result.additions.push(format!(
                        "Action contract correction: {} — {}",
                        patch.name, patch.reason
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for patch in &input.definition_corrections {
            let build = || -> anyhow::Result<Value> {
                if patch.reason.trim().is_empty() {
                    anyhow::bail!("Give the reason for this ancestry/applicability correction.");
                }
                if patch.parent.is_none() && patch.scope.is_none() {
                    anyhow::bail!("Specify the ancestry or applicability correction; omitted fields stay unchanged.");
                }
                let found: Vec<_> = base
                    .iter()
                    .filter_map(|r| match &r.payload {
                        Payload::EntityType(d)
                            if d.key == patch.name
                                || d.name == patch.name
                                || d.labels.values().any(|n| n == &patch.name) =>
                        {
                            Some((r, d))
                        }
                        _ => None,
                    })
                    .collect();
                let [(original, d)] = found.as_slice() else {
                    anyhow::bail!("Which exact authored definition is '{}' ?", patch.name);
                };
                let mut replacement = (*d).clone();
                if let Some(parent) = &patch.parent {
                    replacement.parent = match parent {
                        WritingParent::Root => None,
                        WritingParent::Definition { name } => {
                            let parents:Vec<_>=rows.iter().filter(|r|matches!(&r.payload,Payload::EntityType(p)if p.key==*name||p.name==*name||p.labels.values().any(|n|n==name))).collect();
                            let [p] = parents.as_slice() else {
                                anyhow::bail!("Which exact parent definition is '{}' ?", name);
                            };
                            Some(p.identity.record_id.clone())
                        }
                    };
                    replacement.parent_resolution = if replacement.parent.is_some() {
                        universe_domain::records::ParentResolution::Resolved
                    } else {
                        universe_domain::records::ParentResolution::Root
                    };
                }
                if let Some(scope) = &patch.scope {
                    replacement.applicability = applicability(self, scope, &rows)?;
                }
                Ok(
                    json!({"kind":"revise_definition","record":{"universe":u,"record":original.identity.record_id},"expected_version":original.record_version_id,"replacement":Payload::EntityType(replacement)}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    result.additions.push(format!(
                        "Definition correction: {} — {}",
                        patch.name, patch.reason
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for policy in &input.knowledge_policies {
            let build = || -> anyhow::Result<Value> {
                let name = match policy {
                    WritingKnowledgePolicy::Knowledge { name, .. }
                    | WritingKnowledgePolicy::Channel { name, .. } => name,
                };
                if name.trim().is_empty() || rows.iter().any(|r|matches!(&r.payload,Payload::Rule(d)if d.key==*name||d.labels.values().any(|n|n==name))) {anyhow::bail!("Explicitly declare a uniquely named knowledge/communication policy; revisions require advanced review.");}
                let mut rule = json!({"namespace":"authoring","key":name,"labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":[],"expression":{"kind":"lit","value":true},"executable":true,"validity":{"kind":"unspecified"}});
                match policy {
                    WritingKnowledgePolicy::Knowledge { mode, .. } => {
                        rule["knowledgePolicy"] = json!({"context":ctx.frame.context,"mode":mode});
                        rule["capabilities"] = json!([crate::knowledge::CAPABILITY]);
                    }
                    WritingKnowledgePolicy::Channel {
                        channel,
                        forward_only,
                        minimum_delay,
                        maximum_delay,
                        ..
                    } => {
                        rule["channelChronology"] = json!({"channel":channel,"forwardOnly":forward_only,"minimumDelay":minimum_delay,"maximumDelay":maximum_delay});
                        rule["capabilities"] = json!([crate::communications::CAPABILITY]);
                    }
                }
                let r: Rule = serde_json::from_value(rule.clone())?;
                crate::knowledge::validate_rule(&r)?;
                crate::communications::validate_rule(&r)?;
                Ok(
                    json!({"kind":"define_rule","client_ref":RecordId::generate(&mut rand::rng()),"record":r}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    result.additions.push("Explicit knowledge/communication policy; separate author contract review required.".into());
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        for c in &input.constraints {
            let (name, key, scope) = match c {
                WritingConstraint::ResourceAccounting {
                    name,
                    property,
                    scope,
                }
                | WritingConstraint::NoOpposingEvidence {
                    name,
                    property,
                    scope,
                    ..
                } => (name, property, scope),
            };
            let mut build = || -> anyhow::Result<Value> {
                if name.trim().is_empty() || !names.insert(("constraint",name.clone())) || rows.iter().any(|r|matches!(&r.payload,Payload::Rule(d)if d.key==*name||d.labels.values().any(|v|v==name))) {anyhow::bail!("Introduce a uniquely named constraint; existing policies require explicit revision.");}
                let (_, p) = property(&rows, key)?;
                let predicate = format!("{}:{}", p.namespace, p.key);
                let (expression, capabilities, policy) = match c {
                    WritingConstraint::ResourceAccounting { .. } => {
                        if !matches!(p.value, ValueShape::Integer | ValueShape::Quantity { .. })
                            || p.multiplicity != Multiplicity::Single
                        {
                            anyhow::bail!("Resource accounting requires an explicitly authored single integer/quantity property.");
                        }
                        (
                            json!({"kind":"lit","value":true}),
                            vec!["resources.accounting.v1"],
                            "block_unless_exception",
                        )
                    }
                    WritingConstraint::NoOpposingEvidence { object, .. } => {
                        let object = super::writing_connected::object(&rows, object, &ctx.frame)
                            .ok_or_else(|| {
                                anyhow::anyhow!(
                                    "Which exact object is '{object}' for the constraint?"
                                )
                            })?;
                        (
                            json!({"kind":"no_opposing_evidence","subject":{"kind":"record","ref":{"universe":u,"record":object}},"predicate":predicate,"context":{"kind":"record","ref":ctx.frame.context}}),
                            vec!["opposing_evidence.v1"],
                            "always_block",
                        )
                    }
                };
                Ok(
                    json!({"kind":"define_rule","client_ref":RecordId::generate(&mut rand::rng()),"record":{"namespace":"authoring","key":name,"labels":{},"kind":"physical_constraint","commitPolicy":policy,"applicability":applicability(self,scope,&rows)?,"subjectTypes":[],"targetPredicates":[predicate],"expression":expression,"capabilities":capabilities,"executable":true,"validity":{"kind":"unspecified"}}}),
                )
            };
            match build() {
                Ok(op) => {
                    ops.push(op);
                    result.additions.push(format!(
                        "New authored constraint: {name}; use separate author contract review."
                    ));
                }
                Err(e) => result.clarifications.push(e.to_string()),
            }
        }
        Ok(())
    }
}

pub(super) fn validity(
    time: &universe_domain::temporal::TemporalExpression,
    lifetime: &FactLifetime,
) -> anyhow::Result<universe_domain::scope::Validity> {
    use universe_domain::scope::Validity;
    use universe_domain::temporal::{TemporalBound, TemporalExpression};
    match (lifetime, time) {
        (FactLifetime::Unspecified, _) => Ok(Validity::Instant { at: time.clone() }),
        (lifetime, TemporalExpression::Exact { calendar, value }) => {
            Ok(Validity::CalendarInterval {
                calendar: calendar.clone(),
                start: TemporalBound::Exact {
                    value: value.clone(),
                },
                end: match lifetime {
                    FactLifetime::Until { end_tick } => TemporalBound::Exact {
                        value: end_tick.clone(),
                    },
                    _ => TemporalBound::Unbounded,
                },
            })
        }
        _ => anyhow::bail!("What exact authored contract time/lifetime applies?"),
    }
}
pub(super) fn supported_policy(r: &Rule) -> bool {
    use universe_domain::expr::Expr;
    r.executable
        && r.kind == RuleKind::PhysicalConstraint
        && r.target_predicates.len() == 1
        && r.subject_types.is_empty()
        && r.knowledge_policy.is_none()
        && r.channel_chronology.is_none()
        && r.relation_cardinality.is_none()
        && (r.capabilities == ["resources.accounting.v1"]
            && r.commit_policy == CommitPolicy::BlockUnlessException
            && matches!(r.expression, Expr::Lit { value: true })
            || r.capabilities == ["opposing_evidence.v1"]
                && r.commit_policy == CommitPolicy::AlwaysBlock
                && matches!(&r.expression, Expr::NoOpposingEvidence {
                    subject: universe_domain::expr::Operand::Record { .. },
                    predicate,
                    context: universe_domain::expr::Operand::Record { .. }
                } if predicate == &r.target_predicates[0]))
}

pub(super) fn supported_knowledge_policy(r: &Rule) -> bool {
    (r.knowledge_policy.is_some() || r.channel_chronology.is_some())
        && crate::knowledge::validate_rule(r).is_ok()
        && crate::communications::validate_rule(r).is_ok()
        && r.relation_cardinality.is_none()
}
