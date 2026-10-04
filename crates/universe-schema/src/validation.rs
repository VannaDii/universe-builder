//! Definition validation against the registry (WP02.3, spec §27.2).
//!
//! Every check is explicit: a duplicate key, a dangling reference, an
//! inheritance cycle, a recursive value schema, a zero unit scale, or a
//! pack claiming an unimplemented capability is an error. Nothing is
//! silently repaired or coerced.

use std::collections::{HashMap, HashSet};

use universe_domain::ids::RecordId;
use universe_domain::records::{
    CalendarDef, DomainPack, EntityType, PropertyDef, RelationDef, UnitDef, ValueDef, ValueShape,
};
use universe_domain::value::Value;

use crate::error::{SchemaError, SchemaResult};
use crate::registry::DefinitionRegistry;

/// The capability set a domain pack may declare (spec §27.2: "a newly
/// installed pack cannot declare the application capable of evaluating
/// code that has not been implemented").
pub fn known_capabilities() -> &'static [&'static str] {
    use universe_domain::capabilities as caps;
    &[
        caps::ASSERTION_QUALIFIED,
        caps::TIME_EXACT_INTERVAL,
        caps::TIME_RELATIVE_ORDER,
        caps::STATE_DECLARED_PERSISTENCE,
        caps::RULE_FINITE_CONSTRAINTS,
        caps::KNOWLEDGE_EXPLICIT_ATTITUDES,
        caps::CONTINUITY_PINNED_INHERITANCE,
    ]
}

/// Bound on nested structured-value references (spec §27.2: no unbounded
/// recursive schemas).
pub const MAX_VALUE_DEF_DEPTH: usize = 32;

/// Validate the whole registry. Returns the first violation.
pub fn validate(reg: &DefinitionRegistry) -> SchemaResult<()> {
    for (key, t) in reg.entity_types() {
        validate_entity_type(reg, key, t)?;
    }
    for (key, p) in reg.properties() {
        validate_property(reg, key, p)?;
    }
    for (key, r) in reg.relations() {
        validate_relation(reg, key, r)?;
    }
    for (key, u) in reg.units() {
        validate_unit(reg, key, u)?;
    }
    for (key, c) in reg.calendars() {
        validate_calendar(reg, key, c)?;
    }
    for (key, v) in reg.value_definitions() {
        validate_value_def(reg, key, v)?;
    }
    for (key, p) in reg.domain_packs() {
        validate_domain_pack(reg, key, p)?;
    }
    Ok(())
}

// -- entity types -----------------------------------------------------------

fn validate_entity_type(reg: &DefinitionRegistry, key: &str, t: &EntityType) -> SchemaResult<()> {
    if t.namespace.is_empty() || t.key.is_empty() {
        return Err(SchemaError::InvalidDefinition {
            family: "entity_type".into(),
            record: key.into(),
            reason: "namespace and key must be non-empty".into(),
        });
    }
    if (t.parent_resolution == universe_domain::records::ParentResolution::Resolved)
        != t.parent.is_some()
    {
        return Err(SchemaError::InvalidDefinition {
            family: "entity_type".into(),
            record: key.into(),
            reason: "parent resolution disagrees with parent identity".into(),
        });
    }
    for parent in t.parent.iter() {
        if reg.entity_type(parent).is_none() {
            return Err(SchemaError::MissingReference {
                from: format!("entity type {key}"),
                reference: parent.to_owned(),
                family: "entity_type".into(),
            });
        }
    }
    // Inheritance cycles are rejected (spec §27.2: executable subtype
    // traversal must terminate). One DFS from each node; the first cycle
    // found is reported with its path.
    for (start, _) in reg.entity_types() {
        let mut state: HashMap<String, u8> = HashMap::new(); // 0 = visiting, 1 = done
        let mut path: Vec<String> = Vec::new();
        let mut found: Option<Vec<String>> = None;
        dfs(reg, start, &mut state, &mut path, &mut found);
        if let Some(cycle) = found {
            return Err(SchemaError::InheritanceCycle {
                path: cycle.join(" -> "),
            });
        }
    }
    Ok(())
}

fn dfs(
    reg: &DefinitionRegistry,
    node: &str,
    state: &mut HashMap<String, u8>,
    path: &mut Vec<String>,
    found: &mut Option<Vec<String>>,
) {
    if found.is_some() {
        return;
    }
    let id = RecordId::parse(node).expect("registry keys are record ids");
    if state.get(&id.to_owned()) == Some(&0) {
        // Already on the path: this edge closes a cycle.
        let start = path.iter().position(|p| *p == id.to_owned()).unwrap_or(0);
        let mut cycle = path[start..].to_vec();
        cycle.push(id.to_owned());
        *found = Some(cycle);
        return;
    }
    if state.contains_key(&id.to_owned()) {
        return; // already fully explored
    }
    state.insert(id.to_owned(), 0);
    path.push(id.to_owned());
    if let Some(t) = reg.entity_type(&id) {
        for parent in t.parent.iter() {
            dfs(reg, &parent.to_owned(), state, path, found);
            if found.is_some() {
                break;
            }
        }
    }
    path.pop();
    state.insert(id.to_owned(), 1);
}

// -- properties -------------------------------------------------------------

fn validate_property(reg: &DefinitionRegistry, key: &str, p: &PropertyDef) -> SchemaResult<()> {
    if p.namespace.is_empty() || p.key.is_empty() {
        return Err(SchemaError::InvalidDefinition {
            family: "property".into(),
            record: key.into(),
            reason: "namespace and key must be non-empty".into(),
        });
    }
    for subject in &p.subject_types {
        if reg.entity_type(subject).is_none() {
            return Err(SchemaError::MissingReference {
                from: format!("property {key}"),
                reference: subject.to_owned(),
                family: "entity_type".into(),
            });
        }
    }
    // A quantity/range shape must name a unit that exists; a declared
    // dimension must agree with that unit's dimension (spec §27.2).
    let shape_unit = match &p.value {
        ValueShape::Quantity { unit } => Some(unit),
        ValueShape::Range { unit } => unit.as_ref(),
        _ => None,
    };
    if let Some(unit_id) = shape_unit {
        let Some(unit_def) = reg.unit(unit_id) else {
            return Err(SchemaError::MissingReference {
                from: format!("property {key}"),
                reference: unit_id.to_owned(),
                family: "unit".into(),
            });
        };
        if let Some(dim) = &p.unit_dimension {
            if unit_def.dimension != *dim {
                return Err(SchemaError::InvalidDefinition {
                    family: "property".into(),
                    record: key.into(),
                    reason: format!(
                        "declares dimension {dim} but unit {} is dimension {}",
                        unit_id.to_owned(),
                        unit_def.dimension
                    ),
                });
            }
        }
    }
    if let ValueShape::Enum { definition } | ValueShape::Structured { definition } = &p.value {
        if reg.value_definition(definition).is_none() {
            return Err(SchemaError::MissingReference {
                from: format!("property {key}"),
                reference: definition.to_owned(),
                family: "value_definition".into(),
            });
        }
    }
    // Inverse references must resolve to a real property (spec §27.2:
    // optional inverse/symmetry metadata, but never dangling).
    if let Some(inv) = &p.inverse {
        if reg.property_by_key(&p.namespace, inv).is_none() {
            return Err(SchemaError::MissingReference {
                from: format!("property {key}"),
                reference: inv.clone(),
                family: "property".into(),
            });
        }
    }
    Ok(())
}

// -- relations ----------------------------------------------------------------

fn validate_relation(reg: &DefinitionRegistry, key: &str, r: &RelationDef) -> SchemaResult<()> {
    if r.roles.is_empty() {
        return Err(SchemaError::InvalidDefinition {
            family: "relation".into(),
            record: key.into(),
            reason: "a relation declares at least one role".into(),
        });
    }
    let mut names = HashSet::new();
    for role in &r.roles {
        if role.name.is_empty() || !names.insert(role.name.as_str()) {
            return Err(SchemaError::InvalidDefinition {
                family: "relation".into(),
                record: key.into(),
                reason: format!("role name `{}` is empty or duplicated", role.name),
            });
        }
        for pt in &role.participant_types {
            if reg.entity_type(pt).is_none() {
                return Err(SchemaError::MissingReference {
                    from: format!("relation {key}"),
                    reference: pt.to_owned(),
                    family: "entity_type".into(),
                });
            }
        }
    }
    Ok(())
}

// -- units --------------------------------------------------------------------

/// Strictly-positive test for an exact decimal digit string (sign optional,
/// one fraction point, leading zeros allowed). `"0"`, `"-0.5"`, `"0.0"`
/// are not positive.
fn is_positive_digits(s: &str) -> bool {
    let (negative, rest) = if let Some(r) = s.strip_prefix('-') {
        (true, r)
    } else {
        (false, s.strip_prefix('+').unwrap_or(s))
    };
    let digits: String = rest.chars().filter(|c| *c != '.').collect();
    let mag = digits.trim_start_matches('0');
    let mag = if mag.is_empty() { "0" } else { mag };
    !negative && mag != "0"
}

fn is_strictly_positive(v: &Value) -> bool {
    match v {
        Value::Integer { digits } | Value::Decimal { digits } => is_positive_digits(digits),
        // Both parts must be positive as written; a negative/zero
        // denominator would invert or negate the scale.
        Value::Rational {
            numerator,
            denominator,
        } => is_positive_digits(numerator) && is_positive_digits(denominator),
        _ => false,
    }
}

fn own_unit_id(record_key: &str) -> String {
    universe_domain::ids::UnitId::from_id(
        RecordId::parse(record_key).expect("registry keys are record ids"),
    )
    .map(|u| u.to_owned())
    .unwrap_or_default()
}

fn validate_unit(reg: &DefinitionRegistry, key: &str, u: &UnitDef) -> SchemaResult<()> {
    if u.dimension.is_empty() {
        return Err(SchemaError::InvalidDefinition {
            family: "unit".into(),
            record: key.into(),
            reason: "a unit must declare a dimension".into(),
        });
    }
    // Conversion must be defined and compatible (spec §27.2).
    if let Some(scale) = &u.scale_to_base {
        if !is_strictly_positive(scale) {
            return Err(SchemaError::InvalidDefinition {
                family: "unit".into(),
                record: key.into(),
                reason: "scale_to_base must be a strictly positive exact number".into(),
            });
        }
    }
    if let Some(base) = &u.base {
        if base.to_owned() == own_unit_id(key) {
            return Err(SchemaError::InvalidDefinition {
                family: "unit".into(),
                record: key.into(),
                reason: "a unit cannot be its own base".into(),
            });
        }
        let Some(base_def) = reg.unit(base) else {
            return Err(SchemaError::MissingReference {
                from: format!("unit {key}"),
                reference: base.to_owned(),
                family: "unit".into(),
            });
        };
        if base_def.dimension != u.dimension {
            return Err(SchemaError::InvalidDefinition {
                family: "unit".into(),
                record: key.into(),
                reason: format!(
                    "base unit {} has dimension {} but this unit has {}",
                    base.to_owned(),
                    base_def.dimension,
                    u.dimension
                ),
            });
        }
    }
    Ok(())
}

// -- calendars ------------------------------------------------------------------

fn validate_calendar(reg: &DefinitionRegistry, key: &str, c: &CalendarDef) -> SchemaResult<()> {
    for conv in &c.conversions {
        if reg.calendar(&conv.target).is_none() {
            return Err(SchemaError::MissingReference {
                from: format!("calendar {key}"),
                reference: conv.target.to_owned(),
                family: "calendar".into(),
            });
        }
    }
    // A label-only calendar is legal (spec §27.2); arithmetic support is a
    // capability, not a validation error.
    Ok(())
}

// -- value definitions -------------------------------------------------------------

fn validate_value_def(reg: &DefinitionRegistry, key: &str, v: &ValueDef) -> SchemaResult<()> {
    let mut names = HashSet::new();
    for f in &v.fields {
        if f.name.is_empty() || !names.insert(f.name.as_str()) {
            return Err(SchemaError::InvalidDefinition {
                family: "value_definition".into(),
                record: key.into(),
                reason: format!("field `{}` is empty or duplicated", f.name),
            });
        }
    }
    // Recursion through nested structured definitions is bounded
    // (spec §27.2: "no ... unbounded recursive schemas").
    check_value_def_recursion(reg, key, &mut Vec::new(), 0)
}

fn check_value_def_recursion(
    reg: &DefinitionRegistry,
    record_key: &str,
    trail: &mut Vec<String>,
    depth: usize,
) -> SchemaResult<()> {
    if depth > MAX_VALUE_DEF_DEPTH {
        return Err(SchemaError::SchemaRecursion {
            path: trail.join(" -> "),
        });
    }
    let Some((_, def)) = reg.value_definitions().find(|(k, _)| *k == record_key) else {
        return Ok(()); // registry guarantees presence, but stay total
    };
    trail.push(record_key.to_string());
    for f in &def.fields {
        if let ValueShape::Structured { definition } = &f.shape {
            let target = definition.to_record_id()?.to_owned();
            if target == record_key {
                let mut path = trail.clone();
                path.push(record_key.to_string());
                return Err(SchemaError::SchemaRecursion {
                    path: path.join(" -> "),
                });
            }
            check_value_def_recursion(reg, &target, trail, depth + 1)?;
        }
    }
    trail.pop();
    Ok(())
}

// -- domain packs ------------------------------------------------------------------

fn validate_domain_pack(reg: &DefinitionRegistry, key: &str, p: &DomainPack) -> SchemaResult<()> {
    let invalid = |message: &str| SchemaError::InvalidDefinition {
        family: "domain_pack".into(),
        record: key.into(),
        reason: message.into(),
    };
    if p.key.trim().is_empty() || p.version.trim().is_empty() {
        return Err(invalid("pack key and exact version are required"));
    }
    if reg
        .domain_packs()
        .filter(|(_, other)| other.key == p.key)
        .count()
        != 1
    {
        return Err(invalid("pack keys must be unique"));
    }
    let mut path = vec![p.key.as_str()];
    fn visit<'a>(
        reg: &'a DefinitionRegistry,
        p: &'a DomainPack,
        path: &mut Vec<&'a str>,
        visited: &mut HashSet<&'a str>,
    ) -> Result<(), &'static str> {
        if visited.contains(p.key.as_str()) {
            return Ok(());
        }
        if path.len() > 32 {
            return Err("pack dependency depth exceeds 32");
        }
        for (name, version) in &p.dependencies {
            if path.contains(&name.as_str()) {
                return Err("pack dependency cycle");
            }
            let Some((_, dependency)) = reg
                .domain_packs()
                .find(|(_, d)| &d.key == name && &d.version == version)
            else {
                return Err("missing dependency or exact version mismatch");
            };
            path.push(&dependency.key);
            visit(reg, dependency, path, visited)?;
            path.pop();
        }
        visited.insert(p.key.as_str());
        Ok(())
    }
    visit(reg, p, &mut path, &mut HashSet::new()).map_err(invalid)?;
    for cap in &p.capabilities {
        if !known_capabilities().contains(&cap.as_str()) {
            return Err(SchemaError::UnknownCapability {
                capability: cap.clone(),
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use universe_domain::ids::{RecordVersionId, UnitId, UniverseId, ValueDefinitionId};
    use universe_domain::records::{
        Multiplicity, Payload, PropertyDef, RecordIdentity, RecordKind, RecordVersion, RelationDef,
        RoleDef, UnitDef, ValueDef, ValueDefField,
    };
    use universe_domain::scope::{PersistenceSemantics, Validity};

    const UNIV: &str = "unv_0123456789abcdef01234567";

    fn rec(n: u8) -> RecordId {
        RecordId::parse(&format!("rec_{:024x}", n)).unwrap()
    }
    fn unit_body(n: u8) -> UnitId {
        UnitId::from_id(rec(n)).unwrap()
    }

    fn add_version(
        reg: &mut DefinitionRegistry,
        kind: RecordKind,
        record: RecordId,
        payload: Payload,
    ) -> SchemaResult<()> {
        let ver = RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{:024x}", 1)).unwrap(),
            RecordIdentity::new(UniverseId::parse(UNIV).unwrap(), record, kind),
            payload,
        )
        .unwrap();
        reg.add(&ver)
    }

    fn entity_type_payload(ns: &str, k: &str, parents: Vec<RecordId>) -> Payload {
        assert!(parents.len() <= 1, "test definitions use one parent");
        Payload::EntityType(EntityType {
            namespace: ns.into(),
            key: k.into(),
            labels: BTreeMap::new(),
            name: k.into(),
            parent: parents.first().cloned(),
            parent_resolution: if parents.is_empty() {
                universe_domain::records::ParentResolution::Root
            } else {
                universe_domain::records::ParentResolution::Resolved
            },
            applicability: universe_domain::scope::Applicability::UniverseWide,
            classification_executable: true,
        })
    }

    #[test]
    fn duplicate_namespace_key_is_rejected() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        let err = add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(2),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap_err();
        assert!(matches!(err, SchemaError::DuplicateDefinition { .. }));
    }

    #[test]
    fn cross_universe_definition_is_rejected() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        let other = UniverseId::parse("unv_fedcba9876543210fedcba98").unwrap();
        let ver = RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{:024x}", 2)).unwrap(),
            RecordIdentity::new(other, rec(2), RecordKind::EntityType),
            entity_type_payload("starter", "other", vec![]),
        )
        .unwrap();
        let err = reg.add(&ver).unwrap_err();
        assert!(matches!(err, SchemaError::CrossUniverse { .. }));
    }

    #[test]
    fn inheritance_cycle_is_detected() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "a", vec![rec(2)]),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(2),
            entity_type_payload("starter", "b", vec![rec(1)]),
        )
        .unwrap();
        let err = validate(&reg).unwrap_err();
        match err {
            SchemaError::InheritanceCycle { path } => assert!(path.contains(" -> ")),
            other => panic!("expected cycle, got {other:?}"),
        }
    }

    fn property_payload(
        k: &str,
        value: ValueShape,
        dim: Option<&str>,
        inverse: Option<&str>,
    ) -> Payload {
        Payload::Property(PropertyDef {
            namespace: "starter".into(),
            key: k.into(),
            labels: BTreeMap::new(),
            subject_types: vec![rec(1)],
            value,
            multiplicity: Multiplicity::Single,
            unit_dimension: dim.map(str::to_string),
            persistence: PersistenceSemantics::Unspecified,
            exclusive: false,
            inverse: inverse.map(str::to_string),
            symmetric: false,
            transitive: false,
        })
    }

    fn unit_payload(k: &str, dim: &str, base: Option<UnitId>, scale: Option<Value>) -> Payload {
        Payload::Unit(UnitDef {
            namespace: "starter".into(),
            key: k.into(),
            dimension: dim.into(),
            symbol: k.into(),
            labels: BTreeMap::new(),
            scale_to_base: scale,
            base,
            validity: Validity::default(),
        })
    }

    #[test]
    fn property_unit_must_exist_and_match_dimension() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::Unit,
            rec(2),
            unit_payload("gram", "mass", None, None),
        )
        .unwrap();
        // Property names gram (mass) but declares a length dimension.
        add_version(
            &mut reg,
            RecordKind::Property,
            rec(3),
            property_payload(
                "weight",
                ValueShape::Quantity { unit: unit_body(2) },
                Some("length"),
                None,
            ),
        )
        .unwrap();
        let err = validate(&reg).unwrap_err();
        match err {
            SchemaError::InvalidDefinition { reason, .. } => {
                assert!(reason.contains("dimension"), "reason: {reason}");
            }
            other => panic!("expected invalid definition, got {other:?}"),
        }

        // Dangling unit reference.
        let mut reg2 = DefinitionRegistry::new();
        add_version(
            &mut reg2,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        add_version(
            &mut reg2,
            RecordKind::Property,
            rec(3),
            property_payload(
                "weight",
                ValueShape::Quantity { unit: unit_body(9) },
                None,
                None,
            ),
        )
        .unwrap();
        let err = validate(&reg2).unwrap_err();
        assert!(matches!(err, SchemaError::MissingReference { .. }));
    }

    #[test]
    fn dangling_inverse_is_rejected() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::Property,
            rec(3),
            property_payload(
                "elder_sibling",
                ValueShape::Text,
                None,
                Some("younger_sibling"),
            ),
        )
        .unwrap();
        let err = validate(&reg).unwrap_err();
        assert!(matches!(err, SchemaError::MissingReference { .. }));
    }

    #[test]
    fn zero_and_negative_unit_scale_are_invalid() {
        for digits in ["0", "-1", "0.0"] {
            let mut reg = DefinitionRegistry::new();
            add_version(
                &mut reg,
                RecordKind::Unit,
                rec(2),
                unit_payload(
                    "kilogram",
                    "mass",
                    None,
                    Some(Value::Decimal {
                        digits: digits.into(),
                    }),
                ),
            )
            .unwrap();
            let err = validate(&reg).unwrap_err();
            match &err {
                SchemaError::InvalidDefinition { reason, .. } => {
                    assert!(reason.contains("positive"), "reason: {reason}");
                }
                other => panic!("expected invalid definition, got {other:?}"),
            }
        }
        // A real conversion (1000 g per kg) is fine.
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::Unit,
            rec(2),
            unit_payload(
                "gram",
                "mass",
                None,
                Some(Value::Integer {
                    digits: "1000".into(),
                }),
            ),
        )
        .unwrap();
        assert!(validate(&reg).is_ok());
    }

    #[test]
    fn self_recursive_value_definition_is_rejected() {
        let mut reg = DefinitionRegistry::new();
        let a = ValueDefinitionId::from_id(rec(1)).unwrap();
        let b = ValueDefinitionId::from_id(rec(2)).unwrap();
        add_version(
            &mut reg,
            RecordKind::ValueDefinition,
            rec(1),
            Payload::ValueDefinition(ValueDef {
                namespace: "starter".into(),
                key: "a".into(),
                labels: BTreeMap::new(),
                fields: vec![ValueDefField {
                    name: "next".into(),
                    shape: ValueShape::Structured { definition: b },
                    required: false,
                    allows_unknown: true,
                }],
            }),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::ValueDefinition,
            rec(2),
            Payload::ValueDefinition(ValueDef {
                namespace: "starter".into(),
                key: "b".into(),
                labels: BTreeMap::new(),
                fields: vec![ValueDefField {
                    name: "back".into(),
                    shape: ValueShape::Structured { definition: a },
                    required: false,
                    allows_unknown: true,
                }],
            }),
        )
        .unwrap();
        let err = validate(&reg).unwrap_err();
        assert!(matches!(err, SchemaError::SchemaRecursion { .. }));
    }

    #[test]
    fn pack_cannot_declare_unknown_capability() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::DomainPack,
            rec(1),
            Payload::DomainPack(crate::registry::DomainPack {
                key: "fantasy".into(),
                version: "1".into(),
                dependencies: BTreeMap::new(),
                capabilities: vec!["time.crystal_ball.v9".into()],
                records: vec![],
            }),
        )
        .unwrap();
        let err = validate(&reg).unwrap_err();
        assert!(matches!(err, SchemaError::UnknownCapability { .. }));
    }

    #[test]
    fn valid_definitions_pass() {
        let mut reg = DefinitionRegistry::new();
        add_version(
            &mut reg,
            RecordKind::EntityType,
            rec(1),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::Unit,
            rec(2),
            unit_payload("kilogram", "mass", None, None),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::Property,
            rec(3),
            property_payload(
                "mass",
                ValueShape::Quantity { unit: unit_body(2) },
                Some("mass"),
                None,
            ),
        )
        .unwrap();
        add_version(
            &mut reg,
            RecordKind::Relation,
            rec(4),
            Payload::Relation(RelationDef {
                namespace: "starter".into(),
                key: "parent_of".into(),
                labels: BTreeMap::new(),
                roles: vec![RoleDef {
                    name: "parent".into(),
                    participant_types: vec![rec(1)],
                    multiplicity: Multiplicity::Single,
                    ordered: false,
                }],
            }),
        )
        .unwrap();
        assert!(validate(&reg).is_ok());
    }

    #[test]
    fn registry_rejects_tampered_payload() {
        let mut reg = DefinitionRegistry::new();
        let mut ver = RecordVersion::build(
            RecordVersionId::parse(&format!("ver_{:024x}", 7)).unwrap(),
            RecordIdentity::new(
                UniverseId::parse(UNIV).unwrap(),
                rec(1),
                RecordKind::EntityType,
            ),
            entity_type_payload("starter", "character", vec![]),
        )
        .unwrap();
        // Tamper with the payload after the digest was computed.
        if let Payload::EntityType(e) = &mut ver.payload {
            e.key = "tampered".into();
        }
        assert!(matches!(
            reg.add(&ver).unwrap_err(),
            SchemaError::DigestMismatch { .. }
        ));
    }
}
