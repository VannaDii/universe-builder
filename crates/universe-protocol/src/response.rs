//! Typed results. Evidence coverage and delivery completeness are independent.
use crate::request::{OperationKind, Selector, Submission};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use universe_domain::{ids::*, DomainOperation, Frame, RecordKind, RecordVersion};

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Envelope<T> {
    pub contract_version: String,
    pub request_id: u64,
    pub universe_id: UniverseId,
    pub universe: Selector,
    pub alias_matched: bool,
    pub frame: Option<Frame>,
    pub world_focus: Option<WorldId>,
    pub authorization_scope: String,
    pub delivery: Delivery,
    pub result: T,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Delivery {
    pub complete: bool,
    pub cursor: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityStatus {
    Implemented,
    Partial,
    DescriptiveOnly,
    Unsupported,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Capability {
    pub id: String,
    pub status: CapabilityStatus,
    pub limitation: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldSummary {
    pub id: WorldId,
    pub name: Selector,
}
/// Visible context choices at one continuity head, for opening the first frame.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RepresentedContextSummary {
    pub id: RecordId,
    pub kind: universe_domain::records::RepresentedContextKind,
    pub labels: std::collections::BTreeMap<String, String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ContinuitySummary {
    pub id: ContinuityId,
    pub revision_id: RevisionId,
    pub name: String,
    pub represented_contexts: Vec<RepresentedContextSummary>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Description {
    pub fixture: bool,
    pub worlds: Vec<WorldSummary>,
    pub capabilities: Vec<Capability>,
    pub definition_ids: Vec<RecordId>,
    pub continuities: Vec<ContinuitySummary>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OpenedContext {
    pub context_id: ContextId,
    pub frame: Frame,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SearchHit {
    pub record_id: RecordId,
    pub kind: RecordKind,
    pub label: String,
    pub world_ids: Vec<WorldId>,
    pub scope_category: ScopeCategory,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ScopeCategory {
    SelectedWorld,
    Shared,
    Unassigned,
    RequiredDependency,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SearchResults {
    pub hits: Vec<SearchHit>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Records {
    pub records: Vec<RecordVersion>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub summaries: Vec<RecordSummary>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub evidence: Vec<RecordVersion>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub history: Vec<HistoryEntry>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_coverage: Option<Coverage>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RecordSummary {
    pub record_id: RecordId,
    pub kind: universe_domain::RecordKind,
    pub label: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct HistoryEntry {
    pub record_id: RecordId,
    pub revision: RevisionId,
    pub continuity: ContinuityId,
    pub principal: PrincipalId,
    pub reason: String,
    pub record: Option<RecordVersion>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Coverage {
    Complete,
    Partial,
    Unsupported,
    Restricted,
    Failed,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct DerivedFact {
    pub subject: universe_domain::value::RecordRef,
    pub predicate: universe_domain::value::RecordRef,
    pub value: universe_domain::value::Value,
    pub evidence: Vec<RecordVersionId>,
    pub rule: RecordId,
}
/// A visible authored candidate, never a selected or materialized value.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ObjectEvidence {
    pub record: RecordVersion,
    pub applicability: Option<bool>,
    pub unknowns: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ObjectConflict {
    /// None means a possible conflict with unresolved applicability.
    pub applicability: Option<bool>,
    pub predicate: RecordId,
    pub assertions: Vec<RecordVersionId>,
    pub initial_values: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EffectiveObject {
    pub identity: RecordVersion,
    pub ancestry: Vec<RecordVersion>,
    pub ancestry_complete: bool,
    pub shared_attributes: Vec<ObjectEvidence>,
    pub instance_facts: Vec<ObjectEvidence>,
    pub initial_value_candidates: Vec<ObjectEvidence>,
    pub initialization_receipts: Vec<universe_domain::records::InitializationReceipt>,
    pub initialization_history_coverage: Coverage,
    pub behavioral_requirements: Vec<ObjectEvidence>,
    pub rules: Vec<ObjectEvidence>,
    /// Exact visible proposition/property dependencies for the evidence above.
    pub dependencies: Vec<RecordVersion>,
    pub conflicts: Vec<ObjectConflict>,
    pub unknowns: Vec<String>,
    pub coverage: Coverage,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct State {
    pub objects: Vec<EffectiveObject>,
    pub derived: Vec<DerivedFact>,
    pub epistemic: Vec<RecordVersion>,
    /// Authored clock at the pinned revision, separate from the query's time.
    pub chronology: Option<universe_domain::chronology::Chronology>,
    /// Evidence retained because its temporal applicability cannot be resolved.
    pub unresolved_assertion_ids: Vec<RecordId>,
    pub assertions: Vec<RecordVersion>,
    /// Explicit propositions retain qualified values; no alternative is selected as fact.
    pub propositions: Vec<RecordVersion>,
    /// Authored completeness declarations, including explicitly empty collections.
    /// An empty list never establishes a negative claim.
    pub completeness: Vec<RecordVersion>,
    pub coverage: Coverage,
    pub unsupported_capabilities: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ContextBrief {
    pub records: Vec<RecordVersion>,
    /// Required records on this page; concatenate manifests and records until delivery is complete.
    pub required_dependencies: Vec<RecordId>,
    pub coverage: Coverage,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceOutcome {
    Supported,
    Refuted,
    Conflicting,
    NotEstablished,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Finding {
    /// Repair guidance from the evaluator; never populated from hidden records.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    /// Existing record references resolving the version evidence at this frame.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub records: Vec<universe_domain::value::RecordRef>,
    pub fingerprint: FindingFingerprint,
    pub rule_id: RecordId,
    pub outcome: EvidenceOutcome,
    pub evidence: Vec<RecordVersionId>,
    pub coverage: Coverage,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum OpposingKind {
    Definite,
    Unresolved,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum OpposingIntersection {
    Unqualified,
    Exact {
        validity: universe_domain::scope::Validity,
    },
    Uncertain {
        left: universe_domain::scope::Validity,
        right: universe_domain::scope::Validity,
        guaranteed: Option<Box<universe_domain::scope::Validity>>,
    },
    Unresolved,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OpposingChain {
    pub assertion_id: RecordId,
    pub proposition_id: RecordId,
    pub assertion: RecordVersionId,
    pub proposition: RecordVersionId,
    pub dependencies: Vec<universe_domain::value::VersionRef>,
    pub complete: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum OpposingReason {
    Equality,
    Context,
    Realm,
    Worlds,
    Time,
    Precision,
    Persistence,
    Provenance,
    Budget,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OpposingEvidence {
    pub diagnostic_version: String,
    pub fingerprint: FindingFingerprint,
    pub kind: OpposingKind,
    pub proposition: universe_domain::records::Proposition,
    pub support: OpposingChain,
    pub refutation: OpposingChain,
    pub context: universe_domain::value::RecordRef,
    pub applicability: Option<universe_domain::scope::Applicability>,
    pub realm: Option<universe_domain::value::RecordRef>,
    pub intersection: OpposingIntersection,
    pub coverage: Coverage,
    pub unresolved_reasons: Vec<OpposingReason>,
    pub policy_versions: Vec<RecordVersionId>,
    pub exception_versions: Vec<RecordVersionId>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Validation {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub operation_id: Option<OperationId>,
    pub run_id: ValidationRunId,
    pub coverage: Coverage,
    pub findings: Vec<Finding>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub opposing_evidence: Vec<OpposingEvidence>,
    pub unsupported_capabilities: Vec<String>,
    pub input_digest: String,
    pub evaluator_version: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Proposal {
    pub base_frame: Frame,
    pub world_scope: Option<WorldId>,
    pub proposal_id: ProposalId,
    pub version: u64,
    pub digest: String,
    pub submission: Submission,
    pub operations: Vec<DomainOperation>,
    /// Exact compiled expansion for proposal retrieval. Paged with the authored operations.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub compiled_changes: Vec<CompiledChange>,
    pub rationale: String,
    pub canonical: bool,
    pub operation_id: OperationId,
    pub withdrawn: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CompiledChange {
    pub record_id: RecordId,
    pub expected: Option<RecordVersionId>,
    pub next: Option<RecordVersion>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Impact {
    pub records: Vec<RecordId>,
    pub coverage: Coverage,
    pub world_ids: Vec<WorldId>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CommitReceipt {
    pub operation_id: OperationId,
    pub proposal_id: ProposalId,
    pub revision: RevisionId,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum OperationState {
    Queued,
    Running,
    AwaitingAuthority,
    Committing,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OperationStatus {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub validation: Option<Box<Validation>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub failure: Option<String>,
    pub operation_id: OperationId,
    pub kind: OperationKind,
    pub state: OperationState,
    pub proposal: Option<Proposal>,
    pub receipt: Option<CommitReceipt>,
    pub cancellation_requested: bool,
}
pub type DescribeResult = Envelope<Description>;
pub type OpenContextResult = Envelope<OpenedContext>;
pub type SearchResult = Envelope<SearchResults>;
pub type GetResult = Envelope<Records>;
pub type GetStateResult = Envelope<State>;
pub type GetContextResult = Envelope<ContextBrief>;
pub type ValidateResult = Envelope<crate::validation_scope::ValidationV3>;
/// Semantic proposal actions retain their wire shape; assessment actions return
/// the independently versioned selection without modifying the frozen proposal.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum ProposalOutcome {
    Proposal(Box<Proposal>),
    AssessmentSelection(crate::assessment::AssessmentSelection),
}
pub type ProposeResult = Envelope<ProposalOutcome>;
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum ProposalViewResult {
    Proposal(Box<Proposal>),
    Assessment(Box<crate::assessment::AssessmentReviewPage>),
}
pub type GetProposalResult = Envelope<ProposalViewResult>;
pub type GetImpactResult = Envelope<Impact>;
pub type CommitResult = Envelope<CommitReceipt>;
pub type GetOperationResult = Envelope<crate::validation_scope::OperationStatusV3>;
pub type CancelOperationResult = Envelope<crate::validation_scope::OperationStatusV3>;
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "tool", content = "body", deny_unknown_fields)]
pub enum Response {
    #[serde(rename = "universe_check_changes")]
    CheckChanges(Envelope<crate::writing::WritingCheck>),
    ReadFacts(Envelope<serde_json::Value>),
    #[serde(rename = "universe_read_contracts")]
    ReadContracts(Envelope<serde_json::Value>),
    #[serde(rename = "universe_describe")]
    Describe(DescribeResult),
    #[serde(rename = "universe_open_context")]
    OpenContext(OpenContextResult),
    #[serde(rename = "universe_search")]
    Search(SearchResult),
    #[serde(rename = "universe_get")]
    Get(GetResult),
    #[serde(rename = "universe_get_state")]
    GetState(GetStateResult),
    #[serde(rename = "universe_get_context")]
    GetContext(GetContextResult),
    #[serde(rename = "universe_validate")]
    Validate(ValidateResult),
    #[serde(rename = "universe_propose")]
    Propose(ProposeResult),
    #[serde(rename = "universe_get_proposal")]
    GetProposal(GetProposalResult),
    #[serde(rename = "universe_get_impact")]
    GetImpact(GetImpactResult),
    #[serde(rename = "universe_commit")]
    Commit(CommitResult),
    #[serde(rename = "universe_get_operation")]
    GetOperation(GetOperationResult),
    #[serde(rename = "universe_cancel_operation")]
    CancelOperation(CancelOperationResult),
}
impl Response {
    pub fn body_json(&self) -> serde_json::Value {
        match self {
            Self::ReadContracts(v) => serde_json::to_value(v).expect("typed response"),
            Self::ReadFacts(v) => serde_json::to_value(v).expect("typed response"),
            Self::CheckChanges(v) => serde_json::to_value(v).expect("typed response"),
            Self::Describe(v) => serde_json::to_value(v).expect("typed response"),
            Self::OpenContext(v) => serde_json::to_value(v).expect("typed response"),
            Self::Search(v) => serde_json::to_value(v).expect("typed response"),
            Self::Get(v) => serde_json::to_value(v).expect("typed response"),
            Self::GetState(v) => serde_json::to_value(v).expect("typed response"),
            Self::GetContext(v) => serde_json::to_value(v).expect("typed response"),
            Self::Validate(v) => serde_json::to_value(v).expect("typed response"),
            Self::Propose(v) => serde_json::to_value(v).expect("typed response"),
            Self::GetProposal(v) => serde_json::to_value(v).expect("typed response"),
            Self::GetImpact(v) => serde_json::to_value(v).expect("typed response"),
            Self::Commit(v) => serde_json::to_value(v).expect("typed response"),
            Self::GetOperation(v) => serde_json::to_value(v).expect("typed response"),
            Self::CancelOperation(v) => serde_json::to_value(v).expect("typed response"),
        }
    }
}
