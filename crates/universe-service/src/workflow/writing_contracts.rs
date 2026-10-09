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
fn applicability(
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
        rows: &[&RecordVersion],
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
            let shape = match d.value_type {
                PlainPropertyType::Text => json!({"kind":"text"}),
                PlainPropertyType::Boolean => json!({"kind":"boolean"}),
                PlainPropertyType::Integer => json!({"kind":"integer"}),
                PlainPropertyType::Decimal => json!({"kind":"decimal"}),
                PlainPropertyType::Object => json!({"kind":"entity_ref","subject_types":[]}),
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
        if input.actions.is_empty() && input.constraints.is_empty() {
            return Ok(());
        }
        let rows =
            super::writing_connected::candidate_records(self.kernel.universe(), ctx, base, ops)?;
        let u = self.kernel.universe();
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
                        } => {
                            if d.value != ValueShape::Integer {
                                anyhow::bail!("Plain delta effects require an authored integer property; units/quantities need advanced explicit contracts.");
                            }
                            json!({"kind":"delta","delta":integer(amount)?,"minimum":integer(minimum)?,"maximum":integer(maximum)?,"unit":null})
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
                        if p.value != ValueShape::Integer || p.multiplicity != Multiplicity::Single
                        {
                            anyhow::bail!("Resource accounting requires an explicitly authored single integer property.");
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

fn validity(
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
