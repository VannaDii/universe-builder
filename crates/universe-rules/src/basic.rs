//! Bounded, exact scalar and finite-collection evaluation. No missing-as-false.
use crate::evidence::Evidence;
use std::{cmp::Ordering, collections::BTreeMap};
use universe_domain::{
    expr::{Comparator, Expr, Operand, Quantifier},
    temporal::{TemporalExpression, TemporalRelation},
    value::Value,
};

fn truth(value: bool) -> Evidence {
    if value {
        Evidence::supported(vec![])
    } else {
        Evidence::refuted(vec![])
    }
}
fn number(value: &Value) -> Option<(i128, i128)> {
    match value {
        Value::Integer { digits } => Some((digits.parse().ok()?, 1)),
        Value::Decimal { digits } => {
            let (a, b) = digits.split_once('.').unwrap_or((digits, ""));
            let denominator = 10_i128.checked_pow(b.len().try_into().ok()?)?;
            Some((format!("{a}{b}").parse().ok()?, denominator))
        }
        Value::Rational {
            numerator,
            denominator,
        } => {
            let (n, d): (i128, i128) = (numerator.parse().ok()?, denominator.parse().ok()?);
            if d > 0 {
                Some((n, d))
            } else {
                None
            }
        }
        _ => None,
    }
}
fn ordering(left: &Value, right: &Value) -> Option<Ordering> {
    if let (Some((a, b)), Some((c, d))) = (number(left), number(right)) {
        return Some(a.checked_mul(d)?.cmp(&c.checked_mul(b)?));
    }
    match (left, right) {
        (Value::Text { text: a }, Value::Text { text: b }) => Some(a.cmp(b)),
        (Value::Boolean { value: a }, Value::Boolean { value: b }) => Some(a.cmp(b)),
        (Value::Quantity { value: a, unit: u }, Value::Quantity { value: b, unit: v })
            if u == v =>
        {
            ordering(a, b)
        }
        _ => None,
    }
}
pub fn compare(left: &Value, op: Comparator, right: &Value) -> Option<bool> {
    if matches!(left, Value::Range { .. }) || matches!(right, Value::Range { .. }) {
        return compare_ranges(left, op, right);
    }
    let order = ordering(left, right)?;
    Some(match op {
        Comparator::Eq => order == Ordering::Equal,
        Comparator::Neq => order != Ordering::Equal,
        Comparator::Lt => order == Ordering::Less,
        Comparator::LtEq => order != Ordering::Greater,
        Comparator::Gt => order == Ordering::Greater,
        Comparator::GtEq => order != Ordering::Less,
    })
}
fn compare_ranges(left: &Value, op: Comparator, right: &Value) -> Option<bool> {
    type Bounds<'a> = (
        &'a Value,
        &'a Value,
        bool,
        bool,
        Option<&'a universe_domain::ids::UnitId>,
    );
    fn bounds(v: &Value) -> Option<Bounds<'_>> {
        let b = match v {
            Value::Range {
                lower,
                upper,
                lower_inclusive,
                upper_inclusive,
                unit,
            } => (
                lower.as_ref(),
                upper.as_ref(),
                *lower_inclusive,
                *upper_inclusive,
                unit.as_ref(),
            ),
            Value::Quantity { value, unit } => {
                (value.as_ref(), value.as_ref(), true, true, Some(unit))
            }
            _ => (v, v, true, true, None),
        };
        number(b.0)?;
        number(b.1)?;
        match ordering(b.0, b.1)? {
            Ordering::Greater => None,
            Ordering::Equal if !b.2 || !b.3 => None,
            _ => Some(b),
        }
    }
    let (a, b, ai, bi, unit) = bounds(left)?;
    let (c, d, ci, di, other) = bounds(right)?;
    if unit != other {
        return None;
    }
    let bc = ordering(b, c)?;
    let ad = ordering(a, d)?;
    let disjoint = bc == Ordering::Less
        || ad == Ordering::Greater
        || (bc == Ordering::Equal && !(bi && ci))
        || (ad == Ordering::Equal && !(ai && di));
    match op {
        Comparator::Eq | Comparator::Neq => {
            let equal = if ordering(a, b)? == Ordering::Equal && ordering(c, d)? == Ordering::Equal
            {
                Some(ordering(a, c)? == Ordering::Equal)
            } else if disjoint {
                Some(false)
            } else {
                None
            }?;
            Some(if op == Comparator::Eq { equal } else { !equal })
        }
        Comparator::Lt => {
            if bc == Ordering::Less || (bc == Ordering::Equal && !(bi && ci)) {
                Some(true)
            } else if ad != Ordering::Less {
                Some(false)
            } else {
                None
            }
        }
        Comparator::LtEq => {
            if bc != Ordering::Greater {
                Some(true)
            } else if ad == Ordering::Greater || (ad == Ordering::Equal && !(ai && di)) {
                Some(false)
            } else {
                None
            }
        }
        Comparator::Gt => compare_ranges(right, Comparator::Lt, left),
        Comparator::GtEq => compare_ranges(right, Comparator::LtEq, left),
    }
}
fn operand(op: &Operand, vars: &BTreeMap<String, Value>) -> Option<Value> {
    match op {
        Operand::Value { value } => Some(value.clone()),
        Operand::Variable { name } => vars.get(name).cloned(),
        Operand::Record { record } => Some(Value::RecordRef {
            record: record.clone(),
        }),
        _ => None,
    }
}
fn items(value: Value) -> Option<Vec<Value>> {
    match value {
        Value::Set { items } => {
            let mut unique = std::collections::BTreeSet::new();
            Some(
                items
                    .into_iter()
                    .filter(|v| {
                        unique.insert(universe_domain::canonical::canonical_serde(v).to_bytes())
                    })
                    .collect(),
            )
        }
        Value::Sequence { items } => Some(items),
        _ => None,
    }
}
/// Calendar values here are exact integer ticks. Other calendar encodings require
/// a calendar adapter and remain unsupported, never lexically ordered.
pub fn temporal(
    left: &TemporalExpression,
    relation: TemporalRelation,
    right: &TemporalExpression,
) -> Option<bool> {
    crate::time::relation(left, relation, right)
}

pub fn evaluate(expr: &Expr, ctx: &crate::EvaluationContext<'_>) -> (Evidence, bool) {
    let mut budget = 10_000;
    eval(expr, &BTreeMap::new(), &mut budget, ctx)
}
fn eval(
    expr: &Expr,
    vars: &BTreeMap<String, Value>,
    budget: &mut usize,
    ctx: &crate::EvaluationContext<'_>,
) -> (Evidence, bool) {
    if *budget == 0 {
        return (Evidence::not_established(), false);
    }
    *budget -= 1;
    let result = match expr {
        Expr::NoOpposingEvidence {
            subject,
            predicate,
            context,
        } => (|| {
            use universe_domain::{
                records::Payload,
                scope::{Applicability, Validity},
            };
            let reference = |v| match v {
                Value::RecordRef { record } | Value::EntityRef { record } => Some(record),
                _ => None,
            };
            let subject = reference(operand(subject, vars)?)?;
            let context = reference(operand(context, vars)?)?;
            let frame = ctx.frame?;
            subject.resolve_namespace(&frame.universe).ok()?;
            context.resolve_namespace(&frame.universe).ok()?;
            let mut snapshot: BTreeMap<_, _> = ctx
                .base_snapshot
                .iter()
                .map(|r| (r.identity.record_id.clone(), r.clone()))
                .collect();
            for (id, next) in &ctx.candidate_changes {
                if let Some(r) = next {
                    snapshot.insert((*id).clone(), (*r).clone());
                } else {
                    snapshot.remove(*id);
                }
            }
            let definitions: Vec<_> = snapshot
                .values()
                .filter(|r| match &r.payload {
                    Payload::Property(p) => format!("{}:{}", p.namespace, p.key) == *predicate,
                    Payload::Relation(p) => format!("{}:{}", p.namespace, p.key) == *predicate,
                    _ => false,
                })
                .map(|r| r.identity.record_id.clone())
                .collect();
            if definitions.len() != 1
                || !snapshot.contains_key(&subject.record)
                || !snapshot
                    .get(&context.record)
                    .is_some_and(|r| matches!(r.payload, Payload::RepresentedContext(_)))
            {
                return None;
            }
            let props: std::collections::BTreeSet<_> = snapshot
                .values()
                .filter_map(|r| match &r.payload {
                    Payload::Proposition(p)
                        if p.subject.resolve_namespace(&frame.universe).ok()
                            == subject.resolve_namespace(&frame.universe).ok()
                            && p.context.resolve_namespace(&frame.universe).ok()
                                == context.resolve_namespace(&frame.universe).ok()
                            && p.predicate.record == definitions[0] =>
                    {
                        Some(r.identity.record_id.clone())
                    }
                    _ => None,
                })
                .collect();
            let records: Vec<_> = snapshot.values().cloned().collect();
            let mut complete = true;
            let mut exact_cell = std::collections::BTreeSet::new();
            snapshot.retain(|_, r| {
                let Payload::Assertion(a) = &r.payload else {
                    return true;
                };
                if !props.contains(&a.proposition.record) {
                    return false;
                }
                let world = match &a.scope.applicability {
                    Applicability::UniverseWide => Some(true),
                    Applicability::Worlds { world_ids } if world_ids.is_empty() => Some(false),
                    Applicability::Worlds { world_ids } => ctx.world_scope.as_ref().map(|ws| {
                        ws.iter().any(|r| {
                            world_ids.iter().any(|w| {
                                r.as_str().strip_prefix("rec_") == w.as_str().strip_prefix("wld_")
                            })
                        })
                    }),
                    _ => None,
                };
                let time = if a.validity == Validity::Unspecified {
                    Some(true)
                } else {
                    crate::events::applies(&a.validity, &frame.time, &records)
                };
                if world == Some(false) || time == Some(false) {
                    return false;
                }
                if world == Some(true) && time == Some(true) && a.scope.realm.is_none() {
                    exact_cell.insert(r.identity.record_id.clone());
                }
                true
            });
            if snapshot.len() > *budget {
                return None;
            }
            *budget -= snapshot.len();
            let scan = crate::opposing::detect(
                &frame.universe,
                &snapshot.into_values().collect::<Vec<_>>(),
                ctx.index.is_some(),
                *budget,
            )
            .ok()?;
            *budget = budget.saturating_sub(scan.comparisons);
            complete &= scan.complete
                && scan.pairs.iter().all(|p| {
                    exact_cell.contains(&p.support.assertion.identity.record_id)
                        && exact_cell.contains(&p.refutation.assertion.identity.record_id)
                });
            let sources = scan
                .pairs
                .iter()
                .flat_map(|p| [&p.support, &p.refutation])
                .flat_map(|c| {
                    std::iter::once(c.assertion.record_version_id.clone())
                        .chain(std::iter::once(c.proposition.record_version_id.clone()))
                        .chain(c.dependencies.iter().map(|r| r.record_version_id.clone()))
                })
                .collect();
            if scan.pairs.iter().any(|p| {
                p.definite()
                    && exact_cell.contains(&p.support.assertion.identity.record_id)
                    && exact_cell.contains(&p.refutation.assertion.identity.record_id)
            }) {
                Some((Evidence::refuted(sources), complete))
            } else if complete {
                Some((Evidence::supported(sources), true))
            } else {
                Some((Evidence::not_established(), false))
            }
        })(),
        Expr::Attitude {
            holder,
            proposition,
            attitude,
        } => {
            let mut evidence = Evidence::not_established();
            let mut complete = true;
            if ctx.base_snapshot.len() > *budget {
                return (evidence, false);
            }
            *budget -= ctx.base_snapshot.len();
            if !ctx.base_snapshot.iter().any(|r|r.identity.record_id==proposition.record && matches!(&r.payload,universe_domain::records::Payload::Proposition(p) if ctx.frame.is_some_and(|f|p.context==f.context))){return (evidence,false);}
            for r in ctx.base_snapshot {
                if let universe_domain::records::Payload::EpistemicAttitude(a) = &r.payload {
                    if &a.holder == holder
                        && &a.proposition == proposition
                        && &a.attitude == attitude
                    {
                        if ctx.frame.is_some_and(|f| {
                            matches!(f.time, universe_domain::frame::FrameTime::Timeless)
                        }) && a.validity != universe_domain::scope::Validity::Unspecified
                        {
                            complete = false;
                            continue;
                        }
                        match ctx.frame.and_then(|f| {
                            crate::events::applies(&a.validity, &f.time, ctx.base_snapshot)
                        }) {
                            Some(true) => {
                                evidence = evidence
                                    .any(Evidence::supported(vec![r.record_version_id.clone()]))
                            }
                            Some(false) => {}
                            None => complete = false,
                        }
                    }
                }
            }
            Some((evidence, complete))
        }
        Expr::Lit { value } => Some((truth(*value), true)),
        Expr::Not { expr } => {
            let (e, c) = eval(expr, vars, budget, ctx);
            Some((e.negate(), c))
        }
        Expr::All { exprs } | Expr::Any { exprs } => {
            let all = matches!(expr, Expr::All { .. });
            Some(exprs.iter().fold((truth(all), true), |(acc, complete), e| {
                let (v, c) = eval(e, vars, budget, ctx);
                (if all { acc.all(v) } else { acc.any(v) }, complete && c)
            }))
        }
        Expr::Compare { left, op, right } => (|| {
            Some((
                truth(compare(&operand(left, vars)?, *op, &operand(right, vars)?)?),
                true,
            ))
        })(),
        Expr::Temporal {
            left,
            relation,
            right,
        } => (|| {
            let (Value::Temporal { temporal: a }, Value::Temporal { temporal: b }) =
                (operand(left, vars)?, operand(right, vars)?)
            else {
                return None;
            };
            Some((truth(temporal(&a, *relation, &b)?), true))
        })(),
        Expr::Membership {
            element,
            collection,
            complete,
        } => (|| {
            let element = operand(element, vars)?;
            let values = items(operand(collection, vars)?)?;
            if values.len() > *budget {
                return None;
            }
            *budget -= values.len();
            let found = values
                .iter()
                .any(|v| v == &element || compare(v, Comparator::Eq, &element) == Some(true));
            Some((
                if found {
                    truth(true)
                } else if *complete == Some(true) {
                    truth(false)
                } else {
                    Evidence::not_established()
                },
                true,
            ))
        })(),
        Expr::Cardinality {
            collection,
            op,
            count,
            complete,
        } => (|| {
            let values = items(operand(collection, vars)?)?;
            if values.len() > *budget {
                return None;
            }
            *budget -= values.len();
            let actual = Value::Integer {
                digits: values.len().to_string(),
            };
            let yes = compare(&actual, *op, count)?;
            let monotone = matches!(op, Comparator::Gt | Comparator::GtEq) && yes
                || matches!(op, Comparator::Lt | Comparator::LtEq) && !yes;
            Some((
                if *complete == Some(true) || monotone {
                    truth(yes)
                } else {
                    Evidence::not_established()
                },
                true,
            ))
        })(),
        Expr::Quantify {
            variable,
            over,
            complete,
            quantifier,
            body,
        } => (|| {
            let values = items(operand(over, vars)?)?;
            if values.len() > *budget {
                return None;
            }
            let all = matches!(quantifier, Quantifier::ForAll);
            let mut acc = truth(all);
            let mut coverage = true;
            for value in values {
                let mut bound = vars.clone();
                bound.insert(variable.clone(), value);
                let (e, c) = eval(body, &bound, budget, ctx);
                coverage &= c;
                acc = if all { acc.all(e) } else { acc.any(e) };
            }
            if !complete {
                if all {
                    acc.support = crate::evidence::EvidenceBit::absent();
                } else {
                    acc.refutation = crate::evidence::EvidenceBit::absent();
                }
            }
            Some((acc, coverage))
        })(),
        Expr::Claim {
            subject,
            predicate,
            roles,
            value,
            polarity,
            context,
        } => claim(
            subject,
            predicate,
            roles,
            value.as_ref(),
            context.as_ref(),
            vars,
            ctx,
            budget,
            true,
        )
        .map(|(e, c)| {
            (
                if *polarity == universe_domain::scope::Polarity::Refutation {
                    e.negate()
                } else {
                    e
                },
                c,
            )
        }),
        Expr::NegatedClaim {
            subject,
            predicate,
            roles,
            value,
            context,
        } => claim(
            subject,
            predicate,
            roles,
            value.as_ref(),
            context.as_ref(),
            vars,
            ctx,
            budget,
            true,
        )
        .map(|(e, c)| (e.negate(), c)),
        Expr::Existence {
            subject,
            predicate,
            roles,
            value,
            context,
        } => claim(
            subject,
            predicate,
            roles,
            value.as_ref(),
            context.as_ref(),
            vars,
            ctx,
            budget,
            true,
        )
        .map(|(mut e, c)| {
            e.refutation = crate::evidence::EvidenceBit::absent();
            (e, c)
        }),
        Expr::RoleHolds {
            subject,
            predicate,
            role,
            participant,
        } => claim(
            subject,
            predicate,
            &[(role.clone(), participant.clone())],
            None,
            None,
            vars,
            ctx,
            budget,
            false,
        )
        .map(|(mut e, c)| {
            e.refutation = crate::evidence::EvidenceBit::absent();
            (e, c)
        }),
    };
    result.unwrap_or((Evidence::not_established(), false))
}

#[allow(clippy::too_many_arguments)]
fn claim(
    subject: &Operand,
    predicate: &str,
    roles: &[(String, Operand)],
    value: Option<&Operand>,
    context: Option<&Operand>,
    vars: &BTreeMap<String, Value>,
    ctx: &crate::EvaluationContext<'_>,
    budget: &mut usize,
    exact_roles: bool,
) -> Option<(Evidence, bool)> {
    use universe_domain::{
        records::Payload,
        scope::{Applicability, Polarity, Precision},
        value::RecordRef,
    };
    fn reference(v: Value) -> Option<RecordRef> {
        match v {
            Value::RecordRef { record } | Value::EntityRef { record } => Some(record),
            _ => None,
        }
    }
    let subject = reference(operand(subject, vars)?)?;
    let context = if let Some(op) = context {
        reference(operand(op, vars)?)?
    } else {
        ctx.frame?.context.clone()
    };
    let frame = ctx.frame?;
    subject.resolve_namespace(&frame.universe).ok()?;
    context.resolve_namespace(&frame.universe).ok()?;
    let expected = value.map(|v| operand(v, vars)).transpose_option()?;
    let roles: Option<Vec<_>> = roles
        .iter()
        .map(|(key, op)| Some((key.clone(), reference(operand(op, vars)?)?)))
        .collect();
    let roles = roles?;
    let mut all: BTreeMap<_, _> = ctx
        .base_snapshot
        .iter()
        .map(|r| (&r.identity.record_id, r))
        .collect();
    for (id, next) in &ctx.candidate_changes {
        if let Some(r) = next {
            all.insert(id, r);
        } else {
            all.remove(id);
        }
    }
    let all_records: Vec<_> = all.values().map(|r| (*r).clone()).collect();
    let inherits = all
        .get(&subject.record)
        .is_some_and(|r| matches!(&r.payload, Payload::Entity(_)));
    let chain = crate::definitions::ancestry(&subject.record, &all_records);
    let indexed = ctx
        .index
        .filter(|_| ctx.candidate_changes.is_empty() && !inherits)
        .map(|i| i.claim(&subject, predicate, &context));
    let selected: Vec<_> = indexed.unwrap_or_else(|| all.values().copied().collect());
    let snapshot: BTreeMap<_, _> = selected
        .into_iter()
        .map(|r| (&r.identity.record_id, r))
        .collect();
    if snapshot.len() > *budget {
        return None;
    }
    *budget -= snapshot.len();
    let definitions: Vec<_> = snapshot
        .values()
        .filter(|r| match &r.payload {
            Payload::Property(p) => format!("{}:{}", p.namespace, p.key) == predicate,
            Payload::Relation(p) => format!("{}:{}", p.namespace, p.key) == predicate,
            _ => false,
        })
        .map(|r| r.identity.record_id.clone())
        .collect();
    if definitions.len() != 1 {
        return None;
    }
    let propositions: Vec<_> = snapshot
        .values()
        .filter(|r| {
            if let Payload::Proposition(p) = &r.payload {
                (p.subject == subject || inherits && chain.types.contains(&p.subject.record))
                    && p.context == context
                    && p.predicate.record == definitions[0]
                    && (!exact_roles || p.roles.len() == roles.len())
                    && roles.iter().all(|(key, participant)| {
                        p.roles
                            .iter()
                            .any(|r| r.role == *key && r.participant == *participant)
                    })
            } else {
                false
            }
        })
        .map(|r| r.identity.record_id.clone())
        .collect();
    let mut evidence = Evidence::not_established();
    let mut complete = true;
    let property = snapshot.values().find_map(|r| match &r.payload {
        Payload::Property(p) if r.identity.record_id == definitions[0] => Some(p),
        _ => None,
    });
    if let Some(property) = property.filter(|p| !p.subject_types.is_empty()) {
        match crate::definitions::matches(
            &subject.record,
            &property.subject_types,
            &all_records,
            Some(ctx.world_scope.as_deref().unwrap_or(&[])),
        ) {
            Some(false) => return Some((Evidence::not_established(), true)),
            None => complete = false,
            Some(true) => {}
        }
    }
    if inherits && !chain.complete && all.values().any(|r| {
        let Payload::Assertion(a) = &r.payload else { return false; };
        a.attribute_mode == universe_domain::records::AttributeMode::Shared
            && a.scope.context == context
            && crate::definitions::world_applies(&a.scope.applicability, ctx.world_scope.as_deref().unwrap_or(&[])) != Some(false)
            && ctx.frame.and_then(|f| crate::events::applies(&a.validity, &f.time, &all_records)) != Some(false)
            && matches!(all.get(&a.proposition.record).map(|r| &r.payload), Some(Payload::Proposition(p)) if p.context == context && p.predicate.record == definitions[0] && matches!(all.get(&p.subject.record).map(|r| &r.payload), Some(Payload::EntityType(_))))
    }) { complete = false; }
    let has_shared = snapshot.values().any(|r| {
        let Payload::Assertion(a) = &r.payload else {
            return false;
        };
        let Some(prop) = snapshot.get(&a.proposition.record) else {
            return false;
        };
        let Payload::Proposition(p) = &prop.payload else {
            return false;
        };
        a.attribute_mode == universe_domain::records::AttributeMode::Shared
            && p.subject != subject
            && propositions.contains(&a.proposition.record)
            && a.scope.context == context
            && a.scope.realm.is_none()
            && crate::definitions::world_applies(
                &a.scope.applicability,
                ctx.world_scope.as_deref().unwrap_or(&[]),
            ) == Some(true)
            && ctx
                .frame
                .and_then(|f| crate::events::applies(&a.validity, &f.time, &all_records))
                == Some(true)
            && crate::definitions::matches(
                &subject.record,
                std::slice::from_ref(&p.subject.record),
                &all_records,
                Some(ctx.world_scope.as_deref().unwrap_or(&[])),
            ) == Some(true)
    });
    for r in snapshot.values() {
        let Payload::Assertion(a) = &r.payload else {
            continue;
        };
        if !propositions.contains(&a.proposition.record) || a.scope.context != context {
            continue;
        }
        let Payload::Proposition(p) = &snapshot.get(&a.proposition.record)?.payload else {
            continue;
        };
        let inherited = p.subject != subject;
        if inherited && a.attribute_mode != universe_domain::records::AttributeMode::Shared {
            continue;
        }
        let value_matches = match (&expected, &p.value) {
            (None, _) => true,
            (Some(a), Some(b)) => a == b || compare(a, Comparator::Eq, b) == Some(true),
            _ => false,
        };
        if !value_matches
            && !((inherited || inherits && has_shared)
                && property.is_some_and(|p| {
                    p.multiplicity == universe_domain::records::Multiplicity::Single
                }))
        {
            continue;
        }
        let world = crate::definitions::world_applies(
            &a.scope.applicability,
            ctx.world_scope.as_deref().unwrap_or(&[]),
        );
        let validity = ctx
            .frame
            .and_then(|f| crate::events::applies(&a.validity, &f.time, &all_records));
        // Proven disjointness makes uncertainty in another dimension irrelevant.
        if world == Some(false) || validity == Some(false) {
            continue;
        }
        let definition_subject = all
            .get(&p.subject.record)
            .is_some_and(|r| matches!(r.payload, Payload::EntityType(_)));
        if inherited || definition_subject {
            match crate::definitions::matches(
                if inherited {
                    &subject.record
                } else {
                    &p.subject.record
                },
                std::slice::from_ref(&p.subject.record),
                &all_records,
                Some(ctx.world_scope.as_deref().unwrap_or(&[])),
            ) {
                Some(false) => continue,
                None => {
                    complete = false;
                    continue;
                }
                Some(true) => {}
            }
        }
        if world.is_none() || a.scope.realm.is_some() {
            complete = false;
            continue;
        }
        // All-validities queries cannot collapse temporal evidence into one fact.
        let timeless_temporal = ctx
            .frame
            .is_some_and(|f| matches!(f.time, universe_domain::frame::FrameTime::Timeless))
            && !matches!(a.validity, universe_domain::scope::Validity::Unspecified);
        if a.precision != Precision::Exact
            || !a.alternatives.is_empty()
            || validity.is_none()
            || timeless_temporal
        {
            complete = false;
            continue;
        }
        let mut sources = vec![r.record_version_id.clone()];
        if inherited {
            sources.push(
                snapshot
                    .get(&a.proposition.record)?
                    .record_version_id
                    .clone(),
            );
            if let Some(owner) = all.get(&subject.record) {
                sources.push(owner.record_version_id.clone());
            }
            sources.extend(
                chain
                    .types
                    .iter()
                    .filter_map(|id| all.get(id).map(|r| r.record_version_id.clone())),
            );
        }
        let bit = crate::evidence::EvidenceBit::with_sources(sources);
        match (a.polarity, value_matches) {
            (Polarity::Support, true) => evidence.support = evidence.support.or(bit),
            (Polarity::Refutation, true) | (Polarity::Support, false) => {
                evidence.refutation = evidence.refutation.or(bit)
            }
            _ => {}
        }
    }
    // Possession-derived attributes use the same exact owner/time/evidence
    // resolver as state queries. Indexed direct claims do not discard their
    // item, custody or grant dependencies.
    let has_powers =
        ctx.index
            .filter(|_| ctx.candidate_changes.is_empty())
            .map_or_else(
                || {
                    ctx.base_snapshot
                        .iter()
                        .any(|r| matches!(r.payload, Payload::ItemPower(_)))
                        || ctx.candidate_changes.iter().any(|(_, r)| {
                            r.is_some_and(|r| matches!(r.payload, Payload::ItemPower(_)))
                        })
                },
                |i| i.has_powers(),
            );
    if roles.is_empty() && has_powers {
        if ctx.base_snapshot.len() > *budget {
            return None;
        }
        *budget -= ctx.base_snapshot.len();
        let mut all: BTreeMap<_, _> = ctx
            .base_snapshot
            .iter()
            .map(|r| (r.identity.record_id.clone(), r.clone()))
            .collect();
        for (id, next) in &ctx.candidate_changes {
            if let Some(r) = next {
                all.insert((*id).clone(), (*r).clone());
            } else {
                all.remove(*id);
            }
        }
        let all: Vec<_> = all.into_values().collect();
        let worlds: Vec<_> = ctx
            .world_scope
            .as_ref()
            .into_iter()
            .flatten()
            .filter_map(|r| {
                universe_domain::ids::WorldId::parse(&r.as_str().replacen("rec_", "wld_", 1)).ok()
            })
            .collect();
        let queries: Vec<_> = if worlds.is_empty() {
            vec![None]
        } else {
            worlds.iter().map(Some).collect()
        };
        for world in queries {
            let derived = crate::powers::derive(
                &all,
                std::slice::from_ref(&subject.record),
                &definitions,
                &context,
                &ctx.frame?.time,
                world,
            )
            .ok()?;
            for fact in derived {
                if fact.subject != subject {
                    continue;
                }
                let value_matches = expected.as_ref().is_none_or(|v| *v == fact.value);
                let bit = crate::evidence::EvidenceBit::with_sources(fact.evidence);
                if value_matches {
                    evidence.support = evidence.support.or(bit);
                } else if has_shared
                    && property.is_some_and(|p| {
                        p.multiplicity == universe_domain::records::Multiplicity::Single
                    })
                {
                    // A scoped indirect grant cannot silently override or be
                    // discarded in favor of an incompatible shared definition.
                    evidence.refutation = evidence.refutation.or(bit);
                }
            }
        }
    }
    // Closed membership is authored evidence, not negation by failed search.
    // Only objective, exact, currently applicable declarations can refute a
    // member (or establish that an explicitly empty collection has none).
    for r in snapshot.values() {
        let Payload::Completeness(c) = &r.payload else {
            continue;
        };
        if c.subject != subject
            || c.predicate != predicate
            || c.scope.context != context
            || c.completeness != universe_domain::records::CompletenessKind::ObjectiveReality
            || !roles.is_empty()
            || c.scope.realm.is_some()
        {
            continue;
        }
        let applies = match &c.scope.applicability {
            Applicability::UniverseWide => true,
            Applicability::Worlds { world_ids } => ctx.world_scope.as_ref().is_some_and(|scope| {
                scope.len() == 1
                    && world_ids.iter().any(|w| {
                        scope[0].as_str().strip_prefix("rec_") == w.as_str().strip_prefix("wld_")
                    })
            }),
            _ => false,
        };
        if !applies {
            continue;
        }
        let time = &ctx.frame?.time;
        if matches!(time, universe_domain::frame::FrameTime::Timeless)
            && c.validity != universe_domain::scope::Validity::Unspecified
        {
            continue;
        }
        if crate::events::applies(&c.validity, time, ctx.base_snapshot) != Some(true) {
            continue;
        }
        let absent = match &expected {
            Some(Value::RecordRef { record } | Value::EntityRef { record }) => {
                !c.members.contains(record)
            }
            None => c.members.is_empty(),
            _ => false,
        };
        if absent {
            evidence.refutation =
                evidence
                    .refutation
                    .or(crate::evidence::EvidenceBit::with_source(
                        r.record_version_id.clone(),
                    ));
        }
    }
    Some((evidence, complete))
}
trait TransposeOption<T> {
    fn transpose_option(self) -> Option<Option<T>>;
}
impl<T> TransposeOption<T> for Option<Option<T>> {
    fn transpose_option(self) -> Option<Option<T>> {
        match self {
            None => Some(None),
            Some(Some(v)) => Some(Some(v)),
            Some(None) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{EvaluationContext, EvidenceOutcome};
    use universe_domain::temporal::TemporalBound;
    fn val(value: Value) -> Operand {
        Operand::Value { value }
    }
    fn int(n: &str) -> Value {
        Value::Integer { digits: n.into() }
    }
    fn run(e: Expr) -> (Evidence, bool) {
        evaluate(
            &e,
            &EvaluationContext {
                frame: None,
                base_snapshot: &[],
                candidate_changes: vec![],
                index: None,
                world_scope: None,
            },
        )
    }
    #[test]
    fn exact_comparison_avoids_float_rounding_and_reports_overflow() {
        assert_eq!(
            run(Expr::Compare {
                left: val(int("9007199254740993")),
                op: Comparator::Gt,
                right: val(int("9007199254740992"))
            })
            .0
            .outcome(),
            EvidenceOutcome::Supported
        );
        assert_eq!(
            run(Expr::Compare {
                left: val(Value::Decimal {
                    digits: "0.5".into()
                }),
                op: Comparator::Eq,
                right: val(Value::Rational {
                    numerator: "1".into(),
                    denominator: "2".into()
                })
            })
            .0
            .outcome(),
            EvidenceOutcome::Supported
        );
        assert!(
            !run(Expr::Compare {
                left: val(int("999999999999999999999999999999999999999999999")),
                op: Comparator::Gt,
                right: val(int("1"))
            })
            .1
        );
    }
    #[test]
    fn incomplete_collections_cannot_establish_negative_membership_or_exact_count() {
        let collection = val(Value::Set {
            items: vec![int("1")],
        });
        assert_eq!(
            run(Expr::Membership {
                element: val(int("2")),
                collection: collection.clone(),
                complete: None
            })
            .0
            .outcome(),
            EvidenceOutcome::NotEstablished
        );
        assert_eq!(
            run(Expr::Membership {
                element: val(int("2")),
                collection: collection.clone(),
                complete: Some(true)
            })
            .0
            .outcome(),
            EvidenceOutcome::Refuted
        );
        assert_eq!(
            run(Expr::Cardinality {
                collection: collection.clone(),
                op: Comparator::Eq,
                count: int("1"),
                complete: None
            })
            .0
            .outcome(),
            EvidenceOutcome::NotEstablished
        );
        assert_eq!(
            run(Expr::Cardinality {
                collection,
                op: Comparator::GtEq,
                count: int("1"),
                complete: None
            })
            .0
            .outcome(),
            EvidenceOutcome::Supported
        );
    }
    #[test]
    fn quantifiers_preserve_open_domain_and_variable_binding() {
        let expression = |complete, quantifier| Expr::Quantify {
            variable: "x".into(),
            over: val(Value::Sequence {
                items: vec![int("2"), int("3")],
            }),
            complete,
            quantifier,
            body: Box::new(Expr::Compare {
                left: Operand::Variable { name: "x".into() },
                op: Comparator::Gt,
                right: val(int("1")),
            }),
        };
        assert_eq!(
            run(expression(true, Quantifier::ForAll)).0.outcome(),
            EvidenceOutcome::Supported
        );
        assert_eq!(
            run(expression(false, Quantifier::ForAll)).0.outcome(),
            EvidenceOutcome::NotEstablished
        );
        assert_eq!(
            run(expression(false, Quantifier::Exists)).0.outcome(),
            EvidenceOutcome::Supported
        );
    }
    #[test]
    fn temporal_boundaries_are_half_open_and_never_cross_calendars() {
        use universe_domain::ids::CalendarId;
        let calendar = CalendarId::parse("cal_000000000000000000000001").unwrap();
        let interval = TemporalExpression::Interval {
            calendar: calendar.clone(),
            start: TemporalBound::Exact { value: "1".into() },
            end: TemporalBound::Exact { value: "3".into() },
        };
        let point = TemporalExpression::Exact {
            calendar: calendar.clone(),
            value: "3".into(),
        };
        assert_eq!(
            temporal(&interval, TemporalRelation::Overlaps, &point),
            Some(false)
        );
        assert_eq!(
            temporal(&point, TemporalRelation::During, &interval),
            Some(false)
        );
        let other = TemporalExpression::Exact {
            calendar: CalendarId::parse("cal_000000000000000000000002").unwrap(),
            value: "3".into(),
        };
        assert_eq!(
            temporal(&point, TemporalRelation::Simultaneous, &other),
            None
        );
        let unknown = TemporalExpression::Interval {
            calendar,
            start: TemporalBound::Unknown,
            end: TemporalBound::Unbounded,
        };
        assert_eq!(temporal(&point, TemporalRelation::During, &unknown), None);
    }
    #[test]
    fn nested_finite_evaluation_stops_at_the_shared_work_budget() {
        let items = vec![int("1"); 200];
        let inner = Expr::Quantify {
            variable: "y".into(),
            over: val(Value::Sequence {
                items: items.clone(),
            }),
            complete: true,
            quantifier: Quantifier::ForAll,
            body: Box::new(Expr::Lit { value: true }),
        };
        let outer = Expr::Quantify {
            variable: "x".into(),
            over: val(Value::Sequence { items }),
            complete: true,
            quantifier: Quantifier::ForAll,
            body: Box::new(inner),
        };
        assert!(!run(outer).1);
    }
}
