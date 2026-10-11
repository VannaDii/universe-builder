//! Explicit author-declared knowledge absence; missing attitudes remain unknown.
use universe_domain::{expr::Expr, records::*, scope::*, Frame};
use universe_protocol::{
    response::{Coverage, EvidenceOutcome, Finding},
    ProtocolError,
};
pub(crate) const CAPABILITY: &str = "knowledge.boundaries.v1";
pub(crate) fn validate_rule(rule: &Rule, rows: &[RecordVersion]) -> anyhow::Result<()> {
    let Some(b) = &rule.knowledge_boundary else {
        if rule.capabilities.iter().any(|c| c == CAPABILITY) {
            anyhow::bail!(ProtocolError::invalid_argument(
                "knowledgeBoundary",
                "boundary capability requires an explicit boundary"
            ));
        }
        return Ok(());
    };
    if !rule.executable
        || rule.kind != RuleKind::PhysicalConstraint
        || rule.commit_policy != CommitPolicy::AlwaysBlock
        || rule.expression != (Expr::Lit { value: true })
        || rule.capabilities != [CAPABILITY]
        || !rule.target_predicates.is_empty()
        || !rule.subject_types.is_empty()
        || rule.knowledge_policy.is_some()
        || rule.channel_chronology.is_some()
        || rule.relation_cardinality.is_some()
        || !matches!(
            rule.applicability,
            Applicability::UniverseWide | Applicability::Worlds { .. }
        )
        || !matches!(rule.validity, Validity::CalendarInterval { .. })
    {
        anyhow::bail!(ProtocolError::invalid_argument("knowledgeBoundary", "requires a separate executable always_block physical rule, explicit world applicability and calendar interval, literal true and only its boundary capability"));
    }
    let period_ok = matches!(&rule.validity,Validity::CalendarInterval {start:universe_domain::temporal::TemporalBound::Exact{value:a},end:universe_domain::temporal::TemporalBound::Exact{value:b},..} if a.parse::<i128>().ok().zip(b.parse::<i128>().ok()).is_some_and(|(a,b)|a<=b));
    if !period_ok
        || matches!(&rule.applicability,Applicability::Worlds{world_ids} if world_ids.is_empty())
    {
        anyhow::bail!(ProtocolError::invalid_argument(
            "knowledgeBoundary",
            "explicit finite exact start/end and nonempty authored world scope required"
        ));
    }
    if let Some(universe) = rows.first().map(|r| &r.identity.universe_id) {
        for reference in [&b.holder, &b.proposition, &b.context] {
            reference.resolve_namespace(universe)?;
        }
    }
    let find = |id: &universe_domain::ids::RecordId| {
        rows.iter()
            .find(|r| &r.identity.record_id == id)
            .map(|r| &r.payload)
    };
    if let Applicability::Worlds { world_ids } = &rule.applicability {
        for world in world_ids {
            let id = universe_domain::ids::RecordId::parse(&universe_store::kernel::world_record(
                world,
            ))?;
            if !matches!(find(&id), Some(Payload::World(_))) {
                anyhow::bail!(ProtocolError::invalid_argument(
                    "knowledgeBoundary",
                    "boundary worlds must resolve to authored worlds"
                ));
            }
        }
    }
    if !matches!(find(&b.holder.record), Some(Payload::Entity(_)))
        || !matches!(
            find(&b.context.record),
            Some(Payload::RepresentedContext(_))
        )
        || !matches!(find(&b.proposition.record),Some(Payload::Proposition(p)) if p.context==b.context)
    {
        anyhow::bail!(ProtocolError::invalid_argument(
            "knowledgeBoundary",
            "holder, matching proposition and represented context must resolve"
        ));
    }
    Ok(())
}
fn claim_equal(a: &Proposition, b: &Proposition, rows: &[RecordVersion]) -> bool {
    let predicate = |p: &Proposition| {
        rows.iter()
            .find(|r| r.identity.record_id == p.predicate.record)
            .and_then(|r| match &r.payload {
                Payload::Property(d) => Some((&d.namespace, &d.key)),
                Payload::Relation(d) => Some((&d.namespace, &d.key)),
                _ => None,
            })
    };
    a.context == b.context
        && a.subject == b.subject
        && a.roles.len() == b.roles.len()
        && a.roles.iter().all(|role| b.roles.contains(role))
        && match (&a.value, &b.value) {
            (Some(a), Some(b)) => {
                a == b
                    || universe_rules::basic::compare(a, universe_domain::expr::Comparator::Eq, b)
                        == Some(true)
            }
            (None, None) => true,
            _ => false,
        }
        && a.quantification == b.quantification
        && (a.predicate == b.predicate || predicate(a).is_some() && predicate(a) == predicate(b))
}
pub(crate) fn assess(rows: &[RecordVersion], _frame: &Frame) -> Vec<Finding> {
    let mut out = vec![];
    for rule_row in rows {
        let Payload::Rule(rule) = &rule_row.payload else {
            continue;
        };
        let Some(b) = &rule.knowledge_boundary else {
            continue;
        };
        let prop = rows
            .iter()
            .find(|r| r.identity.record_id == b.proposition.record)
            .and_then(|r| {
                if let Payload::Proposition(p) = &r.payload {
                    Some(p)
                } else {
                    None
                }
            });
        if matches!(&rule.validity,Validity::CalendarInterval {start:universe_domain::temporal::TemporalBound::Exact{value:a},end:universe_domain::temporal::TemporalBound::Exact{value:b},..} if a.parse::<i128>().ok()==b.parse::<i128>().ok())
        {
            continue;
        }
        for row in rows {
            let Payload::EpistemicAttitude(a) = &row.payload else {
                continue;
            };
            if a.attitude != EpistemicAttitudeKind::Knows || a.holder != b.holder {
                continue;
            }
            let other = rows
                .iter()
                .find(|r| r.identity.record_id == a.proposition.record)
                .and_then(|r| {
                    if let Payload::Proposition(p) = &r.payload {
                        Some(p)
                    } else {
                        None
                    }
                });
            let (Some(prop), Some(other)) = (prop, other) else {
                continue;
            };
            if !claim_equal(prop, other, rows) {
                continue;
            }
            if a.acquisition
                .as_ref()
                .is_some_and(|k| k.truth_context != b.context)
            {
                continue;
            }
            let world = match &rule.applicability {
                Applicability::UniverseWide => Some(true),
                Applicability::Worlds { world_ids } => {
                    a.acquisition.as_ref().and_then(|k| match &k.world {
                        None => Some(true),
                        Some(w) => universe_domain::ids::WorldId::parse(
                            &w.record.as_str().replacen("rec_", "wld_", 1),
                        )
                        .ok()
                        .map(|w| world_ids.contains(&w)),
                    })
                }
                _ => None,
            };
            let overlap = universe_rules::time::overlaps(&a.validity, &rule.validity);
            if world == Some(false) || overlap == Some(false) {
                continue;
            }
            let definite = world == Some(true) && overlap == Some(true);
            out.push(Finding {message:Some(if definite{"An explicit author knowledge boundary prohibits this holder knowing this claim during an overlapping period. Correct the knowledge claim or explicitly revise/end the boundary; approval cannot waive it."}else{"Knowledge boundary applicability or temporal overlap is unresolved; clarify the authored world and interval."}.into()),records:vec![b.holder.clone(),b.proposition.clone()],fingerprint:universe_domain::ids::FindingFingerprint(String::new()),rule_id:rule_row.identity.record_id.clone(),outcome:if definite{EvidenceOutcome::Refuted}else{EvidenceOutcome::NotEstablished},evidence:vec![rule_row.record_version_id.clone(),row.record_version_id.clone()],coverage:if definite{Coverage::Complete}else{Coverage::Unsupported}});
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use universe_domain::ids::*;
    fn rr(n: u32) -> serde_json::Value {
        json!({"universe":"unv_000000000000000000000001","record":format!("rec_{n:024x}")})
    }
    fn row(n: u32, p: serde_json::Value) -> RecordVersion {
        let p: Payload = serde_json::from_value(p).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(
                UniverseId::parse("unv_000000000000000000000001").unwrap(),
                RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
                p.kind(),
            ),
            p,
        )
        .unwrap()
    }
    fn interval(a: &str, b: &str) -> serde_json::Value {
        json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000009","start":{"kind":"exact","value":a},"end":{"kind":"exact","value":b}})
    }
    fn frame() -> Frame {
        serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(9),"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
    }
    fn records() -> Vec<RecordVersion> {
        vec![
            row(
                1,
                json!({"record_kind":"proposition","predicate":rr(5),"subject":rr(6),"value":{"kind":"decimal","digits":"1.0"},"quantification":"particular","context":rr(9)}),
            ),
            row(
                2,
                json!({"record_kind":"proposition","predicate":rr(5),"subject":rr(6),"value":{"kind":"integer","digits":"1"},"quantification":"particular","context":rr(9)}),
            ),
            row(
                3,
                json!({"record_kind":"rule","namespace":"test","key":"absent","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"worlds","world_ids":["wld_000000000000000000000007"]},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[CAPABILITY],"executable":true,"validity":interval("10","18"),"knowledgeBoundary":{"holder":rr(6),"proposition":rr(1),"context":rr(9)}}),
            ),
            row(
                4,
                json!({"record_kind":"epistemic_attitude","holder":rr(6),"proposition":rr(2),"attitude":"knows","certainty":null,"validity":interval("0","30"),"basis":{"kind":"author_decision","note":"explicit decision"},"acquisition":{"truthContext":rr(9),"time":{"kind":"exact","calendar":"cal_000000000000000000000009","value":"0"},"basis":{"kind":"author_established"}}}),
            ),
        ]
    }
    #[test]
    fn overlapping_retained_and_author_established_knowledge_cannot_bypass_boundary() {
        let mut rows = records();
        assert!(matches!(
            assess(&rows, &frame())[0].outcome,
            EvidenceOutcome::Refuted
        ));
        let Payload::EpistemicAttitude(a) = &mut rows[3].payload else {
            unreachable!()
        };
        a.validity = serde_json::from_value(interval("18", "30")).unwrap();
        assert!(assess(&rows, &frame()).is_empty());
        let Payload::EpistemicAttitude(a) = &mut rows[3].payload else {
            unreachable!()
        };
        a.validity = serde_json::from_value(interval("0", "30")).unwrap();
        a.acquisition.as_mut().unwrap().world = Some(serde_json::from_value(rr(8)).unwrap());
        assert!(assess(&rows, &frame()).is_empty());
        let Payload::EpistemicAttitude(a) = &mut rows[3].payload else {
            unreachable!()
        };
        a.acquisition.as_mut().unwrap().world = None;
        a.holder = serde_json::from_value(rr(8)).unwrap();
        assert!(assess(&rows, &frame()).is_empty());
        let Payload::EpistemicAttitude(a) = &mut rows[3].payload else {
            unreachable!()
        };
        a.holder = serde_json::from_value(rr(6)).unwrap();
        a.attitude = EpistemicAttitudeKind::Remembers;
        assert!(assess(&rows, &frame()).is_empty());
        let Payload::EpistemicAttitude(a) = &mut rows[3].payload else {
            unreachable!()
        };
        a.attitude = EpistemicAttitudeKind::Knows;
        a.validity = Validity::Unspecified;
        assert!(matches!(
            assess(&rows, &frame())[0].outcome,
            EvidenceOutcome::NotEstablished
        ));
        let Payload::Proposition(p) = &mut rows[1].payload else {
            unreachable!()
        };
        p.context = serde_json::from_value(rr(8)).unwrap();
        assert!(assess(&rows, &frame()).is_empty());
    }
    #[test]
    fn raw_boundaries_cannot_weaken_protected_wrapper_or_guess_scope() {
        let mut rows = records();
        rows.push(row(6,json!({"record_kind":"entity","labels":{"en":"Iven"},"names":[],"classificationResolution":"unclassified","worldAssociations":[],"metadata":{}})));
        rows.push(row(
            7,
            json!({"record_kind":"world","selector":"World A","labels":{},"metadata":{}}),
        ));
        rows.push(row(9,json!({"record_kind":"represented_context","universe":"unv_000000000000000000000001","kind":{"kind":"objective"},"labels":{}})));
        let Payload::Rule(r) = &rows[2].payload else {
            unreachable!()
        };
        assert!(validate_rule(r, &rows).is_ok());
        for edit in 0..5 {
            let mut r = r.clone();
            match edit {
                0 => r.commit_policy = CommitPolicy::Advisory,
                1 => r.applicability = Applicability::Unspecified,
                2 => r.validity = Validity::Unspecified,
                3 => r.capabilities.clear(),
                _ => {
                    r.knowledge_boundary.as_mut().unwrap().context =
                        serde_json::from_value(rr(8)).unwrap()
                }
            };
            assert!(validate_rule(&r, &rows).is_err());
        }
    }
}
