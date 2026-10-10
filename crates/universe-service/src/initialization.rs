//! Explicit start compilation. No mention, classification or process lifecycle
//! calls this path; the generated records are frozen before exact review.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{frame::FrameTime, ids::*, records::*, scope::*, temporal::*, value::*};
use universe_protocol::ProtocolError;
use universe_rules::{basic, definitions, events};
use universe_store::kernel::Assignment;
fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("initialize_instance", message).into()
}
fn same_value(a: &Option<Value>, b: &Option<Value>) -> Option<bool> {
    if a == b {
        Some(true)
    } else {
        a.as_ref()
            .zip(b.as_ref())
            .and_then(|(a, b)| basic::compare(a, universe_domain::Comparator::Eq, b))
    }
}
pub fn compile(
    u: &UniverseId,
    revision: &RevisionId,
    base: &[RecordVersion],
    operations: &[DomainOperation],
    changes: &mut Vec<Assignment>,
) -> anyhow::Result<()> {
    let mut candidate: BTreeMap<_, _> = base
        .iter()
        .map(|r| (r.identity.record_id.clone(), r.clone()))
        .collect();
    for change in changes.iter() {
        if let Some(next) = &change.next {
            candidate.insert(change.record_id.clone(), next.clone());
        } else {
            candidate.remove(&change.record_id);
        }
    }
    let records: Vec<_> = candidate.values().cloned().collect();
    let get = |id: &RecordId| {
        candidate
            .get(id)
            .ok_or_else(|| invalid("referenced record absent"))
    };
    let mut keys = BTreeSet::new();
    let mut input_refs: BTreeSet<_> = changes.iter().map(|c| c.record_id.clone()).collect();
    for op in operations {
        let DomainOperation::InitializeInstance {
            client_ref,
            instance,
            start,
            definition,
            scope,
            validity,
        } = op
        else {
            continue;
        };
        if instance.universe.as_ref() != Some(u)
            || start.universe.as_ref() != Some(u)
            || definition.universe.as_ref() != Some(u)
            || scope.context.universe.as_ref() != Some(u)
        {
            return Err(invalid("explicit local identities and context required"));
        }
        let Payload::Entity(_) = &get(&instance.record)?.payload else {
            return Err(invalid("subject is not an instance"));
        };
        let chain = definitions::ancestry(&instance.record, &records);
        if !chain.complete {
            return Err(invalid("classification or ancestry unresolved"));
        }
        let start_version = get(&start.record)?;
        let Payload::Event(event) = &start_version.payload else {
            return Err(invalid("start must be an authored event"));
        };
        let TemporalExpression::Exact { calendar, value } = &event.time else {
            return Err(invalid("exact authored start required"));
        };
        if event.occurrence != OccurrenceMode::Occurred
            || !event.participants.iter().any(|p| p.record == *instance)
            || !matches!(validity, Validity::CalendarInterval {calendar: c, start:TemporalBound::Exact {value: s}, ..} if c == calendar && s == value)
            || events::applies(
                validity,
                &FrameTime::At {
                    time: event.time.clone(),
                },
                &records,
            ) != Some(true)
        {
            return Err(invalid(
                "initial interval must include and begin at this occurred instance start",
            ));
        }
        let source = base
            .iter()
            .find(|r| {
                r.identity.record_id == definition.record
                    && r.record_version_id == definition.version
            })
            .ok_or_else(|| invalid("source definition must be approved at the review base"))?;
        if get(&definition.record)? != source {
            return Err(invalid("source definition changed in proposal"));
        }
        let Payload::Assertion(initial) = &source.payload else {
            return Err(invalid("source must be an initial-value assertion"));
        };
        let source_p = base
            .iter()
            .find(|r| r.identity.record_id == initial.proposition.record)
            .ok_or_else(|| invalid("source proposition absent"))?;
        if get(&initial.proposition.record)? != source_p {
            return Err(invalid("source proposition changed in proposal"));
        }
        let Payload::Proposition(p) = &source_p.payload else {
            return Err(invalid("source proposition kind"));
        };
        if initial.attribute_mode != AttributeMode::InitialValue
            || initial.polarity != Polarity::Support
            || initial.precision != Precision::Exact
            || !initial.alternatives.is_empty()
            || p.value.is_none()
            || !p.roles.is_empty()
            || p.context != scope.context
            || initial.scope.context != scope.context
            || scope.realm.is_some()
            || initial.scope.realm.is_some()
        {
            return Err(invalid(
                "initial source value, polarity, precision or context unresolved",
            ));
        }
        let Payload::Property(property) = &get(&p.predicate.record)?.payload else {
            return Err(invalid("initialization requires a property"));
        };
        if !keys.insert((instance.record.clone(), p.predicate.record.clone())) {
            return Err(invalid("duplicate instance/property initialization"));
        }
        let worlds: Vec<Option<WorldId>> = match &scope.applicability {
            Applicability::Worlds { world_ids } if !world_ids.is_empty() => {
                world_ids.iter().cloned().map(Some).collect()
            }
            Applicability::UniverseWide => {
                let all: Vec<_> = records
                    .iter()
                    .filter(|r| matches!(r.payload, Payload::World(_)))
                    .map(|r| Some(universe_store::kernel::record_world(&r.identity.record_id)))
                    .collect();
                if all.is_empty() {
                    vec![None]
                } else {
                    all
                }
            }
            _ => return Err(invalid("initialization jurisdiction unresolved")),
        };
        for world in worlds {
            if world.as_ref().is_some_and(|w| !event.worlds.contains(w)) {
                return Err(invalid("start does not establish the requested world"));
            }
            let worlds: Vec<_> = world
                .iter()
                .map(|w| {
                    RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)).expect("world record")
                })
                .collect();
            if definitions::matches(
                &instance.record,
                &property.subject_types,
                &records,
                Some(&worlds),
            ) != Some(true)
            {
                return Err(invalid("property applicability unresolved"));
            }
            let mut selected = false;
            for row in &records {
                let Payload::Assertion(a) = &row.payload else {
                    continue;
                };
                if a.attribute_mode != AttributeMode::InitialValue {
                    continue;
                }
                let Payload::Proposition(other) = &get(&a.proposition.record)?.payload else {
                    continue;
                };
                if other.predicate != p.predicate
                    || !chain.types.contains(&other.subject.record)
                    || other.context != scope.context
                    || a.scope.context != scope.context
                {
                    continue;
                }
                let Payload::EntityType(t) = &get(&other.subject.record)?.payload else {
                    continue;
                };
                let checks = [
                    definitions::world_applies(&a.scope.applicability, &worlds),
                    definitions::world_applies(&t.applicability, &worlds),
                    events::applies(
                        &a.validity,
                        &FrameTime::At {
                            time: event.time.clone(),
                        },
                        &records,
                    ),
                ];
                if checks.contains(&Some(false)) {
                    continue;
                }
                if checks.contains(&None)
                    || a.scope.realm.is_some()
                    || a.precision != Precision::Exact
                    || !a.alternatives.is_empty()
                    || other.value.is_none()
                    || !other.roles.is_empty()
                {
                    return Err(invalid(
                        "initial-value candidates unresolved; retain evidence for resolution",
                    ));
                }
                let equal = same_value(&p.value, &other.value);
                if (a.polarity == Polarity::Support && equal != Some(true))
                    || (a.polarity == Polarity::Refutation && equal != Some(false))
                {
                    return Err(invalid("initial-value candidates conflict or are unresolved; retain evidence for resolution"));
                }
                selected |= row.record_version_id == definition.version;
            }
            if !selected {
                return Err(invalid(
                    "selected initial source is inapplicable to this start",
                ));
            }
        }
        let proposition_id =
            RecordId::parse(client_ref).unwrap_or_else(|_| RecordId::generate(&mut rand::rng()));
        if client_ref.trim().is_empty()
            || candidate.contains_key(&proposition_id)
            || !input_refs.insert(proposition_id.clone())
        {
            return Err(invalid("initial proposition identity already used"));
        }
        let assertion_id = RecordId::generate(&mut rand::rng());
        let assertion = Assertion {
            attribute_mode: AttributeMode::Instance,
            proposition: RecordRef::new(u.clone(), proposition_id.clone()),
            polarity: Polarity::Support,
            scope: scope.clone(),
            validity: validity.clone(),
            persistence: initial.persistence,
            precision: Precision::Exact,
            alternatives: vec![],
            basis: EvidenceBasis::InstanceInitialization {
                start: VersionRef {
                    universe: Some(u.clone()),
                    record: start.record.clone(),
                    version: start_version.record_version_id.clone(),
                },
                definition: definition.clone(),
                source_revision: revision.clone(),
            },
            established_by: None,
        };
        let mut proposition = p.clone();
        proposition.subject = instance.clone();
        proposition.quantification = Quantification::Particular;
        for (record_id, payload) in [
            (proposition_id, Payload::Proposition(proposition)),
            (assertion_id, Payload::Assertion(assertion)),
        ] {
            changes.push(Assignment {
                record_id: record_id.clone(),
                expected: None,
                next: Some(RecordVersion::build(
                    RecordVersionId::generate(&mut rand::rng()),
                    RecordIdentity::new(u.clone(), record_id, payload.kind()),
                    payload,
                )?),
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value as Json};
    fn id(prefix: &str, n: u64) -> String {
        format!("{prefix}_{n:024x}")
    }
    fn u() -> UniverseId {
        UniverseId::parse(&id("unv", 1)).unwrap()
    }
    fn revision() -> RevisionId {
        RevisionId::parse(&id("rev", 1)).unwrap()
    }
    fn rr(n: u64) -> Json {
        json!({"universe":u(),"record":id("rec",n)})
    }
    fn record(n: u64, payload: Json) -> RecordVersion {
        let p: Payload = serde_json::from_value(payload).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&id("ver", n)).unwrap(),
            RecordIdentity::new(u(), RecordId::parse(&id("rec", n)).unwrap(), p.kind()),
            p,
        )
        .unwrap()
    }
    fn interval(start: i32, end: i32) -> Json {
        json!({"kind":"calendar_interval","calendar":id("cal",6),"start":{"kind":"exact","value":start.to_string()},"end":{"kind":"exact","value":end.to_string()}})
    }
    fn scope() -> Json {
        json!({"context":rr(5),"applicability":{"kind":"universe_wide"}})
    }
    fn definition(n: u64, parent: Option<u64>) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"entity_type","namespace":"init","key":format!("type{n}"),"name":format!("Type{n}"),"labels":{},"parent":parent.map(|n|id("rec",n)),"parentResolution":if parent.is_some(){"resolved"}else{"root"},"applicability":{"kind":"universe_wide"},"classificationExecutable":true}),
        )
    }
    fn proposition(n: u64, subject: u64, value: &str) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"proposition","subject":rr(subject),"predicate":rr(4),"value":{"kind":"integer","digits":value},"quantification":"particular","context":rr(5)}),
        )
    }
    fn assertion(n: u64, prop: u64) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"assertion","attributeMode":"initial_value","proposition":rr(prop),"polarity":"support","scope":scope(),"validity":interval(0,100),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored initial definition"}}),
        )
    }
    fn fixture() -> Vec<RecordVersion> {
        vec![
            definition(1, None),
            definition(2, Some(1)),
            record(
                3,
                json!({"record_kind":"entity","names":[],"classification":id("rec",2),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}}),
            ),
            record(
                4,
                json!({"record_kind":"property","namespace":"init","key":"rounds","labels":{},"subjectTypes":[id("rec",1)],"value":{"kind":"integer"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
            ),
            record(
                5,
                json!({"record_kind":"represented_context","universe":u(),"kind":{"kind":"objective"},"labels":{}}),
            ),
            record(
                6,
                json!({"record_kind":"calendar","namespace":"init","key":"clock","labels":{},"unitStructure":{}}),
            ),
            proposition(7, 1, "7"),
            assertion(8, 7),
            record(
                9,
                json!({"record_kind":"event","occurrence":"occurred","expansionVersion":universe_rules::events::EXPANSION,"worlds":[],"time":{"kind":"exact","calendar":id("cal",6),"value":"10"},"participants":[{"record":rr(3),"role":"starting_instance"}],"labels":{}}),
            ),
        ]
    }
    fn op() -> Json {
        json!({"kind":"initialize_instance","client_ref":id("rec",50),"instance":rr(3),"start":rr(9),"definition":{"universe":u(),"record":id("rec",8),"version":id("ver",8)},"scope":scope(),"validity":interval(10,20)})
    }
    fn run(base: &[RecordVersion], operation: Json) -> anyhow::Result<Vec<Assignment>> {
        crate::operations::compile(
            &u(),
            &revision(),
            base,
            &[serde_json::from_value(operation).unwrap()],
        )
    }
    #[test]
    fn selected_source_generates_separate_frozen_instance_state() {
        let rows = fixture();
        let changes = run(&rows, op()).unwrap();
        assert_eq!(changes.len(), 2);
        let assertion = changes
            .iter()
            .find_map(|c| {
                if let Some(RecordVersion {
                    payload: Payload::Assertion(a),
                    ..
                }) = &c.next
                {
                    Some(a)
                } else {
                    None
                }
            })
            .unwrap();
        assert_eq!(assertion.attribute_mode, AttributeMode::Instance);
        assert_eq!(
            assertion.validity,
            serde_json::from_value(interval(10, 20)).unwrap()
        );
        assert!(
            matches!(&assertion.basis,EvidenceBasis::InstanceInitialization{start,definition,source_revision} if start.version.as_str()==id("ver",9) && definition.version.as_str()==id("ver",8) && source_revision==&revision())
        );
        let proposition = changes
            .iter()
            .find_map(|c| {
                if let Some(RecordVersion {
                    payload: Payload::Proposition(p),
                    ..
                }) = &c.next
                {
                    Some(p)
                } else {
                    None
                }
            })
            .unwrap();
        assert_eq!(proposition.subject, serde_json::from_value(rr(3)).unwrap());
        assert_eq!(
            proposition.value,
            Some(Value::Integer { digits: "7".into() })
        );

        let mut initialized=rows.clone();
        initialized.extend(changes.iter().filter_map(|c|c.next.clone()));
        let error=run(&initialized,json!({"kind":"withdraw_event","record":rr(9),"expected_version":id("ver",9),"rationale":"Incorrectly recorded instance start"})).unwrap_err();
        assert!(error.to_string().contains("surviving initialization requires its occurred start"),"{error}");
        assert_eq!(initialized.iter().filter(|r|matches!(&r.payload,Payload::Assertion(a) if matches!(&a.basis,EvidenceBasis::InstanceInitialization{..}))).count(),1);
        assert_eq!(rows, fixture());
    }
    #[test]
    fn conflicting_unknown_and_opposed_candidates_are_retained_and_block_initialization() {
        for mode in 0..3 {
            let mut rows = fixture();
            rows.push(proposition(10, 2, if mode == 0 { "3" } else { "7" }));
            let mut other = assertion(11, 10);
            if let Payload::Assertion(a) = &mut other.payload {
                if mode == 1 {
                    a.validity = Validity::Unknown;
                }
                if mode == 2 {
                    a.polarity = Polarity::Refutation;
                }
            }
            rows.push(other);
            let original = rows.clone();
            assert!(run(&rows, op()).is_err());
            assert_eq!(rows, original);
        }
    }
    #[test]
    fn agreeing_sources_keep_the_explicitly_selected_provenance() {
        let mut rows = fixture();
        rows.push(proposition(10, 2, "7"));
        rows.push(assertion(11, 10));
        let changes = run(&rows, op()).unwrap();
        assert_eq!(changes.len(), 2);
        assert!(changes.iter().any(|c|matches!(&c.next.as_ref().unwrap().payload,Payload::Assertion(a) if matches!(&a.basis,EvidenceBasis::InstanceInitialization{definition,..} if definition.version.as_str()==id("ver",8)))));
    }
    #[test]
    fn authored_start_and_source_boundaries_are_required() {
        let mut rows = fixture();
        if let Payload::Event(e) = &mut rows[8].payload {
            e.occurrence = OccurrenceMode::Planned;
        }
        assert!(run(&rows, op()).is_err());
        let mut wrong = op();
        wrong["validity"] = interval(11, 20);
        assert!(run(&fixture(), wrong).is_err());
        let mut rows = fixture();
        if let Payload::Assertion(a) = &mut rows[7].payload {
            a.validity = serde_json::from_value(interval(0, 10)).unwrap();
        }
        assert!(run(&rows, op()).is_err());
    }
    #[test]
    fn scope_can_narrow_an_approved_universe_definition_without_borrowing_other_worlds() {
        let mut rows = fixture();
        rows.push(record(
            12,
            json!({"record_kind":"world","selector":"A","labels":{},"metadata":{}}),
        ));
        let world = WorldId::parse(&id("wld", 12)).unwrap();
        if let Payload::Event(e) = &mut rows[8].payload {
            e.worlds = vec![world.clone()];
        }
        let mut operation = op();
        operation["scope"]["applicability"] = json!({"kind":"worlds","world_ids":[world]});
        let changes = run(&rows, operation.clone()).unwrap();
        assert!(changes.iter().any(|c|matches!(&c.next.as_ref().unwrap().payload,Payload::Assertion(a) if serde_json::to_value(&a.scope).unwrap()["applicability"]==operation["scope"]["applicability"])));
        operation["scope"]["applicability"]["world_ids"] = json!([id("wld", 13)]);
        assert!(run(&rows, operation).is_err());
    }
    #[test]
    fn same_batch_source_edit_cannot_change_the_frozen_initial_definition() {
        let rows = fixture();
        let mut replacement = serde_json::to_value(&rows[7].payload).unwrap();
        replacement.as_object_mut().unwrap().remove("record_kind");
        replacement["precision"] = json!("unresolved");
        let change = json!({"kind":"supersede_assertion","record":rr(8),"expected_version":id("ver",8),"replacement":replacement,"rationale":"Explicit correction"});
        let ops = vec![
            serde_json::from_value(op()).unwrap(),
            serde_json::from_value(change).unwrap(),
        ];
        assert!(crate::operations::compile(&u(), &revision(), &rows, &ops).is_err());
    }
    #[test]
    fn raw_assertions_cannot_bypass_initial_candidate_resolution() {
        let rows = fixture();
        let changes = run(&rows, op()).unwrap();
        let p = changes
            .iter()
            .find_map(|c| {
                if let Payload::Proposition(p) = &c.next.as_ref().unwrap().payload {
                    Some(p)
                } else {
                    None
                }
            })
            .unwrap();
        let a = changes
            .iter()
            .find_map(|c| {
                if let Payload::Assertion(a) = &c.next.as_ref().unwrap().payload {
                    Some(a)
                } else {
                    None
                }
            })
            .unwrap();
        let raw = json!({"kind":"assert_proposition","client_ref":id("rec",50),"proposition":p,"assertion":a});
        assert!(run(&rows, raw)
            .unwrap_err()
            .to_string()
            .contains("requires initialize_instance"));
    }
}
