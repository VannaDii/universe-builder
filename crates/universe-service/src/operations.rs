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
pub fn compile(
    u: &UniverseId,
    base: &[RecordVersion],
    operations: &[DomainOperation],
) -> anyhow::Result<Vec<Assignment>> {
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
            RecordVersionId::generate(&mut rand::rng()),
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
    for op in operations {
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
            ReviseAppearance { .. }
            | ReviseDefinition { .. }
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
    for op in operations {
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
                if !e.types.contains(entity_type) {
                    e.types.push(entity_type.clone());
                }
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
    for op in operations {
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
    crate::events::recompile(u, base, &mut changes)?;
    Ok(changes)
}
