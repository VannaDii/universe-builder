//! Stable, prefixed, opaque identifiers (spec §27.1).
//!
//! A prefix helps detect mistakes but does not confer authority or establish
//! membership in a universe (spec §27.1). IDs are generated in the service
//! from a CSPRNG; humans never supply identity, only selectors.

use serde::{Deserialize, Serialize};

use crate::error::{DomainError, DomainResult};

/// Maximum length of a generated id body (24 hex chars) plus prefix.
const ID_BODY_LEN: usize = 24;

macro_rules! define_id {
    ($name:ident, $prefix:literal, $doc:expr) => {
        #[doc = $doc]
        #[derive(
            Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, schemars::JsonSchema,
        )]
        #[serde(transparent)]
        pub struct $name(
            #[schemars(regex(pattern = concat!("^", $prefix, "[0-9a-f]{24}$")))] pub String,
        );

        impl std::fmt::Display for $name {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str(&self.0) }
        }
        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
                let value = String::deserialize(deserializer)?;
                Self::parse(&value).map_err(serde::de::Error::custom)
            }
        }

        impl $name {
            /// Serialized prefix, e.g. `unv_`.
            pub const PREFIX: &'static str = $prefix;

            /// Generate a new collision-resistant id (`prefix` + 24 hex chars, 96 bits).
            pub fn generate<R>(rng: &mut R) -> Self
            where
                R: rand::RngCore + rand::CryptoRng,
            {
                let mut bytes = [0u8; 12];
                rng.fill_bytes(&mut bytes);
                let mut body = String::with_capacity(ID_BODY_LEN);
                for byte in &bytes {
                    body.push_str(&format!("{byte:02x}"));
                }
                Self(format!("{}{}", Self::PREFIX, body))
            }

            /// Parse and validate an id string.
            pub fn parse(value: &str) -> Result<Self, crate::error::DomainError> {
                Id::check_prefix(Self::PREFIX, value)?;
                if value.len() != Self::PREFIX.len() + ID_BODY_LEN || !value[Self::PREFIX.len()..].bytes().all(|b|matches!(b,b'0'..=b'9'|b'a'..=b'f')) {
                    return Err(crate::error::DomainError::InvalidId {
                        kind: Self::PREFIX.to_string(),
                        value: value.to_string(),
                    });
                }
                Ok(Self(value.to_string()))
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }

            pub fn to_owned(&self) -> String {
                self.0.clone()
            }
        }
    };
}

define_id!(
    UniverseId,
    "unv_",
    "Stable identity of a named universe (top-level storage and reference boundary)."
);
define_id!(
    WorldId,
    "wld_",
    "Stable identity of a named world record within a universe."
);
define_id!(
    WorkId,
    "wrk_",
    "Stable identity of an external narrative work owned by a universe."
);
define_id!(SagaId, "sag_", "Stable identity of a saga/series grouping.");
define_id!(
    ContinuityId,
    "cont_",
    "Stable identity of a continuity (one canon revision head)."
);
define_id!(
    RevisionId,
    "rev_",
    "Stable identity of an immutable canon revision."
);
define_id!(
    RecordId,
    "rec_",
    "Stable identity of a canonical record within a universe."
);
define_id!(
    RecordVersionId,
    "ver_",
    "Stable identity of an immutable record version."
);
define_id!(ProposalId, "prp_", "Stable identity of a proposal.");
define_id!(
    ProposalVersionId,
    "prv_",
    "Stable identity of an immutable proposal version."
);
define_id!(
    OperationId,
    "op_",
    "Stable identity of a durable operation."
);
define_id!(
    PrincipalId,
    "prn_",
    "Stable identity of an authenticated application principal."
);
define_id!(
    ContextId,
    "ctx_",
    "Opaque application context handle (frame pin, not a grant)."
);
define_id!(
    ValidationRunId,
    "val_",
    "Stable identity of an immutable validation run."
);
define_id!(FindingId, "fnd_", "Stable identity of a durable finding.");
define_id!(
    ApprovalId,
    "appr_",
    "Stable identity of an immutable approval record."
);
define_id!(
    ProfileId,
    "prf_",
    "Stable identity of an MCP profile (installation state)."
);
define_id!(
    GrantId,
    "grn_",
    "Stable identity of an authorization grant (installation state)."
);

/// A generic prefixed identifier that accepts any of the known prefixes.
/// Used when the exact family is unknown at parse time (wire boundaries).
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(transparent)]
pub struct Id(pub String);

impl Id {
    /// Structural prefix check shared by the typed `Id` families.
    pub fn check_prefix(prefix: &str, value: &str) -> Result<(), crate::error::DomainError> {
        if value.is_empty()
            || !value.starts_with(prefix)
            || !value
                .as_bytes()
                .iter()
                .all(|b| b.is_ascii_alphanumeric() || *b == b'_')
            || value.len() < prefix.len() + 8
        {
            return Err(crate::error::DomainError::InvalidId {
                kind: prefix.to_string(),
                value: value.to_string(),
            });
        }
        Ok(())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// The known id prefixes, used for validation at wire boundaries.
pub const KNOWN_PREFIXES: &[&str] = &[
    UniverseId::PREFIX,
    WorldId::PREFIX,
    WorkId::PREFIX,
    SagaId::PREFIX,
    ContinuityId::PREFIX,
    RevisionId::PREFIX,
    RecordId::PREFIX,
    RecordVersionId::PREFIX,
    ProposalId::PREFIX,
    ProposalVersionId::PREFIX,
    OperationId::PREFIX,
    PrincipalId::PREFIX,
    ContextId::PREFIX,
    ValidationRunId::PREFIX,
    FindingId::PREFIX,
    ApprovalId::PREFIX,
    ProfileId::PREFIX,
    GrantId::PREFIX,
    CalendarId::PREFIX,
    PropositionId::PREFIX,
    RuleId::PREFIX,
    ExceptionId::PREFIX,
    AnchorId::PREFIX,
];

impl Id {
    pub fn is_known(value: &str) -> bool {
        KNOWN_PREFIXES.iter().any(|p| value.starts_with(p))
    }
}

// Definition-family typed ids. Definitions are records, but the wire and
// evaluation layers reference them with dedicated id families so that a
// RecordRef to a definition is distinguishable from one to an entity
// (spec §27.2; §11.5 `predicate_id` examples).
define_id!(
    CalendarId,
    "cal_",
    "Stable identity of a calendar / temporal reference system definition."
);
define_id!(
    PropositionId,
    "prop_",
    "Stable identity of a proposition record."
);
define_id!(
    RuleId,
    "rule_",
    "Stable identity of a rule definition record."
);
define_id!(
    ExceptionId,
    "exc_",
    "Stable identity of an exception record."
);
define_id!(
    AnchorId,
    "anch_",
    "Stable identity of an evidence anchor record."
);
define_id!(
    UnitId,
    "unit_",
    "Stable identity of a unit definition record."
);
define_id!(
    ValueDefinitionId,
    "vdef_",
    "Stable identity of a structured value definition record."
);

/// Remap an id's 24-hex body between families.
///
/// The id *body* is the identity; only the family prefix changes. This makes
/// the definition families total mappings over `RecordId` (a calendar
/// definition is a record; its `cal_` reference carries the same body) and
/// keeps the forward/inverse mappings deterministic.
fn remap_id_body(id: &str, from_prefix: &str, to_prefix: &str) -> DomainResult<String> {
    let body = id.strip_prefix(from_prefix).unwrap_or("");
    if body.len() != ID_BODY_LEN || !body.bytes().all(|c| c.is_ascii_hexdigit()) {
        return Err(DomainError::InvalidId {
            kind: from_prefix.to_string(),
            value: id.to_string(),
        });
    }
    Ok(format!("{to_prefix}{body}"))
}

macro_rules! definition_id_mappings {
    ($name:ident) => {
        impl $name {
            /// Derive this definition reference from the record id of the
            /// definition it denotes (body-preserving prefix remap).
            pub fn from_id(id: RecordId) -> DomainResult<$name> {
                remap_id_body(&id.0, RecordId::PREFIX, Self::PREFIX).map($name)
            }

            /// The inverse mapping: the record id of the definition this
            /// reference denotes.
            pub fn to_record_id(&self) -> DomainResult<RecordId> {
                remap_id_body(&self.0, Self::PREFIX, RecordId::PREFIX).map(RecordId)
            }
        }
    };
}

definition_id_mappings!(CalendarId);
definition_id_mappings!(UnitId);
definition_id_mappings!(ValueDefinitionId);
definition_id_mappings!(PropositionId);
definition_id_mappings!(RuleId);
definition_id_mappings!(ExceptionId);
definition_id_mappings!(AnchorId);

impl From<&str> for Id {
    fn from(s: &str) -> Self {
        Id(s.to_string())
    }
}

/// An entity identified by its record id (alias for readability; entities
/// are records — spec §5.1: a ship that is also an individual does not
/// require duplicate identities).
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(transparent)]
pub struct EntityIdAlias(pub RecordId);

impl EntityIdAlias {
    pub fn from_id(id: RecordId) -> DomainResult<Self> {
        if !id.0.starts_with(RecordId::PREFIX) {
            return Err(DomainError::InvalidId {
                kind: RecordId::PREFIX.to_string(),
                value: id.to_owned(),
            });
        }
        Ok(Self(id))
    }
    pub fn record_id(&self) -> &RecordId {
        &self.0
    }
}

impl std::fmt::Display for EntityIdAlias {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0.as_str())
    }
}

/// A finding fingerprint: rule version, candidate digest, relevant fact and
/// source versions, temporal/context scope, and issue category (spec §31.7).
///
/// A resolution applies to the exact fingerprint/scope; the same wording
/// with changed evidence or rule produces a new fingerprint (E24).
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(transparent)]
pub struct FindingFingerprint(pub String);

impl FindingFingerprint {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::RngCore;

    #[test]
    fn ids_round_trip_through_serialization() {
        let mut rng = rand::rng();
        let u = UniverseId::generate(&mut rng);
        let w = WorldId::generate(&mut rng);
        let json = serde_json::to_string(&u).unwrap();
        assert_eq!(UniverseId::parse(u.as_str()).unwrap(), u);
        let back: UniverseId = serde_json::from_str(&json).unwrap();
        assert_eq!(back, u);
        assert!(w.0.starts_with("wld_"));
    }

    #[test]
    fn id_generation_is_unique_and_prefixed() {
        let mut rng = rand::rng();
        let mut seen = std::collections::HashSet::new();
        for _ in 0..10_000 {
            let id = RecordId::generate(&mut rng);
            assert_eq!(id.0.len(), 4 + 24);
            assert!(seen.insert(id.0));
            let _ = rng.next_u64();
        }
        assert_eq!(seen.len(), 10_000);
    }

    #[test]
    fn invalid_ids_are_rejected() {
        let err = UniverseId::parse("unv_short");
        assert!(matches!(err, Err(DomainError::InvalidId { .. })));
        assert!(matches!(
            UniverseId::parse("wld_000000000000000000000000"),
            Err(DomainError::InvalidId { .. })
        ));
        assert!(matches!(
            UniverseId::parse("unv_00000000000000000000 0"),
            Err(DomainError::InvalidId { .. })
        ));
        assert!(UniverseId::parse("unv_0123456789abcdef01234567").is_ok());
    }

    use crate::error::DomainError;

    #[test]
    fn generic_id_accepts_known_prefixes() {
        assert!(Id::is_known("rec_abc123def456abc123def45"));
        assert!(!Id::is_known("nonsense_abc123def456abc123def4"));
    }
}

#[cfg(test)]
mod wire_id_tests {
    use super::*;
    #[test]
    fn typed_ids_reject_invalid_bodies_during_deserialization() {
        for body in ["z".repeat(24), "A".repeat(24), "_".repeat(24)] {
            let value = format!("unv_{body}");
            assert!(UniverseId::parse(&value).is_err());
            assert!(serde_json::from_value::<UniverseId>(serde_json::json!(value)).is_err());
        }
    }
}
