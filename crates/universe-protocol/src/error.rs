//! Protocol-layer error types (WP03, spec §11.6).
//!
//! These errors are returned to MCP clients and the desktop UI. They map
//! closely to the MCP error taxonomy in spec §11.6, with additional fields
//! for world scope and context information where relevant.

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// All protocol-visible errors (spec §11.6).
#[derive(Debug, Error, PartialEq, Eq, Clone, Serialize, Deserialize)]
#[serde(tag = "code", rename_all = "SCREAMING_SNAKE_CASE", deny_unknown_fields)]
pub enum ProtocolError {
    /// Invalid typed input; includes field path and expected form.
    #[error("invalid argument: {field}: {message}")]
    InvalidArgument { field: String, message: String },

    /// Choose an authorized candidate explicitly; never use fuzzy routing.
    #[error("ambiguous reference: {message}")]
    AmbiguousReference { message: String },

    /// Supply a nonempty universe name; no context/profile/default fallback.
    #[error("universe name required")]
    UniverseRequired,

    /// Correct the name/ID guard; emitted only when both are safely
    /// disclosable, otherwise generic inaccessible result.
    #[error("universe ID mismatch: expected {expected}, got {actual}")]
    UniverseIdMismatch { expected: String, actual: String },

    /// A handle/reference conflicts with the explicitly selected authorized
    /// universe; never auto-switch.
    #[error("universe scope mismatch: {message}")]
    UniverseScopeMismatch { message: String },

    /// The named world is absent from this accessible universe/revision;
    /// never search another universe.
    #[error("world not found or not accessible: {message}")]
    WorldNotFoundOrNotAccessible { message: String },

    /// The requested world focus/write envelope conflicts with explicit
    /// targets or effects.
    #[error("world scope conflict: {message}")]
    WorldScopeConflict { message: String },

    /// Select another administrative name or resolve a duplicate/alias
    /// through author controls; disclose no hidden owner.
    #[error("name unavailable: {message}")]
    NameUnavailable { message: String },

    /// Do not infer whether a restricted record exists.
    #[error("not found or not accessible: {message}")]
    NotFoundOrNotAccessible { message: String },

    /// Open a new context; do not silently switch revision.
    #[error("context expired")]
    ContextExpired,

    /// Inspect diff, explicitly rebase, and revalidate.
    #[error("base revision conflict: expected {expected}, got {actual}")]
    BaseRevisionConflict { expected: String, actual: String },

    /// Present the proposal to the author; do not retry with a fabricated
    /// approval field.
    #[error("approval required: {message}")]
    ApprovalRequired { message: String },

    /// Review the changed proposal/canon/policy again.
    #[error("approval stale")]
    ApprovalStale,

    /// Recover the original operation or use a genuinely new request key.
    #[error("idempotency key reused: {message}")]
    IdempotencyKeyReused { message: String },

    /// Preserve the data; report the unsupported capability.
    #[error("unsupported semantics: {message}")]
    UnsupportedSemantics { message: String },

    /// Retrieve partial output/job status; no pass claim.
    #[error("evaluation limit reached: {message}")]
    EvaluationLimitReached { message: String },

    /// Stop that mutation path.
    #[error("policy denied: {message}")]
    PolicyDenied { message: String },

    /// Preserve input and use diagnostics/recovery; no success claim.
    #[error("storage failure: {message}")]
    StorageFailure { message: String },

    /// Wait for explicit maintenance completion; no alternate writer.
    #[error("maintenance required")]
    MaintenanceRequired,

    /// A domain-layer error from `universe-domain`.
    #[error("domain: {message}")]
    Domain { message: String },
}

impl ProtocolError {
    /// Create a generic "not found" error that hides whether the record exists.
    pub fn not_found(message: impl Into<String>) -> Self {
        ProtocolError::NotFoundOrNotAccessible {
            message: message.into(),
        }
    }

    /// Create an invalid argument error with a field path.
    pub fn invalid_argument(field: impl Into<String>, message: impl Into<String>) -> Self {
        ProtocolError::InvalidArgument {
            field: field.into(),
            message: message.into(),
        }
    }

    /// Convert a domain error into a protocol error.
    pub fn from_domain(err: &crate::DomainError) -> Self {
        ProtocolError::Domain {
            message: err.to_string(),
        }
    }

    /// The error code string for MCP tool-visible errors.
    pub fn code(&self) -> &'static str {
        match self {
            ProtocolError::InvalidArgument { .. } => "INVALID_ARGUMENT",
            ProtocolError::AmbiguousReference { .. } => "AMBIGUOUS_REFERENCE",
            ProtocolError::UniverseRequired => "UNIVERSE_REQUIRED",
            ProtocolError::UniverseIdMismatch { .. } => "UNIVERSE_ID_MISMATCH",
            ProtocolError::UniverseScopeMismatch { .. } => "UNIVERSE_SCOPE_MISMATCH",
            ProtocolError::WorldNotFoundOrNotAccessible { .. } => {
                "WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE"
            }
            ProtocolError::WorldScopeConflict { .. } => "WORLD_SCOPE_CONFLICT",
            ProtocolError::NameUnavailable { .. } => "NAME_UNAVAILABLE",
            ProtocolError::NotFoundOrNotAccessible { .. } => "NOT_FOUND_OR_NOT_ACCESSIBLE",
            ProtocolError::ContextExpired => "CONTEXT_EXPIRED",
            ProtocolError::BaseRevisionConflict { .. } => "BASE_REVISION_CONFLICT",
            ProtocolError::ApprovalRequired { .. } => "APPROVAL_REQUIRED",
            ProtocolError::ApprovalStale => "APPROVAL_STALE",
            ProtocolError::IdempotencyKeyReused { .. } => "IDEMPOTENCY_KEY_REUSED",
            ProtocolError::UnsupportedSemantics { .. } => "UNSUPPORTED_SEMANTICS",
            ProtocolError::EvaluationLimitReached { .. } => "EVALUATION_LIMIT_REACHED",
            ProtocolError::PolicyDenied { .. } => "POLICY_DENIED",
            ProtocolError::StorageFailure { .. } => "STORAGE_FAILURE",
            ProtocolError::MaintenanceRequired => "MAINTENANCE_REQUIRED",
            ProtocolError::Domain { .. } => "DOMAIN_ERROR",
        }
    }

    /// Whether this error is a protocol-level failure (malformed/unroutable)
    /// versus a tool-visible error (valid request that cannot complete).
    pub fn is_protocol_failure(&self) -> bool {
        matches!(
            self,
            ProtocolError::InvalidArgument { .. }
                | ProtocolError::UniverseRequired
                | ProtocolError::Domain { .. }
        )
    }
}

/// Result type for protocol operations.
pub type ProtocolResult<T> = Result<T, ProtocolError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_codes_match_spec() {
        let codes: Vec<&str> = vec![
            "INVALID_ARGUMENT",
            "AMBIGUOUS_REFERENCE",
            "UNIVERSE_REQUIRED",
            "UNIVERSE_ID_MISMATCH",
            "UNIVERSE_SCOPE_MISMATCH",
            "WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE",
            "WORLD_SCOPE_CONFLICT",
            "NAME_UNAVAILABLE",
            "NOT_FOUND_OR_NOT_ACCESSIBLE",
            "CONTEXT_EXPIRED",
            "BASE_REVISION_CONFLICT",
            "APPROVAL_REQUIRED",
            "APPROVAL_STALE",
            "IDEMPOTENCY_KEY_REUSED",
            "UNSUPPORTED_SEMANTICS",
            "EVALUATION_LIMIT_REACHED",
            "POLICY_DENIED",
            "STORAGE_FAILURE",
            "MAINTENANCE_REQUIRED",
        ];

        let actual: Vec<&str> = vec![
            ProtocolError::InvalidArgument {
                field: "x".into(),
                message: "y".into(),
            }
            .code(),
            ProtocolError::AmbiguousReference {
                message: "x".into(),
            }
            .code(),
            ProtocolError::UniverseRequired.code(),
            ProtocolError::UniverseIdMismatch {
                expected: "a".into(),
                actual: "b".into(),
            }
            .code(),
            ProtocolError::UniverseScopeMismatch {
                message: "x".into(),
            }
            .code(),
            ProtocolError::WorldNotFoundOrNotAccessible {
                message: "x".into(),
            }
            .code(),
            ProtocolError::WorldScopeConflict {
                message: "x".into(),
            }
            .code(),
            ProtocolError::NameUnavailable {
                message: "x".into(),
            }
            .code(),
            ProtocolError::NotFoundOrNotAccessible {
                message: "x".into(),
            }
            .code(),
            ProtocolError::ContextExpired.code(),
            ProtocolError::BaseRevisionConflict {
                expected: "a".into(),
                actual: "b".into(),
            }
            .code(),
            ProtocolError::ApprovalRequired {
                message: "x".into(),
            }
            .code(),
            ProtocolError::ApprovalStale.code(),
            ProtocolError::IdempotencyKeyReused {
                message: "x".into(),
            }
            .code(),
            ProtocolError::UnsupportedSemantics {
                message: "x".into(),
            }
            .code(),
            ProtocolError::EvaluationLimitReached {
                message: "x".into(),
            }
            .code(),
            ProtocolError::PolicyDenied {
                message: "x".into(),
            }
            .code(),
            ProtocolError::StorageFailure {
                message: "x".into(),
            }
            .code(),
            ProtocolError::MaintenanceRequired.code(),
        ];

        assert_eq!(codes, actual);
    }

    #[test]
    fn serialization_roundtrip() {
        let err = ProtocolError::WorldScopeConflict {
            message: "test".into(),
        };
        let json = serde_json::to_string(&err).unwrap();
        let restored: ProtocolError = serde_json::from_str(&json).unwrap();
        assert_eq!(err, restored);
    }

    #[test]
    fn not_found_hides_existence() {
        let err = ProtocolError::not_found("entity");
        assert!(matches!(err, ProtocolError::NotFoundOrNotAccessible { .. }));
    }

    #[test]
    fn is_protocol_failure_identifies_malformed() {
        assert!(ProtocolError::UniverseRequired.is_protocol_failure());
        assert!(!ProtocolError::ContextExpired.is_protocol_failure());
    }
}
