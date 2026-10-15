//! Closed application contracts (spec 30). Transport and MCP share these types.
use crate::{ProtocolError, ProtocolResult};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use universe_domain::{ids::*, DomainOperation, FrameTime, Perspective, RecordKind};

pub fn present<'de, D: serde::Deserializer<'de>, T: Deserialize<'de>>(
    d: D,
) -> Result<Option<T>, D::Error> {
    T::deserialize(d).map(Some)
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(transparent)]
pub struct Selector(
    #[schemars(length(min = 1, max = 256), regex(pattern = r"^[^\s*/\\][^*/\\]*$"))] pub String,
);

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ProposalRef {
    pub proposal_id: ProposalId,
    pub version: u64,
    pub digest: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Filters {
    pub record_kinds: Vec<RecordKind>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Submission {
    Draft,
    Submitted,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum CheckScope {
    Candidate,
    Dependencies,
    Universe,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum FieldGroup {
    Summary,
    Payload,
    Evidence,
    History,
}
/// Proposal assessment review is separate from canonical record field groups.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ProposalView {
    Summary,
    Payload,
    Evidence,
    History,
    Assessment,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum RevisionSelector {
    Head,
    Exact { revision_id: RevisionId },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OperationKind {
    Propose,
    Validate,
    Commit,
    Cancel,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum Describe {
    Summary {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
    },
    Capabilities {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
    },
    Worlds {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
    },
    Definitions {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "Selector")]
        world: Option<Selector>,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "WorldId")]
        world_id: Option<WorldId>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OpenContext {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub continuity_id: ContinuityId,
    pub revision: RevisionSelector,
    /// Existing opaque context identity, or an exact discovered context name. Ambiguous/inaccessible names are rejected.
    pub represented_context: RepresentedContextSelector,
    pub temporal_query: FrameTime,
    pub temporal_systems: Vec<CalendarId>,
    pub perspective: Perspective,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    /// Existing opaque scene identity or exact discovered scene name; ambiguous names are rejected. Reader order never implies story time.
    pub reader_scene: Option<RepresentedContextSelector>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged, deny_unknown_fields)]
pub enum RepresentedContextSelector {
    Id(RecordId),
    Name { name: String },
}
impl From<RecordId> for RepresentedContextSelector {
    fn from(value: RecordId) -> Self {
        Self::Id(value)
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Search {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub context_id: ContextId,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "Selector")]
    pub world: Option<Selector>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "WorldId")]
    pub world_id: Option<WorldId>,
    pub query: String,
    pub typed_filters: Filters,
    #[schemars(range(min = 1, max = 100))]
    pub limit: u32,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "String")]
    pub cursor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Get {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub context_id: ContextId,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "Selector")]
    pub world: Option<Selector>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "WorldId")]
    pub world_id: Option<WorldId>,
    #[schemars(length(min = 1, max = 100))]
    pub record_ids: Vec<RecordId>,
    pub field_groups: Vec<FieldGroup>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GetState {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub context_id: ContextId,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "Selector")]
    pub world: Option<Selector>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "WorldId")]
    pub world_id: Option<WorldId>,
    #[schemars(length(min = 1, max = 100))]
    pub entity_ids: Vec<RecordId>,
    pub predicate_filters: Vec<RecordId>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "RecordId")]
    pub event: Option<RecordId>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "universe_domain::frame::EventTimeSide")]
    pub event_side: Option<universe_domain::frame::EventTimeSide>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GetContext {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub context_id: ContextId,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "Selector")]
    pub world: Option<Selector>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "WorldId")]
    pub world_id: Option<WorldId>,
    #[schemars(length(min = 1, max = 100))]
    pub focus_ids: Vec<RecordId>,
    #[schemars(length(min = 1, max = 4096))]
    pub purpose: String,
    #[schemars(range(min = 256, max = 65536))]
    pub byte_budget: u32,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "String")]
    pub cursor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum Validate {
    QueuedProposal {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        check_scope: CheckScope,
        idempotency_key: String,
    },
    Inline {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "Selector")]
        world: Option<Selector>,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "WorldId")]
        world_id: Option<WorldId>,
        #[schemars(length(min = 1, max = 100))]
        operations: Vec<DomainOperation>,
        check_scope: CheckScope,
    },
    Proposal {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        check_scope: CheckScope,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum Propose {
    AttachAssessment {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        expected_selection_generation: u64,
        body: Box<crate::assessment::SourceAssessmentV1>,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
    },
    SelectAssessment {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        expected_selection_generation: u64,
        #[serde(deserialize_with = "crate::assessment::required_nullable")]
        assessment_reference: Option<crate::validation_scope::AssessmentRef>,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
    },
    Create {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "Selector")]
        world: Option<Selector>,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "WorldId")]
        world_id: Option<WorldId>,
        #[schemars(length(min = 1, max = 100))]
        operations: Vec<DomainOperation>,
        submission: Submission,
        #[schemars(length(min = 1, max = 4096))]
        rationale: String,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
    },
    Revise {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "Selector")]
        world: Option<Selector>,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "WorldId")]
        world_id: Option<WorldId>,
        proposal_reference: ProposalRef,
        #[schemars(length(min = 1, max = 100))]
        operations: Vec<DomainOperation>,
        submission: Submission,
        #[schemars(length(min = 1, max = 4096))]
        rationale: String,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
    },
    Submit {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
    },
    Withdraw {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GetProposal {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub proposal_id: ProposalId,
    pub version: u64,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "String")]
    pub cursor: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "ProposalView")]
    pub view_group: Option<ProposalView>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "crate::validation_scope::AssessmentRef")]
    pub assessment_reference: Option<crate::validation_scope::AssessmentRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum GetImpact {
    Inline {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "Selector")]
        world: Option<Selector>,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "WorldId")]
        world_id: Option<WorldId>,
        #[schemars(length(min = 1, max = 100))]
        changed_records: Vec<RecordId>,
        scope: CheckScope,
        #[schemars(range(min = 256, max = 65536))]
        byte_budget: u32,
    },
    Proposal {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        context_id: ContextId,
        proposal_reference: ProposalRef,
        scope: CheckScope,
        #[schemars(range(min = 256, max = 65536))]
        byte_budget: u32,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Commit {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub proposal_reference: ProposalRef,
    pub expected_base_revision: RevisionId,
    pub validation_run: ValidationRunId,
    #[schemars(length(min = 1, max = 4096))]
    pub idempotency_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "lookup", rename_all = "snake_case", deny_unknown_fields)]
pub enum GetOperation {
    Id {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        operation_id: OperationId,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "String")]
        cursor: Option<String>,
    },
    Key {
        universe: Selector,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "UniverseId")]
        universe_id: Option<UniverseId>,
        operation_kind: OperationKind,
        #[schemars(length(min = 1, max = 4096))]
        idempotency_key: String,
        #[serde(
            default,
            skip_serializing_if = "Option::is_none",
            deserialize_with = "present"
        )]
        #[schemars(with = "String")]
        cursor: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CancelOperation {
    pub universe: Selector,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "UniverseId")]
    pub universe_id: Option<UniverseId>,
    pub operation_id: OperationId,
    #[schemars(length(min = 1, max = 4096))]
    pub idempotency_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "tool", content = "args", deny_unknown_fields)]
pub enum Request {
    #[serde(rename = "universe_check_changes")]
    CheckChanges(Box<crate::writing::CheckChanges>),
    #[serde(rename = "universe_read_facts")]
    ReadFacts(crate::writing::ReadFacts),
    #[serde(rename = "universe_read_contracts")]
    ReadContracts(crate::writing::ReadContracts),
    #[serde(rename = "universe_describe")]
    Describe(Describe),
    #[serde(rename = "universe_open_context")]
    OpenContext(OpenContext),
    #[serde(rename = "universe_search")]
    Search(Search),
    #[serde(rename = "universe_get")]
    Get(Get),
    #[serde(rename = "universe_get_state")]
    GetState(GetState),
    #[serde(rename = "universe_get_context")]
    GetContext(GetContext),
    #[serde(rename = "universe_validate")]
    Validate(Validate),
    #[serde(rename = "universe_propose")]
    Propose(Propose),
    #[serde(rename = "universe_get_proposal")]
    GetProposal(GetProposal),
    #[serde(rename = "universe_get_impact")]
    GetImpact(GetImpact),
    #[serde(rename = "universe_commit")]
    Commit(Commit),
    #[serde(rename = "universe_get_operation")]
    GetOperation(GetOperation),
    #[serde(rename = "universe_cancel_operation")]
    CancelOperation(CancelOperation),
}
impl Request {
    pub fn tool_name(&self) -> &'static str {
        match self {
            Self::ReadContracts(..) => "universe_read_contracts",
            Self::ReadFacts(..) => "universe_read_facts",
            Self::CheckChanges(..) => "universe_check_changes",
            Self::Describe(..) => "universe_describe",
            Self::OpenContext(..) => "universe_open_context",
            Self::Search(..) => "universe_search",
            Self::Get(..) => "universe_get",
            Self::GetState(..) => "universe_get_state",
            Self::GetContext(..) => "universe_get_context",
            Self::Validate(..) => "universe_validate",
            Self::Propose(..) => "universe_propose",
            Self::GetProposal(..) => "universe_get_proposal",
            Self::GetImpact(..) => "universe_get_impact",
            Self::Commit(..) => "universe_commit",
            Self::GetOperation(..) => "universe_get_operation",
            Self::CancelOperation(..) => "universe_cancel_operation",
        }
    }
    pub fn universe(&self) -> &Selector {
        match self {
            Self::ReadContracts(a) => &a.universe,
            Self::ReadFacts(a) => &a.universe,
            Self::CheckChanges(a) => &a.universe,
            Self::Describe(Describe::Summary { universe, .. }) => universe,
            Self::Describe(Describe::Capabilities { universe, .. }) => universe,
            Self::Describe(Describe::Worlds { universe, .. }) => universe,
            Self::Describe(Describe::Definitions { universe, .. }) => universe,
            Self::OpenContext(a) => &a.universe,
            Self::Search(a) => &a.universe,
            Self::Get(a) => &a.universe,
            Self::GetState(a) => &a.universe,
            Self::GetContext(a) => &a.universe,
            Self::Validate(Validate::Inline { universe, .. }) => universe,
            Self::Validate(
                Validate::Proposal { universe, .. } | Validate::QueuedProposal { universe, .. },
            ) => universe,
            Self::Propose(Propose::Create { universe, .. }) => universe,
            Self::Propose(Propose::Revise { universe, .. }) => universe,
            Self::Propose(Propose::Submit { universe, .. }) => universe,
            Self::Propose(Propose::Withdraw { universe, .. }) => universe,
            Self::Propose(Propose::AttachAssessment { universe, .. }) => universe,
            Self::Propose(Propose::SelectAssessment { universe, .. }) => universe,
            Self::GetProposal(a) => &a.universe,
            Self::GetImpact(GetImpact::Inline { universe, .. }) => universe,
            Self::GetImpact(GetImpact::Proposal { universe, .. }) => universe,
            Self::Commit(a) => &a.universe,
            Self::GetOperation(GetOperation::Id { universe, .. }) => universe,
            Self::GetOperation(GetOperation::Key { universe, .. }) => universe,
            Self::CancelOperation(a) => &a.universe,
        }
    }
    pub fn from_tool(name: &str, args: serde_json::Value) -> ProtocolResult<Self> {
        let request: Self = serde_json::from_value(serde_json::json!({"tool":name,"args":args}))
            .map_err(|e| ProtocolError::invalid_argument("arguments", e.to_string()))?;
        request.validate()?;
        Ok(request)
    }
    pub fn validate(&self) -> ProtocolResult<()> {
        if let Self::ReadContracts(input) = self {
            if input.action_names.len() > 100
                || input.action_names.iter().any(|n| n.trim().is_empty())
            {
                return Err(ProtocolError::invalid_argument(
                    "action_names",
                    "at most 100 nonempty exact action names",
                ));
            }
        }
        if let Self::ReadFacts(input) = self {
            if input.object_names.is_empty()
                || input.object_names.len() > 100
                || input.object_names.iter().any(|n| n.trim().is_empty())
            {
                return Err(ProtocolError::invalid_argument(
                    "object_names",
                    "one to 100 nonempty object names required",
                ));
            }
        }
        if let Self::CheckChanges(a) = self {
            if a.events.len() + a.messages.len() + a.attitudes.len() + a.corrections.len() > 100
                || a.changes.len() > 100
                || a.changes.iter().map(|o| o.facts.len()).sum::<usize>() > 100
                || a.questions.len() > 20
            {
                return Err(ProtocolError::invalid_argument(
                    "changes",
                    "at most 100 objects/facts and 20 questions",
                ));
            }
            for fact in a.changes.iter().flat_map(|o| &o.facts) {
                if !matches!(
                    fact.statement.as_str(),
                    "objective" | "dialogue" | "belief" | "plan" | "hypothetical" | "metaphor"
                ) || !matches!(fact.when.as_str(), "scene" | "unspecified")
                    || fact.scope.trim().is_empty()
                {
                    return Err(ProtocolError::invalid_argument(
                        "changes",
                        "unknown statement, time or empty scope intent",
                    ));
                }
            }
        }
        if let Self::GetProposal(a) = self {
            if a.assessment_reference.is_some()
                && !matches!(a.view_group, Some(ProposalView::Assessment))
            {
                return Err(ProtocolError::invalid_argument(
                    "assessment_reference",
                    "requires assessment view",
                ));
            }
        }
        let all = serde_json::to_value(self)
            .map_err(|_| ProtocolError::invalid_argument("request", "cannot encode"))?;
        let args = &all["args"];
        for key in ["universe", "world"] {
            if let Some(value) = args.get(key) {
                let v = value.as_str().unwrap_or("");
                if v.trim().is_empty()
                    || v.len() > 256
                    || v.contains(['*', '/', '\\'])
                    || v.chars().any(char::is_control)
                    || v.starts_with(char::is_whitespace)
                {
                    return Err(ProtocolError::invalid_argument(
                        key,
                        "expected an exact nonblank selector",
                    ));
                }
            }
        }
        if args.get("world_id").is_some() && args.get("world").is_none() {
            return Err(ProtocolError::invalid_argument(
                "world_id",
                "requires world",
            ));
        }
        if args.get("event").is_some() != args.get("event_side").is_some() {
            return Err(ProtocolError::invalid_argument(
                "event",
                "event and event_side must be supplied together",
            ));
        }
        for key in ["idempotency_key", "rationale", "purpose"] {
            if let Some(v) = args.get(key) {
                if v.as_str()
                    .is_none_or(|s| s.trim().is_empty() || s.len() > 4096)
                {
                    return Err(ProtocolError::invalid_argument(
                        key,
                        "expected 1..4096 bytes",
                    ));
                }
            }
        }
        for key in [
            "operations",
            "record_ids",
            "entity_ids",
            "focus_ids",
            "changed_records",
        ] {
            if let Some(a) = args.get(key).and_then(|v| v.as_array()) {
                if a.is_empty() || a.len() > 100 {
                    return Err(ProtocolError::invalid_argument(
                        key,
                        "expected 1..100 items",
                    ));
                }
            }
        }
        for (key, lo, hi) in [("limit", 1, 100), ("byte_budget", 256, 65536)] {
            if let Some(v) = args.get(key).and_then(|v| v.as_u64()) {
                if !(lo..=hi).contains(&v) {
                    return Err(ProtocolError::invalid_argument(
                        key,
                        "outside request limits",
                    ));
                }
            }
        }
        Ok(())
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolSchema {
    pub name: String,
    pub description: String,
    pub input_schema: serde_json::Value,
    pub output_schema: serde_json::Value,
}
pub fn tool_schemas() -> Vec<ToolSchema> {
    serde_json::from_str(include_str!("../../../contracts/tools.json"))
        .expect("generated public tool schemas")
}
