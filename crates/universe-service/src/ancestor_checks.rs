//! Independently stated outcomes: Tree applies to Cedar, never Stone; exact
//! half-open scope and both opposing witnesses survive inheritance.
use serde_json::{json, Value};
use universe_domain::{ids::*, records::*, Frame};
fn id(n: usize) -> String {
    format!("rec_{n:024x}")
}
fn rr(n: usize) -> Value {
    json!({"universe":"unv_000000000000000000000001","record":id(n)})
}
fn v(n: usize, p: Value) -> RecordVersion {
    let p: Payload = serde_json::from_value(p).unwrap();
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
fn fixture() -> Vec<RecordVersion> {
    vec![
        v(
            1,
            json!({"record_kind":"entity_type","namespace":"proof","key":"tree","name":"Tree","labels":{},"parent":null,"parentResolution":"root","classificationExecutable":true,"applicability":{"kind":"universe_wide"}}),
        ),
        v(
            2,
            json!({"record_kind":"entity_type","namespace":"proof","key":"cedar","name":"Cedar","labels":{},"parent":id(1),"parentResolution":"resolved","classificationExecutable":true,"applicability":{"kind":"universe_wide"}}),
        ),
        v(
            3,
            json!({"record_kind":"entity_type","namespace":"proof","key":"stone","name":"Stone","labels":{},"parent":null,"parentResolution":"root","classificationExecutable":true,"applicability":{"kind":"universe_wide"}}),
        ),
        v(
            4,
            json!({"record_kind":"entity","names":[],"classification":id(2),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}}),
        ),
        v(
            5,
            json!({"record_kind":"property","namespace":"proof","key":"grows","labels":{},"subjectTypes":[id(1)],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
        ),
        v(
            6,
            json!({"record_kind":"proposition","subject":rr(1),"predicate":rr(5),"context":rr(99),"value":{"kind":"boolean","value":true},"quantification":"particular"}),
        ),
        v(
            7,
            json!({"record_kind":"assertion","attributeMode":"shared","proposition":rr(6),"polarity":"support","scope":{"context":rr(99),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000010","start":{"kind":"exact","value":"10"},"end":{"kind":"exact","value":"20"}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored capability"}}),
        ),
    ]
}
fn claim(records: &[RecordVersion], day: &str, indexed: bool) -> (universe_rules::Evidence, bool) {
    claim_at(records, day, indexed, 4, vec![])
}
fn claim_at(
    records: &[RecordVersion],
    day: &str,
    indexed: bool,
    subject: usize,
    worlds: Vec<RecordId>,
) -> (universe_rules::Evidence, bool) {
    let f: Frame = serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(99),"time":{"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000010","value":day}},"perspective":"author"})).unwrap();
    let e = serde_json::from_value(json!({"kind":"claim","subject":{"kind":"record","ref":rr(subject)},"predicate":"proof:grows","value":{"kind":"value","value":{"kind":"boolean","value":true}},"polarity":"support"})).unwrap();
    let index = universe_rules::EvaluationIndex::new(records);
    universe_rules::basic::evaluate(
        &e,
        &universe_rules::EvaluationContext {
            frame: Some(&f),
            base_snapshot: records,
            candidate_changes: vec![],
            index: if indexed { Some(&index) } else { None },
            world_scope: Some(worlds),
        },
    )
}
#[test]
fn cedar_ancestry_scope_time_and_revision_are_explicit() {
    use universe_rules::{definitions::*, EvidenceOutcome::*};
    let mut rows = fixture();
    let tree = RecordId::parse(&id(1)).unwrap();
    let owner = RecordId::parse(&id(4)).unwrap();
    assert_eq!(matches(&owner, &[tree.clone()], &rows, None), Some(true));
    for indexed in [false, true] {
        assert_eq!(claim(&rows, "10", indexed).0.outcome(), Supported);
        assert_eq!(claim(&rows, "19", indexed).0.outcome(), Supported);
        assert_eq!(claim(&rows, "20", indexed).0.outcome(), NotEstablished);
    }
    let historical = rows.clone();
    if let Payload::EntityType(t) = &mut rows[1].payload {
        t.parent = Some(RecordId::parse(&id(3)).unwrap());
    }
    assert_eq!(matches(&owner, &[tree.clone()], &rows, None), Some(false));
    assert_eq!(claim(&historical, "15", true).0.outcome(), Supported);
    assert_eq!(claim(&rows, "15", true).0.outcome(), NotEstablished);
    if let Payload::EntityType(t) = &mut rows[1].payload {
        t.parent = None;
        t.parent_resolution = ParentResolution::Ambiguous;
    }
    assert_eq!(matches(&owner, &[tree], &rows, None), None);
    assert!(!claim(&rows, "15", true).1);
}
#[test]
fn inherited_conflicts_have_no_subtype_or_instance_precedence() {
    use universe_rules::EvidenceOutcome::*;
    let mut rows = fixture();
    rows.push(v(8,json!({"record_kind":"proposition","subject":rr(2),"predicate":rr(5),"context":rr(99),"value":{"kind":"boolean","value":false},"quantification":"particular"})));
    let mut a = rows[6].payload.clone();
    if let Payload::Assertion(a) = &mut a {
        a.proposition = serde_json::from_value(rr(8)).unwrap();
    }
    rows.push(v(9, serde_json::to_value(a).unwrap()));
    for indexed in [false, true] {
        let (e, c) = claim(&rows, "15", indexed);
        assert!(c);
        assert_eq!(e.outcome(), Conflicting);
        assert!(e.all_sources().contains(&rows[6].record_version_id));
        assert!(e.all_sources().contains(&rows[8].record_version_id));
        assert!(e.all_sources().contains(&rows[1].record_version_id));
    }
    assert!(!crate::validation::scalar_conflicts(&rows).0.is_empty());
    if let Payload::Assertion(a) = &mut rows[8].payload {
        a.attribute_mode = AttributeMode::InitialValue;
    }
    assert_eq!(claim(&rows, "15", true).0.outcome(), Supported);
    assert!(crate::validation::scalar_conflicts(&rows).0.is_empty());
}
#[test]
fn every_ancestor_has_its_own_world_and_unknown_is_not_universal() {
    use universe_rules::definitions::*;
    let mut rows = fixture();
    let owner = RecordId::parse(&id(4)).unwrap();
    let tree = RecordId::parse(&id(1)).unwrap();
    let a = RecordId::parse(&id(20)).unwrap();
    let b = RecordId::parse(&id(21)).unwrap();
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.applicability = serde_json::from_value(
            json!({"kind":"worlds","world_ids":["wld_000000000000000000000014"]}),
        )
        .unwrap();
    }
    if let Payload::EntityType(t) = &mut rows[1].payload {
        t.applicability = serde_json::from_value(
            json!({"kind":"worlds","world_ids":["wld_000000000000000000000015"]}),
        )
        .unwrap();
    }
    assert_eq!(
        matches(&owner, &[tree.clone()], &rows, Some(&[a])),
        Some(true)
    );
    assert_eq!(
        matches(&owner, &[tree.clone()], &rows, Some(&[b])),
        Some(false)
    );
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.applicability = universe_domain::scope::Applicability::Unspecified;
    }
    assert_eq!(matches(&owner, &[tree.clone()], &rows, Some(&[])), None);
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.applicability = universe_domain::scope::Applicability::Worlds { world_ids: vec![] };
    }
    assert_eq!(matches(&owner, &[tree], &rows, Some(&[])), Some(false));
}

#[test]
fn inherited_evidence_keeps_context_realm_unknown_time_and_instance_conflict() {
    use universe_rules::EvidenceOutcome::*;
    let mut rows = fixture();
    if let Payload::Assertion(a) = &mut rows[6].payload {
        a.scope.context = serde_json::from_value(rr(98)).unwrap();
    }
    assert_eq!(claim(&rows, "15", true).0.outcome(), NotEstablished);
    if let Payload::Assertion(a) = &mut rows[6].payload {
        a.scope.context = serde_json::from_value(rr(99)).unwrap();
        a.scope.realm = Some(serde_json::from_value(rr(97)).unwrap());
    }
    assert!(!claim(&rows, "15", true).1);
    rows = fixture();
    if let Payload::Assertion(a) = &mut rows[6].payload {
        a.validity = universe_domain::scope::Validity::Unknown;
    }
    assert!(!claim(&rows, "15", true).1);
    rows = fixture();
    rows.push(v(8,json!({"record_kind":"proposition","subject":rr(4),"predicate":rr(5),"context":rr(99),"value":{"kind":"boolean","value":false},"quantification":"particular"})));
    let mut a = rows[6].payload.clone();
    if let Payload::Assertion(a) = &mut a {
        a.proposition = serde_json::from_value(rr(8)).unwrap();
        a.attribute_mode = AttributeMode::Instance;
    }
    rows.push(v(9, serde_json::to_value(a).unwrap()));
    assert_eq!(claim(&rows, "15", true).0.outcome(), Conflicting);
    assert!(!crate::validation::scalar_conflicts(&rows).0.is_empty());
}

#[test]
fn type_targets_do_not_choose_a_known_ancestor_over_an_unknown_one() {
    use universe_rules::definitions::*;
    let mut rows = fixture();
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.applicability = universe_domain::scope::Applicability::Conditional;
    }
    assert_eq!(
        matches(
            &RecordId::parse(&id(4)).unwrap(),
            &[
                RecordId::parse(&id(1)).unwrap(),
                RecordId::parse(&id(2)).unwrap()
            ],
            &rows,
            Some(&[])
        ),
        None
    );
    if let Payload::Entity(e) = &mut rows[3].payload {
        e.classification_resolution = ClassificationResolution::Ambiguous;
    }
    assert!(ancestry(&RecordId::parse(&id(4)).unwrap(), &rows)
        .types
        .is_empty());
}

#[test]
fn rule_targeting_uses_ancestors_without_rebinding_authored_operands() {
    let mut rows = fixture();
    let rule: Rule=serde_json::from_value(json!({"namespace":"proof","key":"r","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"subjectTypes":[id(1)],"targetPredicates":[],"expression":{"kind":"lit","value":false},"capabilities":["basic.v1"],"executable":true,"validity":{"kind":"unspecified"}})).unwrap();
    assert_eq!(
        universe_rules::definitions::rule_applies(&rule, &rows, &[]),
        Some(true)
    );
    if let Payload::Entity(e) = &mut rows[3].payload {
        e.classification = Some(RecordId::parse(&id(3)).unwrap());
    }
    assert_eq!(
        universe_rules::definitions::rule_applies(&rule, &rows, &[]),
        Some(false)
    );
    if let Payload::Entity(e) = &mut rows[3].payload {
        e.classification = None;
        e.classification_resolution = ClassificationResolution::Unclassified;
    }
    assert_eq!(
        universe_rules::definitions::rule_applies(&rule, &rows, &[]),
        None
    );
}

#[test]
fn an_exact_instance_witness_does_not_erase_unknown_inherited_validity() {
    use universe_rules::EvidenceOutcome::*;
    let mut rows = fixture();
    rows.push(v(8,json!({"record_kind":"proposition","subject":rr(4),"predicate":rr(5),"context":rr(99),"value":{"kind":"boolean","value":true},"quantification":"particular"})));
    let mut a = rows[6].payload.clone();
    if let Payload::Assertion(a) = &mut a {
        a.attribute_mode = AttributeMode::Instance;
        a.proposition = serde_json::from_value(rr(8)).unwrap();
    }
    rows.push(v(9, serde_json::to_value(a).unwrap()));
    if let Payload::Assertion(a) = &mut rows[6].payload {
        a.validity = universe_domain::scope::Validity::Unspecified;
    }
    let (e, c) = claim(&rows, "15", true);
    assert_eq!(e.outcome(), Supported);
    assert!(!c);
}

#[test]
fn direct_definition_claims_check_the_definition_world_without_a_ui_default() {
    use universe_rules::EvidenceOutcome::*;
    let mut rows = fixture();
    if let Payload::Property(p) = &mut rows[4].payload {
        p.subject_types.clear();
    }
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.applicability = serde_json::from_value(
            json!({"kind":"worlds","world_ids":["wld_000000000000000000000014"]}),
        )
        .unwrap();
    }
    let a = RecordId::parse(&id(20)).unwrap();
    let b = RecordId::parse(&id(21)).unwrap();
    let (e, c) = claim_at(&rows, "15", true, 1, vec![a]);
    assert!(c);
    assert_eq!(e.outcome(), Supported);
    let (e, c) = claim_at(&rows, "15", true, 1, vec![b]);
    assert!(c);
    assert_eq!(e.outcome(), NotEstablished);
    assert!(!claim_at(&rows, "15", true, 1, vec![]).1);
}

#[test]
fn possession_grants_cannot_choose_over_a_conflicting_shared_definition() {
    use universe_rules::EvidenceOutcome::*;
    let mut rows = fixture();
    rows.push(v(10,json!({"record_kind":"entity","names":[],"classification":id(3),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}})));
    rows.push(v(11,json!({"record_kind":"property","namespace":"proof","key":"holder","labels":{},"value":{"kind":"entity_ref","subject_types":[]},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false})));
    rows.push(v(12,json!({"record_kind":"proposition","subject":rr(10),"predicate":rr(11),"context":rr(99),"value":{"kind":"entity_ref","ref":rr(4)},"quantification":"particular"})));
    let mut a = rows[6].payload.clone();
    if let Payload::Assertion(a) = &mut a {
        a.attribute_mode = AttributeMode::Instance;
        a.proposition = serde_json::from_value(rr(12)).unwrap();
    }
    rows.push(v(13, serde_json::to_value(a).unwrap()));
    rows.push(v(14,json!({"record_kind":"item_power","item":rr(10),"holderPredicate":rr(11),"powerPredicate":rr(5),"value":{"kind":"boolean","value":false},"scope":{"context":rr(99),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000010","start":{"kind":"exact","value":"10"},"end":{"kind":"exact","value":"20"}}})));
    for indexed in [false, true] {
        let (e, c) = claim(&rows, "15", indexed);
        assert!(c);
        assert_eq!(e.outcome(), Conflicting);
        assert!(e.all_sources().contains(&rows[10].record_version_id));
    }
}
