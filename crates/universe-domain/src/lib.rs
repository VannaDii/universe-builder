//! Universe Builder canonical domain model.
//!
//! Typed records, values, and invariants with a single versioned canonical
//! serializer (spec §27.8). This crate has no transport, database, or
//! service dependencies (spec §3.4): it must be testable without LM Studio,
//! a webview, SQLite, or a model.
//!
//! Key distinctions preserved here (spec §1.1, §5):
//! - entity vs. assertion vs. proposition vs. represented context
//! - fictional time vs. editorial time (editorial time lives on commits,
//!   never in `TemporalExpression`)
//! - explicit absence vs. missing/unknown (tagged alternatives, never a
//!   bare `None` where the distinction matters)
//! - universe vs. world vs. work/saga ownership (§5.6, §36.1)

pub mod canonical;
pub mod chronology;
pub mod consequences;
pub mod error;
pub mod expr;
pub mod frame;
pub mod ids;
pub mod records;
pub mod scope;
pub mod temporal;
pub mod value;

pub use canonical::{
    canonical_bytes, canonical_json, payload_digest, Canonical, CanonicalValue, PayloadDigest,
};
pub use error::{DomainError, DomainResult};
pub use expr::{Comparator, Expr, Operand, Quantifier};
pub use frame::{Frame, FrameTime, Perspective};
pub use ids::{
    AnchorId, ApprovalId, CalendarId, ContextId, ContinuityId, ExceptionId, FindingFingerprint,
    FindingId, GrantId, Id, OperationId, PrincipalId, ProfileId, ProposalId, ProposalVersionId,
    PropositionId, RecordId, RecordVersionId, RevisionId, RuleId, SagaId, UnitId, UniverseId,
    ValidationRunId, ValueDefinitionId, WorkId, WorldId,
};
pub use records::{
    Assertion, CalendarDef, Commitment, Communication, CompletenessDecl, CreativeBoundary,
    DomainOperation, DomainPack, Entity, EntityEffect, EntityType, EpistemicAttitude, Event,
    Exception, IssueDecision, Memory, Observation, Payload, PropertyDef, Realm, RecordIdentity,
    RecordKind, RecordVersion, RelationDef, RepresentedContext, Rule, Secret, Source,
    SourceVersion, UnitDef, ValueDef, Work, WorkVersion, World,
};
pub use scope::{
    Applicability, EvidenceBasis, PersistenceSemantics, Polarity, Precision, Scope, Validity,
};
pub use temporal::{TemporalBound, TemporalExpression, TemporalRelation};
pub use value::{limits, LocalRef, RecordRef, SpatialExpression, Value, VersionRef};

/// Application contract version (independent of database and MCP protocol
/// versions; spec §11.4).
pub const CONTRACT_VERSION: &str = "1";

/// Rule expression language version (spec §14.5, §27.10).
pub const EXPR_LANGUAGE_VERSION: &str = "rule-expr-v1";

/// Capability identifiers published by the capability registry (spec §27.10).
pub mod capabilities {
    pub const ASSERTION_QUALIFIED: &str = "assertion.qualified.v1";
    pub const TIME_EXACT_INTERVAL: &str = "time.exact_interval.v1";
    pub const TIME_RELATIVE_ORDER: &str = "time.relative_order.v1";
    pub const STATE_DECLARED_PERSISTENCE: &str = "state.declared_persistence.v1";
    pub const RULE_FINITE_CONSTRAINTS: &str = "rule.finite_constraints.v1";
    pub const KNOWLEDGE_EXPLICIT_ATTITUDES: &str = "knowledge.explicit_attitudes.v1";
    pub const CONTINUITY_PINNED_INHERITANCE: &str = "continuity.pinned_inheritance.v1";
}

pub mod appearance;

pub mod starter;
