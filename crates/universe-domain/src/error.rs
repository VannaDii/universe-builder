use crate::ids::Id;

/// Errors produced by domain-level validation and canonical (de)serialization.
///
/// These are structural errors: they never depend on access control, storage,
/// or transport (spec §9.2 structural stage; §27.8).
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DomainError {
    #[error("invalid id `{value}` for {kind}")]
    InvalidId { kind: String, value: String },
    #[error("id `{value}` for {kind} belongs to a different universe (expected {expected}, got {actual})")]
    CrossUniverseReference {
        kind: String,
        value: String,
        expected: String,
        actual: String,
    },
    #[error("reference {what} has kind {actual} but {kind} is required")]
    WrongRecordKind {
        what: String,
        kind: String,
        actual: String,
    },
    #[error("invalid numeric value `{value}`: {reason}")]
    InvalidNumeric { value: String, reason: String },
    #[error("invalid value: {reason}")]
    InvalidValue { reason: String },
    #[error("invalid temporal expression: {reason}")]
    InvalidTemporal { reason: String },
    #[error("duplicate key `{key}` in canonical object")]
    DuplicateKey { key: String },
    #[error("unknown field `{field}` in closed schema {schema}")]
    UnknownField { schema: String, field: String },
    #[error("field `{field}` is required in {schema}")]
    MissingField { schema: String, field: String },
    #[error("expression: {reason}")]
    Expression { reason: String },
    #[error("selector key `{key}` is invalid: {reason}")]
    InvalidSelector { key: String, reason: String },
}

pub type DomainResult<T> = Result<T, DomainError>;

impl DomainError {
    pub fn code(&self) -> &'static str {
        match self {
            DomainError::InvalidId { .. } => "INVALID_ID",
            DomainError::CrossUniverseReference { .. } => "CROSS_UNIVERSE_REFERENCE",
            DomainError::WrongRecordKind { .. } => "WRONG_RECORD_KIND",
            DomainError::InvalidNumeric { .. } => "INVALID_NUMERIC",
            DomainError::InvalidValue { .. } => "INVALID_VALUE",
            DomainError::InvalidTemporal { .. } => "INVALID_TEMPORAL",
            DomainError::DuplicateKey { .. } => "DUPLICATE_KEY",
            DomainError::UnknownField { .. } => "UNKNOWN_FIELD",
            DomainError::MissingField { .. } => "MISSING_FIELD",
            DomainError::Expression { .. } => "EXPRESSION_ERROR",
            DomainError::InvalidSelector { .. } => "INVALID_SELECTOR",
        }
    }
}

impl Id {
    /// Structural check used by `Id::parse` implementations.
    pub fn validate_prefix(prefix: &str, value: &str) -> Result<(), DomainError> {
        if value.len() < prefix.len() + 8
            || !value.starts_with(prefix)
            || !value
                .as_bytes()
                .iter()
                .all(|b| b.is_ascii_alphanumeric() || *b == b'_')
        {
            Err(DomainError::InvalidId {
                kind: prefix.to_string(),
                value: value.to_string(),
            })
        } else {
            Ok(())
        }
    }
}
