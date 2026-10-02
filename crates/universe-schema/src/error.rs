//! Schema-layer error types (WP02.3).
//!
//! Domain-internal errors stay in `universe-domain`; this crate reports
//! *registry-level* problems: a single definition in isolation may be
//! structurally valid (domain) while being wrong for its universe
//! (this crate) — duplicate keys, dangling references, cycles, capability
//! overreach, or value/shape non-conformance.

use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SchemaError {
    /// The stored `payload_digest` does not match the payload's canonical
    /// bytes. Integrity failure, not an authoring error.
    #[error("digest mismatch for record {record}")]
    DigestMismatch { record: String },

    /// A definition record references a universe different from the
    /// registry's universe.
    #[error("record {record} belongs to universe {actual}; registry is {expected}")]
    CrossUniverse {
        record: String,
        expected: String,
        actual: String,
    },

    /// Two records in the same family with the same (namespace, key).
    /// Names are human labels; a duplicate reserved key means two
    /// definitions claim one identity (spec §27.2).
    #[error("duplicate definition key {namespace}:{key} in {family} ({record})")]
    DuplicateDefinition {
        family: String,
        namespace: String,
        key: String,
        record: String,
    },

    /// The same record id was registered twice.
    #[error("record {record} is already registered")]
    DuplicateRecord { record: String },

    /// A definition references another definition (unit, value definition,
    /// entity type, calendar) that is not present in the registry.
    #[error("{from} references {reference}, which is not in the registry ({family})")]
    MissingReference {
        from: String,
        reference: String,
        family: String,
    },

    /// Parent-type graph cycle (spec §27.2: inheritance cycles are
    /// rejected for executable subtype traversal).
    #[error("entity type inheritance cycle: {path}")]
    InheritanceCycle { path: String },

    /// A structured value definition refers back to itself, directly or
    /// transitively (spec §27.2: no unbounded recursive schemas).
    #[error("recursive value definition: {path}")]
    SchemaRecursion { path: String },

    /// A definition is structurally present but semantically invalid
    /// (zero unit scale, label-only calendar used where arithmetic is
    /// required, ...).
    #[error("invalid {family} {record}: {reason}")]
    InvalidDefinition {
        family: String,
        record: String,
        reason: String,
    },

    /// A domain pack declared a capability the application does not
    /// implement (spec §27.2: the registry cross-checks; a newly
    /// installed pack cannot make the application capable of evaluating
    /// code that has not been implemented).
    #[error("pack declares unknown capability `{capability}`")]
    UnknownCapability { capability: String },

    /// A value does not conform to its declared shape. The reason names
    /// the mismatch precisely; nothing is silently coerced (spec §27.2,
    /// E07).
    #[error("value does not conform to shape: {reason}")]
    ValueMismatch { reason: String },

    /// A pure-domain error (invalid id, invalid numeric, ...) surfaced
    /// through the schema layer.
    #[error(transparent)]
    Domain(#[from] universe_domain::DomainError),
}

pub type SchemaResult<T> = Result<T, SchemaError>;

impl SchemaError {
    pub fn code(&self) -> &'static str {
        match self {
            SchemaError::DigestMismatch { .. } => "DIGEST_MISMATCH",
            SchemaError::CrossUniverse { .. } => "CROSS_UNIVERSE_REFERENCE",
            SchemaError::DuplicateDefinition { .. } => "DUPLICATE_DEFINITION",
            SchemaError::DuplicateRecord { .. } => "DUPLICATE_RECORD",
            SchemaError::MissingReference { .. } => "MISSING_REFERENCE",
            SchemaError::InheritanceCycle { .. } => "INHERITANCE_CYCLE",
            SchemaError::SchemaRecursion { .. } => "SCHEMA_RECURSION",
            SchemaError::InvalidDefinition { .. } => "INVALID_DEFINITION",
            SchemaError::UnknownCapability { .. } => "UNKNOWN_CAPABILITY",
            SchemaError::ValueMismatch { .. } => "VALUE_MISMATCH",
            SchemaError::Domain(e) => e.code(),
        }
    }
}
