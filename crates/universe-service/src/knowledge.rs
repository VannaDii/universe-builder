//! Declared knowledge acquisition; receipt and belief never infer understanding.
use universe_domain::{
    expr::{Expr, Operand},
    frame::FrameTime,
    ids::FindingFingerprint,
    records::*,
    scope::*,
    temporal::{TemporalBound, TemporalExpression},
    Frame,
};
use universe_protocol::{
    response::{Coverage, EvidenceOutcome, Finding},
    ProtocolError,
};

pub(crate) const CAPABILITY: &str = "knowledge.acquisition.v1";
pub(crate) fn validate_rule(rule: &Rule) -> anyhow::Result<()> {
    let Some(_) = &rule.knowledge_policy else {
        if rule.capabilities.iter().any(|c| c == CAPABILITY) {
            return Err(ProtocolError::invalid_argument(
                "knowledgePolicy",
                "knowledge capability requires an explicit context policy",
            )
            .into());
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
        || rule.knowledge_boundary.is_some()
        || rule.channel_chronology.is_some()
    {
        return Err(ProtocolError::invalid_argument("knowledgePolicy", "knowledge needs an executable universe-wide physical constraint with always_block, unspecified validity, literal true and only its capability").into());
    }
    Ok(())
}
fn coordinate(time: &TemporalExpression) -> Option<(&universe_domain::ids::CalendarId, i128)> {
    match time {
        TemporalExpression::Exact { calendar, value } => Some((calendar, value.parse().ok()?)),
        _ => None,
    }
}
fn before_or_at(a: &TemporalExpression, b: &TemporalExpression) -> Option<bool> {
    let (ac, a) = coordinate(a)?;
    let (bc, b) = coordinate(b)?;
    (ac == bc).then_some(a <= b)
}
fn beginning(v: &Validity) -> Option<TemporalExpression> {
    match v {
        Validity::Instant { at } => Some(at.clone()),
        Validity::CalendarInterval {
            calendar,
            start: TemporalBound::Exact { value },
            ..
        } => Some(TemporalExpression::Exact {
            calendar: calendar.clone(),
            value: value.clone(),
        }),
        _ => None,
    }
}
fn check(
    records: &[RecordVersion],
    row: &RecordVersion,
    policy: &KnowledgePolicy,
    frame: &Frame,
    evidence: &mut Vec<universe_domain::ids::RecordVersionId>,
    reason: &mut String,
) -> Option<bool> {
    let find = |reference: &universe_domain::value::RecordRef| {
        records.iter().find(|r| {
            r.identity.record_id == reference.record
                && reference.resolve_namespace(&frame.universe).is_ok()
        })
    };
    let Payload::EpistemicAttitude(a) = &row.payload else {
        return None;
    };
    *reason =
        "Knowledge requires explicit acquisition time, truth context and acquisition basis.".into();
    let acquisition = a.acquisition.as_ref()?;
    *reason = "Retrieve the claimed proposition and its represented truth context.".into();
    let prop = find(&a.proposition)?;
    evidence.push(prop.record_version_id.clone());
    let Payload::Proposition(p) = &prop.payload else {
        return None;
    };
    *reason = "The acquisition truth context must match both the proposition and the authored knowledge policy.".into();
    if acquisition.truth_context != p.context || acquisition.truth_context != policy.context {
        return Some(false);
    }
    let context = find(&acquisition.truth_context)?;
    evidence.push(context.record_version_id.clone());
    if !matches!(context.payload, Payload::RepresentedContext(_)) {
        return None;
    }
    *reason = "Acquisition must be at or before knowledge onset on the same exact authored clock; repair acquisition time or knowledge validity.".into();
    if !before_or_at(&acquisition.time, &beginning(&a.validity)?)? {
        return Some(false);
    }
    *reason =
        "The acquisition basis must match the authored author-established or justified policy."
            .into();
    match (&policy.mode, &acquisition.basis) {
        (KnowledgeMode::AuthorEstablished, KnowledgeBasis::AuthorEstablished) => {
            return matches!(a.basis, EvidenceBasis::AuthorDecision { .. }).then_some(true);
        }
        (KnowledgeMode::AuthorEstablished, _)
        | (KnowledgeMode::Justified, KnowledgeBasis::AuthorEstablished) => return Some(false),
        (
            KnowledgeMode::Justified,
            KnowledgeBasis::CommunicationReceipt {
                communication,
                interpretation,
            },
        ) => {
            let message = find(communication)?;
            evidence.push(message.record_version_id.clone());
            let Payload::Communication(c) = &message.payload else {
                return None;
            };
            *reason =
                "The communication needs an actual recipient and an authored receipt time.".into();
            if c.actual_recipients.is_empty() {
                return None;
            }
            *reason =
                "The knowledge holder must be an actual recipient of the communication.".into();
            if !c.actual_recipients.contains(&a.holder) {
                return Some(false);
            }
            *reason = "Supply an explicit interpretation referencing the claimed proposition contained in the communication.".into();
            let interpreted = interpretation.as_ref()?;
            if interpreted != &a.proposition || !c.content.contains(interpreted) {
                return Some(false);
            }
            *reason = "Distorted communication does not establish interpreted knowledge in this bounded receipt lane.".into();
            if c.distorted {
                return None;
            }
            *reason = "Receipt must be at or before acquisition on the same exact authored clock; repair receipt or acquisition time.".into();
            if !before_or_at(c.received_at.as_ref()?, &acquisition.time)? {
                return Some(false);
            }
            // Reuse Goal 39, including authored reverse channels and unresolved clocks.
            *reason = "Retrieve the matching channel chronology contract and repair its missing or violated transmission timing.".into();
            let mut chronology_records:Vec<_>=records.iter().filter(|r| matches!(&r.payload,Payload::Rule(rule) if rule.channel_chronology.is_some())).cloned().collect();
            if chronology_records.is_empty() {
                return None;
            }
            chronology_records.push(message.clone());
            let chronology = crate::communications::assess(&chronology_records);
            for finding in &chronology {
                evidence.extend(finding.evidence.clone());
            }
            if chronology.iter().any(|f| f.coverage != Coverage::Complete) {
                return None;
            }
            if chronology
                .iter()
                .any(|f| !matches!(f.outcome, EvidenceOutcome::Supported))
            {
                return Some(false);
            }
        }
    }
    *reason =
        "Justified acquisition requires a particular proposition with a supported definition."
            .into();
    if p.quantification != Quantification::Particular {
        return None;
    }
    let definition = find(&p.predicate)?;
    evidence.push(definition.record_version_id.clone());
    let predicate = match &definition.payload {
        Payload::Property(d) => format!("{}:{}", d.namespace, d.key),
        Payload::Relation(d) => format!("{}:{}", d.namespace, d.key),
        _ => return None,
    };
    let mut truth_frame = frame.clone();
    truth_frame.context = acquisition.truth_context.clone();
    truth_frame.time = FrameTime::At {
        time: acquisition.time.clone(),
    };
    let world_scope = if let Some(world) = &acquisition.world {
        let world = find(world)?;
        evidence.push(world.record_version_id.clone());
        if !matches!(world.payload, Payload::World(_)) {
            return None;
        }
        Some(vec![world.identity.record_id.clone()])
    } else {
        Some(vec![])
    };
    let expr = Expr::Claim {
        subject: Operand::Record {
            record: p.subject.clone(),
        },
        predicate,
        roles: p
            .roles
            .iter()
            .map(|r| {
                (
                    r.role.clone(),
                    Operand::Record {
                        record: r.participant.clone(),
                    },
                )
            })
            .collect(),
        value: p.value.clone().map(|value| Operand::Value { value }),
        polarity: Polarity::Support,
        context: None,
    };
    *reason = "The claimed proposition needs unopposed supporting truth in its acquisition context, world and time. Retrieve its assertions; repair acquisition time or the missing/conflicting truth evidence.".into();
    let (truth, complete) = universe_rules::basic::evaluate(
        &expr,
        &universe_rules::EvaluationContext {
            index: None,
            frame: Some(&truth_frame),
            base_snapshot: records,
            candidate_changes: vec![],
            world_scope,
        },
    );
    evidence.extend(truth.all_sources());
    if !complete {
        return None;
    }
    match truth.outcome() {
        universe_rules::EvidenceOutcome::Supported => Some(true),
        universe_rules::EvidenceOutcome::Refuted | universe_rules::EvidenceOutcome::Conflicting => {
            Some(false)
        }
        universe_rules::EvidenceOutcome::NotEstablished => None,
    }
}
/// Whole-candidate reassessment makes corrections invalidate dependent publication.
pub(crate) fn assess(records: &[RecordVersion], frame: &Frame) -> Vec<Finding> {
    let policies: Vec<_> = records
        .iter()
        .filter_map(|r| match &r.payload {
            Payload::Rule(rule) => rule.knowledge_policy.as_ref().map(|p| (r, p)),
            _ => None,
        })
        .collect();
    let mut findings = vec![];
    for row in records {
        let Payload::EpistemicAttitude(a) = &row.payload else {
            continue;
        };
        if a.attitude != EpistemicAttitudeKind::Knows {
            continue;
        }
        if policies.is_empty() && a.acquisition.is_none() {
            continue;
        }
        let context = records.iter().find_map(|r| match &r.payload {
            Payload::Proposition(p) if r.identity.record_id == a.proposition.record => {
                Some(&p.context)
            }
            _ => None,
        });
        let matching: Vec<_> = policies
            .iter()
            .filter(|(_, p)| Some(&p.context) == context)
            .collect();
        if matching.is_empty() && a.acquisition.is_none() {
            // A context policy does not certify or constrain attitudes elsewhere.
            continue;
        }
        if matching.is_empty() {
            findings.push(Finding {
                message: Some("No matching knowledge policy covers this explicit acquisition. Retrieve or author the policy for the proposition truth context.".into()),
                records: vec![],
                fingerprint: FindingFingerprint(String::new()),
                rule_id: row.identity.record_id.clone(),
                outcome: EvidenceOutcome::NotEstablished,
                evidence: vec![row.record_version_id.clone()],
                coverage: Coverage::Unsupported,
            });
        }
        for (rule, policy) in matching {
            let mut evidence = vec![
                rule.record_version_id.clone(),
                row.record_version_id.clone(),
            ];
            let mut reason = String::new();
            let pass = check(records, row, policy, frame, &mut evidence, &mut reason);
            evidence.sort();
            evidence.dedup();
            findings.push(Finding {
                message: Some(if pass == Some(true) {
                    "Declared knowledge acquisition is supported.".into()
                } else {
                    reason
                }),
                records: vec![],
                fingerprint: FindingFingerprint(String::new()),
                rule_id: rule.identity.record_id.clone(),
                outcome: match pass {
                    Some(true) => EvidenceOutcome::Supported,
                    Some(false) => EvidenceOutcome::Refuted,
                    None => EvidenceOutcome::NotEstablished,
                },
                evidence,
                coverage: if pass.is_some() {
                    Coverage::Complete
                } else {
                    Coverage::Unsupported
                },
            });
        }
    }
    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use universe_domain::ids::*;
    fn rr(n: u32) -> serde_json::Value {
        json!({"universe":"unv_000000000000000000000001","record":format!("rec_{n:024x}")})
    }
    fn row(n: u32, payload: serde_json::Value) -> RecordVersion {
        let payload: Payload = serde_json::from_value(payload).unwrap();
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
    fn frame() -> Frame {
        serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(9),"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
    }
    fn rule() -> Rule {
        serde_json::from_value(json!({"namespace":"test","key":"knowledge","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"executable":true,"validity":{"kind":"unspecified"},"capabilities":[CAPABILITY],"knowledgePolicy":{"context":rr(9),"mode":"justified"}})).unwrap()
    }
    fn records() -> Vec<RecordVersion> {
        vec![
            row(
                1,
                json!({"record_kind":"proposition","predicate":rr(5),"subject":rr(6),"value":{"kind":"boolean","value":true},"quantification":"particular","context":rr(8)}),
            ),
            row(
                2,
                json!({"record_kind":"epistemic_attitude","holder":rr(6),"proposition":rr(1),"attitude":"knows","certainty":null,"validity":{"kind":"unspecified"},"basis":{"kind":"author_decision","note":"authored fact"}}),
            ),
            RecordVersion::build(
                RecordVersionId::parse("ver_000000000000000000000003").unwrap(),
                RecordIdentity::new(
                    frame().universe,
                    RecordId::parse("rec_000000000000000000000003").unwrap(),
                    RecordKind::Rule,
                ),
                Payload::Rule(rule()),
            )
            .unwrap(),
        ]
    }
    #[test]
    fn policy_isolates_contexts_without_certifying_other_knowledge() {
        let mut r = records();
        assert!(assess(&r, &frame()).is_empty());
        if let Payload::Proposition(p) = &mut r[0].payload {
            p.context = serde_json::from_value(rr(9)).unwrap();
        }
        let f = assess(&r, &frame());
        assert_eq!(f.len(), 1);
        assert!(matches!(f[0].outcome, EvidenceOutcome::NotEstablished));
    }
    #[test]
    fn declared_acquisition_needs_a_policy_even_if_no_policy_exists() {
        let mut r = records();
        r.pop();
        if let Payload::EpistemicAttitude(a) = &mut r[1].payload {
            a.acquisition=Some(serde_json::from_value(json!({"truthContext":rr(8),"time":{"kind":"unspecified"},"basis":{"kind":"author_established"}})).unwrap());
        }
        let f = assess(&r, &frame());
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].coverage, Coverage::Unsupported);
    }
    #[test]
    fn unsupported_policy_shapes_cannot_bypass_shared_admission() {
        let r = rule();
        assert!(validate_rule(&r).is_ok());
        for next in [
            CommitPolicy::Advisory,
            CommitPolicy::RecordFinding,
            CommitPolicy::BlockUnlessException,
        ] {
            let mut r = r.clone();
            r.commit_policy = next;
            assert!(validate_rule(&r).is_err());
        }
        let mut r = r.clone();
        r.knowledge_policy = None;
        assert!(validate_rule(&r).is_err());
    }
    #[test]
    fn acquisition_order_is_inclusive_and_requires_comparable_exact_clocks() {
        let time = |calendar: &str, value: &str| {
            serde_json::from_value(json!({"kind":"exact","calendar":calendar,"value":value}))
                .unwrap()
        };
        let c = "cal_000000000000000000000001";
        let other = "cal_000000000000000000000002";
        assert_eq!(before_or_at(&time(c, "7"), &time(c, "7")), Some(true));
        assert_eq!(before_or_at(&time(c, "8"), &time(c, "7")), Some(false));
        assert_eq!(before_or_at(&time(c, "7"), &time(other, "8")), None);
        assert_eq!(
            before_or_at(&TemporalExpression::Unspecified, &time(c, "7")),
            None
        );
    }
}
