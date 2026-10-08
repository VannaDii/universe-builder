//! Ordinary factual deltas; canonical record construction belongs to the engine.
use crate::request::Selector;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use universe_domain::ids::ContextId;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum FactValue {
    Text(String),
    Boolean(bool),
    Number(serde_json::Number),
    Object { object: String },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FactChange {
    pub property: String,
    pub value: FactValue,
    #[serde(default)]
    pub negated: bool,
    /// objective, dialogue, belief, plan, hypothetical or metaphor. Only objective claims become facts.
    #[serde(default = "objective")]
    #[schemars(with = "StatementIntent")]
    pub statement: String,
    /// universe, a retrieved world name, or unspecified. Never infer a world from its universe name.
    #[serde(default = "unspecified")]
    pub scope: String,
    /// scene uses the pinned research time; unspecified preserves missing time.
    #[serde(default = "unspecified")]
    #[schemars(with = "TimeIntent")]
    pub when: String,
    /// Explicit scene tick on the selected context's authored calendar. Missing tick never chooses a current-time default.
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Explicit scene fact lifetime. Unspecified preserves authored property persistence only.
    #[serde(default)]
    pub lifetime: FactLifetime,
}
#[derive(JsonSchema)]
#[schemars(rename_all = "snake_case")]
#[allow(dead_code)]
enum StatementIntent {
    Objective,
    Dialogue,
    Belief,
    Plan,
    Hypothetical,
    Metaphor,
}
#[derive(JsonSchema)]
#[schemars(rename_all = "snake_case")]
#[allow(dead_code)]
enum TimeIntent {
    Scene,
    Unspecified,
}
fn objective() -> String {
    "objective".into()
}
fn unspecified() -> String {
    "unspecified".into()
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ObjectChange {
    pub name: String,
    /// Explicit intent to introduce a new independent identity. False resolves existing visible canon.
    #[serde(default)]
    pub introduce: bool,
    #[serde(default)]
    pub facts: Vec<FactChange>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CheckChanges {
    pub universe: Selector,
    /// Opaque context handle returned by research. The engine pins author admission to the same revision.
    pub context_id: ContextId,
    /// Only factual deltas; do not restate the universe or unchanged facts.
    #[schemars(length(max = 100))]
    #[serde(default)]
    pub changes: Vec<ObjectChange>,
    #[serde(default)]
    pub events: Vec<WritingEvent>,
    #[serde(default)]
    pub messages: Vec<WritingMessage>,
    #[serde(default)]
    pub attitudes: Vec<WritingAttitude>,
    #[serde(default)]
    pub corrections: Vec<WritingCorrection>,
    /// Material ambiguities identified in the writing. Any unresolved question holds the entire delta without creating a candidate.
    #[serde(default)]
    pub questions: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingCheck {
    pub status: String,
    pub candidate_handle: Option<String>,
    pub additions: Vec<String>,
    pub unchanged: Vec<String>,
    pub clarifications: Vec<String>,
    pub excluded: Vec<String>,
    pub unknowns: Vec<String>,
    pub validation: Option<serde_json::Value>,
    pub impact: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ReadFacts {
    pub universe: Selector,
    pub context_id: ContextId,
    /// Exact object names to research. A missing or ambiguous match remains explicit.
    #[schemars(length(min = 1, max = 100))]
    pub object_names: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum FactLifetime {
    #[default]
    Unspecified,
    UntilChanged,
    /// Explicit exclusive end on the same authored calendar; never inferred.
    Until {
        end_tick: String,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingClaim {
    pub subject: String,
    pub property: String,
    pub value: FactValue,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingEvent {
    /// Exact authored action name; effects and balances come from its existing contract.
    pub action: String,
    /// Authored action role to exact object name.
    pub participants: std::collections::BTreeMap<String, String>,
    /// Explicit tick on the selected context's authored calendar; omit only when research pins an exact scene time.
    #[serde(default)]
    pub at_tick: Option<String>,
    #[serde(default)]
    pub world: Option<String>,
    /// Additional knowledge explicitly required by this depicted action, never inferred physics.
    #[serde(default)]
    pub requires_knowledge: Vec<WritingKnowledgeRequirement>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingKnowledgeRequirement {
    pub holder: String,
    pub claim: WritingClaim,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingMessage {
    /// Local label for an explicitly depicted communication, usable by attitudes in this delta.
    pub label: String,
    pub from: String,
    pub to: Vec<String>,
    /// Actual recipients, not merely intended recipients.
    pub received_by: Vec<String>,
    pub claim: WritingClaim,
    /// Explicit understanding of the claim, not a statement that it is true or known.
    #[serde(default)]
    pub understood_by: Vec<String>,
    #[serde(default)]
    pub channel: Option<String>,
    #[serde(default)]
    pub sent_tick: Option<String>,
    #[serde(default)]
    pub received_tick: Option<String>,
    #[serde(default)]
    pub distorted: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum WritingAttitudeKind {
    Believes,
    Suspects,
    Rejects,
    Remembers,
    Knows,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingAttitude {
    pub holder: String,
    pub claim: WritingClaim,
    pub attitude: WritingAttitudeKind,
    /// Local communication label or pinned opaque message handle. Knowledge requires explicit interpretation/receipt and authored policy.
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Explicit attitude lifetime; unspecified is an observation at the acquisition time.
    #[serde(default)]
    pub lifetime: FactLifetime,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingCorrection {
    /// Opaque authored fact handle returned by plain factual research. Generated event facts cannot be corrected directly.
    pub fact_handle: String,
    pub value: FactValue,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ReadContracts {
    pub universe: Selector,
    pub context_id: ContextId,
    /// Exact action names. Empty returns visible action names plus relevant knowledge/channel contracts.
    #[serde(default)]
    pub action_names: Vec<String>,
}
