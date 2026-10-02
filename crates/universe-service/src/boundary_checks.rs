//! Creative boundaries protect transitive subject references and exact periods.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{frame::FrameTime, records::*, scope::*, Frame};
use universe_rules::{EvaluationContext, Evidence, EvidenceOutcome};

use crate::rule_checks::CheckedRule;

pub fn evaluate(
    target: &RecordVersion,
    changes: &[&RecordVersion],
    records: &[RecordVersion],
    historical: &[RecordVersion],
    frame: &Frame,
    author: bool,
) -> anyhow::Result<CheckedRule> {
    let Payload::Boundary(b) = &target.payload else {
        unreachable!()
    };
    let mut timing = historical.to_vec();
    timing.extend_from_slice(records);
    let map: BTreeMap<_, _> = timing.iter().map(|r| (&r.identity.record_id, r)).collect();
    let mut result = CheckedRule {
        evidence: Evidence::supported(vec![]),
        complete: true,
        accepted: true,
    };
    let mut work = 100_000usize;
    for changed in changes {
        if matches!(
            changed.payload,
            Payload::Boundary(_) | Payload::Exception(_) | Payload::IssueDecision(_)
        ) {
            continue;
        }
        let mut pending = vec![*changed];
        let mut visited = BTreeSet::new();
        let mut touches = false;
        while let Some(r) = pending.pop() {
            if !visited.insert(&r.identity.record_id) {
                continue;
            }
            let Some(left) = work.checked_sub(1) else {
                result.complete = false;
                result.accepted = false;
                return Ok(result);
            };
            work = left;
            touches |= match &b.area {
                BoundaryArea::Record(reference) => r.identity.record_id == reference.record,
                BoundaryArea::Category { entity_type } => {
                    matches!(&r.payload, Payload::Entity(e) if e.types.contains(entity_type))
                }
                BoundaryArea::Predicate { predicate, subject } => match &r.payload {
                    Payload::Proposition(p) if subject.as_ref().is_none_or(|s| *s == p.subject) => {
                        map.get(&p.predicate.record)
                            .is_some_and(|d| match &d.payload {
                                Payload::Property(d) => {
                                    format!("{}:{}", d.namespace, d.key) == *predicate
                                }
                                Payload::Relation(d) => {
                                    format!("{}:{}", d.namespace, d.key) == *predicate
                                }
                                _ => false,
                            })
                    }
                    _ => false,
                },
            };
            for id in universe_store::kernel::record_dependencies(r)? {
                if let Some(dep) = map.get(&id) {
                    pending.push(dep);
                }
            }
        }
        if !touches {
            continue;
        }
        // Proposition content with accompanying assertions takes their explicit
        // scope. Merely adding the mention must not widen the assertion's time.
        let mut scopes = Vec::new();
        match &changed.payload {
            Payload::Assertion(a) => scopes.push((Some(&a.scope), &a.validity)),
            Payload::Completeness(c) => scopes.push((Some(&c.scope), &c.validity)),
            Payload::Event(e) if !e.effects.is_empty() => {
                scopes.extend(e.effects.iter().map(|e| (Some(&e.scope), &e.validity)))
            }
            Payload::Proposition(_) => {
                scopes.extend(records.iter().filter_map(|r| match &r.payload {
                    Payload::Assertion(a) if a.proposition.record == changed.identity.record_id => {
                        Some((Some(&a.scope), &a.validity))
                    }
                    _ => None,
                }));
                if scopes.is_empty() {
                    scopes.push((None, &Validity::Unspecified));
                }
            }
            _ => scopes.push((None, &Validity::Unspecified)),
        }
        for (scope, validity) in scopes {
            if let Some(scope) = scope {
                if scope.context != b.scope.context {
                    continue;
                }
                if matches!((&scope.realm, &b.scope.realm), (Some(a), Some(b)) if a != b) {
                    continue;
                }
                if scope.realm.is_none() && b.scope.realm.is_some() {
                    result.complete = false;
                    result.accepted = false;
                    continue;
                }
                if matches!((&scope.applicability, &b.scope.applicability), (Applicability::Worlds{world_ids:a}, Applicability::Worlds{world_ids:b}) if !a.iter().any(|w| b.contains(w)))
                {
                    continue;
                }
                if !matches!(
                    scope.applicability,
                    Applicability::UniverseWide | Applicability::Worlds { .. }
                ) {
                    result.complete = false;
                    result.accepted = false;
                    continue;
                }
            }
            if !matches!(
                b.scope.applicability,
                Applicability::UniverseWide | Applicability::Worlds { .. }
            ) {
                result.complete = false;
                result.accepted = false;
                continue;
            }
            if *validity != Validity::Unspecified && b.validity != Validity::Unspecified {
                match universe_rules::time::overlaps(validity, &b.validity) {
                    Some(false) => continue,
                    None => {
                        result.complete = false;
                        result.accepted = false;
                        continue;
                    }
                    Some(true) => {}
                }
            }
            let period = if b.validity == Validity::Unspecified {
                validity
            } else {
                &b.validity
            };
            let mut base = frame.clone();
            base.context = b.scope.context.clone();
            base.time = FrameTime::Timeless;
            let Some(frames) = crate::rule_checks::frames(period, &timing, &base) else {
                result.complete = false;
                result.accepted = false;
                continue;
            };
            let worlds = match scope.map(|s| &s.applicability) {
                Some(Applicability::Worlds { world_ids }) => world_ids.clone(),
                _ => match &b.scope.applicability {
                    Applicability::Worlds { world_ids } => world_ids.clone(),
                    _ => vec![],
                },
            };
            let worlds = worlds
                .iter()
                .map(|w| {
                    universe_domain::ids::RecordId::parse(&universe_store::kernel::world_record(w))
                })
                .collect::<Result<Vec<_>, _>>()?;
            for frame in frames {
                let Some(left) = work.checked_sub(1) else {
                    result.complete = false;
                    result.accepted = false;
                    return Ok(result);
                };
                work = left;
                if *validity != Validity::Unspecified && !matches!(frame.time, FrameTime::Timeless)
                {
                    match universe_rules::events::applies(validity, &frame.time, records) {
                        Some(false) => continue,
                        None => {
                            result.complete = false;
                            result.accepted = false;
                            continue;
                        }
                        Some(true) => {}
                    }
                }
                let world_cells = if worlds.is_empty() {
                    vec![vec![]]
                } else {
                    worlds
                        .iter()
                        .filter(|w| match &b.scope.applicability {
                            Applicability::Worlds { world_ids } => world_ids
                                .iter()
                                .any(|b| universe_store::kernel::world_record(b) == w.as_str()),
                            _ => true,
                        })
                        .map(|w| vec![w.clone()])
                        .collect()
                };
                for worlds in world_cells {
                    let mut evidence = Evidence::supported(vec![]);
                    let mut complete = true;
                    match b.mode {
                        BoundaryMode::Fixed
                        | BoundaryMode::Prohibited
                        | BoundaryMode::IntentionallyUnresolved => {
                            evidence = Evidence::refuted(vec![target.record_version_id.clone()])
                        }
                        BoundaryMode::AuthorReserved if !author => {
                            evidence = Evidence::refuted(vec![target.record_version_id.clone()])
                        }
                        BoundaryMode::OpenWithConstraints => {
                            if b.scope.realm.is_some() {
                                complete = false;
                            }
                            for expr in &b.constraints {
                                let (e, c) = universe_rules::basic::evaluate(
                                    expr,
                                    &EvaluationContext {
                                        frame: Some(&frame),
                                        base_snapshot: records,
                                        candidate_changes: vec![],
                                        index: None,
                                        world_scope: Some(worlds.clone()),
                                    },
                                );
                                evidence = evidence.all(e);
                                complete &= c;
                            }
                        }
                        _ => {}
                    }
                    let waived = records.iter().any(|r| matches!(&r.payload, Payload::Exception(e) if crate::rule_checks::exception_at(e, target, &frame, &worlds, records)));
                    result.accepted &=
                        complete && (evidence.outcome() == EvidenceOutcome::Supported || waived);
                    result.complete &= complete;
                    result.evidence = result.evidence.all(evidence);
                }
            }
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    use universe_domain::ids::*;
    fn id(n: usize) -> String {
        format!("rec_{n:024x}")
    }
    fn rr(n: usize) -> Value {
        json!({"universe":"unv_000000000000000000000001","record":id(n)})
    }
    fn record(n: usize, payload: Value) -> RecordVersion {
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
    fn interval(a: i32, b: i32) -> Value {
        json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"exact","value":a.to_string()},"end":{"kind":"exact","value":b.to_string()}})
    }
    fn fixture() -> (Vec<RecordVersion>, Frame) {
        let scope = json!({"applicability":{"kind":"universe_wide"},"context":rr(99)});
        (vec![
            record(1, json!({"record_kind":"entity","labels":{"en":"Unanswered question"},"names":[],"types":[],"worldAssociations":[],"metadata":{}})),
            record(2, json!({"record_kind":"property","namespace":"test","key":"answer","labels":{},"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false})),
            record(3, json!({"record_kind":"proposition","subject":rr(1),"predicate":rr(2),"roles":[],"value":{"kind":"boolean","value":true},"context":rr(99),"quantification":"particular"})),
            record(4, json!({"record_kind":"assertion","proposition":rr(3),"polarity":"support","scope":scope,"validity":interval(12,18),"persistence":"explicit_interval","precision":"exact","alternatives":[],"basis":{"kind":"author_decision","note":"Explicit fact"}})),
            record(5, json!({"record_kind":"boundary","key":"test:question","area":{"kind":"record","universe":"unv_000000000000000000000001","record":id(1)},"mode":"intentionally_unresolved","constraints":[],"scope":scope,"validity":interval(10,20)})),
            record(6, json!({"record_kind":"issue_decision","fingerprints":[],"mode":"accept","scope":id(5),"rationale":"Reviewed exact period","principal":"prn_000000000000000000000001"})),
        ], serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(99),"time":{"kind":"timeless"},"perspective":"author"})).unwrap())
    }
    #[test]
    fn temporal_boundary_follows_existing_proposition_and_exact_exception_cells() {
        let (mut records, frame) = fixture();
        let check = |records: &[RecordVersion]| {
            evaluate(&records[4], &[&records[3]], records, &[], &frame, true).unwrap()
        };
        let r = check(&records);
        assert!(
            r.complete && !r.accepted,
            "existing proposition must not bypass subject boundary"
        );
        records.push(record(7, json!({"record_kind":"exception","rule":rr(5),"ruleVersion":records[4].record_version_id,"scope":{"applicability":{"kind":"universe_wide"},"context":rr(99)},"validity":interval(12,17),"authorizingDecision":rr(6),"rationale":"Only the stated period"})));
        assert!(
            !check(&records).accepted,
            "one uncovered tick cannot be waived"
        );
        if let Payload::Exception(e) = &mut records[6].payload {
            e.validity = serde_json::from_value(interval(12, 18)).unwrap();
        }
        let r = check(&records);
        assert!(r.complete && r.accepted);
        assert_eq!(
            r.evidence.outcome(),
            EvidenceOutcome::Refuted,
            "authorized waiver keeps original finding"
        );
        if let Payload::Assertion(a) = &mut records[3].payload {
            a.validity = serde_json::from_value(interval(20, 25)).unwrap();
        }
        assert!(
            check(&records).accepted,
            "boundary cannot leak beyond exclusive end"
        );
        if let Payload::Assertion(a) = &mut records[3].payload {
            a.validity = serde_json::from_value(interval(15, 25)).unwrap();
        }
        assert!(
            !check(&records).accepted,
            "partially overlapping edit still protected"
        );
    }
    #[test]
    fn removing_old_temporal_evidence_and_unknown_dates_do_not_escape_boundary() {
        let (records, frame) = fixture();
        let mut next = records.clone();
        next.remove(3);
        let r = evaluate(&records[4], &[&records[3]], &next, &records, &frame, true).unwrap();
        assert!(r.complete && !r.accepted);
        let mut changed = records[3].clone();
        if let Payload::Assertion(a) = &mut changed.payload {
            a.validity = serde_json::from_value(json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000099","start":{"kind":"exact","value":"12"},"end":{"kind":"exact","value":"18"}})).unwrap();
        }
        let r = evaluate(&records[4], &[&changed], &records, &[], &frame, true).unwrap();
        assert!(
            !r.complete && !r.accepted,
            "independent clocks must not be assumed disjoint"
        );
    }
}
