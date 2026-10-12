//! Publication continuity for properties named by an authored accounting rule.
//! Acceptance retains an unexplained arrival; it never fabricates an event.
use std::collections::BTreeMap;
use universe_domain::{
    consequences::EffectChange,
    frame::FrameTime,
    ids::*,
    records::*,
    scope::*,
    temporal::{TemporalBound, TemporalExpression},
    Frame,
};
use universe_protocol::ProtocolError;

pub(crate) const CAPABILITY: &str = "resources.accounting.v1";

pub(crate) struct Gap {
    pub rule: RecordId,
    pub assertion: RecordId,
    pub proposition: RecordId,
    pub fingerprint: FindingFingerprint,
    pub evidence: Vec<RecordVersionId>,
    pub acceptance: Option<RecordId>,
}
fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("resource.accounting", message).into()
}
fn coordinate(a: &Assertion) -> anyhow::Result<(&CalendarId, i128)> {
    match &a.validity {
        Validity::CalendarInterval {
            calendar,
            start: TemporalBound::Exact { value },
            ..
        } => Ok((
            calendar,
            value
                .parse()
                .map_err(|_| invalid("invalid stock coordinate"))?,
        )),
        _ => Err(invalid(
            "accounted stock needs an exact named-calendar interval",
        )),
    }
}
fn objective(a: &Assertion) -> bool {
    a.attribute_mode == AttributeMode::Instance && a.polarity == Polarity::Support
}
fn world_applies(scope: &Applicability, world: Option<&WorldId>) -> anyhow::Result<bool> {
    match scope {
        Applicability::UniverseWide => Ok(true),
        Applicability::Worlds { world_ids } => Ok(world.is_some_and(|w| world_ids.contains(w))),
        _ => Err(invalid(
            "resource accounting world applicability is unresolved",
        )),
    }
}
fn accounted(a: &Assertion, p: &Proposition, by_id: &BTreeMap<&RecordId, &RecordVersion>) -> bool {
    let Some(link) = &a.established_by else {
        return false;
    };
    let Some(Payload::Event(event)) = by_id.get(&link.event.record).map(|r| &r.payload) else {
        return false;
    };
    let Some(Payload::ActionDefinition(action)) = event
        .action
        .as_ref()
        .and_then(|r| by_id.get(&r.record))
        .map(|r| &r.payload)
    else {
        return false;
    };
    action.consequence_contract.as_ref().is_some_and(|c| {
        c.slots.iter().any(|s| {
            s.slot == link.slot
                && s.target.predicate == p.predicate
                && matches!(s.change, EffectChange::Delta { .. })
        })
    })
}

/// Check the full factual timeline, including unchanged history. Exact decision
/// fingerprints bind claim contents and their preceding evidence, not a proposal's
/// incidental generated version IDs or ordinary approval receipt.
pub(crate) fn assess(records: &[RecordVersion], base: &Frame) -> anyhow::Result<Vec<Gap>> {
    let by_id: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let mut remaining = 1_000_000usize;
    let mut gaps = Vec::new();
    let all_worlds: Vec<WorldId> = records
        .iter()
        .filter(|r| matches!(r.payload, Payload::World(_)))
        .map(|r| WorldId::parse(&r.identity.record_id.as_str().replacen("rec_", "wld_", 1)))
        .collect::<Result<_, _>>()?;
    for rule_row in records {
        let Payload::Rule(rule) = &rule_row.payload else {
            continue;
        };
        if !rule.capabilities.iter().any(|c| c == CAPABILITY) {
            continue;
        }
        if !rule.executable
            || rule.commit_policy != CommitPolicy::BlockUnlessException
            || rule.target_predicates.is_empty()
        {
            return Err(invalid("accounting rules must be executable, target resource properties and require explicit exception resolution"));
        }
        for name in &rule.target_predicates {
            let properties: Vec<_> = records.iter().filter(|r| matches!(&r.payload,Payload::Property(p) if format!("{}:{}",p.namespace,p.key)==*name)).collect();
            if properties.len() != 1 {
                return Err(invalid("accounting target must identify one property"));
            }
            let property_row = properties[0];
            let Payload::Property(property) = &property_row.payload else {
                unreachable!()
            };
            if property.multiplicity != Multiplicity::Single
                || !matches!(
                    property.value,
                    ValueShape::Integer | ValueShape::Decimal | ValueShape::Quantity { .. }
                )
            {
                return Err(invalid(
                    "accounting requires a single integer/decimal or exact-unit quantity property",
                ));
            }
            for row in records {
                let Payload::Assertion(a) = &row.payload else {
                    continue;
                };
                if !objective(a) {
                    continue;
                }
                let Some(Payload::Proposition(p)) =
                    by_id.get(&a.proposition.record).map(|r| &r.payload)
                else {
                    continue;
                };
                if p.predicate.record != property_row.identity.record_id {
                    continue;
                }
                if let (
                    Applicability::Worlds {
                        world_ids: policy_worlds,
                    },
                    Applicability::Worlds {
                        world_ids: claim_worlds,
                    },
                ) = (&rule.applicability, &a.scope.applicability)
                {
                    if policy_worlds.iter().all(|w| !claim_worlds.contains(w)) {
                        continue;
                    }
                }
                if a.precision != Precision::Exact
                    || !a.alternatives.is_empty()
                    || a.scope.realm.is_some()
                    || !p.roles.is_empty()
                {
                    return Err(invalid("accounted stock must be exact objective evidence without alternate values or roles"));
                }
                let (calendar, tick) = coordinate(a)?;
                let worlds: Vec<Option<&WorldId>> = match &a.scope.applicability {
                    Applicability::UniverseWide => {
                        if all_worlds.is_empty() {
                            vec![None]
                        } else {
                            all_worlds.iter().map(Some).collect()
                        }
                    }
                    Applicability::Worlds { world_ids } => world_ids.iter().map(Some).collect(),
                    _ => return Err(invalid("resource accounting scope is unresolved")),
                };
                check_claim(
                    records,
                    base,
                    &by_id,
                    rule_row,
                    property_row,
                    row,
                    a,
                    p,
                    calendar,
                    tick,
                    &worlds,
                    &mut gaps,
                    &mut remaining,
                )?;
            }
        }
    }
    Ok(gaps)
}

#[allow(clippy::too_many_arguments)]
fn check_claim(
    records: &[RecordVersion],
    base: &Frame,
    by_id: &BTreeMap<&RecordId, &RecordVersion>,
    rule_row: &RecordVersion,
    property_row: &RecordVersion,
    row: &RecordVersion,
    a: &Assertion,
    p: &Proposition,
    calendar: &CalendarId,
    tick: i128,
    worlds: &[Option<&WorldId>],
    gaps: &mut Vec<Gap>,
    remaining: &mut usize,
) -> anyhow::Result<()> {
    let Payload::Rule(rule) = &rule_row.payload else {
        unreachable!()
    };
    for world in worlds {
        if !world_applies(&rule.applicability, *world)? {
            continue;
        }
        let mut frame = base.clone();
        frame.context = p.context.clone();
        frame.time = FrameTime::At {
            time: TemporalExpression::Exact {
                calendar: calendar.clone(),
                value: tick.to_string(),
            },
        };
        if rule.validity != Validity::Unspecified {
            match universe_rules::events::applies(&rule.validity, &frame.time, records) {
                Some(false) => continue,
                Some(true) => {}
                None => return Err(invalid("accounting rule validity unresolved")),
            }
        }
        let world_records: Vec<_> = world
            .iter()
            .map(|w| RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)))
            .collect::<Result<_, _>>()?;
        match universe_rules::definitions::matches(
            &p.subject.record,
            &rule.subject_types,
            records,
            Some(&world_records),
        ) {
            Some(false) => continue,
            Some(true) => {}
            None => return Err(invalid("accounting rule subject applicability unresolved")),
        }
        if accounted(a, p, by_id) {
            continue;
        }
        let mut prior = Vec::new();
        let mut latest = None;
        for prev in records {
            *remaining = remaining
                .checked_sub(1)
                .ok_or_else(|| invalid("resource accounting work budget exceeded"))?;
            let Payload::Assertion(pa) = &prev.payload else {
                continue;
            };
            if !objective(pa)
                || pa.scope.context != a.scope.context
                || pa.scope.realm != a.scope.realm
            {
                continue;
            }
            let Some(Payload::Proposition(pp)) =
                by_id.get(&pa.proposition.record).map(|r| &r.payload)
            else {
                continue;
            };
            if pp.subject != p.subject || pp.predicate != p.predicate || pp.context != p.context {
                continue;
            }
            if !world_applies(&pa.scope.applicability, *world)? {
                continue;
            }
            let (pc, pt) = coordinate(pa)?;
            if pc != calendar || pt >= tick {
                continue;
            }
            if latest.is_none_or(|l| pt > l) {
                prior.clear();
                latest = Some(pt);
            }
            if latest == Some(pt) {
                prior.push((prev, pa, pp));
            }
        }
        // A first authored observation establishes a baseline. A later observation
        // corroborates it only if it preserves the last known stock value.
        if prior.is_empty() || prior.iter().all(|(_, _, pp)| pp.value == p.value || matches!((&pp.value,&p.value),(Some(a),Some(b)) if universe_rules::basic::compare(a,universe_domain::expr::Comparator::Eq,b)==Some(true))) {
            continue;
        }
        prior.sort_by_key(|(r, _, _)| &r.identity.record_id);
        let fingerprint = FindingFingerprint(crate::workflow::hash(&(
            CAPABILITY,
            &rule_row.identity.record_id,
            &rule_row.payload,
            &property_row.identity.record_id,
            &property_row.payload,
            &a.proposition.record,
            a,
            p,
            world,
            prior
                .iter()
                .map(|(_, pa, pp)| (*pa, *pp))
                .collect::<Vec<_>>(),
        )));
        if gaps.iter().any(|g| g.fingerprint == fingerprint) {
            continue;
        }
        let scope = format!("resource:{}", a.proposition.record);
        let acceptance = records.iter().find(|r| matches!(&r.payload, Payload::IssueDecision(d)
            if d.mode == IssueDecisionMode::Accept && d.scope == scope && d.fingerprints == vec![fingerprint.clone()] && !d.rationale.trim().is_empty()));
        let mut evidence = vec![
            rule_row.record_version_id.clone(),
            property_row.record_version_id.clone(),
            row.record_version_id.clone(),
        ];
        evidence.extend(prior.iter().map(|(r, _, _)| r.record_version_id.clone()));
        if let Some(decision) = acceptance {
            evidence.push(decision.record_version_id.clone());
        }
        evidence.sort();
        evidence.dedup();
        gaps.push(Gap {
            rule: rule_row.identity.record_id.clone(),
            assertion: row.identity.record_id.clone(),
            proposition: a.proposition.record.clone(),
            fingerprint,
            evidence,
            acceptance: acceptance.map(|r| r.identity.record_id.clone()),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    fn id(prefix: &str, n: u64) -> String {
        format!("{prefix}_{n:024x}")
    }
    fn rr(n: u64) -> Value {
        json!({"universe":id("unv",1),"record":id("rec",n)})
    }
    fn record(n: u64, p: Value) -> RecordVersion {
        let payload: Payload = serde_json::from_value(p).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&id("ver", n)).unwrap(),
            RecordIdentity::new(
                UniverseId::parse(&id("unv", 1)).unwrap(),
                RecordId::parse(&id("rec", n)).unwrap(),
                payload.kind(),
            ),
            payload,
        )
        .unwrap()
    }
    fn frame() -> Frame {
        serde_json::from_value(json!({"universe":id("unv",1),"continuity":id("cont",1),"revision":id("rev",1),"context":rr(5),"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
    }
    fn proposition(n: u64, value: &str) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"proposition","subject":rr(3),"predicate":rr(4),"value":{"kind":"integer","digits":value},"quantification":"particular","context":rr(5)}),
        )
    }
    fn assertion(n: u64, p: u64, start: i32, end: i32) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(p),"polarity":"support","scope":{"context":rr(5),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":id("cal",6),"start":{"kind":"exact","value":start.to_string()},"end":{"kind":"exact","value":end.to_string()}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Stock evidence"}}),
        )
    }
    fn fixture() -> Vec<RecordVersion> {
        vec![
            record(
                3,
                json!({"record_kind":"entity","classificationResolution":"unclassified","names":[],"worldAssociations":[],"labels":{},"metadata":{}}),
            ),
            record(
                4,
                json!({"record_kind":"property","namespace":"resource","key":"rounds","labels":{},"subjectTypes":[],"value":{"kind":"integer"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
            ),
            record(
                9,
                json!({"record_kind":"rule","namespace":"resource","key":"accounting","labels":{},"kind":"physical_constraint","commitPolicy":"block_unless_exception","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":["resource:rounds"],"expression":{"kind":"lit","value":true},"capabilities":[CAPABILITY],"executable":true,"validity":{"kind":"unspecified"}}),
            ),
            proposition(10, "1"),
            assertion(11, 10, 0, 5),
            proposition(12, "2"),
            assertion(13, 12, 5, 20),
        ]
    }
    fn accept(gap: &Gap) -> RecordVersion {
        record(
            14,
            json!({"record_kind":"issue_decision","fingerprints":[gap.fingerprint],"mode":"accept","scope":format!("resource:{}",gap.proposition),"rationale":"Author accepts the exact unexplained arrival","principal":id("prn",1)}),
        )
    }
    #[test]
    fn unexplained_change_needs_separate_exact_acceptance() {
        let mut rs = fixture();
        let gaps = assess(&rs, &frame()).unwrap();
        assert_eq!(gaps.len(), 1);
        assert_eq!(
            gaps[0].fingerprint.as_str(),
            "a83f2bb1814718261840609516169513da91564bf89abc07f184996f32f67074"
        );
        assert!(gaps[0].acceptance.is_none());
        rs.push(accept(&gaps[0]));
        let accepted = assess(&rs, &frame()).unwrap();
        assert_eq!(accepted[0].fingerprint, gaps[0].fingerprint);
        assert!(accepted[0].acceptance.is_some());
        rs[5] = proposition(12, "3");
        assert!(assess(&rs, &frame()).unwrap()[0].acceptance.is_none());
    }
    #[test]
    fn coherent_earlier_correction_removes_the_jump() {
        let mut rs = fixture();
        rs[3] = proposition(10, "2");
        assert!(assess(&rs, &frame()).unwrap().is_empty());
    }
    #[test]
    fn version_regeneration_does_not_change_reviewed_claim_contents() {
        let mut rs = fixture();
        let gaps = assess(&rs, &frame()).unwrap();
        rs.push(accept(&gaps[0]));
        for row in &mut rs {
            row.record_version_id = RecordVersionId::generate(&mut rand::rng());
        }
        assert!(assess(&rs, &frame()).unwrap()[0].acceptance.is_some());
    }
    #[test]
    fn acceptance_does_not_cover_changed_time_or_predecessor() {
        let mut rs = fixture();
        let gaps = assess(&rs, &frame()).unwrap();
        rs.push(accept(&gaps[0]));
        rs[6] = assertion(13, 12, 6, 20);
        assert!(assess(&rs, &frame()).unwrap()[0].acceptance.is_none());
        rs[6] = assertion(13, 12, 5, 20);
        rs[3] = proposition(10, "0");
        assert!(assess(&rs, &frame()).unwrap()[0].acceptance.is_none());
    }
    #[test]
    fn opt_in_policy_is_required_and_uncertain_stock_fails_closed() {
        let mut rs = fixture();
        rs.remove(2);
        assert!(assess(&rs, &frame()).unwrap().is_empty());
        let mut rs = fixture();
        let Payload::Assertion(a) = &mut rs[6].payload else {
            unreachable!()
        };
        a.precision = Precision::Unresolved;
        assert!(assess(&rs, &frame()).is_err());
    }
}
