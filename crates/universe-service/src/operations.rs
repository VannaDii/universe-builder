//! Pure operation compilation. IDs, versions and full effects are frozen before review.
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{ids::*, records::*, value::RecordRef};
use universe_protocol::ProtocolError;
use universe_store::kernel::{record_world, Assignment};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Footprint {
    pub worlds: BTreeSet<WorldId>,
    pub shared: bool,
    pub protected: bool,
}
pub fn worlds(record: &RecordVersion) -> BTreeSet<WorldId> {
    use universe_domain::scope::Applicability;
    match &record.payload {
        Payload::World(_) => BTreeSet::from([record_world(&record.identity.record_id)]),
        Payload::Entity(e) => e
            .world_associations
            .iter()
            .map(|w| w.world.clone())
            .collect(),
        Payload::Work(w) => w
            .world_associations
            .iter()
            .map(|w| w.world.clone())
            .collect(),
        Payload::Assertion(a) => match &a.scope.applicability {
            Applicability::Worlds { world_ids } => world_ids.iter().cloned().collect(),
            _ => BTreeSet::new(),
        },
        Payload::Event(e) => e.worlds.iter().cloned().collect(),
        Payload::ItemPower(p) => match &p.scope.applicability {
            Applicability::Worlds { world_ids } => world_ids.iter().cloned().collect(),
            _ => BTreeSet::new(),
        },
        Payload::ActionDefinition(a) => match &a.scope.applicability {
            Applicability::Worlds { world_ids } => world_ids.iter().cloned().collect(),
            _ => BTreeSet::new(),
        },
        Payload::Rule(r) => match &r.applicability {
            Applicability::Worlds { world_ids } => world_ids.iter().cloned().collect(),
            _ => BTreeSet::new(),
        },
        _ => BTreeSet::new(),
    }
}
pub fn protected(payload: &Payload) -> bool {
    !matches!(
        payload,
        Payload::Appearance(_)
            | Payload::ImageAsset(_)
            | Payload::Entity(_)
            | Payload::World(_)
            | Payload::Work(_)
            | Payload::Saga(_)
            | Payload::Proposition(_)
            | Payload::Assertion(_)
            | Payload::Anchor(_)
            | Payload::Source(_)
            | Payload::SourceVersion(_)
            | Payload::WorkVersion(_)
            | Payload::SceneRef(_)
            | Payload::PassageRef(_)
    )
}
pub fn footprint(base: &[RecordVersion], changes: &[Assignment]) -> Footprint {
    let mut result = Footprint::default();
    for change in changes {
        for record in base
            .iter()
            .filter(|r| r.identity.record_id == change.record_id)
            .chain(change.next.iter())
        {
            let w = worlds(record);
            result.shared |= w.is_empty();
            result.worlds.extend(w);
            result.protected |= protected(&record.payload);
        }
        // Include world effects reachable through explicit typed references. Prose
        // and authored metadata keys cannot turn an unassigned write into a grant.
        let mut pending: Vec<_> = base
            .iter()
            .filter(|r| r.identity.record_id == change.record_id)
            .chain(change.next.iter())
            .collect();
        let mut visited = BTreeSet::new();
        while let Some(record) = pending.pop() {
            if !visited.insert(record.record_version_id.clone()) {
                continue;
            }
            if let Ok(dependencies) = universe_store::kernel::record_dependencies(record) {
                for id in dependencies {
                    if let Some(next) = changes
                        .iter()
                        .find(|a| a.record_id == id)
                        .and_then(|a| a.next.as_ref())
                        .or_else(|| base.iter().find(|r| r.identity.record_id == id))
                    {
                        result.worlds.extend(worlds(next));
                        pending.push(next);
                    }
                }
            } else {
                result.shared = true;
            }
        }
        result.protected |= change.next.is_none();
    }
    result
}
fn unsupported() -> anyhow::Error {
    ProtocolError::UnsupportedSemantics { message:"operation requires event/knowledge/pack semantics outside the basic authoring evaluator".into() }.into()
}
fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("operations", message).into()
}
fn id(client_ref: &str, seen: &mut BTreeSet<String>) -> anyhow::Result<RecordId> {
    if client_ref.is_empty() || !seen.insert(client_ref.into()) {
        return Err(invalid("duplicate or empty client_ref"));
    }
    // An explicit rec_ ID reserves a forward-reference identity for this batch.
    // The kernel checks collision and namespace; friendly client refs allocate IDs.
    Ok(RecordId::parse(client_ref).unwrap_or_else(|_| RecordId::generate(&mut rand::rng())))
}
fn current<'a>(
    records: &'a BTreeMap<RecordId, RecordVersion>,
    u: &UniverseId,
    reference: &RecordRef,
    expected: &RecordVersionId,
) -> anyhow::Result<&'a RecordVersion> {
    if reference.universe.as_ref() != Some(u) {
        return Err(invalid("explicit local universe is required"));
    }
    let v = records
        .get(&reference.record)
        .ok_or_else(|| invalid("record unavailable"))?;
    if &v.record_version_id != expected {
        return Err(invalid("expected record version differs"));
    }
    Ok(v)
}
/// Lower authoring conveniences into the same closed canonical operations used
/// by all other proposal clients. Allocated IDs are frozen in StoredProposal.
fn incremental_operations(
    u: &UniverseId,
    base: &[RecordVersion],
    operations: &[DomainOperation],
) -> anyhow::Result<Vec<DomainOperation>> {
    use DomainOperation::*;
    let mut lowered = Vec::new();
    let mut properties: Vec<(RecordId, PropertyDef)> = base
        .iter()
        .filter_map(|r| {
            if let Payload::Property(p) = &r.payload {
                Some((r.identity.record_id.clone(), p.clone()))
            } else {
                None
            }
        })
        .collect();
    // Include explicit property creations regardless of operation ordering.
    for op in operations {
        if let DefineProperty { client_ref, record } = op {
            if !operations.iter().any(|op| matches!(op, AddNamedAttribute { namespace, key, .. } if namespace == &record.namespace && key == &record.key)) {
                continue;
            }
            let record_id = RecordId::parse(client_ref).map_err(|_| {
                invalid("a property referenced by name in this batch requires a rec_ ID")
            })?;
            properties.push((record_id, record.clone()));
        }
    }
    // Keep friendly input references unique even when lowering replaces one
    // with a reserved canonical proposition ID.
    let mut input_refs = BTreeSet::new();
    for op in operations {
        let input = serde_json::to_value(op)?;
        if let Some(name) = input.get("client_ref").and_then(|v| v.as_str()) {
            if name.is_empty() || !input_refs.insert(name.to_owned()) {
                return Err(invalid("duplicate or empty client_ref"));
            }
        }
    }
    let mut refs = BTreeSet::new();
    for op in operations {
        match op {
            IntroduceDefinition {
                client_ref,
                namespace,
                key,
                name,
                parent,
                applicability,
                classification_executable,
            } => {
                if name.trim().is_empty() {
                    return Err(invalid("definition name is required"));
                }
                lowered.push(DefineType {
                    client_ref: client_ref.clone(),
                    record: EntityType {
                        namespace: namespace.clone(),
                        key: key.clone(),
                        name: name.clone(),
                        labels: BTreeMap::new(),
                        parent: parent.clone(),
                        parent_resolution: if parent.is_some() {
                            ParentResolution::Resolved
                        } else {
                            ParentResolution::Root
                        },
                        applicability: applicability.clone(),
                        classification_executable: *classification_executable,
                    },
                });
            }
            IntroduceInstance {
                client_ref,
                name,
                classification,
                world_associations,
            } => {
                if name.text.trim().is_empty() {
                    return Err(invalid("instance name is required"));
                }
                lowered.push(CreateEntity {
                    client_ref: client_ref.clone(),
                    record: Entity {
                        names: vec![name.clone()],
                        classification: classification.clone(),
                        classification_resolution: if classification.is_some() {
                            ClassificationResolution::Resolved
                        } else {
                            ClassificationResolution::Unclassified
                        },
                        world_associations: world_associations.clone(),
                        labels: BTreeMap::new(),
                        metadata: BTreeMap::new(),
                    },
                });
            }
            AddNamedAttribute {
                client_ref,
                subject,
                namespace,
                key,
                value_shape,
                subject_types,
                multiplicity,
                value,
                evidence,
            } => {
                if matches!(
                    evidence.basis,
                    universe_domain::scope::EvidenceBasis::EventEffect { .. }
                ) {
                    return Err(invalid(
                        "physical transformations require the event operation path",
                    ));
                }
                if matches!(
                    evidence.basis,
                    universe_domain::scope::EvidenceBasis::InstanceInitialization { .. }
                ) {
                    return Err(invalid(
                        "initialization evidence requires initialize_instance",
                    ));
                }
                let definition = PropertyDef {
                    namespace: namespace.clone(),
                    key: key.clone(),
                    labels: BTreeMap::new(),
                    subject_types: subject_types.clone(),
                    value: value_shape.clone(),
                    multiplicity: *multiplicity,
                    unit_dimension: None,
                    persistence: evidence.persistence,
                    exclusive: false,
                    inverse: None,
                    symmetric: false,
                    transitive: false,
                };
                let matches: Vec<_> = properties
                    .iter()
                    .filter(|(_, p)| p.namespace == *namespace && p.key == *key)
                    .collect();
                let predicate = match matches.as_slice() {
                    [] => {
                        let predicate = RecordId::generate(&mut rand::rng());
                        lowered.push(DefineProperty {
                            client_ref: predicate.to_string(),
                            record: definition.clone(),
                        });
                        properties.push((predicate.clone(), definition));
                        predicate
                    }
                    [(id, existing)] => {
                        let mut expected = definition;
                        expected.labels = existing.labels.clone();
                        if existing != &expected {
                            return Err(invalid("named attribute definition differs; use an explicit definition revision"));
                        }
                        (*id).clone()
                    }
                    _ => return Err(invalid("named attribute is ambiguous")),
                };
                let proposition_id = id(client_ref, &mut refs)?;
                lowered.push(AssertProposition {
                    client_ref: proposition_id.to_string(),
                    proposition: Proposition {
                        predicate: RecordRef::new(u.clone(), predicate),
                        subject: subject.clone(),
                        roles: vec![],
                        value: Some(value.clone()),
                        quantification: Quantification::Particular,
                        context: evidence.scope.context.clone(),
                    },
                    assertion: Assertion {
                        proposition: RecordRef::new(u.clone(), proposition_id),
                        attribute_mode: evidence.attribute_mode,
                        polarity: evidence.polarity,
                        scope: evidence.scope.clone(),
                        validity: evidence.validity.clone(),
                        persistence: evidence.persistence,
                        precision: evidence.precision,
                        alternatives: evidence.alternatives.clone(),
                        basis: evidence.basis.clone(),
                        established_by: None,
                    },
                });
            }
            RefineClassification {
                record,
                expected_version,
                entity_type,
            } => lowered.push(AddTypeMembership {
                record: record.clone(),
                expected_version: expected_version.clone(),
                entity_type: entity_type.clone(),
            }),
            _ => lowered.push(op.clone()),
        }
    }
    Ok(lowered)
}

pub fn compile(
    u: &UniverseId,
    revision: &RevisionId,
    base: &[RecordVersion],
    operations: &[DomainOperation],
) -> anyhow::Result<Vec<Assignment>> {
    compile_allocated(u, revision, base, operations, &BTreeMap::new())
}

/// Server-allocated immutable versions for privately prepared source records.
/// Ordinary domain operations still use fresh engine-generated versions.
pub(crate) fn compile_allocated(
    u: &UniverseId,
    revision: &RevisionId,
    base: &[RecordVersion],
    operations: &[DomainOperation],
    versions: &BTreeMap<RecordId, RecordVersionId>,
) -> anyhow::Result<Vec<Assignment>> {
    let operations = incremental_operations(u, base, operations)?;
    let records: BTreeMap<_, _> = base
        .iter()
        .cloned()
        .map(|r| (r.identity.record_id.clone(), r))
        .collect();
    let mut changes = Vec::new();
    let mut seen = BTreeSet::new();
    let mut create = |name: &str, payload: Payload| -> anyhow::Result<()> {
        let record_id = id(name, &mut seen)?;
        if records.contains_key(&record_id) {
            return Err(invalid("new record identity already exists"));
        }
        let next = RecordVersion::build(
            versions
                .get(&record_id)
                .cloned()
                .unwrap_or_else(|| RecordVersionId::generate(&mut rand::rng())),
            RecordIdentity::new(u.clone(), record_id.clone(), payload.kind()),
            payload,
        )?;
        changes.push(Assignment {
            record_id,
            expected: None,
            next: Some(next),
        });
        Ok(())
    };
    for op in &operations {
        use DomainOperation::*;
        match op {
            CreateEntity { client_ref, record } => {
                create(client_ref, Payload::Entity(record.clone()))?
            }
            CreateWorld { client_ref, record } => {
                create(client_ref, Payload::World(record.clone()))?
            }
            CreateWork { client_ref, record } => create(client_ref, Payload::Work(record.clone()))?,
            CreateSaga { client_ref, record } => create(client_ref, Payload::Saga(record.clone()))?,
            DefineType { client_ref, record } => {
                create(client_ref, Payload::EntityType(record.clone()))?
            }
            DefineProperty { client_ref, record } => {
                create(client_ref, Payload::Property(record.clone()))?
            }
            DefineRelation { client_ref, record } => {
                create(client_ref, Payload::Relation(record.clone()))?
            }
            DefineUnit { client_ref, record } => create(client_ref, Payload::Unit(record.clone()))?,
            DefineCalendar { client_ref, record } => {
                create(client_ref, Payload::Calendar(record.clone()))?
            }
            DefineValue { client_ref, record } => {
                create(client_ref, Payload::ValueDefinition(record.clone()))?
            }
            DefineRule { client_ref, record } => create(client_ref, Payload::Rule(record.clone()))?,
            SetCompleteness { client_ref, record } => {
                create(client_ref, Payload::Completeness(record.clone()))?
            }
            SetCreativeBoundary { client_ref, record } => {
                create(client_ref, Payload::Boundary(record.clone()))?
            }
            AddException { client_ref, record } => {
                create(client_ref, Payload::Exception(record.clone()))?
            }
            AddSourceAnchor { client_ref, record } => {
                create(client_ref, Payload::Anchor(record.clone()))?
            }
            RecordNarrativeReference {
                client_ref,
                record,
                payload,
            } => {
                if *record != payload.kind()
                    || !matches!(
                        payload,
                        Payload::RepresentedContext(_)
                            | Payload::Source(_)
                            | Payload::SourceVersion(_)
                            | Payload::WorkVersion(_)
                            | Payload::SceneRef(_)
                            | Payload::PassageRef(_)
                    )
                {
                    return Err(invalid(
                        "narrative reference kind is not a narrative/source/context payload",
                    ));
                }
                create(client_ref, payload.clone())?;
            }
            AssertProposition {
                client_ref,
                proposition,
                assertion,
            }
            | RecordRelation {
                client_ref,
                proposition,
                assertion,
            } => {
                if matches!(
                    assertion.basis,
                    universe_domain::scope::EvidenceBasis::InstanceInitialization { .. }
                ) {
                    return Err(invalid(
                        "initialization evidence requires initialize_instance",
                    ));
                }
                // Caller reserves the proposition identity in client_ref so the
                // typed assertion can refer to it before either record exists.
                let reserved = RecordId::parse(client_ref)
                    .map_err(|_| invalid("proposition client_ref must reserve a rec_ ID"))?;
                if assertion.proposition != RecordRef::new(u.clone(), reserved) {
                    return Err(invalid("assertion must name this batch's proposition"));
                }
                create(client_ref, Payload::Proposition(proposition.clone()))?;
                create(
                    &format!("{client_ref}:assertion"),
                    Payload::Assertion(assertion.clone()),
                )?;
            }
            CreateAppearance { client_ref, record } => {
                create(client_ref, Payload::Appearance(record.clone()))?
            }
            AddImageAsset { client_ref, record } => {
                create(client_ref, Payload::ImageAsset(record.clone()))?
            }
            DefineItemPower { client_ref, record } => {
                create(client_ref, Payload::ItemPower(record.clone()))?
            }
            DefineAction { client_ref, record } => {
                create(client_ref, Payload::ActionDefinition(record.clone()))?
            }
            DefineProposition { client_ref, record } => {
                create(client_ref, Payload::Proposition(record.clone()))?
            }
            RecordEvent { client_ref, record } => {
                let mut event = record.clone();
                event.expansion_version = Some(universe_rules::events::EXPANSION.into());
                create(client_ref, Payload::Event(event))?;
            }
            AddBelief { client_ref, record } => {
                create(client_ref, Payload::EpistemicAttitude(record.clone()))?
            }
            RecordObservation { client_ref, record } => {
                create(client_ref, Payload::Observation(record.clone()))?
            }
            RecordCommunication { client_ref, record } => {
                create(client_ref, Payload::Communication(record.clone()))?
            }
            RecordMemory { client_ref, record } => {
                create(client_ref, Payload::Memory(record.clone()))?
            }
            RecordPlan { client_ref, record } => create(client_ref, Payload::Goal(record.clone()))?,
            RecordCommitment { client_ref, record } => {
                create(client_ref, Payload::Commitment(record.clone()))?
            }
            RecordIssueDecision { client_ref, record } => {
                create(client_ref, Payload::IssueDecision(record.clone()))?
            }
            InstallPack { client_ref, record } => {
                create(client_ref, Payload::DomainPack(record.clone()))?
            }
            InitializeInstance { .. }
            | ReviseAppearance { .. }
            | ReviseDefinition { .. }
            | ReviseItemPower { .. }
            | AdoptRecordVersion { .. }
            | ReviseEvent { .. }
            | UpgradePack { .. }
            | SetStoryTime { .. }
            | AddName { .. }
            | AddTypeMembership { .. }
            | RenameWorldSelector { .. }
            | AddWorldAlias { .. }
            | SetWorkBinding { .. }
            | AssociateWorkWorld { .. }
            | SetSagaMembership { .. }
            | EndAssertionAt { .. }
            | SupersedeAssertion { .. }
            | RetractAssertion { .. }
            | TombstoneRecord { .. } => {}
            _ => return Err(unsupported()),
        }
    }
    let mut ancestry: BTreeMap<_, _> = records
        .iter()
        .map(|(id, r)| (id.clone(), r.clone()))
        .chain(
            changes
                .iter()
                .filter_map(|a| a.next.as_ref().map(|r| (a.record_id.clone(), r.clone()))),
        )
        .collect();
    // Refinement is checked against the candidate definition graph, including
    // authored revisions/adoptions/tombstones in this batch, not stale ancestry.
    for op in &operations {
        match op {
            DomainOperation::ReviseDefinition {
                record,
                expected_version,
                replacement,
            } if matches!(replacement.as_ref(), Payload::EntityType(_)) => {
                let mut candidate = current(&records, u, record, expected_version)?.clone();
                candidate.payload = *replacement.clone();
                ancestry.insert(record.record.clone(), candidate);
            }
            DomainOperation::AdoptRecordVersion { source, .. }
                if matches!(source.payload, Payload::EntityType(_)) =>
            {
                ancestry.insert(source.identity.record_id.clone(), *source.clone());
            }
            DomainOperation::TombstoneRecord { record, .. } => {
                ancestry.remove(&record.record);
            }
            _ => {}
        }
    }
    for op in &operations {
        use DomainOperation::*;
        let (reference, expected, payload) = match op {
            ReviseAppearance {
                record,
                expected_version,
                replacement,
            } => {
                if !matches!(
                    current(&records, u, record, expected_version)?.payload,
                    Payload::Appearance(_)
                ) {
                    return Err(invalid("expected appearance"));
                }
                (
                    record,
                    expected_version,
                    Some(Payload::Appearance(replacement.clone())),
                )
            }
            ReviseEvent {
                record,
                expected_version,
                replacement,
            } => {
                if !matches!(
                    current(&records, u, record, expected_version)?.payload,
                    Payload::Event(_)
                ) {
                    return Err(invalid("expected event"));
                }
                let mut e = replacement.clone();
                e.expansion_version = Some(universe_rules::events::EXPANSION.into());
                (record, expected_version, Some(Payload::Event(e)))
            }
            ReviseItemPower {
                record,
                expected_version,
                replacement,
                rationale,
            } => {
                let Payload::ItemPower(old) =
                    &current(&records, u, record, expected_version)?.payload
                else {
                    return Err(invalid("expected item-power declaration"));
                };
                if rationale.trim().is_empty()
                    || old.item != replacement.item
                    || old.holder_predicate != replacement.holder_predicate
                    || old.power_predicate != replacement.power_predicate
                    || old.scope.context != replacement.scope.context
                {
                    return Err(invalid("item-power correction requires a reason and must retain item, holder property, ability property and represented context"));
                }
                let calendar = |v: &universe_domain::scope::Validity| match v {
                    universe_domain::scope::Validity::CalendarInterval { calendar, .. } => {
                        Some(calendar.clone())
                    }
                    universe_domain::scope::Validity::Instant {
                        at: universe_domain::temporal::TemporalExpression::Exact { calendar, .. },
                    } => Some(calendar.clone()),
                    _ => None,
                };
                if calendar(&old.validity).is_some()
                    && calendar(&old.validity) != calendar(&replacement.validity)
                {
                    return Err(invalid(
                        "item-power correction must retain its authored calendar",
                    ));
                }
                (
                    record,
                    expected_version,
                    Some(Payload::ItemPower(replacement.clone())),
                )
            }
            ReviseDefinition {
                record,
                expected_version,
                replacement,
            } => {
                let old = &current(&records, u, record, expected_version)?.payload;
                if old.kind() != replacement.kind()
                    || !matches!(
                        old,
                        Payload::EntityType(_)
                            | Payload::Property(_)
                            | Payload::Relation(_)
                            | Payload::Unit(_)
                            | Payload::Calendar(_)
                            | Payload::ValueDefinition(_)
                            | Payload::Rule(_)
                            | Payload::ActionDefinition(_)
                    )
                {
                    return Err(invalid("only a same-kind definition can be revised"));
                }
                let a = serde_json::to_value(old)?;
                let b = serde_json::to_value(replacement)?;
                if a["namespace"] != b["namespace"] || a["key"] != b["key"] {
                    return Err(invalid("definition revision must retain namespace and key"));
                }
                (record, expected_version, Some(*replacement.clone()))
            }
            UpgradePack {
                record,
                expected_version,
                replacement,
            } => {
                let Payload::DomainPack(old) =
                    &current(&records, u, record, expected_version)?.payload
                else {
                    return Err(invalid("expected domain pack"));
                };
                if old.key != replacement.key || old.version == replacement.version {
                    return Err(invalid("pack upgrade must retain key and change version"));
                }
                (
                    record,
                    expected_version,
                    Some(Payload::DomainPack(replacement.clone())),
                )
            }
            AddName {
                record,
                expected_version,
                name,
            } => {
                let Payload::Entity(mut e) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected entity"));
                };
                e.names.push(name.clone());
                (record, expected_version, Some(Payload::Entity(e)))
            }
            AddTypeMembership {
                record,
                expected_version,
                entity_type,
            } => {
                let Payload::Entity(mut e) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected entity"));
                };
                if e.classification_resolution == ClassificationResolution::Ambiguous {
                    return Err(invalid(
                        "ambiguous classification requires an explicit authored correction",
                    ));
                }
                if !matches!(ancestry.get(entity_type).map(|r| &r.payload), Some(Payload::EntityType(t)) if t.parent_resolution != ParentResolution::Ambiguous)
                {
                    return Err(invalid("refinement requires a resolved definition"));
                }
                if let Some(prior) = &e.classification {
                    let mut next = Some(entity_type);
                    let mut seen = BTreeSet::new();
                    let mut refinement = false;
                    while let Some(id) = next {
                        if id == prior {
                            refinement = true;
                            break;
                        }
                        if !seen.insert(id) {
                            break;
                        }
                        next = match ancestry.get(id).map(|r| &r.payload) {
                            Some(Payload::EntityType(t))
                                if t.parent_resolution != ParentResolution::Ambiguous =>
                            {
                                t.parent.as_ref()
                            }
                            _ => None,
                        };
                    }
                    if !refinement {
                        return Err(invalid("classification change is not a descendant refinement; use an explicit authored correction"));
                    }
                }
                e.classification = Some(entity_type.clone());
                e.classification_resolution = ClassificationResolution::Resolved;
                (record, expected_version, Some(Payload::Entity(e)))
            }
            RenameWorldSelector {
                record,
                expected_version,
                new_selector,
            }
            | AddWorldAlias {
                record,
                expected_version,
                alias: new_selector,
            } => {
                let Payload::World(mut w) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected world"));
                };
                if matches!(op, RenameWorldSelector { .. }) {
                    w.aliases.push(w.selector);
                    w.selector = new_selector.clone();
                } else {
                    w.aliases.push(new_selector.clone());
                }
                (record, expected_version, Some(Payload::World(w)))
            }
            SetWorkBinding {
                record,
                expected_version,
                binding,
            } => {
                let Payload::WorkVersion(mut w) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected work version"));
                };
                w.binding = binding.clone();
                (record, expected_version, Some(Payload::WorkVersion(w)))
            }
            AssociateWorkWorld {
                record,
                expected_version,
                association,
            } => {
                let Payload::Work(mut w) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected work"));
                };
                w.world_associations.push(association.clone());
                (record, expected_version, Some(Payload::Work(w)))
            }
            SetSagaMembership {
                record,
                expected_version,
                membership,
            } => {
                let Payload::Saga(mut saga) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected saga"));
                };
                if membership.work.universe.as_ref() != Some(u) {
                    return Err(invalid("membership must name a work in this universe"));
                }
                // Membership is keyed by work and role; a work may serve multiple roles.
                if let Some(existing) = saga
                    .memberships
                    .iter_mut()
                    .find(|m| m.work == membership.work && m.role == membership.role)
                {
                    *existing = membership.clone();
                } else {
                    saga.memberships.push(membership.clone());
                }
                (record, expected_version, Some(Payload::Saga(saga)))
            }
            SupersedeAssertion {
                record,
                expected_version,
                replacement,
                ..
            } => {
                if !matches!(
                    current(&records, u, record, expected_version)?.payload,
                    Payload::Assertion(_)
                ) {
                    return Err(invalid("expected assertion"));
                }
                (
                    record,
                    expected_version,
                    Some(Payload::Assertion(replacement.clone())),
                )
            }
            RetractAssertion {
                record,
                expected_version,
                rationale,
            } => {
                if !matches!(
                    current(&records, u, record, expected_version)?.payload,
                    Payload::Assertion(_)
                ) {
                    return Err(invalid("expected assertion"));
                }
                if rationale.trim().is_empty() {
                    return Err(invalid("explain the assertion retraction"));
                }
                (record, expected_version, None)
            }
            TombstoneRecord {
                record,
                expected_version,
                ..
            } => {
                current(&records, u, record, expected_version)?;
                (record, expected_version, None)
            }
            SetStoryTime {
                record,
                expected_version,
                value,
                mode,
                reason,
            } => {
                let Payload::RepresentedContext(mut c) =
                    current(&records, u, record, expected_version)?
                        .payload
                        .clone()
                else {
                    return Err(invalid("expected represented context"));
                };
                c.chronology
                    .as_mut()
                    .ok_or_else(|| {
                        invalid("this legacy context needs an authored starting chronology")
                    })?
                    .change(value, *mode, reason)
                    .map_err(|e| invalid(&e))?;
                (
                    record,
                    expected_version,
                    Some(Payload::RepresentedContext(c)),
                )
            }
            EndAssertionAt {
                record,
                expected_version,
                at,
                basis,
            } => {
                use universe_domain::{
                    scope::Validity,
                    temporal::{TemporalBound, TemporalExpression},
                };
                let Payload::Assertion(mut a) = current(&records, u, record, expected_version)?
                    .payload
                    .clone()
                else {
                    return Err(invalid("expected assertion"));
                };
                let TemporalExpression::Exact { calendar, value } = at else {
                    return Err(invalid(
                        "ending an assertion requires an exact authored-clock instant",
                    ));
                };
                let Validity::CalendarInterval {
                    calendar: clock,
                    start,
                    end,
                } = &a.validity
                else {
                    return Err(unsupported());
                };
                if calendar != clock
                    || universe_rules::time::applies(
                        &a.validity,
                        &universe_domain::frame::FrameTime::At { time: at.clone() },
                    ) != Some(true)
                {
                    // An identical exclusive end is a valid idempotent semantic edit.
                    if calendar != clock || !matches!(end,TemporalBound::Exact{value:e} if e==value)
                    {
                        return Err(invalid(
                            "end must be within the assertion's declared interval and calendar",
                        ));
                    }
                }
                a.validity = Validity::CalendarInterval {
                    calendar: clock.clone(),
                    start: start.clone(),
                    end: TemporalBound::Exact {
                        value: value.clone(),
                    },
                };
                a.basis = basis.clone();
                (record, expected_version, Some(Payload::Assertion(a)))
            }
            _ => continue,
        };
        let next = payload
            .map(|p| {
                RecordVersion::build(
                    RecordVersionId::generate(&mut rand::rng()),
                    RecordIdentity::new(u.clone(), reference.record.clone(), p.kind()),
                    p,
                )
            })
            .transpose()?;
        changes.push(Assignment {
            record_id: reference.record.clone(),
            expected: Some(expected.clone()),
            next,
        });
    }
    for op in &operations {
        if let DomainOperation::AdoptRecordVersion {
            source,
            expected_version,
        } = op
        {
            if source.identity.universe_id != *u || !source.verify_digest() {
                return Err(invalid("adoption source has invalid identity or digest"));
            }
            if records
                .get(&source.identity.record_id)
                .map(|r| &r.record_version_id)
                != expected_version.as_ref()
            {
                return Err(invalid("adoption target version changed"));
            }
            changes.push(Assignment {
                record_id: source.identity.record_id.clone(),
                expected: expected_version.clone(),
                next: Some(RecordVersion::build(
                    RecordVersionId::generate(&mut rand::rng()),
                    source.identity.clone(),
                    source.payload.clone(),
                )?),
            });
        }
    }
    crate::initialization::compile(u, revision, base, &operations, &mut changes)?;
    crate::events::recompile(u, base, &mut changes)?;
    Ok(changes)
}

#[cfg(test)]
mod incremental_tests {
    use super::*;
    use serde_json::{json, Value};
    fn u() -> UniverseId {
        UniverseId::parse("unv_000000000000000000000001").unwrap()
    }
    fn rid(n: usize) -> String {
        format!("rec_{n:024x}")
    }
    fn rr(n: usize) -> Value {
        json!({"universe":u(),"record":rid(n)})
    }
    fn record(n: usize, payload: Value) -> RecordVersion {
        let payload: Payload = serde_json::from_value(payload).unwrap();
        RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
            RecordIdentity::new(u(), RecordId::parse(&rid(n)).unwrap(), payload.kind()),
            payload,
        )
        .unwrap()
    }
    fn definition(n: usize, parent: Option<usize>) -> RecordVersion {
        record(
            n,
            json!({"record_kind":"entity_type","namespace":"test","key":format!("type{n}"),"name":format!("Type{n}"),"labels":{},"parent":parent.map(rid),"parentResolution":if parent.is_some(){"resolved"}else{"root"},"applicability":{"kind":"universe_wide"},"classificationExecutable":true}),
        )
    }
    fn fixture() -> Vec<RecordVersion> {
        vec![
            definition(1, None),
            definition(2, Some(1)),
            definition(3, None),
            record(
                4,
                json!({"record_kind":"entity","names":[],"classification":rid(1),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}}),
            ),
        ]
    }
    fn refinement() -> Value {
        json!({"kind":"refine_classification","record":rr(4),"expected_version":format!("ver_{:024x}",4),"entity_type":rid(2)})
    }
    fn compile_json(base: &[RecordVersion], ops: Vec<Value>) -> anyhow::Result<Vec<Assignment>> {
        compile(
            &u(),
            &RevisionId::parse("rev_000000000000000000000001").unwrap(),
            base,
            &ops.into_iter()
                .map(|op| serde_json::from_value(op).unwrap())
                .collect::<Vec<_>>(),
        )
    }
    #[test]
    fn item_power_revision_is_version_and_target_bound() {
        let mut rows = fixture();
        rows.push(record(5,json!({"record_kind":"item_power","item":rr(4),"holderPredicate":rr(1),"powerPredicate":rr(2),"value":{"kind":"boolean","value":true},"scope":{"context":rr(3),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"exact","value":"0"},"end":{"kind":"exact","value":"20"}}})));
        let mut replacement = serde_json::to_value(&rows[4].payload).unwrap();
        replacement.as_object_mut().unwrap().remove("record_kind");
        replacement["value"] = json!({"kind":"boolean","value":false});
        let op = json!({"kind":"revise_item_power","record":rr(5),"expected_version":rows[4].record_version_id,"replacement":replacement,"rationale":"Explicit author correction"});
        assert!(compile_json(&rows, vec![op.clone()]).is_ok());
        for field in ["item", "holderPredicate", "powerPredicate"] {
            let mut bad = op.clone();
            bad["replacement"][field] = rr(3);
            assert!(compile_json(&rows, vec![bad])
                .unwrap_err()
                .to_string()
                .contains("retain item"));
        }
        let mut bad = op.clone();
        bad["replacement"]["scope"]["context"] = rr(4);
        assert!(compile_json(&rows, vec![bad])
            .unwrap_err()
            .to_string()
            .contains("represented context"));
        let mut bad = op.clone();
        bad["replacement"]["validity"]["calendar"] = json!("cal_000000000000000000000002");
        assert!(compile_json(&rows, vec![bad])
            .unwrap_err()
            .to_string()
            .contains("authored calendar"));
        let mut stale = op;
        stale["expected_version"] = json!("ver_000000000000000000000006");
        assert!(compile_json(&rows, vec![stale]).is_err());
    }
    #[test]
    fn candidate_reparenting_cannot_bypass_descendant_refinement() {
        let rows = fixture();
        let mut replacement = serde_json::to_value(&rows[1].payload).unwrap();
        replacement["parent"] = json!(rid(3));
        let edit = json!({"kind":"revise_definition","record":rr(2),"expected_version":rows[1].record_version_id,"replacement":replacement});
        for ops in [vec![edit.clone(), refinement()], vec![refinement(), edit]] {
            assert!(compile_json(&rows, ops)
                .unwrap_err()
                .to_string()
                .contains("not a descendant refinement"));
        }
        assert_eq!(rows, fixture());
    }
    #[test]
    fn ambiguous_instance_requires_correction_even_without_classification() {
        let mut rows = fixture();
        if let Payload::Entity(e) = &mut rows[3].payload {
            e.classification = None;
            e.classification_resolution = ClassificationResolution::Ambiguous;
        }
        assert!(compile_json(&rows, vec![refinement()])
            .unwrap_err()
            .to_string()
            .contains("explicit authored correction"));
    }
    #[test]
    fn tombstoned_target_cannot_be_used_as_refinement() {
        let rows = fixture();
        let tombstone = json!({"kind":"tombstone_record","record":rr(2),"expected_version":rows[1].record_version_id,"rationale":"Authored removal"});
        assert!(compile_json(&rows, vec![refinement(), tombstone])
            .unwrap_err()
            .to_string()
            .contains("resolved definition"));
    }
    #[test]
    fn new_instance_identity_can_be_referenced_by_attribute_in_same_batch() {
        let instance = json!({"kind":"introduce_instance","client_ref":rid(20),"name":{"text":"New identity","validity":{"kind":"unspecified"}},"world_associations":[]});
        let attribute = json!({"kind":"add_named_attribute","client_ref":"attribute","subject":rr(20),"namespace":"test","key":"color","value_shape":{"kind":"text"},"subject_types":[],"multiplicity":"single","value":{"kind":"text","text":"green"},"evidence":{"attributeMode":"instance","polarity":"support","scope":{"context":rr(99),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","basis":{"kind":"imported_claim"}}});
        let changes = compile_json(&fixture(), vec![instance, attribute]).unwrap();
        assert!(changes.iter().any(|c| c.record_id.to_string() == rid(20)));
        assert!(changes.iter().any(|c| matches!(c.next.as_ref().map(|v| &v.payload), Some(Payload::Proposition(p)) if p.subject.record.to_string() == rid(20))));
    }
    #[test]
    fn same_batch_named_attributes_share_one_definition_and_keep_evidence() {
        let attribute = |n| json!({"kind":"add_named_attribute","client_ref":format!("attribute{n}"),"subject":rr(4),"namespace":"test","key":"hazard","value_shape":{"kind":"text"},"subject_types":[rid(1)],"multiplicity":"multiple","value":{"kind":"text","text":format!("Hazard{n}")},"evidence":{"attributeMode":"instance","polarity":"support","scope":{"context":rr(99),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unknown"},"persistence":"unspecified","precision":"unresolved","basis":{"kind":"imported_claim"}}});
        let changes = compile_json(&fixture(), vec![attribute(1), attribute(2)]).unwrap();
        assert_eq!(changes.len(), 5);
        assert_eq!(
            changes
                .iter()
                .filter(|c| matches!(c.next.as_ref().unwrap().payload, Payload::Property(_)))
                .count(),
            1
        );
        for change in &changes {
            if let Payload::Assertion(a) = &change.next.as_ref().unwrap().payload {
                assert_eq!(a.validity, universe_domain::scope::Validity::Unknown);
                assert_eq!(a.precision, universe_domain::scope::Precision::Unresolved);
                assert_eq!(
                    a.basis,
                    universe_domain::scope::EvidenceBasis::ImportedClaim
                );
                assert!(a.established_by.is_none());
            }
        }
    }
}
