//! Authored cross-instance maxima. No minimum or completeness inference.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{expr::Expr, ids::*, records::*, scope::*, temporal::*, value::RecordRef};
use universe_protocol::{
    response::{Coverage, EvidenceOutcome, Finding},
    ProtocolError,
};

type ParticipantWindows = BTreeMap<(RecordRef, CalendarId), Vec<(RecordRef, i128, i128)>>;

pub(crate) const CAPABILITY: &str = "relations.cardinality.v1";
fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("relationCardinality", message).into()
}
pub(crate) fn validate_rule(rule: &Rule, records: &[RecordVersion]) -> anyhow::Result<()> {
    let Some(c) = &rule.relation_cardinality else {
        if rule.capabilities.iter().any(|v| v == CAPABILITY) {
            return Err(invalid(
                "cardinality capability requires an authored contract",
            ));
        }
        return Ok(());
    };
    if !rule.executable
        || rule.kind != RuleKind::PhysicalConstraint
        || rule.commit_policy != CommitPolicy::AlwaysBlock
        || rule.applicability != Applicability::UniverseWide
        || rule.validity != Validity::Unspecified
        || !rule.subject_types.is_empty()
        || !rule.target_predicates.is_empty()
        || rule.expression != (Expr::Lit { value: true })
        || rule.capabilities != [CAPABILITY]
        || rule.channel_chronology.is_some()
        || rule.knowledge_policy.is_some()
    {
        return Err(invalid("requires an executable physical always_block rule, universe-wide wrapper, unspecified wrapper validity, literal true and only its capability; scope and time belong to the contract"));
    }
    let find = |r: &RecordRef| records.iter().find(|v| v.identity.record_id == r.record);
    let Some(Payload::Relation(d)) = find(&c.relation).map(|v| &v.payload) else {
        return Err(invalid("relation must resolve to a relation definition"));
    };
    if !d.roles.iter().any(|r| r.name == c.counted_role)
        || matches!(&c.grouping, CardinalityKey::Role { role } if !d.roles.iter().any(|r| &r.name == role))
    {
        return Err(invalid(
            "grouping and counted roles must be declared by the relation",
        ));
    }
    if !matches!(
        find(&c.scope.context).map(|v| &v.payload),
        Some(Payload::RepresentedContext(_))
    ) || c
        .scope
        .realm
        .as_ref()
        .is_some_and(|r| !matches!(find(r).map(|v| &v.payload), Some(Payload::Realm(_))))
    {
        return Err(invalid(
            "scope needs a represented context and optional realm",
        ));
    }
    if let Applicability::Worlds { world_ids } = &c.scope.applicability {
        for w in world_ids {
            let id =
                RecordId::parse(&universe_store::kernel::world_record(w)).expect("world identity");
            if !records
                .iter()
                .any(|r| r.identity.record_id == id && matches!(r.payload, Payload::World(_)))
            {
                return Err(invalid("contract world must resolve to a world"));
            }
        }
    }
    Ok(())
}

/// Closed integer-tick windows: half-open interval ends become the prior tick.
/// None preserves unknown validity, unmapped clocks and unsupported precision.
fn window(v: &Validity) -> Option<(CalendarId, i128, i128)> {
    match v {
        Validity::Instant {
            at: TemporalExpression::Exact { calendar, value },
        } => {
            let t = value.parse().ok()?;
            Some((calendar.clone(), t, t))
        }
        Validity::CalendarInterval {
            calendar,
            start,
            end,
        } => {
            let lo = match start {
                TemporalBound::Exact { value } => value.parse().ok()?,
                TemporalBound::Unbounded => i128::MIN,
                _ => return None,
            };
            let hi = match end {
                TemporalBound::Exact { value } => value.parse::<i128>().ok()?.checked_sub(1)?,
                TemporalBound::Unbounded => i128::MAX,
                _ => return None,
            };
            (lo <= hi).then_some((calendar.clone(), lo, hi))
        }
        _ => None,
    }
}
fn empty(v: &Validity) -> bool {
    matches!(v, Validity::CalendarInterval { start: TemporalBound::Exact { value: a }, end: TemporalBound::Exact { value: b }, .. } if a.parse::<i128>().ok().zip(b.parse::<i128>().ok()).is_some_and(|(a,b)| a == b))
}
fn worlds(scope: &Applicability, world: &Option<WorldId>) -> Option<bool> {
    match scope {
        Applicability::UniverseWide => Some(true),
        Applicability::Worlds { world_ids } => {
            Some(world.as_ref().is_some_and(|w| world_ids.contains(w)))
        }
        _ => None,
    }
}
fn scope_match(a: &Scope, c: &Scope) -> bool {
    a.context == c.context && (c.realm.is_none() || a.realm.is_none() || a.realm == c.realm)
}
fn same_relation(a: &Proposition, b: &Proposition) -> bool {
    let roles = |p: &Proposition| {
        p.roles
            .iter()
            .map(|r| (r.role.clone(), r.participant.clone()))
            .collect::<BTreeSet<_>>()
    };
    a.predicate == b.predicate
        && a.subject == b.subject
        && a.context == b.context
        && roles(a) == roles(b)
}

pub(crate) fn assess(records: &[RecordVersion]) -> Vec<Finding> {
    let map: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    // Include a universal cell, plus every explicitly named world. This avoids
    // conflating disjoint worlds while combining universe-wide evidence with each.
    let mut world_cells = BTreeSet::from([None]);
    for row in records {
        let scopes = match &row.payload {
            Payload::Assertion(a) => Some(&a.scope.applicability),
            Payload::Rule(r) => r
                .relation_cardinality
                .as_ref()
                .map(|c| &c.scope.applicability),
            _ => None,
        };
        if let Some(Applicability::Worlds { world_ids }) = scopes {
            world_cells.extend(world_ids.iter().cloned().map(Some));
        }
    }
    let assertions: Vec<_> = records
        .iter()
        .filter_map(|row| {
            let Payload::Assertion(a) = &row.payload else {
                return None;
            };
            let p_row = map.get(&a.proposition.record)?;
            let Payload::Proposition(p) = &p_row.payload else {
                return None;
            };
            Some((row, a, *p_row, p))
        })
        .collect();
    let refutations: Vec<_> = assertions
        .iter()
        .filter(|(_, a, _, _)| a.polarity == Polarity::Refutation)
        .collect();
    let mut findings = vec![];
    for row in records {
        let Payload::Rule(rule) = &row.payload else {
            continue;
        };
        let Some(c) = &rule.relation_cardinality else {
            continue;
        };
        let mut evidence = BTreeSet::from([row.record_version_id.clone()]);
        if let Some(d) = map.get(&c.relation.record) {
            evidence.insert(d.record_version_id.clone());
        }
        let mut unresolved = matches!(
            c.scope.applicability,
            Applicability::Unspecified | Applicability::Conditional
        ) || (c.validity != Validity::Unspecified
            && !empty(&c.validity)
            && window(&c.validity).is_none());
        let mut violation = false;
        let mut work = 100_000usize;
        let realm_cells: BTreeSet<_> = if let Some(realm) = &c.scope.realm {
            BTreeSet::from([Some(realm.clone())])
        } else {
            assertions
                .iter()
                .map(|(_, a, _, _)| a.scope.realm.clone())
                .chain(std::iter::once(None))
                .collect()
        };
        for world in &world_cells {
            let rule_world = worlds(&c.scope.applicability, world);
            if rule_world == Some(false) || empty(&c.validity) {
                continue;
            }
            for realm in &realm_cells {
                // Group by authored key. Count independently per clock.
                let mut groups = ParticipantWindows::new();
                for (a_row, a, p_row, p) in &assertions {
                    if a.polarity != Polarity::Support
                        || p.predicate != c.relation
                        || !scope_match(&a.scope, &c.scope)
                    {
                        continue;
                    }
                    if a.scope.realm.is_some() && &a.scope.realm != realm {
                        continue;
                    }
                    if work == 0 {
                        unresolved = true;
                        break;
                    }
                    work -= 1;
                    let fact_world = worlds(&a.scope.applicability, world);
                    if fact_world == Some(false) || empty(&a.validity) {
                        continue;
                    }
                    if universe_rules::time::overlaps(&a.validity, &c.validity) == Some(false) {
                        continue;
                    }
                    evidence.extend([
                        a_row.record_version_id.clone(),
                        p_row.record_version_id.clone(),
                    ]);
                    let keys = match &c.grouping {
                        CardinalityKey::Subject => vec![p.subject.clone()],
                        CardinalityKey::Role { role } => p
                            .roles
                            .iter()
                            .filter(|r| &r.role == role)
                            .map(|r| r.participant.clone())
                            .collect::<BTreeSet<_>>()
                            .into_iter()
                            .collect(),
                    };
                    let participants: BTreeSet<_> = p
                        .roles
                        .iter()
                        .filter(|r| r.role == c.counted_role)
                        .map(|r| r.participant.clone())
                        .collect();
                    let mut w = window(&a.validity);
                    if c.validity != Validity::Unspecified {
                        w = w
                            .zip(window(&c.validity))
                            .and_then(|((ac, al, ah), (bc, bl, bh))| {
                                (ac == bc && al.max(bl) <= ah.min(bh)).then_some((
                                    ac,
                                    al.max(bl),
                                    ah.min(bh),
                                ))
                            });
                    }
                    let opposed = refutations.iter().any(|(r_row, r, _, rp)| {
                        if work == 0 {
                            unresolved = true;
                            return true;
                        }
                        work -= 1;
                        if r.polarity == Polarity::Refutation
                            && same_relation(p, rp)
                            && r.scope.context == a.scope.context
                            && (r.scope.realm.is_none() || &r.scope.realm == realm)
                            && worlds(&r.scope.applicability, world) != Some(false)
                            && universe_rules::time::overlaps(&r.validity, &a.validity)
                                != Some(false)
                        {
                            evidence.insert(r_row.record_version_id.clone());
                            true
                        } else {
                            false
                        }
                    });
                    if keys.is_empty()
                        || participants.is_empty()
                        || p.quantification != Quantification::Particular
                        || a.precision != Precision::Exact
                        || !a.alternatives.is_empty()
                        || opposed
                        || rule_world.is_none()
                        || fact_world.is_none()
                        || w.is_none()
                    {
                        unresolved = true;
                        continue;
                    }
                    let (clock, lo, hi) = w.unwrap();
                    for key in keys {
                        let group = groups.entry((key, clock.clone())).or_default();
                        for participant in &participants {
                            if work == 0 {
                                unresolved = true;
                                break;
                            }
                            work -= 1;
                            group.push((participant.clone(), lo, hi));
                        }
                    }
                }
                // Different authored clocks in one group have unresolved overlap.
                let mut clocks: BTreeMap<_, BTreeSet<_>> = BTreeMap::new();
                for (key, clock) in groups.keys() {
                    clocks.entry(key).or_default().insert(clock);
                }
                unresolved |= clocks.values().any(|v| v.len() > 1);
                for entries in groups.values() {
                    // Sweep membership changes, retaining a reference count for each
                    // participant so duplicate and overlapping evidence counts once.
                    let mut events: BTreeMap<i128, Vec<(&RecordRef, bool)>> = BTreeMap::new();
                    for (participant, lo, hi) in entries {
                        events.entry(*lo).or_default().push((participant, true));
                        if let Some(after) = hi.checked_add(1) {
                            events.entry(after).or_default().push((participant, false));
                        }
                    }
                    let mut active = BTreeMap::<&RecordRef, usize>::new();
                    for changes in events.values() {
                        for (participant, starts) in changes {
                            if *starts {
                                *active.entry(participant).or_default() += 1;
                            } else if let Some(n) = active.get_mut(participant) {
                                *n -= 1;
                                if *n == 0 {
                                    active.remove(participant);
                                }
                            }
                        }
                        violation |= active.len() > c.maximum as usize;
                    }
                }
            }
        }
        findings.push(Finding {
            fingerprint: FindingFingerprint(String::new()),
            rule_id: row.identity.record_id.clone(),
            outcome: if violation {
                EvidenceOutcome::Refuted
            } else if unresolved {
                EvidenceOutcome::NotEstablished
            } else {
                EvidenceOutcome::Supported
            },
            coverage: if unresolved && !violation {
                Coverage::Unsupported
            } else {
                Coverage::Complete
            },
            evidence: evidence.into_iter().collect(),
        });
    }
    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    fn rr(n: u64) -> Value {
        json!({"universe":"unv_000000000000000000000001","record":format!("rec_{n:024x}")})
    }
    fn row(n: u64, p: Value) -> RecordVersion {
        {
            let payload: Payload = serde_json::from_value(p).unwrap();
            RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                RecordIdentity::new(
                    UniverseId::parse("unv_000000000000000000000001").unwrap(),
                    RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
                    payload.kind(),
                ),
                payload,
            )
            .unwrap()
        }
    }
    fn interval(a: i128, b: i128) -> Value {
        json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"exact","value":a.to_string()},"end":{"kind":"exact","value":b.to_string()}})
    }
    fn scope() -> Value {
        json!({"applicability":{"kind":"universe_wide"},"context":rr(3)})
    }
    fn rule(max: u32) -> RecordVersion {
        row(
            1,
            json!({"record_kind":"rule","namespace":"test","key":"successors","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[CAPABILITY],"executable":true,"validity":{"kind":"unspecified"},"relationCardinality":{"relation":rr(2),"grouping":{"kind":"subject"},"countedRole":"successor","maximum":max,"scope":scope(),"validity":{"kind":"unspecified"}}}),
        )
    }
    fn fact(n: u64, participant: u64, validity: Value) -> Vec<RecordVersion> {
        vec![
            row(
                n,
                json!({"record_kind":"proposition","predicate":rr(2),"subject":rr(10),"roles":[{"role":"office","participant":rr(10)},{"role":"successor","participant":rr(participant)}],"quantification":"particular","context":rr(3)}),
            ),
            row(
                n + 1,
                json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":scope(),"validity":validity,"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"test"}}),
            ),
        ]
    }
    fn outcome(rows: &[RecordVersion]) -> EvidenceOutcome {
        assess(rows)[0].outcome.clone()
    }
    #[test]
    fn common_time_distinct_participants_and_half_open_boundaries() {
        let mut r = vec![rule(1)];
        r.extend(fact(20, 11, interval(0, 10)));
        r.extend(fact(30, 12, interval(5, 15)));
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
        r[0] = rule(2);
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        r.extend(fact(40, 13, interval(10, 20)));
        // Three total, only two at any one time. Pairwise/transitive merging is wrong.
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        r.extend(fact(50, 13, interval(7, 9)));
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
        let mut r = vec![rule(1)];
        r.extend(fact(20, 11, interval(0, 10)));
        r.extend(fact(30, 12, interval(10, 20)));
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
    }
    #[test]
    fn repeated_evidence_unions_membership_and_uncertainty_is_not_certified() {
        let mut r = vec![rule(1)];
        r.extend(fact(20, 11, interval(0, 10)));
        r.extend(fact(30, 11, interval(5, 15)));
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        r.extend(fact(40, 12, json!({"kind":"unknown"})));
        assert!(matches!(outcome(&r), EvidenceOutcome::NotEstablished));
        assert_eq!(assess(&r)[0].coverage, Coverage::Unsupported);
        r.truncate(5);
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.polarity = Polarity::Refutation;
        assert!(matches!(outcome(&r), EvidenceOutcome::NotEstablished));
    }
    #[test]
    fn partition_world_context_group_and_scope_the_rule_window() {
        let mut r = vec![rule(1)];
        r.extend(fact(20, 11, interval(0, 10)));
        r.extend(fact(30, 12, interval(0, 10)));
        let w1 = WorldId::parse("wld_000000000000000000000001").unwrap();
        let w2 = WorldId::parse("wld_000000000000000000000002").unwrap();
        let Payload::Assertion(a) = &mut r[2].payload else {
            panic!()
        };
        a.scope.applicability = Applicability::Worlds {
            world_ids: vec![w1.clone()],
        };
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.scope.applicability = Applicability::Worlds {
            world_ids: vec![w2],
        };
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.scope.applicability = Applicability::UniverseWide;
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
        let Payload::Rule(rule) = &mut r[0].payload else {
            panic!()
        };
        rule.relation_cardinality.as_mut().unwrap().validity =
            serde_json::from_value(interval(10, 20)).unwrap();
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        let Payload::Rule(rule) = &mut r[0].payload else {
            panic!()
        };
        rule.relation_cardinality.as_mut().unwrap().validity = Validity::Unspecified;
        let Payload::Proposition(p) = &mut r[3].payload else {
            panic!()
        };
        p.subject = serde_json::from_value(rr(99)).unwrap();
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        let Payload::Rule(rule) = &mut r[0].payload else {
            panic!()
        };
        rule.relation_cardinality.as_mut().unwrap().grouping = CardinalityKey::Role {
            role: "office".into(),
        };
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.scope.context = serde_json::from_value(rr(99)).unwrap();
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
    }
    #[test]
    fn exact_instants_empty_intervals_and_unknown_clocks() {
        let instant = |time: &str| json!({"kind":"instant","at":{"kind":"exact","calendar":"cal_000000000000000000000001","value":time}});
        let mut r = vec![rule(1)];
        r.extend(fact(20, 11, interval(0, 10)));
        r.extend(fact(30, 12, instant("10")));
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        r[4] = fact(30, 12, instant("9"))[1].clone();
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
        r[4] = fact(30, 12, interval(5, 5))[1].clone();
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        let mut other = interval(0, 10);
        other["calendar"] = json!("cal_000000000000000000000002");
        r[4] = fact(30, 12, other)[1].clone();
        assert!(matches!(outcome(&r), EvidenceOutcome::NotEstablished));
        r[4] = fact(30, 12, json!({"kind":"unspecified"}))[1].clone();
        assert!(matches!(outcome(&r), EvidenceOutcome::NotEstablished));
        let mut uncertain = interval(5, 15);
        uncertain["start"] = json!({"kind":"bounded_uncertainty","lower":"4","upper":"6"});
        r[4] = fact(30, 12, uncertain)[1].clone();
        assert!(matches!(outcome(&r), EvidenceOutcome::NotEstablished));
    }
    #[test]
    fn realm_overlap_unknown_scope_and_authored_zero_maximum() {
        let mut r = vec![rule(1)];
        r.extend(fact(20, 11, interval(0, 10)));
        r.extend(fact(30, 12, interval(0, 10)));
        let Payload::Assertion(a) = &mut r[2].payload else {
            panic!()
        };
        a.scope.realm = serde_json::from_value(rr(90)).ok();
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.scope.realm = serde_json::from_value(rr(91)).ok();
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.scope.realm = None;
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
        let Payload::Assertion(a) = &mut r[4].payload else {
            panic!()
        };
        a.scope.applicability = Applicability::Unspecified;
        assert!(matches!(outcome(&r), EvidenceOutcome::NotEstablished));
        r = vec![rule(0)];
        assert!(matches!(outcome(&r), EvidenceOutcome::Supported));
        r.extend(fact(20, 11, interval(0, 10)));
        assert!(matches!(outcome(&r), EvidenceOutcome::Refuted));
    }
    #[test]
    fn declaration_requires_real_roles_and_a_single_evaluator_contract() {
        let d = row(
            2,
            json!({"record_kind":"relation","namespace":"test","key":"successor","labels":{},"roles":[{"name":"office","multiplicity":"single","participantTypes":[],"ordered":false},{"name":"successor","multiplicity":"single","participantTypes":[],"ordered":false}]}),
        );
        let context = row(
            3,
            json!({"record_kind":"represented_context","universe":"unv_000000000000000000000001","kind":{"kind":"objective"},"labels":{}}),
        );
        let Payload::Rule(mut rule) = self::rule(1).payload else {
            panic!()
        };
        let records = vec![d, context];
        assert!(validate_rule(&rule, &records).is_ok());
        rule.relation_cardinality.as_mut().unwrap().counted_role = "missing".into();
        assert!(validate_rule(&rule, &records).is_err());
        rule.relation_cardinality.as_mut().unwrap().counted_role = "successor".into();
        rule.relation_cardinality.as_mut().unwrap().grouping = CardinalityKey::Role {
            role: "missing".into(),
        };
        assert!(validate_rule(&rule, &records).is_err());
        rule.relation_cardinality.as_mut().unwrap().grouping = CardinalityKey::Subject;
        rule.expression = Expr::Lit { value: false };
        assert!(validate_rule(&rule, &records).is_err());
        rule.expression = Expr::Lit { value: true };
        rule.relation_cardinality = None;
        assert!(validate_rule(&rule, &records).is_err());
    }
}
