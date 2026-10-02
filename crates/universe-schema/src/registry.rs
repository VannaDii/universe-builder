//! The definition registry (WP02.3).
//!
//! A registry holds the *definitions* of one universe — entity types,
//! property/relation definitions, units, calendars, structured value
//! definitions, and domain packs — resolved from their record versions,
//! so that validation and value conformance can cross-reference them
//! (spec §27.2: "Definitions are versioned at the same canon snapshot as
//! their use").
//!
//! It is deliberately not a record store: only the seven definition
//! families are accepted. Instance records live in the canon revisions
//! (WP05), and the service resolves them at the requested snapshot.

use std::collections::BTreeMap;

use universe_domain::ids::{CalendarId, RecordId, UnitId, UniverseId, ValueDefinitionId};
pub use universe_domain::records::{
    CalendarDef, DomainPack, EntityType, Payload, PropertyDef, RecordVersion, RelationDef, UnitDef,
    ValueDef,
};

use crate::error::{SchemaError, SchemaResult};

/// One definition payload with its record identity.
#[derive(Debug, Clone)]
pub enum Definition {
    EntityType(RecordId, EntityType),
    Property(RecordId, PropertyDef),
    Relation(RecordId, RelationDef),
    Unit(UnitId, Box<UnitDef>),
    Calendar(CalendarId, CalendarDef),
    ValueSchema(ValueDefinitionId, ValueDef),
    DomainPack(RecordId, DomainPack),
}

impl Definition {
    pub fn family(&self) -> &'static str {
        match self {
            Definition::EntityType(..) => "entity_type",
            Definition::Property(..) => "property",
            Definition::Relation(..) => "relation",
            Definition::Unit(..) => "unit",
            Definition::Calendar(..) => "calendar",
            Definition::ValueSchema(..) => "value_definition",
            Definition::DomainPack(..) => "domain_pack",
        }
    }

    /// The record id as string (map key). For typed families this is the
    /// body-remapped record id (ADR-0001); it cannot fail for a
    /// definition constructed via `from_version`.
    pub fn record_key(&self) -> SchemaResult<String> {
        Ok(match self {
            Definition::EntityType(id, _)
            | Definition::Property(id, _)
            | Definition::Relation(id, _)
            | Definition::DomainPack(id, _) => id.to_owned(),
            Definition::Unit(id, _) => id.to_record_id()?.to_owned(),
            Definition::Calendar(id, _) => id.to_record_id()?.to_owned(),
            Definition::ValueSchema(id, _) => id.to_record_id()?.to_owned(),
        })
    }

    pub fn namespace_key(&self) -> (String, String) {
        match self {
            Definition::EntityType(_, d) => (d.namespace.clone(), d.key.clone()),
            Definition::Property(_, d) => (d.namespace.clone(), d.key.clone()),
            Definition::Relation(_, d) => (d.namespace.clone(), d.key.clone()),
            Definition::Unit(_, d) => (d.namespace.clone(), d.key.clone()),
            Definition::Calendar(_, d) => (d.namespace.clone(), d.key.clone()),
            Definition::ValueSchema(_, d) => (d.namespace.clone(), d.key.clone()),
            Definition::DomainPack(_, d) => (String::new(), d.key.clone()),
        }
    }

    /// Extract a `Definition` from a record version, enforcing
    /// identity/payload consistency.
    pub fn from_version(version: &RecordVersion) -> SchemaResult<Option<Definition>> {
        use universe_domain::records::RecordKind::*;
        match version.identity.record_kind {
            EntityType => match &version.payload {
                Payload::EntityType(d) => Ok(Some(Definition::EntityType(
                    version.identity.record_id.clone(),
                    d.clone(),
                ))),
                _ => unreachable!("Payload::kind() checked by RecordVersion::build"),
            },
            Property => match &version.payload {
                Payload::Property(d) => Ok(Some(Definition::Property(
                    version.identity.record_id.clone(),
                    d.clone(),
                ))),
                _ => unreachable!(),
            },
            Relation => match &version.payload {
                Payload::Relation(d) => Ok(Some(Definition::Relation(
                    version.identity.record_id.clone(),
                    d.clone(),
                ))),
                _ => unreachable!(),
            },
            Unit => {
                let def = match &version.payload {
                    Payload::Unit(d) => d.clone(),
                    _ => unreachable!(),
                };
                // The typed family id is the record id's 24-hex body with
                // the family prefix (body remap, ADR-0001).
                let unit = UnitId::from_id(version.identity.record_id.clone())?;
                Ok(Some(Definition::Unit(unit, Box::new(def))))
            }
            Calendar => {
                let def = match &version.payload {
                    Payload::Calendar(d) => d.clone(),
                    _ => unreachable!(),
                };
                let cal = CalendarId::from_id(version.identity.record_id.clone())?;
                Ok(Some(Definition::Calendar(cal, def)))
            }
            ValueDefinition => {
                let def = match &version.payload {
                    Payload::ValueDefinition(d) => d.clone(),
                    _ => unreachable!(),
                };
                let vdef = ValueDefinitionId::from_id(version.identity.record_id.clone())?;
                Ok(Some(Definition::ValueSchema(vdef, def)))
            }
            DomainPack => match &version.payload {
                Payload::DomainPack(d) => Ok(Some(Definition::DomainPack(
                    version.identity.record_id.clone(),
                    d.clone(),
                ))),
                _ => unreachable!(),
            },
            // Non-definition records are canon content, not registry data.
            _ => Ok(None),
        }
    }
}

/// The definition registry of one universe.
#[derive(Debug, Clone, Default)]
pub struct DefinitionRegistry {
    universe: Option<UniverseId>,
    entity_types: BTreeMap<String, EntityType>,
    properties: BTreeMap<String, PropertyDef>,
    relations: BTreeMap<String, RelationDef>,
    units: BTreeMap<String, UnitDef>,
    calendars: BTreeMap<String, CalendarDef>,
    value_definitions: BTreeMap<String, ValueDef>,
    domain_packs: BTreeMap<String, DomainPack>,
    /// (family, namespace, key) -> record key, for duplicate detection.
    name_index: BTreeMap<(String, String, String), String>,
}

impl DefinitionRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// The universe this registry holds definitions for.
    pub fn universe(&self) -> Option<&UniverseId> {
        self.universe.as_ref()
    }

    /// Register a record version.
    ///
    /// Non-definition kinds are accepted and ignored (they belong to canon
    /// revisions, WP05). Definition versions replace any earlier version of
    /// the same record id — the registry tracks the *active* definition of
    /// a record within a canon snapshot; superseded bytes remain in the
    /// store's immutable history.
    pub fn add(&mut self, version: &RecordVersion) -> SchemaResult<()> {
        if !version.verify_digest() {
            return Err(SchemaError::DigestMismatch {
                record: version.identity.record_id.to_owned(),
            });
        }
        let Some(def) = Definition::from_version(version)? else {
            return Ok(());
        };
        let record = version.identity.record_id.to_owned();

        // One registry, one universe. A definition from another universe
        // is a namespace collision, never an implicit merge (spec §36.2).
        match &self.universe {
            Some(u) if *u != version.identity.universe_id => {
                return Err(SchemaError::CrossUniverse {
                    record,
                    expected: u.to_owned(),
                    actual: version.identity.universe_id.to_owned(),
                });
            }
            None => self.universe = Some(version.identity.universe_id.clone()),
            _ => {}
        }

        let key = def.record_key()?;
        let (ns, k) = def.namespace_key();
        if let Some(existing) =
            self.name_index
                .get(&(def.family().to_string(), ns.clone(), k.clone()))
        {
            if *existing != key {
                return Err(SchemaError::DuplicateDefinition {
                    family: def.family().to_string(),
                    namespace: ns,
                    key: k,
                    record,
                });
            }
        }
        self.name_index
            .insert((def.family().to_string(), ns, k), key.clone());

        match def {
            Definition::EntityType(_, d) => {
                self.entity_types.insert(key, d);
            }
            Definition::Property(_, d) => {
                self.properties.insert(key, d);
            }
            Definition::Relation(_, d) => {
                self.relations.insert(key, d);
            }
            Definition::Unit(_, d) => {
                self.units.insert(key, *d);
            }
            Definition::Calendar(_, d) => {
                self.calendars.insert(key, d);
            }
            Definition::ValueSchema(_, d) => {
                self.value_definitions.insert(key, d);
            }
            Definition::DomainPack(_, d) => {
                self.domain_packs.insert(key, d);
            }
        }
        Ok(())
    }

    // -- lookups ----------------------------------------------------------

    pub fn entity_type(&self, id: &RecordId) -> Option<&EntityType> {
        self.entity_types.get(&id.to_owned())
    }
    pub fn property(&self, id: &RecordId) -> Option<&PropertyDef> {
        self.properties.get(&id.to_owned())
    }
    pub fn relation(&self, id: &RecordId) -> Option<&RelationDef> {
        self.relations.get(&id.to_owned())
    }
    pub fn unit(&self, id: &UnitId) -> Option<&UnitDef> {
        match id.to_record_id() {
            Ok(r) => self.units.get(&r.to_owned()),
            Err(_) => None,
        }
    }
    pub fn calendar(&self, id: &CalendarId) -> Option<&CalendarDef> {
        match id.to_record_id() {
            Ok(r) => self.calendars.get(&r.to_owned()),
            Err(_) => None,
        }
    }
    pub fn value_definition(&self, id: &ValueDefinitionId) -> Option<&ValueDef> {
        match id.to_record_id() {
            Ok(r) => self.value_definitions.get(&r.to_owned()),
            Err(_) => None,
        }
    }
    pub fn domain_pack(&self, id: &RecordId) -> Option<&DomainPack> {
        self.domain_packs.get(&id.to_owned())
    }

    /// Find a property by (namespace, key) — used for inverse references.
    pub fn property_by_key(&self, namespace: &str, key: &str) -> Option<&PropertyDef> {
        self.properties
            .values()
            .find(|p| p.namespace == namespace && p.key == key)
    }

    // -- iteration for validation ------------------------------------------

    pub fn entity_types(&self) -> impl Iterator<Item = (&str, &EntityType)> {
        self.entity_types.iter().map(|(k, v)| (k.as_str(), v))
    }
    pub fn properties(&self) -> impl Iterator<Item = (&str, &PropertyDef)> {
        self.properties.iter().map(|(k, v)| (k.as_str(), v))
    }
    pub fn relations(&self) -> impl Iterator<Item = (&str, &RelationDef)> {
        self.relations.iter().map(|(k, v)| (k.as_str(), v))
    }
    pub fn units(&self) -> impl Iterator<Item = (&str, &UnitDef)> {
        self.units.iter().map(|(k, v)| (k.as_str(), v))
    }
    pub fn calendars(&self) -> impl Iterator<Item = (&str, &CalendarDef)> {
        self.calendars.iter().map(|(k, v)| (k.as_str(), v))
    }
    pub fn value_definitions(&self) -> impl Iterator<Item = (&str, &ValueDef)> {
        self.value_definitions.iter().map(|(k, v)| (k.as_str(), v))
    }
    pub fn domain_packs(&self) -> impl Iterator<Item = (&str, &DomainPack)> {
        self.domain_packs.iter().map(|(k, v)| (k.as_str(), v))
    }

    pub fn is_empty(&self) -> bool {
        self.entity_types.is_empty()
            && self.properties.is_empty()
            && self.relations.is_empty()
            && self.units.is_empty()
            && self.calendars.is_empty()
            && self.value_definitions.is_empty()
            && self.domain_packs.is_empty()
    }
}
