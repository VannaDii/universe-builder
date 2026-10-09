//! Read-only assembly over the already pinned and permission-filtered snapshot.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{frame::Frame, ids::*, records::*, scope::*};
use universe_protocol::response::*;
use universe_rules::definitions;

fn combine(a: Option<bool>, b: Option<bool>) -> Option<bool> {
    match (a, b) {
        (Some(false), _) | (_, Some(false)) => Some(false),
        (Some(true), Some(true)) => Some(true),
        _ => None,
    }
}
fn evidence(record: &RecordVersion, checks: Vec<(&str, Option<bool>)>) -> ObjectEvidence {
    let mut applicability = Some(true);
    for (_, check) in &checks {
        applicability = combine(applicability, *check);
    }
    ObjectEvidence {
        record: record.clone(),
        applicability,
        unknowns: checks
            .into_iter()
            .filter(|(_, v)| v.is_none())
            .map(|(s, _)| s.into())
            .collect(),
    }
}
fn scoped(scope: &Scope, frame: &Frame, worlds: &[RecordId]) -> Vec<(&'static str, Option<bool>)> {
    vec![
        (
            "world_applicability",
            definitions::world_applies(&scope.applicability, worlds),
        ),
        ("represented_context", Some(scope.context == frame.context)),
        (
            "realm_applicability",
            if scope.realm.is_some() {
                None
            } else {
                Some(true)
            },
        ),
    ]
}

pub fn assemble(
    records: &[RecordVersion],
    ids: &[RecordId],
    predicates: &[RecordId],
    frame: &Frame,
    world: Option<&WorldId>,
    restricted: bool,
) -> Vec<EffectiveObject> {
    assemble_impl(records, ids, predicates, frame, world, restricted, true)
}

#[cfg(test)]
pub(super) fn assemble_reference(
    records: &[RecordVersion],
    ids: &[RecordId],
    predicates: &[RecordId],
    frame: &Frame,
    world: Option<&WorldId>,
    restricted: bool,
) -> Vec<EffectiveObject> {
    assemble_impl(records, ids, predicates, frame, world, restricted, false)
}

fn assemble_impl(
    records: &[RecordVersion],
    ids: &[RecordId],
    predicates: &[RecordId],
    frame: &Frame,
    world: Option<&WorldId>,
    restricted: bool,
    indexed_candidates: bool,
) -> Vec<EffectiveObject> {
    let worlds: Vec<_> = world
        .into_iter()
        .map(|w| RecordId::parse(&w.as_str().replacen("wld_", "rec_", 1)).expect("world identity"))
        .collect();
    let by_id: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let record_index = definitions::RecordIndex::new(records);
    let get = |id: &RecordId| by_id.get(id).copied();
    let type_matches = |subject: &RecordId, targets: &[RecordId], worlds: Option<&[RecordId]>| {
        if indexed_candidates {
            record_index.matches(subject, targets, worlds)
        } else {
            definitions::matches(subject, targets, records, worlds)
        }
    };
    let time_applies = |validity: &universe_domain::scope::Validity,
                        time: &universe_domain::frame::FrameTime| {
        if indexed_candidates {
            universe_rules::events::applies_indexed(validity, time, &record_index)
        } else {
            universe_rules::events::applies(validity, time, records)
        }
    };
    let mut assertions_by_subject: BTreeMap<RecordId, Vec<usize>> = BTreeMap::new();
    let mut shared_candidate_positions = Vec::new();
    for (position, record) in records.iter().enumerate() {
        match &record.payload {
            Payload::Assertion(assertion) => {
                if let Some(RecordVersion {
                    payload: Payload::Proposition(proposition),
                    ..
                }) = get(&assertion.proposition.record)
                {
                    assertions_by_subject
                        .entry(proposition.subject.record.clone())
                        .or_default()
                        .push(position);
                }
            }
            Payload::ActionDefinition(_) | Payload::Rule(_) => {
                shared_candidate_positions.push(position)
            }
            _ => {}
        }
    }
    let resource_gaps = crate::resources::assess(records, frame);
    let mut pairs_remaining = 1_000_000usize;
    ids.iter()
        .filter_map(|id| {
            let identity = get(id)?;
            if !matches!(
                identity.payload,
                Payload::Entity(_) | Payload::EntityType(_)
            ) {
                return None;
            }
            let chain = if indexed_candidates {
                record_index.ancestry(id)
            } else {
                definitions::ancestry(id, records)
            };
            // Include the visible unresolved endpoint as provenance even when
            // executable ancestry stops before that definition.
            let mut ancestry = Vec::new();
            let mut seen = BTreeSet::new();
            let mut next = match &identity.payload {
                Payload::Entity(e) if e.classification_resolution == ClassificationResolution::Resolved => e.classification.clone(),
                Payload::EntityType(_) => Some(id.clone()),
                _ => None,
            };
            while let Some(type_id) = next {
                if !seen.insert(type_id.clone()) { break; }
                let Some(r) = get(&type_id).filter(|r| r.identity.universe_id == identity.identity.universe_id) else { break; };
                let Payload::EntityType(t) = &r.payload else { break; };
                ancestry.push(r.clone());
                if !t.classification_executable || t.parent_resolution != ParentResolution::Resolved { break; }
                next = t.parent.clone();
            }
            let definition_ids: Vec<_> = ancestry.iter().map(|r| r.identity.record_id.clone()).collect();
            let mut candidate_positions = if indexed_candidates {
                let mut positions = shared_candidate_positions.clone();
                for subject in std::iter::once(id).chain(definition_ids.iter()) {
                    if let Some(assertions) = assertions_by_subject.get(subject) {
                        positions.extend(assertions.iter().copied());
                    }
                }
                positions.sort_unstable();
                positions.dedup();
                positions
            } else {
                (0..records.len()).collect()
            };
            let mut object = EffectiveObject {
                identity: identity.clone(),
                contextual_names: if matches!(frame.perspective, universe_domain::frame::Perspective::Author) {
                    if let Payload::Entity(entity) = &identity.payload {
                        entity.names.iter().map(|name| ContextualNameEvidence { name: name.clone(), applicability: universe_rules::events::applies(&name.validity, &frame.time, records) }).collect()
                    } else { vec![] }
                } else { vec![] },
                ancestry,
                ancestry_complete: chain.complete,
                shared_attributes: vec![],
                instance_facts: vec![],
                initial_value_candidates: vec![],
                initialization_receipts: vec![],
                initialization_history_coverage: Coverage::Partial,
                behavioral_requirements: vec![],
                rules: vec![],
                dependencies: vec![],
                conflicts: vec![],
                unknowns: vec![],
                coverage: Coverage::Complete,
            };
            if !chain.complete {
                object
                    .unknowns
                    .push("classification_or_ancestry_unresolved".into());
            }
            if restricted {
                object
                    .unknowns
                    .push("current_permissions_or_perspective_limit_evidence".into());
            }
            let mut dependencies = BTreeSet::new();
            for position in candidate_positions.drain(..) {
                let r = &records[position];
                match &r.payload {
                    Payload::Assertion(a) => {
                        let Some(proposition) = get(&a.proposition.record) else {
                            continue;
                        };
                        let Payload::Proposition(p) = &proposition.payload else {
                            continue;
                        };
                        let direct =
                            a.attribute_mode == AttributeMode::Instance && &p.subject.record == id;
                        let inherited = a.attribute_mode != AttributeMode::Instance
                            && definition_ids.contains(&p.subject.record);
                        if !(direct || inherited)
                            || !predicates.is_empty() && !predicates.contains(&p.predicate.record)
                        {
                            continue;
                        }
                        let mut checks = scoped(&a.scope, frame, &worlds);
                        checks.push(("proposition_context", Some(p.context == frame.context)));
                        checks.push((
                            "temporal_applicability",
                            time_applies(&a.validity, &frame.time),
                        ));
                        if inherited {
                            checks.push((
                                "definition_ancestry",
                                if chain.complete { Some(true) } else { None },
                            ));
                            if let Some(RecordVersion {
                                payload: Payload::EntityType(t),
                                ..
                            }) = get(&p.subject.record)
                            {
                                checks.push((
                                    "ancestor_world_applicability",
                                    definitions::world_applies(&t.applicability, &worlds),
                                ));
                            }
                        }
                        if let Some(RecordVersion {
                            payload: Payload::Property(property),
                            ..
                        }) = get(&p.predicate.record)
                        {
                            checks.push((
                                "property_subject_applicability",
                                    type_matches(
                                        id,
                                        &property.subject_types,
                                        Some(&worlds),
                                ),
                            ));
                        }
                        let mut row = evidence(r, checks);
                        match &resource_gaps {
                            Ok(gaps) => for gap in gaps.iter().filter(|g| g.assertion == r.identity.record_id) {
                                row.unknowns.push(format!("resource_arrival_unexplained:{}",gap.fingerprint.as_str()));
                                object.unknowns.push("resource_arrival_unexplained".into());
                                dependencies.insert(gap.rule.clone());
                                dependencies.insert(gap.proposition.clone());
                                if let Some(decision) = &gap.acceptance { dependencies.insert(decision.clone()); }
                            },
                            Err(_) => row.unknowns.push("resource_accounting_unresolved".into()),
                        }
                        if a.precision != Precision::Exact || !a.alternatives.is_empty() {
                            row.unknowns.push("assertion_value_or_precision_unresolved".into());
                        }
                        if row.applicability == Some(false) {
                            continue;
                        }
                        dependencies.insert(p.predicate.record.clone());
                        dependencies.insert(a.proposition.record.clone());
                        match a.attribute_mode {
                            AttributeMode::Instance => object.instance_facts.push(row),
                            AttributeMode::Shared => object.shared_attributes.push(row),
                            AttributeMode::InitialValue => {
                                object.initial_value_candidates.push(row)
                            }
                        }
                    }
                    Payload::ActionDefinition(a) => {
                        // Requirements describe possible owning roles, never prove the
                        // object can perform an action or bind it to a participant.
                        let mut relevant = if a.requirements.is_empty() {
                            Some(true)
                        } else {
                            Some(false)
                        };
                        for requirement in &a.requirements {
                            let applies =
                                match get(&requirement.predicate.record).map(|r| &r.payload) {
                                    Some(Payload::Property(p)) => type_matches(
                                        id,
                                        &p.subject_types,
                                        Some(&worlds),
                                    ),
                                    _ => None,
                                };
                            relevant = match (relevant, applies) {
                                (Some(true), _) | (_, Some(true)) => Some(true),
                                (None, _) | (_, None) => None,
                                _ => Some(false),
                            };
                        }
                        let mut checks = scoped(&a.scope, frame, &worlds);
                        checks.push(("requirement_subject_applicability", relevant));
                        checks.push((
                            "temporal_applicability",
                            time_applies(&a.validity, &frame.time),
                        ));
                        let row = evidence(r, checks);
                        if row.applicability != Some(false) {
                            dependencies
                                .extend(a.requirements.iter().map(|r| r.predicate.record.clone()));
                            object.behavioral_requirements.push(row);
                        }
                    }
                    Payload::Rule(rule) => {
                        let typed = rule.channel_chronology.is_some() || rule.knowledge_policy.is_some() || rule.relation_cardinality.is_some();
                        let mut checks = vec![
                            ("rule_subject_applicability", type_matches(id, &rule.subject_types, Some(&worlds))),
                            ("world_applicability", definitions::world_applies(&rule.applicability, &worlds)),
                            ("temporal_applicability", if typed { Some(true) } else { time_applies(&rule.validity, &frame.time) }),
                        ];
                        if let Some(policy) = &rule.knowledge_policy {
                            checks.push(("knowledge_truth_context", Some(policy.context == frame.context)));
                        }
                        if let Some(contract) = &rule.relation_cardinality {
                            checks.extend(scoped(&contract.scope, frame, &worlds));
                            checks.push(("cardinality_validity", if contract.validity == Validity::Unspecified { Some(true) } else { time_applies(&contract.validity, &frame.time) }));
                        }
                        let row = evidence(r, checks);
                        if row.applicability != Some(false) {
                            object.rules.push(row);
                        }
                    }
                    _ => {}
                }
            }
            if object.instance_facts.is_empty() {
                object.unknowns.push("instance_state_not_established".into());
            }
            for predicate in predicates {
                if !object.instance_facts.iter().chain(&object.shared_attributes).any(|e| matches!(&e.record.payload, Payload::Assertion(a) if matches!(get(&a.proposition.record).map(|r| &r.payload), Some(Payload::Proposition(p)) if &p.predicate.record == predicate))) {
                    object.unknowns.push(format!("predicate_not_established:{predicate}"));
                }
            }
            object.dependencies = records
                .iter()
                .filter(|r| dependencies.contains(&r.identity.record_id))
                .cloned()
                .collect();
            // Compare continuing evidence together, but initial candidates separately.
            // Preserve every source; no subtype, newest revision or instance wins.
            'comparisons: for (initial, rows) in [
                (
                    false,
                    object
                        .shared_attributes
                        .iter()
                        .chain(object.instance_facts.iter())
                        .collect::<Vec<_>>(),
                ),
                (true, object.initial_value_candidates.iter().collect()),
            ] {
                for (i, a) in rows.iter().enumerate() {
                    let Payload::Assertion(aa) = &a.record.payload else {
                        continue;
                    };
                    let Some(RecordVersion {
                        payload: Payload::Proposition(ap),
                        ..
                    }) = get(&aa.proposition.record)
                    else {
                        continue;
                    };
                    for b in rows.iter().skip(i + 1) {
                        if pairs_remaining == 0 {
                            object.unknowns.push("conflict_comparison_budget_exhausted".into());
                            break 'comparisons;
                        }
                        pairs_remaining -= 1;
                        let Payload::Assertion(ba) = &b.record.payload else {
                            continue;
                        };
                        let Some(RecordVersion {
                            payload: Payload::Proposition(bp),
                            ..
                        }) = get(&ba.proposition.record)
                        else {
                            continue;
                        };
                        let equal = ap.value == bp.value || ap.value.as_ref().zip(bp.value.as_ref()).is_some_and(|(a,b)| universe_rules::basic::compare(a, universe_domain::Comparator::Eq, b) == Some(true));
                        let overlap = universe_rules::time::overlaps(&aa.validity, &ba.validity);
                        let disjoint_worlds = matches!((&aa.scope.applicability, &ba.scope.applicability), (Applicability::Worlds { world_ids: a }, Applicability::Worlds { world_ids: b }) if !a.iter().any(|w| b.contains(w)));
                        if ap.predicate == bp.predicate && ap.roles == bp.roles
                            && aa.scope.realm == ba.scope.realm && !disjoint_worlds && overlap != Some(false)
                            && ((equal && aa.polarity != ba.polarity)
                                || (!equal && aa.polarity == Polarity::Support && ba.polarity == Polarity::Support
                                    && matches!(get(&ap.predicate.record).map(|r| &r.payload), Some(Payload::Property(p)) if p.multiplicity == Multiplicity::Single || p.exclusive)))
                        {
                            object.conflicts.push(ObjectConflict {
                            applicability: combine(combine(combine(a.applicability, b.applicability), overlap),
                                    if aa.precision == Precision::Exact && ba.precision == Precision::Exact && aa.alternatives.is_empty() && ba.alternatives.is_empty() { Some(true) } else { None }),
                                predicate: ap.predicate.record.clone(),
                                assertions: vec![
                                    a.record.record_version_id.clone(),
                                    b.record.record_version_id.clone(),
                                ],
                                initial_values: initial,
                            });
                        }
                    }
                }
            }
            if object
                .shared_attributes
                .iter()
                .chain(&object.instance_facts)
                .chain(&object.initial_value_candidates)
                .chain(&object.behavioral_requirements)
                .chain(&object.rules)
                .any(|r| r.applicability.is_none())
            {
                object
                    .unknowns
                    .push("candidate_applicability_unresolved".into());
            }
            if object.conflicts.iter().any(|c| c.applicability.is_none()) {
                object.unknowns.push("conflict_applicability_unresolved".into());
            }
            if object.shared_attributes.iter().chain(&object.instance_facts).chain(&object.initial_value_candidates).any(|r| r.unknowns.iter().any(|s| s == "assertion_value_or_precision_unresolved")) {
                object.unknowns.push("assertion_value_or_precision_unresolved".into());
            }
            object.coverage = if restricted {
                Coverage::Restricted
            } else if !object.unknowns.is_empty() {
                Coverage::Partial
            } else {
                Coverage::Complete
            };
            Some(object)
        })
        .collect()
}
