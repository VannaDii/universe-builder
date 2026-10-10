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
    assert_eq!(
        matches(&owner, std::slice::from_ref(&tree), &rows, None),
        Some(true)
    );
    for indexed in [false, true] {
        assert_eq!(claim(&rows, "10", indexed).0.outcome(), Supported);
        assert_eq!(claim(&rows, "19", indexed).0.outcome(), Supported);
        assert_eq!(claim(&rows, "20", indexed).0.outcome(), NotEstablished);
    }
    let historical = rows.clone();
    let historical_index = RecordIndex::new(&historical);
    if let Payload::EntityType(t) = &mut rows[1].payload {
        t.parent = Some(RecordId::parse(&id(3)).unwrap());
    }
    assert_eq!(
        matches(&owner, std::slice::from_ref(&tree), &rows, None),
        Some(false)
    );
    let current_index = RecordIndex::new(&rows);
    assert_eq!(
        historical_index.matches(&owner, std::slice::from_ref(&tree), None),
        Some(true)
    );
    assert_eq!(
        current_index.matches(&owner, std::slice::from_ref(&tree), None),
        Some(false)
    );
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
fn indexed_retrieval_stays_pinned_to_store_historical_revisions() {
    use universe_store::kernel::{Assignment, CommitInput, Kernel};
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("history.sqlite");
    let universe = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let continuity = ContinuityId::parse("cont_000000000000000000000001").unwrap();
    let principal = PrincipalId::parse("prn_000000000000000000000001").unwrap();
    let mut rows = fixture();
    rows.push(v(
        16,
        json!({"record_kind":"calendar","namespace":"proof","key":"days","labels":{},"unitStructure":{}}),
    ));
    rows.push(v(
        99,
        json!({"record_kind":"represented_context","universe":"unv_000000000000000000000001","kind":{"kind":"objective"},"labels":{}}),
    ));
    for record in &rows {
        for dependency in universe_store::kernel::record_dependencies(record).unwrap() {
            assert!(
                rows.iter()
                    .any(|candidate| candidate.identity.record_id == dependency),
                "{} references absent {}",
                record.identity.record_id,
                dependency
            );
        }
    }
    let mut kernel = Kernel::create(
        &path,
        universe.clone(),
        "Retrieval history",
        continuity.clone(),
        &principal,
    )
    .unwrap();
    let head = kernel.head(&continuity).unwrap();
    let first = kernel
        .commit(&CommitInput {
            universe: universe.clone(),
            continuity: continuity.clone(),
            expected_head: head,
            principal: principal.clone(),
            decision: "history seed".into(),
            reason: "retrieval parity".into(),
            idempotency_key: "history-seed".into(),
            changes: rows
                .iter()
                .map(|record| Assignment {
                    record_id: record.identity.record_id.clone(),
                    expected: None,
                    next: Some(record.clone()),
                })
                .collect(),
        })
        .unwrap();
    let previous = rows
        .iter()
        .find(|record| record.identity.record_id.as_str() == id(2))
        .unwrap();
    let mut changed_payload = previous.payload.clone();
    if let Payload::EntityType(entity_type) = &mut changed_payload {
        entity_type.parent = Some(RecordId::parse(&id(3)).unwrap());
    }
    let replacement = RecordVersion::build(
        RecordVersionId::parse("ver_000000000000000000000384").unwrap(),
        previous.identity.clone(),
        changed_payload,
    )
    .unwrap();
    let second = kernel
        .commit(&CommitInput {
            universe: universe.clone(),
            continuity: continuity.clone(),
            expected_head: first.clone(),
            principal: principal.clone(),
            decision: "retcon ancestry".into(),
            reason: "historical retrieval proof".into(),
            idempotency_key: "history-change".into(),
            changes: vec![Assignment {
                record_id: previous.identity.record_id.clone(),
                expected: Some(previous.record_version_id.clone()),
                next: Some(replacement),
            }],
        })
        .unwrap();
    let mut last = second.clone();
    for offset in 0..64usize {
        let record = v(
            1_000 + offset,
            json!({"record_kind":"property","namespace":"history","key":format!("revision-{offset}"),"labels":{},"value":{"kind":"boolean"},"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}),
        );
        last = kernel
            .commit(&CommitInput {
                universe: universe.clone(),
                continuity: continuity.clone(),
                expected_head: last,
                principal: principal.clone(),
                decision: "append unrelated history".into(),
                reason: "exercise pinned retrieval".into(),
                idempotency_key: format!("history-{offset}"),
                changes: vec![Assignment {
                    record_id: record.identity.record_id.clone(),
                    expected: None,
                    next: Some(record),
                }],
            })
            .unwrap();
    }
    let old = kernel.records(&continuity, &first).unwrap();
    let current = kernel.records(&continuity, &second).unwrap();
    let latest = kernel.records(&continuity, &last).unwrap();
    let tree = RecordId::parse(&id(1)).unwrap();
    let owner = RecordId::parse(&id(4)).unwrap();
    assert_eq!(
        universe_rules::definitions::RecordIndex::new(&old).matches(
            &owner,
            std::slice::from_ref(&tree),
            None
        ),
        Some(true)
    );
    assert_eq!(
        universe_rules::definitions::RecordIndex::new(&current).matches(
            &owner,
            std::slice::from_ref(&tree),
            None
        ),
        Some(false)
    );
    for (revision, snapshot) in [(&first, &old), (&second, &current), (&last, &latest)] {
        let frame: Frame = serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":revision,"context":rr(99),"time":{"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000010","value":"15"}},"perspective":"author"})).unwrap();
        let indexed = crate::objects::assemble(
            snapshot,
            std::slice::from_ref(&owner),
            &[],
            &frame,
            None,
            false,
        );
        let reference = crate::objects::assemble_reference(
            snapshot,
            std::slice::from_ref(&owner),
            &[],
            &frame,
            None,
            false,
        );
        assert_eq!(
            serde_json::to_value(indexed).unwrap(),
            serde_json::to_value(reference).unwrap()
        );
    }
    let author = ProfileId::parse("prf_000000000000000000000001").unwrap();
    let mut workflow = crate::workflow::Workflow {
        kernel: &mut kernel,
        authority: None,
        principal: crate::registry::Principal {
            id: author.clone(),
            author: true,
        },
        approval_author: author,
        scope: None,
        permissions: (true, true, true),
        name: "Retrieval history".into(),
    };
    let opened = workflow
        .execute(universe_protocol::Request::OpenContext(
            universe_protocol::request::OpenContext {
                universe: universe_protocol::request::Selector("Retrieval history".into()),
                universe_id: Some(universe.clone()),
                continuity_id: continuity.clone(),
                revision: universe_protocol::request::RevisionSelector::Exact {
                    revision_id: last.clone(),
                },
                represented_context: RecordId::parse(&id(99)).unwrap().into(),
                temporal_query: serde_json::from_value(json!({"kind":"timeless"})).unwrap(),
                temporal_systems: vec![],
                perspective: universe_domain::Perspective::Author,
                reader_scene: None,
            },
        ))
        .unwrap();
    let context_id: ContextId =
        serde_json::from_value(opened["result"]["context_id"].clone()).unwrap();
    let visible: std::collections::BTreeSet<_> = latest
        .iter()
        .map(|record| record.identity.record_id.clone())
        .collect();
    let start = std::time::Instant::now();
    let impact = workflow
        .execute(universe_protocol::Request::GetImpact(
            universe_protocol::request::GetImpact::Inline {
                universe: universe_protocol::request::Selector("Retrieval history".into()),
                universe_id: Some(universe.clone()),
                context_id,
                world: None,
                world_id: None,
                changed_records: vec![owner],
                scope: universe_protocol::request::CheckScope::Universe,
                byte_budget: 65_536,
            },
        ))
        .unwrap();
    let end_to_end_impact_elapsed = start.elapsed();
    let reference_records: std::collections::BTreeSet<_> = latest
        .iter()
        .filter(|record| visible.contains(&record.identity.record_id))
        .map(|record| record.identity.record_id.clone())
        .collect();
    let reference_worlds: std::collections::BTreeSet<_> = latest
        .iter()
        .filter(|record| visible.contains(&record.identity.record_id))
        .flat_map(crate::operations::worlds)
        .collect();
    assert_eq!(
        serde_json::to_value(&impact["result"]).unwrap(),
        serde_json::to_value(universe_protocol::response::Impact {
            records: reference_records.into_iter().collect(),
            coverage: universe_protocol::response::Coverage::Complete,
            world_ids: reference_worlds.into_iter().collect(),
        })
        .unwrap()
    );
    eprintln!(
        "end-to-end impact workload: revisions=66 records={} elapsed_ms={}",
        latest.len(),
        end_to_end_impact_elapsed.as_millis()
    );
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
        matches(&owner, std::slice::from_ref(&tree), &rows, Some(&[a])),
        Some(true)
    );
    assert_eq!(
        matches(&owner, std::slice::from_ref(&tree), &rows, Some(&[b])),
        Some(false)
    );
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.applicability = universe_domain::scope::Applicability::Unspecified;
    }
    assert_eq!(
        matches(&owner, std::slice::from_ref(&tree), &rows, Some(&[])),
        None
    );
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
    let indexed = universe_rules::definitions::RecordIndex::new(&rows);
    assert_eq!(
        universe_rules::definitions::rule_applies_indexed(&rule, &rows, &indexed, &[]),
        universe_rules::definitions::rule_applies(&rule, &rows, &[])
    );
    assert_eq!(
        universe_rules::definitions::rule_applies(&rule, &rows, &[]),
        Some(true)
    );
    if let Payload::Entity(e) = &mut rows[3].payload {
        e.classification = Some(RecordId::parse(&id(3)).unwrap());
    }
    let indexed = universe_rules::definitions::RecordIndex::new(&rows);
    assert_eq!(
        universe_rules::definitions::rule_applies_indexed(&rule, &rows, &indexed, &[]),
        universe_rules::definitions::rule_applies(&rule, &rows, &[])
    );
    assert_eq!(
        universe_rules::definitions::rule_applies(&rule, &rows, &[]),
        Some(false)
    );
    if let Payload::Entity(e) = &mut rows[3].payload {
        e.classification = None;
        e.classification_resolution = ClassificationResolution::Unclassified;
    }
    let indexed = universe_rules::definitions::RecordIndex::new(&rows);
    assert_eq!(
        universe_rules::definitions::rule_applies_indexed(&rule, &rows, &indexed, &[]),
        universe_rules::definitions::rule_applies(&rule, &rows, &[])
    );
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

#[test]
fn object_retrieval_retains_unresolved_definition_endpoint_and_source() {
    let mut rows = fixture();
    if let Payload::Entity(entity) = &mut rows[3].payload {
        entity.names.push(ContextualName {
            text: "Cedar".into(),
            language: None,
            community: None,
            role: None,
            validity: universe_domain::Validity::Unknown,
        });
    }
    if let Payload::EntityType(t) = &mut rows[0].payload {
        t.parent_resolution = ParentResolution::Ambiguous;
    }
    let frame: Frame = serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(99),"time":{"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000010","value":"15"}},"perspective":"author"})).unwrap();
    let object = crate::objects::assemble(
        &rows,
        &[RecordId::parse(&id(4)).unwrap()],
        &[],
        &frame,
        None,
        false,
    )
    .remove(0);
    assert_eq!(object.contextual_names[0].applicability, None);
    let mut character_frame = frame.clone();
    character_frame.perspective =
        universe_domain::frame::Perspective::Character(RecordId::parse(&id(4)).unwrap());
    let character = crate::objects::assemble(
        &rows,
        &[RecordId::parse(&id(4)).unwrap()],
        &[],
        &character_frame,
        None,
        true,
    )
    .remove(0);
    assert!(character.contextual_names.is_empty());
    assert_eq!(
        serde_json::to_value(character.identity.payload).unwrap(),
        serde_json::to_value(&object.identity.payload).unwrap()
    );
    let reference = crate::objects::assemble_reference(
        &rows,
        &[RecordId::parse(&id(4)).unwrap()],
        &[],
        &frame,
        None,
        false,
    )
    .remove(0);
    assert_eq!(
        serde_json::to_value(&object).unwrap(),
        serde_json::to_value(&reference).unwrap()
    );
    assert!(!object.ancestry_complete);
    assert_eq!(object.ancestry, vec![rows[1].clone(), rows[0].clone()]);
    assert_eq!(object.shared_attributes.len(), 1);
    assert_eq!(object.shared_attributes[0].record, rows[6]);
    assert_eq!(object.shared_attributes[0].applicability, None);
    assert!(object.shared_attributes[0]
        .unknowns
        .contains(&"definition_ancestry".into()));
    assert!(matches!(
        object.coverage,
        universe_protocol::response::Coverage::Partial
    ));
}

#[test]
fn object_conflicts_respect_multiplicity_time_and_qualified_precision() {
    let mut rows = fixture();
    rows.push(v(8,json!({"record_kind":"proposition","subject":rr(4),"predicate":rr(5),"context":rr(99),"value":{"kind":"boolean","value":false},"quantification":"particular"})));
    let mut a = rows[6].payload.clone();
    if let Payload::Assertion(a) = &mut a {
        a.proposition = serde_json::from_value(rr(8)).unwrap();
        a.attribute_mode = AttributeMode::Instance;
    }
    rows.push(v(9, serde_json::to_value(a).unwrap()));
    let frame: Frame = serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":rr(99),"time":{"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000010","value":"15"}},"perspective":"author"})).unwrap();
    let retrieve = |rows: &[RecordVersion]| {
        let indexed = crate::objects::assemble(
            rows,
            &[RecordId::parse(&id(4)).unwrap()],
            &[],
            &frame,
            None,
            false,
        )
        .remove(0);
        let reference = crate::objects::assemble_reference(
            rows,
            &[RecordId::parse(&id(4)).unwrap()],
            &[],
            &frame,
            None,
            false,
        )
        .remove(0);
        assert_eq!(
            serde_json::to_value(&indexed).unwrap(),
            serde_json::to_value(&reference).unwrap()
        );
        indexed
    };
    assert_eq!(retrieve(&rows).conflicts.len(), 1);
    let restricted_rows: Vec<_> = rows
        .iter()
        .filter(|record| {
            record.identity.record_id != RecordId::parse(&id(8)).unwrap()
                && record.identity.record_id != RecordId::parse(&id(9)).unwrap()
        })
        .cloned()
        .collect();
    let restricted_indexed = crate::objects::assemble(
        &restricted_rows,
        &[RecordId::parse(&id(4)).unwrap()],
        &[],
        &frame,
        None,
        true,
    );
    let restricted_reference = crate::objects::assemble_reference(
        &restricted_rows,
        &[RecordId::parse(&id(4)).unwrap()],
        &[],
        &frame,
        None,
        true,
    );
    assert_eq!(
        serde_json::to_value(&restricted_indexed).unwrap(),
        serde_json::to_value(&restricted_reference).unwrap()
    );
    assert!(restricted_indexed[0].conflicts.is_empty());
    assert!(restricted_indexed[0]
        .unknowns
        .contains(&"current_permissions_or_perspective_limit_evidence".into()));
    if let Payload::Property(p) = &mut rows[4].payload {
        p.multiplicity = Multiplicity::Multiple;
    }
    assert!(retrieve(&rows).conflicts.is_empty());
    if let Payload::Property(p) = &mut rows[4].payload {
        p.multiplicity = Multiplicity::Single;
    }
    if let Payload::Assertion(a) = &mut rows[8].payload {
        a.precision = universe_domain::scope::Precision::Approximate;
    }
    let qualified = retrieve(&rows);
    assert_eq!(qualified.conflicts[0].applicability, None);
    assert!(matches!(
        qualified.coverage,
        universe_protocol::response::Coverage::Partial
    ));
    if let Payload::Assertion(a) = &mut rows[8].payload {
        a.validity = serde_json::from_value(json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000010","start":{"kind":"exact","value":"20"},"end":{"kind":"exact","value":"30"}})).unwrap();
    }
    assert!(retrieve(&rows).conflicts.is_empty());
    if let Payload::Assertion(a) = &mut rows[8].payload {
        a.validity = serde_json::from_value(json!({"kind":"calendar_interval","calendar":"cal_000000000000000000000010","start":{"kind":"exact","value":"10"},"end":{"kind":"exact","value":"20"}})).unwrap();
    }
    if let Payload::Assertion(a) = &mut rows[6].payload {
        a.validity = universe_domain::scope::Validity::Unknown;
    }
    let unknown = retrieve(&rows);
    assert_eq!(unknown.conflicts.len(), 1);
    assert_eq!(unknown.conflicts[0].applicability, None);
    assert!(unknown
        .shared_attributes
        .iter()
        .chain(&unknown.instance_facts)
        .any(|fact| fact.unknowns.contains(&"temporal_applicability".into())));
}

#[test]
fn snapshot_index_matches_complete_ancestor_reference_and_reports_cost() {
    use std::time::Instant;
    use universe_rules::definitions::{ancestry, matches, RecordIndex};

    // Reproducible bounded workload: deep chain, many subjects and unrelated
    // history rows make repeated full-snapshot scans visible.
    let depth = 384usize;
    let subjects = 192usize;
    let mut rows = Vec::with_capacity(depth + subjects + 64);
    for n in 1..=depth {
        let parent = if n == 1 {
            Value::Null
        } else {
            json!(id(n - 1))
        };
        rows.push(v(n, json!({"record_kind":"entity_type","namespace":"perf","key":format!("type{n}"),"name":format!("Type {n}"),"labels":{},"parent":parent,"parentResolution":if n == 1 {"root"} else {"resolved"},"classificationExecutable":true,"applicability":{"kind":"universe_wide"}})));
    }
    for offset in 0..subjects {
        let n = depth + offset + 1;
        rows.push(v(n, json!({"record_kind":"entity","names":[],"classification":id(depth),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}})));
    }
    let targets = vec![
        RecordId::parse(&id(1)).unwrap(),
        RecordId::parse(&id(depth / 2)).unwrap(),
    ];
    let index = RecordIndex::new(&rows);
    let owners: Vec<_> = (0..subjects)
        .map(|offset| RecordId::parse(&id(depth + offset + 1)).unwrap())
        .collect();

    let start = Instant::now();
    let reference: Vec<_> = owners
        .iter()
        .map(|owner| {
            (
                ancestry(owner, &rows),
                matches(owner, &targets, &rows, None),
            )
        })
        .collect();
    let reference_elapsed = start.elapsed();
    let start = Instant::now();
    let optimized: Vec<_> = owners
        .iter()
        .map(|owner| (index.ancestry(owner), index.matches(owner, &targets, None)))
        .collect();
    let indexed_elapsed = start.elapsed();
    for (indexed, linear) in optimized.iter().zip(&reference) {
        assert_eq!(indexed.0.complete, linear.0.complete);
        assert_eq!(indexed.0.types, linear.0.types);
        assert_eq!(indexed.1, linear.1);
    }
    let rule: Rule = serde_json::from_value(json!({"namespace":"perf","key":"ancestor-rule","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"subjectTypes":[id(1)],"targetPredicates":[],"expression":{"kind":"lit","value":false},"capabilities":["basic.v1"],"executable":true,"validity":{"kind":"unspecified"}})).unwrap();
    let start = Instant::now();
    let rule_reference = universe_rules::definitions::rule_applies(&rule, &rows, &[]);
    let rule_reference_elapsed = start.elapsed();
    let start = Instant::now();
    let rule_indexed = universe_rules::definitions::rule_applies_indexed(&rule, &rows, &index, &[]);
    let rule_indexed_elapsed = start.elapsed();
    assert_eq!(rule_indexed, rule_reference);
    eprintln!(
        "retrieval workload: records={} depth={} subjects={} ancestry_reference_us={} ancestry_indexed_us={} rule_reference_us={} rule_indexed_us={}",
        rows.len(),
        depth,
        subjects,
        reference_elapsed.as_micros(),
        indexed_elapsed.as_micros(),
        rule_reference_elapsed.as_micros(),
        rule_indexed_elapsed.as_micros()
    );
}

#[test]
#[ignore = "history-scale retrieval workload; run explicitly"]
fn indexed_context_assembly_matches_full_scan_with_overlapping_history() {
    use std::time::Instant;
    use universe_store::kernel::{Assignment, CommitInput, Kernel};
    let mut rows = fixture();
    rows.push(v(16, json!({"record_kind":"calendar","namespace":"proof","key":"days","labels":{},"unitStructure":{}})));
    rows.push(v(99, json!({"record_kind":"represented_context","universe":"unv_000000000000000000000001","kind":{"kind":"objective"},"labels":{}})));
    let subjects = 64usize;
    let facts_per_subject = 32usize;
    for offset in 0..subjects {
        let owner = 100 + offset;
        rows.push(v(owner, json!({"record_kind":"entity","names":[],"classification":id(2),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}})));
        for fact in 0..facts_per_subject {
            let proposition = 10_000 + offset * facts_per_subject * 2 + fact * 2;
            rows.push(v(proposition, json!({"record_kind":"proposition","subject":rr(owner),"predicate":rr(5),"context":rr(99),"value":{"kind":"boolean","value":true},"quantification":"particular"})));
            rows.push(v(proposition + 1, json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(proposition),"polarity":"support","scope":{"context":rr(99),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000010","start":{"kind":"exact","value":"10"},"end":{"kind":"exact","value":"20"}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"overlapping synthetic evidence"}})));
        }
    }
    // Unrelated retained definitions represent substantial snapshot history
    // and make a full scan per output object measurably expensive.
    for n in 0..512 {
        rows.push(v(100_000 + n, json!({"record_kind":"property","namespace":"history","key":format!("property-{n}"),"labels":{},"value":{"kind":"boolean"},"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false})));
    }
    let directory = tempfile::tempdir().unwrap();
    let universe = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let continuity = ContinuityId::parse("cont_000000000000000000000001").unwrap();
    let principal = PrincipalId::parse("prn_000000000000000000000001").unwrap();
    let mut kernel = Kernel::create(
        &directory.path().join("context-history.sqlite"),
        universe.clone(),
        "Context history",
        continuity.clone(),
        &principal,
    )
    .unwrap();
    let start = Instant::now();
    let mut revision = kernel.head(&continuity).unwrap();
    let mut seed_commits = 0usize;
    for batch in rows.chunks(100) {
        revision = kernel
            .commit(&CommitInput {
                universe: universe.clone(),
                continuity: continuity.clone(),
                expected_head: revision,
                principal: principal.clone(),
                decision: "seed overlapping retrieval workload".into(),
                reason: "Goal 36 context assembly".into(),
                idempotency_key: format!("context-seed-{seed_commits}"),
                changes: batch
                    .iter()
                    .map(|record| Assignment {
                        record_id: record.identity.record_id.clone(),
                        expected: None,
                        next: Some(record.clone()),
                    })
                    .collect(),
            })
            .unwrap();
        seed_commits += 1;
    }
    for offset in 0..64usize {
        let record = v(
            300_000 + offset,
            json!({"record_kind":"property","namespace":"revision","key":format!("unrelated-{offset}"),"labels":{},"value":{"kind":"boolean"},"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}),
        );
        revision = kernel
            .commit(&CommitInput {
                universe: universe.clone(),
                continuity: continuity.clone(),
                expected_head: revision,
                principal: principal.clone(),
                decision: "append history".into(),
                reason: "preserve unrelated revision".into(),
                idempotency_key: format!("context-history-{offset}"),
                changes: vec![Assignment {
                    record_id: record.identity.record_id.clone(),
                    expected: None,
                    next: Some(record),
                }],
            })
            .unwrap();
    }
    let history_and_snapshot_elapsed = start.elapsed();
    let rows = kernel.records(&continuity, &revision).unwrap();
    let owners: Vec<_> = (0..subjects)
        .map(|offset| RecordId::parse(&id(100 + offset)).unwrap())
        .collect();
    let frame: Frame = serde_json::from_value(json!({"universe":universe,"continuity":continuity,"revision":revision,"context":rr(99),"time":{"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000010","value":"15"}},"perspective":"author"})).unwrap();
    let start = Instant::now();
    let reference = crate::objects::assemble_reference(&rows, &owners, &[], &frame, None, false);
    let reference_elapsed = start.elapsed();
    let start = Instant::now();
    let optimized = crate::objects::assemble(&rows, &owners, &[], &frame, None, false);
    let indexed_elapsed = start.elapsed();
    assert_eq!(
        serde_json::to_value(&optimized).unwrap(),
        serde_json::to_value(&reference).unwrap()
    );
    assert_eq!(optimized.len(), subjects);
    assert!(optimized
        .iter()
        .all(|object| object.instance_facts.len() == facts_per_subject));
    eprintln!("context workload: records={} subjects={} overlapping_facts_per_subject={} reference_ms={} indexed_ms={}", rows.len(), subjects, facts_per_subject, reference_elapsed.as_millis(), indexed_elapsed.as_millis());
    eprintln!(
        "context history setup: commits={} records={} setup_and_latest_snapshot_ms={}",
        seed_commits + 64,
        rows.len(),
        history_and_snapshot_elapsed.as_millis()
    );
    let restricted_reference =
        crate::objects::assemble_reference(&rows, &owners, &[], &frame, None, true);
    let restricted_indexed = crate::objects::assemble(&rows, &owners, &[], &frame, None, true);
    assert_eq!(
        serde_json::to_value(restricted_indexed).unwrap(),
        serde_json::to_value(restricted_reference).unwrap()
    );
    let profile = ProfileId::parse("prf_000000000000000000000001").unwrap();
    let mut workflow = crate::workflow::Workflow {
        kernel: &mut kernel,
        authority: None,
        principal: crate::registry::Principal {
            id: profile.clone(),
            author: true,
        },
        approval_author: profile,
        scope: None,
        permissions: (true, true, true),
        name: "Context history".into(),
    };
    let opened = workflow
        .execute(universe_protocol::Request::OpenContext(
            universe_protocol::request::OpenContext {
                universe: universe_protocol::request::Selector("Context history".into()),
                universe_id: Some(universe.clone()),
                continuity_id: continuity.clone(),
                revision: universe_protocol::request::RevisionSelector::Exact {
                    revision_id: revision.clone(),
                },
                represented_context: RecordId::parse(&id(99)).unwrap().into(),
                temporal_query: serde_json::from_value(json!({"kind":"at","time":{"kind":"exact","calendar":"cal_000000000000000000000010","value":"15"}})).unwrap(),
                temporal_systems: vec![CalendarId::parse("cal_000000000000000000000010").unwrap()],
                perspective: universe_domain::Perspective::Author,
                reader_scene: None,
            },
        ))
        .unwrap();
    let context_id: ContextId =
        serde_json::from_value(opened["result"]["context_id"].clone()).unwrap();
    let start = Instant::now();
    let oversized_impact = workflow.execute(universe_protocol::Request::GetImpact(
        universe_protocol::request::GetImpact::Inline {
            universe: universe_protocol::request::Selector("Context history".into()),
            universe_id: Some(universe.clone()),
            context_id,
            world: None,
            world_id: None,
            changed_records: vec![owners[0].clone()],
            scope: universe_protocol::request::CheckScope::Universe,
            byte_budget: 65_536,
        },
    ));
    let large_impact_elapsed = start.elapsed();
    assert!(oversized_impact
        .unwrap_err()
        .to_string()
        .contains("conservative impact closure exceeds"));
    eprintln!(
        "end-to-end large impact: commits={} records={} result=byte_budget_exceeded elapsed_ms={}",
        seed_commits + 64,
        rows.len(),
        large_impact_elapsed.as_millis()
    );
}
