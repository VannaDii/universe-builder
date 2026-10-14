use universe_domain::{ids::*, records::*, scope::Applicability, Expr};
use universe_rules::{compile_rule, evaluate_rule, EvaluationContext, EvaluationCoverage};
fn rule(expression: Expr, applicability: Applicability, executable: bool) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
        RecordIdentity::new(
            UniverseId::parse("unv_000000000000000000000001").unwrap(),
            RecordId::parse("rec_000000000000000000000001").unwrap(),
            RecordKind::Rule,
        ),
        Payload::Rule(Rule {
            required_evidence: None,
            relation_cardinality: None,
            knowledge_boundary: None,
            knowledge_policy: None,
            channel_chronology: None,
            namespace: "fixture".into(),
            key: "rule".into(),
            labels: Default::default(),
            kind: RuleKind::StructuralInvariant,
            commit_policy: CommitPolicy::AlwaysBlock,
            applicability,
            subject_types: vec![],
            target_predicates: vec![],
            expression,
            capabilities: vec![],
            executable,
            validity: Default::default(),
        }),
    )
    .unwrap()
}
#[test]
fn descriptive_rules_cannot_be_activated_by_compilation() {
    let compiled = compile_rule(&rule(
        Expr::Lit { value: true },
        Applicability::UniverseWide,
        false,
    ))
    .unwrap();
    assert!(!compiled.executable);
    let ctx = EvaluationContext {
        frame: None,
        base_snapshot: &[],
        candidate_changes: vec![],
        index: None,
        world_scope: None,
    };
    assert_eq!(
        evaluate_rule(&compiled, &ctx).coverage,
        EvaluationCoverage::Unsupported
    );
}
#[test]
fn unsupported_child_prevents_complete_claim_even_if_other_child_is_true() {
    let unsupported = Expr::Compare {
        left: universe_domain::Operand::EventRef,
        op: universe_domain::Comparator::Eq,
        right: universe_domain::Operand::Value {
            value: universe_domain::Value::Text { text: "x".into() },
        },
    };
    let compiled = compile_rule(&rule(
        Expr::Any {
            exprs: vec![Expr::Lit { value: true }, unsupported],
        },
        Applicability::UniverseWide,
        true,
    ))
    .unwrap();
    let ctx = EvaluationContext {
        frame: None,
        base_snapshot: &[],
        candidate_changes: vec![],
        index: None,
        world_scope: None,
    };
    assert_eq!(
        evaluate_rule(&compiled, &ctx).coverage,
        EvaluationCoverage::Unsupported
    );
}

#[test]
fn explicit_belief_is_not_knowledge_and_acquisition_is_time_and_context_bound() {
    use universe_domain::{frame::*, scope::*, temporal::*, value::*};
    let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let rr = |n| {
        RecordRef::new(
            u.clone(),
            RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
        )
    };
    let cal = CalendarId::parse("cal_000000000000000000000001").unwrap();
    let version = |n, payload: Payload| {
        RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(u.clone(), rr(n).record, payload.kind()),
            payload,
        )
        .unwrap()
    };
    let proposition = version(
        3,
        Payload::Proposition(Proposition {
            subject: rr(1),
            predicate: rr(2),
            value: Some(Value::Boolean { value: true }),
            roles: Default::default(),
            context: rr(4),
            quantification: Quantification::Particular,
        }),
    );
    let attitude = |kind| {
        version(
            5,
            Payload::EpistemicAttitude(EpistemicAttitude {
                acquisition: None,
                holder: rr(1),
                proposition: rr(3),
                attitude: kind,
                certainty: None,
                validity: Validity::CalendarInterval {
                    calendar: cal.clone(),
                    start: TemporalBound::Exact { value: "10".into() },
                    end: TemporalBound::Unbounded,
                },
                basis: EvidenceBasis::AuthorDecision {
                    note: "Explicit acquisition".into(),
                },
            }),
        )
    };
    let mut frame = Frame {
        universe: u.clone(),
        continuity: ContinuityId::parse("cont_000000000000000000000001").unwrap(),
        revision: RevisionId::parse("rev_000000000000000000000001").unwrap(),
        context: rr(4),
        time: FrameTime::At {
            time: TemporalExpression::Exact {
                calendar: cal.clone(),
                value: "10".into(),
            },
        },
        perspective: Perspective::Author,
        reader_scene: None,
        personal_sequence: None,
    };
    let query = |kind| Expr::Attitude {
        holder: rr(1),
        proposition: rr(3),
        attitude: kind,
    };
    let evaluate = |records: &[RecordVersion], frame: &Frame, expr: Expr| {
        universe_rules::basic::evaluate(
            &expr,
            &EvaluationContext {
                frame: Some(frame),
                base_snapshot: records,
                candidate_changes: vec![],
                index: None,
                world_scope: None,
            },
        )
    };
    let beliefs = vec![
        proposition.clone(),
        attitude(EpistemicAttitudeKind::Believes),
    ];
    assert_eq!(
        evaluate(&beliefs, &frame, query(EpistemicAttitudeKind::Believes))
            .0
            .outcome(),
        universe_rules::EvidenceOutcome::Supported
    );
    assert_eq!(
        evaluate(&beliefs, &frame, query(EpistemicAttitudeKind::Knows))
            .0
            .outcome(),
        universe_rules::EvidenceOutcome::NotEstablished
    );
    let knowledge = vec![proposition, attitude(EpistemicAttitudeKind::Knows)];
    assert_eq!(
        evaluate(&knowledge, &frame, query(EpistemicAttitudeKind::Knows))
            .0
            .outcome(),
        universe_rules::EvidenceOutcome::Supported
    );
    frame.time = FrameTime::At {
        time: TemporalExpression::Exact {
            calendar: cal,
            value: "9".into(),
        },
    };
    assert_eq!(
        evaluate(&knowledge, &frame, query(EpistemicAttitudeKind::Knows))
            .0
            .outcome(),
        universe_rules::EvidenceOutcome::NotEstablished
    );
    frame.context = rr(8);
    assert!(!evaluate(&knowledge, &frame, query(EpistemicAttitudeKind::Knows)).1);
}
