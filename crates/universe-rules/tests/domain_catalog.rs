//! Source-catalog representation and no-invention fixtures. Custom definitions
//! preserve domain distinctions without interpreting prose as executable laws.
use std::collections::BTreeMap;
use universe_domain::starter::{Case, EXAMPLES as CASES};
use universe_domain::{
    canonical::Canonical, frame::*, ids::*, records::*, scope::*, value::*, Expr, Operand,
};
use universe_rules::{basic, EvaluationContext, EvidenceOutcome};
fn exercise(case: &Case, adversarial: bool) {
    let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let id = |n| RecordId::parse(&format!("rec_{n:024x}")).unwrap();
    let rr = |n| RecordRef::new(u.clone(), id(n));
    let frame = Frame {
        universe: u.clone(),
        continuity: ContinuityId::parse("cont_000000000000000000000001").unwrap(),
        revision: RevisionId::parse("rev_000000000000000000000001").unwrap(),
        context: rr(999),
        time: FrameTime::Timeless,
        perspective: Perspective::Author,
        reader_scene: None,
        personal_sequence: None,
    };
    let mut records = Vec::new();
    let mut seq = 2000usize;
    let mut push = |identity, payload: Payload| {
        seq += 1;
        records.push(
            RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{seq:024x}")).unwrap(),
                RecordIdentity::new(u.clone(), id(identity), payload.kind()),
                payload,
            )
            .unwrap(),
        );
    };
    for (n, label) in case.nodes.iter().enumerate() {
        push(
            n + 1,
            Payload::Entity(Entity {
                names: vec![],
                classification: None,
                classification_resolution:
                    universe_domain::records::ClassificationResolution::Unclassified,
                world_associations: vec![],
                labels: BTreeMap::from([("en".into(), (*label).into())]),
                metadata: BTreeMap::new(),
            }),
        );
    }
    let mut predicates = BTreeMap::new();
    for (_, key, _) in case.facts.iter().chain(std::iter::once(&case.unproven)) {
        let n = 100 + predicates.len();
        predicates.entry(*key).or_insert(n);
    }
    for (key, n) in &predicates {
        push(
            *n,
            Payload::Property(PropertyDef {
                namespace: case.id.into(),
                key: (*key).into(),
                labels: BTreeMap::new(),
                subject_types: vec![],
                value: ValueShape::EntityRef {
                    subject_types: vec![],
                },
                multiplicity: Multiplicity::Multiple,
                unit_dimension: None,
                persistence: PersistenceSemantics::Unspecified,
                exclusive: false,
                inverse: None,
                symmetric: false,
                transitive: false,
            }),
        );
    }
    for (index, (subject, key, target)) in case.facts.iter().enumerate() {
        let p = 500 + index;
        push(
            p,
            Payload::Proposition(Proposition {
                subject: rr(subject + 1),
                predicate: rr(predicates[key]),
                roles: vec![],
                value: Some(Value::EntityRef {
                    record: rr(target + 1),
                }),
                quantification: Quantification::Particular,
                context: frame.context.clone(),
            }),
        );
        push(
            700 + index,
            Payload::Assertion(Assertion {
                attribute_mode: universe_domain::records::AttributeMode::Instance,
                proposition: rr(p),
                polarity: Polarity::Support,
                scope: Scope {
                    applicability: Applicability::UniverseWide,
                    context: frame.context.clone(),
                    realm: None,
                },
                validity: Validity::Unspecified,
                persistence: PersistenceSemantics::Unspecified,
                precision: Precision::Exact,
                alternatives: vec![],
                basis: EvidenceBasis::AuthorDecision {
                    note: format!("{}M explicit fixture relation", case.id),
                },
                established_by: None,
            }),
        );
    }
    if adversarial {
        let (subject, key, target) = case.unproven;
        push(
            900,
            Payload::Proposition(Proposition {
                subject: rr(subject + 1),
                predicate: rr(predicates[key]),
                roles: vec![],
                value: Some(Value::EntityRef {
                    record: rr(target + 1),
                }),
                quantification: Quantification::Particular,
                context: rr(998),
            }),
        );
        push(
            901,
            Payload::Assertion(Assertion {
                attribute_mode: universe_domain::records::AttributeMode::Instance,
                proposition: rr(900),
                polarity: Polarity::Support,
                scope: Scope {
                    applicability: Applicability::UniverseWide,
                    context: rr(998),
                    realm: None,
                },
                validity: Validity::Unspecified,
                persistence: PersistenceSemantics::Unspecified,
                precision: Precision::Exact,
                alternatives: vec![],
                basis: EvidenceBasis::AuthorDecision {
                    note: format!(
                        "{}A misleading account: preserve without promoting",
                        case.id
                    ),
                },
                established_by: None,
            }),
        );
    }
    for record in &records {
        let decoded: RecordVersion =
            serde_json::from_slice(&serde_json::to_vec(record).unwrap()).unwrap();
        assert_eq!(&decoded, record, "{}M round trip", case.id);
        assert_eq!(
            decoded.payload.to_canonical(),
            record.payload.to_canonical()
        );
    }
    let query = |(subject, key, target): (usize, &str, usize)| Expr::Claim {
        subject: Operand::Record {
            record: rr(subject + 1),
        },
        predicate: format!("{}:{key}", case.id),
        roles: vec![],
        value: Some(Operand::Value {
            value: Value::EntityRef {
                record: rr(target + 1),
            },
        }),
        polarity: Polarity::Support,
        context: None,
    };
    let ctx = EvaluationContext {
        frame: Some(&frame),
        base_snapshot: &records,
        candidate_changes: vec![],
        index: None,
        world_scope: None,
    };
    for fact in case.facts {
        assert_eq!(
            basic::evaluate(&query(*fact), &ctx).0.outcome(),
            EvidenceOutcome::Supported,
            "{}M {:?}",
            case.id,
            fact
        );
    }
    let (result, complete) = basic::evaluate(&query(case.unproven), &ctx);
    assert!(complete, "{}A bounded query", case.id);
    assert_eq!(
        result.outcome(),
        EvidenceOutcome::NotEstablished,
        "{}A must not invent domain inference",
        case.id
    );
    if adversarial {
        let mut account_frame = frame.clone();
        account_frame.context = rr(998);
        let account = EvaluationContext {
            frame: Some(&account_frame),
            base_snapshot: &records,
            candidate_changes: vec![],
            index: None,
            world_scope: None,
        };
        assert_eq!(
            basic::evaluate(&query(case.unproven), &account).0.outcome(),
            EvidenceOutcome::Supported,
            "{}A account evidence must survive",
            case.id
        );
        let identities: std::collections::BTreeSet<_> =
            records.iter().map(|r| &r.identity.record_id).collect();
        assert_eq!(
            identities.len(),
            records.len(),
            "identities never merge by matching labels"
        );
    }
}

macro_rules! pair {
    ($minimal:ident, $adversarial:ident, $index:expr) => {
        #[test]
        fn $minimal() {
            exercise(&CASES[$index], false);
        }
        #[test]
        fn $adversarial() {
            exercise(&CASES[$index], true);
        }
    };
}
pair!(
    d01_minimal_realms_and_cosmology,
    d01_adversarial_realms_and_cosmology,
    0
);
pair!(
    d02_minimal_overlapping_regions_and_map,
    d02_adversarial_overlapping_regions_and_map,
    1
);
pair!(
    d03_minimal_life_and_survival,
    d03_adversarial_life_and_survival,
    2
);
pair!(
    d04_minimal_names_bodies_and_identity,
    d04_adversarial_names_bodies_and_identity,
    3
);
pair!(
    d05_minimal_chosen_households,
    d05_adversarial_chosen_households,
    4
);
pair!(
    d06_minimal_customs_and_preferences,
    d06_adversarial_customs_and_preferences,
    5
);
pair!(
    d07_minimal_claims_and_control,
    d07_adversarial_claims_and_control,
    6
);
pair!(
    d08_minimal_law_treaty_and_proceedings,
    d08_adversarial_law_treaty_and_proceedings,
    7
);
pair!(
    d09_minimal_mission_and_practice,
    d09_adversarial_mission_and_practice,
    8
);
pair!(
    d10_minimal_currency_inventory_and_debt,
    d10_adversarial_currency_inventory_and_debt,
    9
);
pair!(
    d11_minimal_doctrine_and_belief,
    d11_adversarial_doctrine_and_belief,
    10
);
pair!(
    d12_minimal_language_and_messages,
    d12_adversarial_language_and_messages,
    11
);
pair!(
    d13_minimal_devices_and_prerequisites,
    d13_adversarial_devices_and_prerequisites,
    12
);
pair!(
    d14_minimal_rooms_entrances_and_supply,
    d14_adversarial_rooms_entrances_and_supply,
    13
);
pair!(
    d15_minimal_routes_and_capacity,
    d15_adversarial_routes_and_capacity,
    14
);
pair!(
    d16_minimal_work_edition_and_copy,
    d16_adversarial_work_edition_and_copy,
    15
);
pair!(
    d17_minimal_events_and_accounts,
    d17_adversarial_events_and_accounts,
    16
);
pair!(
    d18_minimal_plans_and_disclosure,
    d18_adversarial_plans_and_disclosure,
    17
);
pair!(
    d19_minimal_narrative_and_viewpoint,
    d19_adversarial_narrative_and_viewpoint,
    18
);
