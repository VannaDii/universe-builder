//! Private installation commands. These are not MCP tools or canon-write APIs.
use serde::{Deserialize, Serialize};
use universe_domain::ids::*;
#[derive(Clone, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Credential(String);
impl Credential {
    pub fn new(s: String) -> Self {
        Self(s)
    }
    pub fn expose(&self) -> &str {
        &self.0
    }
}
impl std::fmt::Debug for Credential {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("[redacted]")
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EngineHello {
    pub protocol_version: String,
    pub profile_id: ProfileId,
    pub credential: Credential,
    pub client_name: String,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EngineWelcome {
    pub protocol_version: String,
    pub service_instance: String,
    pub principal: ProfileId,
    pub author: bool,
    pub max_frame_bytes: usize,
    pub max_in_flight: usize,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrantSpec {
    pub profile_id: ProfileId,
    pub universe_id: UniverseId,
    pub worlds: Option<Vec<WorldId>>,
    pub propose: bool,
    pub edit: bool,
    pub protected: bool,
    #[serde(default)]
    pub limits: GrantLimits,
}
/// Explicit write boundaries. Read visibility remains governed by the universe/world grant.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrantLimits {
    pub entities: Option<Vec<RecordId>>,
    pub predicates: Option<Vec<RecordId>>,
    pub continuities: Option<Vec<ContinuityId>>,
    pub expires_at: Option<u64>,
    #[serde(default)]
    pub delegated_commit: bool,
    #[serde(default)]
    pub allow_shared: bool,
}
/// Unsubmitted structured editor operations. Saving a draft never changes canon.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DraftContent {
    pub base_revision: RevisionId,
    pub represented_context: RecordId,
    pub operations: Vec<universe_domain::DomainOperation>,
    pub rationale: String,
    /// Resume edits as a new immutable version of the same submission.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposal: Option<crate::request::ProposalRef>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SavedDraft {
    pub version: u64,
    pub content: DraftContent,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportMode {
    Restore,
    Clone,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "method", rename_all = "snake_case", deny_unknown_fields)]
pub enum EngineRequest {
    Status,
    Doctor,
    Profiles,
    WithdrawGrant {
        profile_id: ProfileId,
        universe_id: UniverseId,
    },
    PreviewPurge {
        universe: crate::request::Selector,
    },
    Purge {
        universe: crate::request::Selector,
        digest: String,
        confirmation: String,
    },
    Tool {
        request: Box<crate::Request>,
    },
    Library {
        universe: crate::request::Selector,
    },
    ForkContinuity {
        universe: crate::request::Selector,
        name: String,
        continuity_id: ContinuityId,
        source: ContinuityId,
        revision: RevisionId,
    },
    CompareContinuities {
        universe: crate::request::Selector,
        target: ContinuityId,
        target_revision: RevisionId,
        source: ContinuityId,
        source_revision: RevisionId,
    },
    PrepareAdoption {
        universe: crate::request::Selector,
        target: ContinuityId,
        target_revision: RevisionId,
        source: ContinuityId,
        source_revision: RevisionId,
        record_ids: Vec<RecordId>,
    },
    LoadDraft {
        universe: crate::request::Selector,
        continuity_id: ContinuityId,
    },
    SaveDraft {
        universe: crate::request::Selector,
        continuity_id: ContinuityId,
        expected_version: u64,
        content: DraftContent,
    },
    StageImage {
        universe: crate::request::Selector,
        source: std::path::PathBuf,
    },
    ImagePreview {
        universe: crate::request::Selector,
        context_id: ContextId,
        asset: RecordId,
    },
    AuthorWriting {
        universe: crate::request::Selector,
        action: AuthorWritingAction,
    },
    StageSource {
        universe: crate::request::Selector,
        label: String,
        text: String,
    },
    Backup {
        universe: crate::request::Selector,
        destination: std::path::PathBuf,
    },
    Restore {
        source: std::path::PathBuf,
        name: String,
    },
    Maintain {
        universe: crate::request::Selector,
        collect: bool,
    },
    ConvertLegacy {
        source: std::path::PathBuf,
        destination: std::path::PathBuf,
    },
    ExportLogical {
        universe: crate::request::Selector,
        destination: std::path::PathBuf,
        record_ids: Vec<RecordId>,
        #[serde(default)]
        complete_history: bool,
    },
    PreviewImport {
        source: std::path::PathBuf,
        name: String,
        mode: ImportMode,
    },
    AcceptImport {
        preview_id: OperationId,
        digest: String,
    },
    Review {
        universe: crate::request::Selector,
        proposal_reference: crate::request::ProposalRef,
    },
    Approve {
        universe: crate::request::Selector,
        proposal_reference: crate::request::ProposalRef,
        validation_run: ValidationRunId,
    },
    CreateUniverse {
        name: String,
        start: universe_domain::chronology::UniverseStart,
    },
    RegisterUniverse {
        path: std::path::PathBuf,
        name: String,
    },
    RenameUniverse {
        universe_id: UniverseId,
        name: String,
    },
    Enroll,
    Grant {
        grant: GrantSpec,
    },
    Revoke {
        profile_id: ProfileId,
    },
    Shutdown,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EngineCall {
    pub id: u64,
    pub request: EngineRequest,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EngineReply {
    pub id: u64,
    pub result: Result<serde_json::Value, crate::ProtocolError>,
}

/// Private author decisions; never exposed as model tools.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum AuthorWritingAction {
    /// Reopen an existing exact source-bound review without staging new source.
    Inspect {
        candidate: crate::request::ProposalRef,
    },
    Prepare {
        candidate: ProposalId,
        label: String,
        text: String,
    },
    /// Explicit private author declaration of supported action contracts/policies; separate approval still required.
    PrepareContracts {
        candidate: ProposalId,
        label: String,
        text: String,
    },
    /// Explicit author-selected knowledge decision, followed by exact review/approval; never model-visible.
    EstablishKnowledge {
        context_id: ContextId,
        declaration: crate::writing::AuthorKnowledgeDeclaration,
        rationale: String,
        label: String,
        text: String,
    },
    Reject {
        candidate: ProposalId,
    },
    Publish {
        candidate: crate::request::ProposalRef,
        validation_run: ValidationRunId,
        idempotency_key: String,
    },
    Accept {
        candidate: crate::request::ProposalRef,
        fingerprint: FindingFingerprint,
        scope: String,
        rationale: String,
    },
}
