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
    pub changes: Vec<ObjectChange>,
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
