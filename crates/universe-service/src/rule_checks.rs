//! Finite rule evaluation partitions exact validity at every evidence boundary.
//! No wall time, sampled approximation, or cross-calendar conversion is used.
use std::collections::BTreeSet;
use universe_domain::{
    frame::FrameTime,
    ids::*,
    records::*,
    scope::{Applicability, Validity},
    temporal::{TemporalBound, TemporalExpression},
    Frame,
};
use universe_rules::{EvaluationContext, EvaluationCoverage, Evidence, EvidenceOutcome};

fn subset(child: &Applicability, parent: &Applicability) -> bool {
    match (child, parent) {
        (
            Applicability::UniverseWide | Applicability::Worlds { .. },
            Applicability::UniverseWide,
        ) => true,
        (Applicability::Worlds { world_ids: a }, Applicability::Worlds { world_ids: b }) => {
            !a.is_empty() && a.iter().all(|w| b.contains(w))
        }
        _ => false,
    }
}
pub fn valid_exception(e: &Exception, records: &[RecordVersion]) -> bool {
    let Some(target) = records.iter().find(|r| {
        r.identity.record_id == e.rule.record
            && e.rule_version.as_ref() == Some(&r.record_version_id)
    }) else {
        return false;
    };
    let (scope, validity, context, realm) = match &target.payload {
        Payload::Rule(r) if r.commit_policy == CommitPolicy::BlockUnlessException => {
            (&r.applicability, &r.validity, None, None)
        }
        Payload::Boundary(b) => (
            &b.scope.applicability,
            &b.validity,
            Some(&b.scope.context),
            b.scope.realm.as_ref(),
        ),
        _ => return false,
    };
    let contained = match (&e.validity, validity) {
        (Validity::Unspecified, Validity::Unspecified) => true,
        (_, Validity::Unspecified) => universe_rules::time::expression(&e.validity).is_some(),
        (a, b) => universe_rules::time::expression(a)
            .zip(universe_rules::time::expression(b))
            .is_some_and(|(a, b)| {
                universe_rules::time::relation(
                    &a,
                    universe_domain::temporal::TemporalRelation::During,
                    &b,
                ) == Some(true)
            }),
    };
    subset(&e.scope.applicability, scope) && contained && e.scope.realm.as_ref() == realm
        && context.is_none_or(|c| c == &e.scope.context) && !e.rationale.trim().is_empty()
        && records.iter().any(|r| r.identity.record_id == e.authorizing_decision.record && matches!(&r.payload, Payload::IssueDecision(d) if d.mode == IssueDecisionMode::Accept && d.scope == e.rule.record.as_str() && !d.rationale.trim().is_empty()))
}
pub fn exception_at(
    e: &Exception,
    target: &RecordVersion,
    frame: &Frame,
    worlds: &[RecordId],
    records: &[RecordVersion],
) -> bool {
    e.rule.record == target.identity.record_id
        && e.scope.context == frame.context
        && valid_exception(e, records)
        && match &e.scope.applicability {
            Applicability::UniverseWide => true,
            Applicability::Worlds { world_ids } => {
                !worlds.is_empty()
                    && worlds.iter().all(|r| {
                        world_ids.iter().any(|w| {
                            r.as_str().strip_prefix("rec_") == w.as_str().strip_prefix("wld_")
                        })
                    })
            }
            _ => false,
        }
        && if matches!(frame.time, FrameTime::Timeless) {
            e.validity == Validity::Unspecified
        } else {
            e.validity == Validity::Unspecified
                || universe_rules::events::applies(&e.validity, &frame.time, records) == Some(true)
        }
}
fn exact_bound(b: &TemporalBound, start: bool) -> Option<i128> {
    match b {
        TemporalBound::Exact { value } => value
            .parse::<i128>()
            .ok()
            .filter(|v| *v > i128::MIN && *v < i128::MAX),
        TemporalBound::Unbounded => Some(if start { i128::MIN + 1 } else { i128::MAX }),
        _ => None,
    }
}
/// On the integer clock, evidence is constant between successive boundary
/// coordinates. Include the tick after a point assertion as well as the point.
pub(crate) fn frames(
    validity: &Validity,
    records: &[RecordVersion],
    base: &Frame,
) -> Option<Vec<Frame>> {
    if *validity == Validity::Unspecified {
        return Some(vec![base.clone()]);
    }
    let (calendar, start, end) = match validity {
        Validity::Instant {
            at: TemporalExpression::Exact { calendar, value },
        } => {
            let at = value.parse::<i128>().ok()?;
            (calendar, at, at.checked_add(1)?)
        }
        Validity::CalendarInterval {
            calendar,
            start,
            end,
        } => (
            calendar,
            exact_bound(start, true)?,
            exact_bound(end, false)?,
        ),
        _ => return None,
    };
    if start >= end || start == i128::MIN {
        return None;
    }
    let mut points = BTreeSet::from([start]);
    for r in records {
        let v = match &r.payload {
            Payload::Assertion(a) => &a.validity,
            Payload::EpistemicAttitude(a) => &a.validity,
            Payload::Completeness(c) => &c.validity,
            Payload::Exception(e) => &e.validity,
            _ => continue,
        };
        match v {
            Validity::CalendarInterval {
                calendar: c,
                start: a,
                end: b,
            } if c == calendar => {
                for n in [exact_bound(a, true)?, exact_bound(b, false)?] {
                    if start <= n && n < end {
                        points.insert(n);
                    }
                }
            }
            Validity::Instant {
                at: TemporalExpression::Exact { calendar: c, value },
            } if c == calendar => {
                let n: i128 = value.parse().ok()?;
                for n in [n, n.checked_add(1)?] {
                    if start <= n && n < end {
                        points.insert(n);
                    }
                }
            }
            _ => {}
        }
        if points.len() > 1000 {
            return None;
        }
    }
    Some(
        points
            .into_iter()
            .map(|point| {
                let mut f = base.clone();
                f.time = FrameTime::At {
                    time: TemporalExpression::Exact {
                        calendar: calendar.clone(),
                        value: point.to_string(),
                    },
                };
                f
            })
            .collect(),
    )
}
// Scope the temporal partition to operands, rather than unrelated assertions.
// Variable subjects remain conservative; finite quantification is evaluated by
// the expression evaluator, without using target-predicate hints as operands.
fn opposing_operands(
    e: &universe_domain::expr::Expr,
    out: &mut Vec<(
        Option<universe_domain::value::RecordRef>,
        String,
        Option<universe_domain::value::RecordRef>,
    )>,
) {
    use universe_domain::{
        expr::{Expr, Operand},
        value::{RecordRef, Value},
    };
    fn reference(o: &Operand) -> Option<RecordRef> {
        match o {
            Operand::Record { record }
            | Operand::Value {
                value: Value::RecordRef { record } | Value::EntityRef { record },
            } => Some(record.clone()),
            _ => None,
        }
    }
    match e {
        Expr::NoOpposingEvidence {
            subject,
            predicate,
            context,
        } => out.push((reference(subject), predicate.clone(), reference(context))),
        Expr::Not { expr } => opposing_operands(expr, out),
        Expr::All { exprs } | Expr::Any { exprs } => {
            for e in exprs {
                opposing_operands(e, out)
            }
        }
        Expr::Quantify { body, .. } => opposing_operands(body, out),
        _ => {}
    }
}
pub struct CheckedRule {
    pub evidence: Evidence,
    pub complete: bool,
    pub accepted: bool,
}
pub fn evaluate_indexed(
    index: Option<&universe_rules::EvaluationIndex<'_>>,
    record: &RecordVersion,
    records: &[RecordVersion],
    base: &Frame,
    footprint: &[RecordId],
) -> CheckedRule {
    let unavailable = || CheckedRule {
        evidence: Evidence::not_established(),
        complete: false,
        accepted: false,
    };
    let Payload::Rule(rule) = &record.payload else {
        return unavailable();
    };
    let Ok(compiled) = universe_rules::compile_rule(record) else {
        return unavailable();
    };
    let mut operands = vec![];
    opposing_operands(&rule.expression, &mut operands);
    let partition_records: Vec<_> = records.iter().filter(|r|match &r.payload {
        Payload::Assertion(a) if !operands.is_empty() => records.iter().any(|p|p.identity.record_id==a.proposition.record && matches!(&p.payload, Payload::Proposition(p) if operands.iter().any(|(subject,predicate,context)| {
            subject.as_ref().is_none_or(|s|s.resolve_namespace(&base.universe).ok()==p.subject.resolve_namespace(&base.universe).ok())
            && context.as_ref().is_none_or(|c|c.resolve_namespace(&base.universe).ok()==p.context.resolve_namespace(&base.universe).ok())
            && records.iter().any(|d|d.identity.record_id==p.predicate.record && match &d.payload {
                Payload::Property(d) => format!("{}:{}",d.namespace,d.key)==*predicate,
                Payload::Relation(d) => format!("{}:{}",d.namespace,d.key)==*predicate,
                _ => false,
            })
        }))),
        Payload::Exception(e) if !operands.is_empty() => e.rule.record==record.identity.record_id,
        _ => operands.is_empty(),
    }).cloned().collect();
    // Unqualified consistency rules must inspect dated opposition across the
    // whole candidate, rather than just the submitted frame.
    let partition_validity =
        if rule.validity == Validity::Unspecified && rule.expression.uses_opposing_evidence() {
            let calendars: BTreeSet<_> = partition_records
                .iter()
                .filter_map(|r| match &r.payload {
                    Payload::Assertion(a) => universe_rules::time::expression(&a.validity),
                    _ => None,
                })
                .filter_map(|e| match e {
                    TemporalExpression::Exact { calendar, .. }
                    | TemporalExpression::Interval { calendar, .. } => Some(calendar),
                    _ => None,
                })
                .collect();
            if calendars.len() > 1 {
                return unavailable();
            }
            calendars
                .into_iter()
                .next()
                .map(|calendar| Validity::CalendarInterval {
                    calendar,
                    start: TemporalBound::Unbounded,
                    end: TemporalBound::Unbounded,
                })
                .unwrap_or(Validity::Unspecified)
        } else {
            rule.validity.clone()
        };
    let Some(frames) = frames(&partition_validity, &partition_records, base) else {
        return unavailable();
    };
    let worlds: Vec<Vec<RecordId>> = match &rule.applicability {
        Applicability::Worlds { world_ids } => world_ids
            .iter()
            .filter_map(|w| RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)).ok())
            .filter(|r| footprint.contains(r))
            .map(|r| vec![r])
            .collect(),
        Applicability::UniverseWide => {
            if footprint.is_empty() {
                vec![vec![]]
            } else {
                footprint.iter().map(|w| vec![w.clone()]).collect()
            }
        }
        _ => return unavailable(),
    };
    if worlds.is_empty() || frames.len().saturating_mul(worlds.len()) > 1000 {
        return unavailable();
    }
    let exceptions: Vec<_> = if let Some(index) = index {
        index.exceptions(&record.identity.record_id).collect()
    } else {
        records.iter().filter(|r| matches!(&r.payload, Payload::Exception(e) if e.rule.record == record.identity.record_id)).collect()
    };
    let mut result = CheckedRule {
        evidence: Evidence::supported(vec![]),
        complete: true,
        accepted: true,
    };
    for frame in &frames {
        for world in &worlds {
            let r = universe_rules::evaluate_rule(
                &compiled,
                &EvaluationContext {
                    frame: Some(frame),
                    base_snapshot: records,
                    candidate_changes: vec![],
                    index,
                    world_scope: Some(world.clone()),
                },
            );
            let complete = r.coverage == EvaluationCoverage::Complete
                && rule.capabilities.iter().all(|c| {
                    matches!(
                        c.as_str(),
                        "basic.v1"
                            | "boolean.v1"
                            | "scalar.v1"
                            | "finite.v1"
                            | "opposing_evidence.v1"
                    )
                });
            let waiver_contexts: Option<Vec<_>> = if operands.is_empty() {
                Some(vec![frame.context.clone()])
            } else {
                operands
                    .iter()
                    .map(|(_, _, context)| context.clone())
                    .collect()
            };
            let waived = rule.commit_policy == CommitPolicy::BlockUnlessException && waiver_contexts.is_some_and(|contexts|contexts.iter().all(|context| {
                let mut cell=frame.clone();cell.context=context.clone();
                exceptions.iter().any(|r| matches!(&r.payload, Payload::Exception(e) if exception_at(e, record, &cell, world, records)))
            }));
            result.accepted &= complete && (r.outcome == EvidenceOutcome::Supported || waived);
            result.complete &= complete;
            result.evidence = result.evidence.all(r.evidence);
        }
    }
    result
}

#[cfg(test)]
fn evaluate(
    record: &RecordVersion,
    records: &[RecordVersion],
    base: &Frame,
    footprint: &[RecordId],
) -> CheckedRule {
    evaluate_indexed(None, record, records, base, footprint)
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
    fn v(n: usize, payload: Value) -> RecordVersion {
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
    fn interval(a: i32, b: i32) -> Value {
        json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000010","start":{"kind":"exact","value":a.to_string()},"end":{"kind":"exact","value":b.to_string()}})
    }
    fn scope() -> Value {
        json!({"applicability":{"kind":"universe_wide"},"context":rr(99)})
    }
    fn frame() -> Frame {
        serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(99),"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
    }
    fn fixture() -> Vec<RecordVersion> {
        vec![
            v(
                1,
                json!({"record_kind":"property","namespace":"test","key":"open","labels":{},"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
            ),
            v(
                2,
                json!({"record_kind":"proposition","subject":rr(80),"predicate":rr(1),"roles":[],"value":{"kind":"boolean","value":true},"quantification":"particular","context":rr(99)}),
            ),
            v(
                3,
                json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(2),"polarity":"support","scope":scope(),"validity":interval(10,20),"persistence":"explicit_interval","precision":"exact","alternatives":[],"basis":{"kind":"author_decision","note":"Explicit period"}}),
            ),
            v(
                4,
                json!({"record_kind":"rule","namespace":"test","key":"period","labels":{},"kind":"physical_constraint","commitPolicy":"block_unless_exception","applicability":{"kind":"universe_wide"},"targetPredicates":["test:open"],"expression":{"kind":"claim","subject":{"kind":"record","ref":rr(80)},"predicate":"test:open","roles":[],"value":{"kind":"value","value":{"kind":"boolean","value":true}},"polarity":"support"},"capabilities":["basic.v1"],"executable":true,"validity":interval(10,20)}),
            ),
        ]
    }
    #[test]
    fn s35_temporal_rules_check_every_cell_without_period_or_world_leakage() {
        let mut records = fixture();
        assert!(evaluate(&records[3], &records, &frame(), &[]).accepted);
        if let Payload::Assertion(a) = &mut records[2].payload {
            a.validity = serde_json::from_value(interval(10, 19)).unwrap();
        }
        assert!(
            !evaluate(&records[3], &records, &frame(), &[]).accepted,
            "last tick must be checked"
        );
        if let Payload::Rule(r) = &mut records[3].payload {
            r.validity = serde_json::from_value(interval(10, 19)).unwrap();
        }
        assert!(
            evaluate(&records[3], &records, &frame(), &[]).accepted,
            "rule cannot leak beyond its exclusive end"
        );
        let wa = WorldId::parse("wld_000000000000000000000020").unwrap();
        let wb = WorldId::parse("wld_000000000000000000000021").unwrap();
        if let Payload::Rule(r) = &mut records[3].payload {
            r.applicability = Applicability::Worlds {
                world_ids: vec![wa],
            };
        }
        if let Payload::Assertion(a) = &mut records[2].payload {
            a.scope.applicability = Applicability::Worlds {
                world_ids: vec![wb],
            };
        }
        let worlds = [
            RecordId::parse("rec_000000000000000000000020").unwrap(),
            RecordId::parse("rec_000000000000000000000021").unwrap(),
        ];
        assert!(
            !evaluate(&records[3], &records, &frame(), &worlds).accepted,
            "B support must not satisfy A's rule"
        );
    }
    #[test]
    fn s18_narrow_exception_does_not_disable_the_rest_of_a_rule() {
        let mut records = fixture();
        if let Payload::Rule(r) = &mut records[3].payload {
            r.expression = universe_domain::expr::Expr::Lit { value: false };
        }
        records.push(v(5,json!({"record_kind":"issue_decision","fingerprints":[],"mode":"accept","scope":id(4),"rationale":"Reviewed exception","principal":"prn_000000000000000000000001"})));
        records.push(v(6,json!({"record_kind":"exception","rule":rr(4),"ruleVersion":records[3].record_version_id,"scope":scope(),"validity":interval(12,18),"authorizingDecision":rr(5),"rationale":"Only inside this period"})));
        let Payload::Exception(e) = &records[5].payload else {
            panic!()
        };
        assert!(valid_exception(e, &records));
        assert!(!evaluate(&records[3], &records, &frame(), &[]).accepted);
        if let Payload::Exception(e) = &mut records[5].payload {
            e.validity = serde_json::from_value(interval(10, 20)).unwrap();
        }
        let checked = evaluate(&records[3], &records, &frame(), &[]);
        assert!(checked.accepted && checked.complete);
        let index = universe_rules::EvaluationIndex::new(&records);
        let indexed = evaluate_indexed(Some(&index), &records[3], &records, &frame(), &[]);
        assert_eq!(indexed.accepted, checked.accepted);
        assert_eq!(
            indexed.evidence.all_sources(),
            checked.evidence.all_sources()
        );
        assert_eq!(
            checked.evidence.outcome(),
            EvidenceOutcome::Refuted,
            "waiver preserves finding"
        );
        if let Payload::Exception(e) = &mut records[5].payload {
            e.validity = serde_json::from_value(interval(9, 20)).unwrap();
        }
        let Payload::Exception(e) = &records[5].payload else {
            panic!()
        };
        assert!(
            !valid_exception(e, &records),
            "exception cannot widen declared rule scope"
        );
    }
    #[test]
    fn generated_interval_cases_match_tick_by_tick_reference_and_record_permutations() {
        for start in 8..=12 {
            for end in 18..=22 {
                let mut records = fixture();
                if let Payload::Assertion(a) = &mut records[2].payload {
                    a.validity = serde_json::from_value(interval(start, end)).unwrap();
                }
                let expected = (10..20).all(|tick| start <= tick && tick < end);
                let target = records[3].clone();
                for rotation in 0..records.len() {
                    records.rotate_left(rotation);
                    let r = evaluate(&target, &records, &frame(), &[]);
                    assert_eq!(
                        r.accepted, expected,
                        "seed start={start} end={end} rotation={rotation}"
                    );
                    let index = universe_rules::EvaluationIndex::new(&records);
                    let indexed = evaluate_indexed(Some(&index), &target, &records, &frame(), &[]);
                    assert_eq!(indexed.accepted, r.accepted);
                    assert_eq!(indexed.complete, r.complete);
                    assert_eq!(indexed.evidence.outcome(), r.evidence.outcome());
                    assert_eq!(indexed.evidence.all_sources(), r.evidence.all_sources());
                }
            }
        }
    }
}
