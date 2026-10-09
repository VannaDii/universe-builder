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
    pub represented_context: RecordId,
    pub temporal_query: FrameTime,
    pub temporal_systems: Vec<CalendarId>,
    pub perspective: Perspective,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    #[schemars(with = "RecordId")]
    pub reader_scene: Option<RecordId>,
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
    vec![
        ToolSchema {
            name: "universe_read_contracts".into(),
            description: "Read plain pinned, visible action roles/requirements/consequences and authored knowledge/channel contracts and named exhaustive object collections, relationship roles, authored cross-occurrence maxima and visible author-perspective relationship assertions. Restricted perspectives omit occurrence values. Objective and observer-known sets remain distinct; absent declarations are open/unknown. Exact action names; empty discovers names. No missing contract implies a default rule. No internal record joins required.".into(),
            input_schema: augment_schema(serde_json::to_value(schemars::schema_for!(crate::writing::ReadContracts)).expect("schema")),
            output_schema: serde_json::to_value(schemars::schema_for!(crate::response::Envelope<serde_json::Value>)).expect("schema"),
        },
        ToolSchema {
            name: "universe_read_facts".into(),
            description: "Read plain effective facts for named objects in a pinned context. Optional world selects an exact authored world; omission never infers one. Returns exact authored property names and plain values, support/refutation/conflicts/unknowns, scope, time and actual coverage. Inherited attributes are returned separately from instance facts and initial-value candidates, with named classification/ancestry. Reusable definitions can also be researched by name. Missing or ambiguous identities never imply a new identity. Reuse returned property names for deltas. Source records are resolved by the engine; no internal schemas or ID joins required.".into(),
            input_schema: augment_schema(serde_json::to_value(schemars::schema_for!(crate::writing::ReadFacts)).expect("schema")),
            output_schema: serde_json::to_value(schemars::schema_for!(crate::response::Envelope<serde_json::Value>)).expect("schema"),
        },
        ToolSchema {
            name: "universe_check_changes".into(),
            description: "Check plain factual deltas from author writing against pinned canon. An explicitly selected authorized author perspective is required; other perspectives are research only. Resolve existing objects by their exact visible names; introduce new identities only explicitly. Preserve dialogue, beliefs, plans, hypothetical and figurative claims as non-objective. The engine constructs canonical records, creates a provisional candidate, validates it and inspects impact. It returns a candidate handle, findings and material clarifications; it never approves or publishes. Scope/time/ownership ambiguities remain unresolved. Named definitions introduce reusable types/parent relationships/shared attributes; classification introduces or refines an instance without replacing identity. Shared attributes never become initial stock. definitions.initial_values declare starting candidates, which must be approved before explicit initializations select their opaque handles. Each initialization requires an explicit occurred start using a declared action/participants/time/world, or a retrieved pinned occurred-event handle, and an authored interval. First mention, classification and restart never initialize or refill. event_corrections use pinned occurred-event handles and changed named fields; omitted fields retain canon. Participants explicitly replace all bindings; empty requires_knowledge explicitly clears direct Knows preconditions. Effects are recalculated from authored contracts, never editable stock facts. Manual effects outside declared slots require advanced correction. Later events are checked but never automatically rewritten. New scalar properties impose no single-value constraint; explicit properties declare type, multiplicity and persistence without revising existing definitions. definition_corrections revise named type ancestry/applicability without reclassifying instances; an explicit root parent removes ancestry. action_corrections replace only supplied requirements/effects/applicability or explicit tick plus lifetime; omitted fields retain canon. Both require private contract review, preserve history and recheck affected instances/events. Supplied action lists replace the complete selected field; custom legacy effect slots require advanced editing. Shared attribute values use pinned factual correction handles. Named actions support role/property/value requirements, set or bounded integer-delta effects and authored lifetimes. Constraints support resource_accounting or no_opposing_evidence. Explicit exhaustive_sets declare all named members of an object-valued property for authored subject/scope/time/lifetime; required members=[] deliberately declares none. Absence never implies completeness. Exhaustive declarations require private contract review; member facts are checked against applicable objective boundaries. relation_definitions explicitly introduce named unordered, unrestricted-type roles with single/multiple local multiplicity. relation_limits declare actual subject-or-role grouping, counted role and maximum in authored scope/time; limits require private contract review and always block violations. relationships submit objective subject/participant names using existing roles; type restrictions and ordering remain authored, missing names/undeclared roles require clarification. relationship_corrections use returned opaque authored assertion-version handles, changed participant roles and a reason; each supplied role list replaces that role ([] clears), omitted roles and subject/relation/scope/time remain unchanged. relationship_endings explicitly end an authored interval at an exclusive end_tick on its original calendar, with a reason. Atomic ending plus a new occurrence supports transfers; overlapping ownership still conflicts. Stale or generated handles cannot edit. Corrections/endings require exact private factual source review. No limit implies exclusivity, no minimum is inferred, and ordinary scoped waivers are unsupported. knowledge_policies explicitly declare author_established or justified mode on the selected context, or named channel forward/delay timing; no delivery or understanding is inferred. Contracts require separate private author declaration review and exact approval. Author-established knows remains held until the separate private establish_knowledge decision selecting holder/claim/time/lifetime/rationale and exact author approval; neither source review nor generic approval creates the decision. Explicit quantities use {amount,unit} with exact authored numbers and named units. Quantity properties require a unit. Visible unit metadata is returned by read_contracts; explicit no-conversion unit declarations require private contract review. Never infer dimension, symbol, unit conversion or physics. Quantity deltas require integer amounts/bounds with the exact declared unit; decimal resource arithmetic remains unsupported. Existing authored property semantics and resource accounting remain enforced.".into(),
            input_schema: augment_schema(serde_json::to_value(schemars::schema_for!(crate::writing::CheckChanges)).expect("schema")),
            output_schema: serde_json::to_value(schemars::schema_for!(crate::response::Envelope<crate::writing::WritingCheck>)).expect("schema"),
        },
        ToolSchema {
            name: "universe_describe".into(),
            description: "Describe: summary discovers visible continuity heads and represented-context IDs needed to open a first context; other modes describe capabilities or pinned world/definition records. Explicit universe required; fixture mode has no canon writes."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(Describe)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::DescribeResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_open_context".into(),
            description:
                "OpenContext: explicit universe required; fixture mode has no canon writes.".into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(OpenContext)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::OpenContextResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_search".into(),
            description: "Literal text search: query is one literal string, not an object-name list or inferred sentence. Resolve named objects with universe_read_facts object_names; an empty search does not establish identity absence. Search: explicit universe required; fixture mode has no canon writes."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(Search)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::SearchResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_get".into(),
            description: "Get: explicit universe required; fixture mode has no canon writes."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(Get)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(crate::response::GetResult))
                .expect("schema"),
        },
        ToolSchema {
            name: "universe_get_state".into(),
            description: "Read explicit and derived state at the pinned story time/perspective before verifying prose. Inspect unresolved evidence and semantic coverage. Explicit universe required; unavailable in fixture mode."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(GetState)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::GetStateResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_get_context".into(),
            description:
                "Research dependency-closed canon before verifying draft prose. Follow pagination and inspect coverage; complete delivery is not prose validation. Explicit universe required; unavailable in fixture mode.".into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(GetContext)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::GetContextResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_validate".into(),
            description: "Validate the exact structured continuity claims and consequences of draft prose before considering it usable. Inspect execution findings/coverage, submitted_input and assessment separately; complete engine checks and source-only commits never certify manuscript continuity. Validation does not commit canon. Explicit universe required; unavailable in fixture mode."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(Validate)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::ValidateResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_propose".into(),
            description: "Propose structured facts, events and other material universe changes represented by draft prose, preserving evidence references when available. Proposals are provisional until validated, approved and committed. attach_assessment and select_assessment attach immutable assessor declarations or replace/withdraw selection without changing the frozen proposal. Explicit universe required; fixture proposals cannot become canon."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(Propose)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::ProposeResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_get_proposal".into(),
            description:
                "Read a frozen proposal or view_group=assessment. Assessment view returns current selection/state and the exact selected or requested historical envelope. Follow pinned cursors; concatenate canonical_envelope_utf8 fragments by byte offset, decode and verify the body digest before treating review as complete. Current permissions are checked on every page. Explicit universe required; fixture mode has no assessments.".into(),
            input_schema: {
                let mut schema = augment_schema(serde_json::to_value(schemars::schema_for!(GetProposal)).expect("schema"));
                schema["allOf"] = serde_json::json!([{
                    "if":{"required":["assessment_reference"]},
                    "then":{"required":["view_group"],"properties":{"view_group":{"const":"assessment"}}}
                }]);
                schema
            },
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::GetProposalResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_get_impact".into(),
            description: "Inspect affected canon and dependencies before using and committing a checked candidate's structured changes. Explicit universe required; unavailable in fixture mode."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(GetImpact)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::GetImpactResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_commit".into(),
            description: "After the author chooses to use checked candidate prose, commit its exact validated structured universe changes so future writing includes their impact. Requires current authority and exact author approval or bounded delegation. Confirm the receipt and reopen at the committed revision. Explicit universe required; denied in fixture mode."
                .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(Commit)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::CommitResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_get_operation".into(),
            description:
                "GetOperation: explicit universe required; fixture mode has no canon writes.".into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(GetOperation)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::GetOperationResult
            ))
            .expect("schema"),
        },
        ToolSchema {
            name: "universe_cancel_operation".into(),
            description:
                "CancelOperation: explicit universe required; fixture mode has no canon writes."
                    .into(),
            input_schema: augment_schema(
                serde_json::to_value(schemars::schema_for!(CancelOperation)).expect("schema"),
            ),
            output_schema: serde_json::to_value(schemars::schema_for!(
                crate::response::CancelOperationResult
            ))
            .expect("schema"),
        },
    ]
}
fn augment_schema(mut schema: serde_json::Value) -> serde_json::Value {
    fn visit(v: &mut serde_json::Value) {
        if let Some(props) = v.get("properties").and_then(|p| p.as_object()) {
            let world = props.contains_key("world_id");
            let event = props.contains_key("event");
            if world {
                v["dependentRequired"] = serde_json::json!({"world_id":["world"]});
            }
            if event {
                v["dependentRequired"] = serde_json::json!({"world_id":["world"],"event":["event_side"],"event_side":["event"]});
            }
        }
        if let Some(m) = v.as_object_mut() {
            for value in m.values_mut() {
                visit(value)
            }
        } else if let Some(a) = v.as_array_mut() {
            for value in a {
                visit(value)
            }
        }
    }
    visit(&mut schema);
    schema
}
