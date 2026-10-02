//! Basic candidate checks. Undefined definitions and temporal prerequisites do not pass.
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    ids::*,
    records::*,
    scope::{Applicability, Polarity, Precision, Validity},
    value::{validate_value, Value},
};
use universe_protocol::ProtocolError;
fn invalid(message: &str) -> anyhow::Error {
    ProtocolError::invalid_argument("candidate", message).into()
}
fn shape(value: &Value, shape: &ValueShape) -> bool {
    match (value, shape) {
        (Value::Text { .. }, ValueShape::Text)
        | (Value::Boolean { .. }, ValueShape::Boolean)
        | (Value::Integer { .. }, ValueShape::Integer)
        | (Value::Decimal { .. }, ValueShape::Decimal)
        | (Value::Rational { .. }, ValueShape::Rational)
        | (Value::Temporal { .. }, ValueShape::Temporal)
        | (Value::Spatial { .. }, ValueShape::Spatial)
        | (Value::EntityRef { .. }, ValueShape::EntityRef { .. }) => true,
        (Value::Quantity { unit: a, .. }, ValueShape::Quantity { unit: b }) => a == b,
        (Value::Range { unit: a, .. }, ValueShape::Range { unit: b }) => a == b,
        (Value::Enum { definition: a, .. }, ValueShape::Enum { definition: b })
        | (Value::Structured { definition: a, .. }, ValueShape::Structured { definition: b }) => {
            a == b
        }
        (Value::Sequence { items }, ValueShape::Sequence { item }) => {
            items.iter().all(|v| self::shape(v, item))
        }
        _ => false,
    }
}
/// Returns structural failures; conflict findings are evaluated separately.
pub fn structural(records: &[RecordVersion]) -> anyhow::Result<()> {
    universe_rules::time::check_orderings(records).map_err(invalid)?;
    universe_rules::events::verify(records).map_err(|e| invalid(&e))?;
    let map: BTreeMap<_, _> = records
        .iter()
        .map(|r| (&r.identity.record_id, &r.payload))
        .collect();
    let mut action_names = BTreeSet::new();
    for record in records {
        crate::provenance::validate_links(&record.payload, &map)?;
        match &record.payload {
            Payload::ActionDefinition(a) => {
                if !action_names.insert((&a.namespace, &a.key)) {
                    return Err(invalid("duplicate action namespace/key"));
                }
                if a.namespace.trim().is_empty()
                    || a.key.trim().is_empty()
                    || a.namespace.len() > 128
                    || a.key.len() > 128
                    || a.requirements.len() > 64
                    || a.scope.realm.is_some()
                    || !matches!(
                        a.scope.applicability,
                        Applicability::UniverseWide | Applicability::Worlds { .. }
                    )
                {
                    return Err(invalid(
                        "action needs a bounded name, explicit scope and supported requirements",
                    ));
                }
                let mut seen = BTreeSet::new();
                for req in &a.requirements {
                    if req.role.trim().is_empty()
                        || req.role.len() > 120
                        || !seen.insert((&req.role, &req.predicate))
                        || !matches!(map.get(&req.predicate.record), Some(Payload::Property(d)) if shape(&req.value, &d.value))
                    {
                        return Err(invalid(
                            "action attributes need unique roles/properties and conforming values",
                        ));
                    }
                    validate_value(&req.value)?;
                }
                if !matches!(
                    map.get(&a.scope.context.record),
                    Some(Payload::RepresentedContext(_))
                ) {
                    return Err(invalid("action needs a represented context"));
                }
            }
            Payload::ImageAsset(asset) => universe_store::kernel::validate_image_metadata(asset)?,
            Payload::Appearance(a) => {
                if a.label.trim().is_empty()
                    || a.label.len() > 256
                    || a.physical_description.len() > 64_000
                    || a.atmosphere.len() > 16_000
                    || a.images.len() > 16
                    || a.links.len() > 32
                    || (a.physical_description.trim().is_empty()
                        && a.atmosphere.trim().is_empty()
                        && a.images.is_empty()
                        && a.links.is_empty())
                {
                    return Err(invalid(
                        "appearance needs content within description, image and link limits",
                    ));
                }
                if let AppearanceTarget::Entry { entry } = &a.target {
                    if !map.contains_key(&entry.record) {
                        return Err(invalid("appearance target unavailable"));
                    }
                }
                for image in &a.images {
                    if image.caption.len() > 2000
                        || !matches!(map.get(&image.asset.record), Some(Payload::ImageAsset(_)))
                    {
                        return Err(invalid(
                            "appearance image must reference an imported image asset",
                        ));
                    }
                }
                for link in &a.links {
                    if link.note.len() > 2000 || !map.contains_key(&link.entry.record) {
                        return Err(invalid("appearance link unavailable or note exceeds limit"));
                    }
                }
                if let Validity::CalendarInterval {
                    calendar,
                    start,
                    end,
                } = &a.validity
                {
                    universe_domain::temporal::TemporalExpression::Interval {
                        calendar: calendar.clone(),
                        start: start.clone(),
                        end: end.clone(),
                    }
                    .validate()?;
                    if universe_rules::time::overlaps(&a.validity, &a.validity) != Some(true) {
                        return Err(invalid("appearance interval must have exact increasing or explicitly unbounded endpoints"));
                    }
                    if !matches!(
                        map.get(&calendar.to_record_id()?),
                        Some(Payload::Calendar(_))
                    ) {
                        return Err(invalid(
                            "appearance interval needs a known calendar and increasing boundaries",
                        ));
                    }
                } else if !matches!(a.validity, Validity::Unspecified) {
                    return Err(invalid(
                        "appearance supports unspecified or exact calendar interval validity",
                    ));
                }
            }
            Payload::RepresentedContext(c) => {
                let mut seen = BTreeSet::from([record.identity.record_id.clone()]);
                let mut parent = c.parent.as_ref();
                while let Some(reference) = parent {
                    if seen.len() >= 32 || !seen.insert(reference.record.clone()) {
                        return Err(invalid(
                            "represented-context nesting is cyclic or exceeds 32 levels",
                        ));
                    }
                    let Some(Payload::RepresentedContext(ancestor)) = map.get(&reference.record)
                    else {
                        return Err(invalid("context parent must be a represented context"));
                    };
                    parent = ancestor.parent.as_ref();
                }
                if let Some(clock) = &c.chronology {
                    clock.validate().map_err(|e| invalid(&e))?;
                    if !matches!(
                        map.get(&clock.calendar.to_record_id()?),
                        Some(Payload::Calendar(_))
                    ) {
                        return Err(invalid("story clock must reference a calendar definition"));
                    }
                }
            }
            Payload::Rule(r)
                if r.kind == RuleKind::StructuralInvariant
                    && r.commit_policy != CommitPolicy::AlwaysBlock =>
            {
                return Err(invalid("structural invariants cannot be waived"))
            }
            Payload::ItemPower(p) => {
                if !matches!(map.get(&p.item.record), Some(Payload::Entity(_))) {
                    return Err(invalid("power item must be an entity"));
                }
                if !matches!(map.get(&p.holder_predicate.record),Some(Payload::Property(d)) if matches!(d.value,ValueShape::EntityRef{..})&&d.multiplicity==Multiplicity::Single)
                {
                    return Err(invalid(
                        "possession requires a single-valued entity-reference holder property",
                    ));
                }
                if !matches!(map.get(&p.power_predicate.record),Some(Payload::Property(d)) if shape(&p.value,&d.value))
                {
                    return Err(invalid("power value must conform to its property"));
                }
                if !matches!(
                    p.scope.applicability,
                    Applicability::UniverseWide | Applicability::Worlds { .. }
                ) {
                    return Err(invalid("item power scope must be explicit"));
                }
                validate_value(&p.value)?;
            }
            Payload::Event(e) => {
                if e.worlds.iter().any(|w| {
                    !matches!(
                        map.get(
                            &RecordId::parse(&universe_store::kernel::world_record(w))
                                .expect("world id")
                        ),
                        Some(Payload::World(_))
                    )
                }) {
                    return Err(invalid("event world is not a world"));
                }
                if e.region.as_ref().is_some_and(|region| {
                    !matches!(
                        map.get(&region.record),
                        Some(Payload::Entity(_) | Payload::Realm(_))
                    )
                }) {
                    return Err(invalid("event region must be an entity or realm"));
                }
            }
            Payload::EpistemicAttitude(a) => {
                if !matches!(map.get(&a.holder.record), Some(Payload::Entity(_)))
                    || !matches!(
                        map.get(&a.proposition.record),
                        Some(Payload::Proposition(_))
                    )
                {
                    return Err(invalid("attitude requires a holder and a proposition"));
                }
            }
            Payload::Observation(o) => {
                if !matches!(map.get(&o.observer.record), Some(Payload::Entity(_))) {
                    return Err(invalid("observer must be an entity"));
                }
            }
            Payload::Communication(c) => {
                if !c.actual_recipients.is_empty() && c.received_at.is_none() {
                    return Err(invalid(
                        "actual communication receipt requires a receipt time",
                    ));
                }
            }
            Payload::Entity(e) => {
                for id in &e.types {
                    if !matches!(map.get(id), Some(Payload::EntityType(_))) {
                        return Err(invalid("entity type target is not an entity type"));
                    }
                }
                for value in e.metadata.values() {
                    validate_value(value)?;
                }
                for association in &e.world_associations {
                    for v in association.qualifiers.values() {
                        validate_value(v)?;
                    }
                }
            }
            Payload::World(w) => {
                for value in w.metadata.values() {
                    validate_value(value)?;
                }
            }
            Payload::Saga(s) => {
                let mut memberships = BTreeSet::new();
                for m in &s.memberships {
                    if !matches!(map.get(&m.work.record), Some(Payload::Work(_))) {
                        return Err(invalid("saga membership must name a work"));
                    }
                    if !memberships.insert((&m.work.record, &m.role)) {
                        return Err(invalid("duplicate saga work/role membership"));
                    }
                }
            }
            Payload::WorkVersion(w) => {
                if !matches!(map.get(&w.work.record), Some(Payload::Work(_))) {
                    return Err(invalid("work version must name a work"));
                }
            }
            Payload::Proposition(p) => {
                if !matches!(map.get(&p.subject.record), Some(Payload::Entity(_))) {
                    return Err(invalid("proposition subject must be an entity"));
                }
                if !matches!(
                    map.get(&p.context.record),
                    Some(Payload::RepresentedContext(_))
                ) {
                    return Err(invalid("proposition context must be a represented context"));
                }
                match map.get(&p.predicate.record) {
                    Some(Payload::Property(property)) => {
                        let value = p.value.as_ref().ok_or_else(|| {
                            invalid("property proposition needs an explicit value")
                        })?;
                        validate_value(value)?;
                        if !shape(value, &property.value) || !p.roles.is_empty() {
                            return Err(invalid(
                                "property value does not conform to its definition",
                            ));
                        }
                        if let Some(Payload::Entity(e)) = map.get(&p.subject.record) {
                            if !property.subject_types.is_empty()
                                && !e.types.iter().any(|t| property.subject_types.contains(t))
                            {
                                return Err(invalid("subject lacks a declared property type"));
                            }
                        }
                    }
                    Some(Payload::Relation(relation)) => {
                        if p.value.is_some() {
                            return Err(invalid(
                                "relation proposition cannot carry a property value",
                            ));
                        }
                        for role in &p.roles {
                            let def = relation
                                .roles
                                .iter()
                                .find(|d| d.name == role.role)
                                .ok_or_else(|| invalid("undefined relation role"))?;
                            let Some(Payload::Entity(e)) = map.get(&role.participant.record) else {
                                return Err(invalid("role participant must be an entity"));
                            };
                            if !def.participant_types.is_empty()
                                && !e.types.iter().any(|t| def.participant_types.contains(t))
                            {
                                return Err(invalid("participant lacks a declared role type"));
                            }
                        }
                        for role in &relation.roles {
                            if matches!(role.multiplicity, Multiplicity::Single)
                                && p.roles.iter().filter(|r| r.role == role.name).count() > 1
                            {
                                return Err(invalid("single role has multiple participants"));
                            }
                        }
                    }
                    _ => {
                        return Err(invalid(
                            "proposition predicate must name a property or relation definition",
                        ))
                    }
                }
            }
            Payload::Assertion(a) => {
                if let Validity::CalendarInterval {
                    calendar,
                    start,
                    end,
                } = &a.validity
                {
                    let interval = universe_domain::temporal::TemporalExpression::Interval {
                        calendar: calendar.clone(),
                        start: start.clone(),
                        end: end.clone(),
                    };
                    interval.validate()?;
                    if let (
                        universe_domain::temporal::TemporalBound::Exact { value: a },
                        universe_domain::temporal::TemporalBound::Exact { value: b },
                    ) = (start, end)
                    {
                        if let (Ok(a), Ok(b)) = (a.parse::<i128>(), b.parse::<i128>()) {
                            if a > b {
                                return Err(invalid("interval start is after its end"));
                            }
                        }
                    }
                }
                if !matches!(
                    map.get(&a.proposition.record),
                    Some(Payload::Proposition(_))
                ) {
                    return Err(invalid("assertion must name a proposition"));
                }
                if !matches!(
                    map.get(&a.scope.context.record),
                    Some(Payload::RepresentedContext(_))
                ) {
                    return Err(invalid("assertion context must be represented"));
                }
                if matches!(
                    a.basis,
                    universe_domain::scope::EvidenceBasis::Derivation { .. }
                        | universe_domain::scope::EvidenceBasis::EventEffect { .. }
                ) {
                    return Err(ProtocolError::UnsupportedSemantics {
                        message: "event and derived evidence require their evaluator".into(),
                    }
                    .into());
                }
                for value in &a.alternatives {
                    validate_value(value)?;
                }
            }
            _ => {}
        }
    }
    Ok(())
}
/// A single-valued property is inconsistent only for exact, overlapping scopes.
/// Unknown time is reported as an unresolved prerequisite rather than guessed.
pub fn scalar_conflicts(
    records: &[RecordVersion],
) -> (Vec<(RecordId, Vec<RecordVersionId>)>, Vec<String>) {
    let map: BTreeMap<_, _> = records
        .iter()
        .map(|r| (&r.identity.record_id, &r.payload))
        .collect();
    type ScalarKey = (RecordId, RecordId, RecordId);
    type ScalarEvidence<'a> = (&'a RecordVersion, &'a Assertion, &'a Proposition);
    let mut groups: BTreeMap<ScalarKey, Vec<ScalarEvidence<'_>>> = BTreeMap::new();
    for r in records {
        let Payload::Assertion(a) = &r.payload else {
            continue;
        };
        if a.polarity != Polarity::Support {
            continue;
        }
        let Some(Payload::Proposition(p)) = map.get(&a.proposition.record) else {
            continue;
        };
        let Some(Payload::Property(property)) = map.get(&p.predicate.record) else {
            continue;
        };
        if matches!(property.multiplicity, Multiplicity::Single) || property.exclusive {
            groups
                .entry((
                    p.subject.record.clone(),
                    p.predicate.record.clone(),
                    a.scope.context.record.clone(),
                ))
                .or_default()
                .push((r, a, p));
        }
    }
    let mut conflicts = Vec::new();
    let mut gaps = BTreeSet::new();
    let mut pairs_remaining = 1_000_000;
    for ((_, predicate, _), assertions) in groups {
        for (i, (left, a, p)) in assertions.iter().enumerate() {
            for (right, b, q) in assertions.iter().skip(i + 1) {
                if pairs_remaining == 0 || conflicts.len() >= 1_000 {
                    gaps.insert("scalar-work-budget-exhausted".into());
                    return (conflicts, gaps.into_iter().collect());
                }
                pairs_remaining -= 1;
                if a.scope.realm != b.scope.realm {
                    continue;
                }
                if p.value == q.value
                    || p.value
                        .as_ref()
                        .zip(q.value.as_ref())
                        .is_some_and(|(a, b)| {
                            universe_rules::basic::compare(a, universe_domain::Comparator::Eq, b)
                                == Some(true)
                        })
                {
                    continue;
                }
                if matches!((&a.scope.applicability,&b.scope.applicability),(Applicability::Worlds{world_ids:x},Applicability::Worlds{world_ids:y}) if x.iter().all(|w|!y.contains(w)))
                {
                    continue;
                }
                if a.precision != Precision::Exact
                    || b.precision != Precision::Exact
                    || universe_rules::time::overlaps(&a.validity, &b.validity).is_none()
                    || matches!(
                        a.scope.applicability,
                        Applicability::Unspecified | Applicability::Conditional
                    )
                    || matches!(
                        b.scope.applicability,
                        Applicability::Unspecified | Applicability::Conditional
                    )
                {
                    gaps.insert(format!("scalar-scope-or-time:{predicate}"));
                    continue;
                }
                if universe_rules::time::overlaps(&a.validity, &b.validity) == Some(false) {
                    continue;
                }
                conflicts.push((
                    predicate.clone(),
                    vec![
                        left.record_version_id.clone(),
                        right.record_version_id.clone(),
                    ],
                ));
            }
        }
    }
    (conflicts, gaps.into_iter().collect())
}

/// A complete objective collection constrains additions only in its declared
/// context, scope and validity. Open/observer-known sets do not close reality.
pub fn completeness_conflicts(
    records: &[RecordVersion],
) -> (Vec<(RecordId, Vec<RecordVersionId>)>, Vec<String>) {
    let mut findings = Vec::new();
    let mut gaps = Vec::new();
    let mut budget = 1_000_000usize;
    let by_id: BTreeMap<_, _> = records.iter().map(|r| (&r.identity.record_id, r)).collect();
    let mut members = BTreeMap::new();
    for record in records {
        let Payload::Assertion(a) = &record.payload else {
            continue;
        };
        if a.polarity != Polarity::Support || a.precision != Precision::Exact {
            continue;
        }
        let Some(r) = by_id.get(&a.proposition.record) else {
            continue;
        };
        let Payload::Proposition(p) = &r.payload else {
            continue;
        };
        let mut keys = vec![p.predicate.record.to_string()];
        if let Some(def) = by_id.get(&p.predicate.record) {
            match &def.payload {
                Payload::Property(d) => keys.push(format!("{}:{}", d.namespace, d.key)),
                Payload::Relation(d) => keys.push(format!("{}:{}", d.namespace, d.key)),
                _ => {}
            }
        }
        for key in keys {
            members
                .entry((p.subject.clone(), key))
                .or_insert_with(Vec::new)
                .push((record, a, p));
        }
    }
    for declaration in records {
        let Payload::Completeness(c) = &declaration.payload else {
            continue;
        };
        if c.completeness != CompletenessKind::ObjectiveReality {
            continue;
        }
        let listed: BTreeSet<_> = c.members.iter().collect();
        for &(record, a, p) in members
            .get(&(c.subject.clone(), c.predicate.clone()))
            .into_iter()
            .flatten()
        {
            if budget == 0 {
                gaps.push("completeness work budget exhausted".into());
                return (findings, gaps);
            }
            budget -= 1;
            if a.scope != c.scope {
                continue;
            }
            let Some(Value::EntityRef { record: member }) = &p.value else {
                continue;
            };
            if listed.contains(member) {
                continue;
            }
            match universe_rules::time::overlaps(&a.validity, &c.validity) {
                Some(true) => findings.push((
                    declaration.identity.record_id.clone(),
                    vec![
                        declaration.record_version_id.clone(),
                        record.record_version_id.clone(),
                    ],
                )),
                Some(false) => {}
                None => gaps.push(format!(
                    "completeness:{}: unresolved temporal overlap",
                    declaration.identity.record_id
                )),
            }
        }
    }
    (findings, gaps)
}

#[cfg(test)]
mod completeness_tests {
    use super::*;
    use universe_domain::{scope::Scope, temporal::TemporalBound, value::RecordRef};
    #[test]
    fn objective_completeness_does_not_escape_its_context_or_realm_or_observer() {
        let u = UniverseId::generate(&mut rand::rng());
        let rr = |n| {
            RecordRef::new(
                u.clone(),
                RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
            )
        };
        let version = |n, payload: Payload| {
            RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                RecordIdentity::new(u.clone(), rr(n).record, payload.kind()),
                payload,
            )
            .unwrap()
        };
        let scope = Scope {
            applicability: Applicability::UniverseWide,
            context: rr(1),
            realm: None,
        };
        let validity = Validity::CalendarInterval {
            calendar: CalendarId::parse("cal_000000000000000000000001").unwrap(),
            start: TemporalBound::Exact { value: "10".into() },
            end: TemporalBound::Exact { value: "20".into() },
        };
        let declaration = CompletenessDecl {
            subject: rr(2),
            predicate: rr(3).record.to_string(),
            members: vec![],
            completeness: CompletenessKind::ObjectiveReality,
            validity: validity.clone(),
            scope: scope.clone(),
        };
        let proposition = version(
            4,
            Payload::Proposition(Proposition {
                subject: rr(2),
                predicate: rr(3),
                roles: vec![],
                value: Some(Value::EntityRef { record: rr(5) }),
                quantification: Quantification::Particular,
                context: scope.context.clone(),
            }),
        );
        let assertion = version(
            6,
            Payload::Assertion(Assertion {
                proposition: rr(4),
                polarity: Polarity::Support,
                scope: scope.clone(),
                validity,
                persistence: universe_domain::scope::PersistenceSemantics::ExplicitInterval,
                precision: Precision::Exact,
                alternatives: vec![],
                basis: universe_domain::scope::EvidenceBasis::AuthorDecision {
                    note: "side entrance".into(),
                },
                established_by: None,
            }),
        );
        let mut records = vec![
            version(7, Payload::Completeness(declaration.clone())),
            proposition,
            assertion,
        ];
        assert_eq!(completeness_conflicts(&records).0.len(), 1);
        let mut observer = declaration.clone();
        observer.completeness = CompletenessKind::ObserverKnown {
            observer: EntityIdAlias::from_id(rr(9).record).unwrap(),
        };
        records[0] = version(7, Payload::Completeness(observer));
        assert!(completeness_conflicts(&records).0.is_empty());
        let mut other = declaration.clone();
        other.scope.realm = Some(rr(8));
        records[0] = version(7, Payload::Completeness(other));
        assert!(completeness_conflicts(&records).0.is_empty());
        let mut other = declaration;
        other.scope.context = rr(9);
        records[0] = version(7, Payload::Completeness(other));
        assert!(completeness_conflicts(&records).0.is_empty());
    }
}

/// Automatic diagnostics do not decide admission. Policy findings above retain
/// authored rule identities; these entries bind both original evidence chains.
pub(crate) fn opposing_evidence(
    records: &[RecordVersion],
    frame: &universe_domain::Frame,
    digest: &str,
    evaluator: &str,
    unsupported: &mut Vec<String>,
) -> anyhow::Result<Vec<universe_protocol::response::OpposingEvidence>> {
    use universe_protocol::response::{
        Coverage, OpposingChain, OpposingEvidence, OpposingIntersection, OpposingKind,
        OpposingReason,
    };
    use universe_rules::opposing::Intersection;
    let scan = match universe_rules::opposing::detect(&frame.universe, records, true, 10_000) {
        Ok(scan) => scan,
        Err(reason) => {
            unsupported.push(format!("opposing_evidence.v1:{reason}"));
            return Ok(vec![]);
        }
    };
    if !scan.complete {
        unsupported.push(format!("opposing_evidence.v1:{:?}", scan.gaps));
    }
    let chain = |c: &universe_rules::opposing::Chain| OpposingChain {
        assertion_id: c.assertion.identity.record_id.clone(),
        proposition_id: c.proposition.identity.record_id.clone(),
        assertion: c.assertion.record_version_id.clone(),
        proposition: c.proposition.record_version_id.clone(),
        dependencies: c
            .dependencies
            .iter()
            .map(|r| universe_domain::value::VersionRef {
                universe: Some(r.identity.universe_id.clone()),
                record: r.identity.record_id.clone(),
                version: r.record_version_id.clone(),
            })
            .collect(),
        complete: c.complete,
    };
    let mut policies: Vec<_> = records
        .iter()
        .filter(|r| matches!(&r.payload, Payload::Rule(_)))
        .map(|r| r.record_version_id.clone())
        .collect();
    let mut exceptions: Vec<_> = records
        .iter()
        .filter(|r| matches!(&r.payload, Payload::Exception(_)))
        .map(|r| r.record_version_id.clone())
        .collect();
    policies.sort();
    exceptions.sort();
    scan.pairs
        .into_iter()
        .map(|pair| {
            let Payload::Proposition(proposition) = &pair.support.proposition.payload else {
                unreachable!()
            };
            let definite = pair.definite();
            let fingerprint = FindingFingerprint(crate::workflow::hash(&(
                frame,
                digest,
                evaluator,
                &pair.comparison_key,
                &pair.context,
                &pair.applicability,
                &pair.realm,
                &pair.intersection,
                chain(&pair.support),
                chain(&pair.refutation),
                &policies,
                &exceptions,
            )));
            Ok(OpposingEvidence {
                diagnostic_version: "opposing_evidence.v1".into(),
                fingerprint,
                kind: if definite {
                    OpposingKind::Definite
                } else {
                    OpposingKind::Unresolved
                },
                proposition: proposition.clone(),
                support: chain(&pair.support),
                refutation: chain(&pair.refutation),
                context: pair.context,
                applicability: pair.applicability,
                realm: pair.realm,
                intersection: match pair.intersection {
                    Intersection::Unqualified => OpposingIntersection::Unqualified,
                    Intersection::Exact(validity) => OpposingIntersection::Exact { validity },
                    Intersection::Uncertain {
                        left,
                        right,
                        guaranteed,
                    } => OpposingIntersection::Uncertain {
                        left,
                        right,
                        guaranteed,
                    },
                    Intersection::Unresolved => OpposingIntersection::Unresolved,
                },
                coverage: if pair.gaps.is_empty() {
                    Coverage::Complete
                } else {
                    Coverage::Partial
                },
                unresolved_reasons: pair
                    .gaps
                    .iter()
                    .map(|g| match g {
                        universe_rules::opposing::Gap::Equality => OpposingReason::Equality,
                        universe_rules::opposing::Gap::Context => OpposingReason::Context,
                        universe_rules::opposing::Gap::Realm => OpposingReason::Realm,
                        universe_rules::opposing::Gap::Worlds => OpposingReason::Worlds,
                        universe_rules::opposing::Gap::Time => OpposingReason::Time,
                        universe_rules::opposing::Gap::Precision => OpposingReason::Precision,
                        universe_rules::opposing::Gap::Persistence => OpposingReason::Persistence,
                        universe_rules::opposing::Gap::Provenance => OpposingReason::Provenance,
                        universe_rules::opposing::Gap::Budget => OpposingReason::Budget,
                    })
                    .collect(),
                policy_versions: policies.clone(),
                exception_versions: exceptions.clone(),
            })
        })
        .collect()
}
