//! Ordinary factual deltas; canonical record construction belongs to the engine.
use crate::request::Selector;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use universe_domain::ids::ContextId;

/// Ordinary JSON scalar, exact object-name reference, or explicit amount with an authored unit. No internal typed value wrappers; communication labels are not object identities.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum FactValue {
    Text(String),
    Boolean(bool),
    Number(serde_json::Number),
    Object {
        object: String,
    },
    /// Exact authored amount and named unit. No implicit conversion.
    Quantity {
        amount: serde_json::Number,
        unit: String,
    },
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
    /// Explicit author intent to introduce a new independent identity. A mention is not introduction. First resolve each name using universe_read_facts; an empty literal text search does not establish identity absence. False reuses existing visible canon.
    #[serde(default)]
    pub introduce: bool,
    /// Exact reusable definition name. On an existing object this refines classification without changing identity; it cannot replace an unrelated type.
    #[serde(default)]
    pub classification: Option<String>,
    #[serde(default)]
    pub facts: Vec<FactChange>,
}
/// Reusable classification and shared characteristics; never an independent instance or initial stock.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct DefinitionChange {
    pub name: String,
    #[serde(default)]
    pub introduce: bool,
    /// Exact parent definition name for a newly introduced subtype. Absence explicitly introduces a root.
    #[serde(default)]
    pub parent: Option<String>,
    /// universe, a retrieved world name, or unspecified. Applies to the new definition; shared facts retain their own scope/time.
    #[serde(default = "unspecified")]
    pub scope: String,
    #[serde(default)]
    pub shared_attributes: Vec<FactChange>,
    /// Starting-value definitions only; never current instance state. Publish before explicit instance initialization.
    #[serde(default)]
    pub initial_values: Vec<FactChange>,
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
    /// Explicit reusable definitions, subtype introductions and shared attributes. Independent stock belongs in changes, not here.
    #[serde(default)]
    #[schemars(length(max = 100))]
    pub definitions: Vec<DefinitionChange>,
    /// Explicit property declarations; never inferred single-value resources. Existing definitions cannot be silently changed.
    #[serde(default)]
    pub properties: Vec<WritingProperty>,
    /// Explicit unit declarations without inferred conversion/scale; private contract review required.
    #[serde(default)]
    pub units: Vec<WritingUnit>,
    #[serde(default)]
    pub actions: Vec<WritingAction>,
    /// Incremental ancestry/applicability revisions; omitted fields keep authored metadata. Requires private contract review.
    #[serde(default)]
    pub definition_corrections: Vec<WritingDefinitionCorrection>,
    /// Incremental supported action revisions; supplied lists explicitly replace those fields, omitted fields stay unchanged. Requires private contract review.
    #[serde(default)]
    pub action_corrections: Vec<WritingActionCorrection>,
    /// Finite supported policies. Separate private author contract review is required before publication.
    #[serde(default)]
    pub constraints: Vec<WritingConstraint>,
    /// Explicit context knowledge modes or communication chronology; private contract review required.
    #[serde(default)]
    pub knowledge_policies: Vec<WritingKnowledgePolicy>,
    /// Apply selected approved initial values once at an explicitly occurred instance start.
    #[serde(default)]
    pub initializations: Vec<WritingInitialization>,
    /// Incremental occurred-event corrections; omitted fields preserve canon. Effects remain engine-derived.
    #[serde(default)]
    pub event_corrections: Vec<WritingEventCorrection>,
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
    /// Neutral material questions only. Do not propose a guessed owner/identity as fact while asking who is intended.
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
    /// Exact instance or reusable definition names to research. A missing or ambiguous match remains explicit.
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
    /// Exact action name returned by universe_read_contracts. Discover the contract before submitting an event; a prose verb is not necessarily its action name. Effects and balances come from that contract.
    pub action: String,
    /// Reuse required/consequence role keys from the action contract exactly. Additional explicitly depicted narrative participants may have ordinary role labels. No declared role alone is not a missing requirement; values are exact object names.
    pub participants: std::collections::BTreeMap<String, String>,
    /// Explicit tick on the selected context's authored calendar; omit only when research pins an exact scene time.
    #[serde(default)]
    pub at_tick: Option<String>,
    #[serde(default)]
    pub world: Option<String>,
    /// Knowledge the author explicitly says this action relies on, even when the action contract has no knowledge requirement. Include its holder and exact claim so the dependency is checked at action time; omission does not check it. Never infer physics or automatic knowledge.
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
    /// Local label for an explicitly depicted communication, usable by attitudes in this delta. This label does not introduce a world object.
    pub label: String,
    pub from: String,
    /// Explicit intended recipients only; empty when no audience is established. Do not invent a recipient from the speaker.
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
    /// Actual distortion of the communication, not merely a deliberately false claim.
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
/// Attributed belief/knowledge belongs here, not in substitute boolean properties. Preserve an explicitly stated continuing lifetime; omitted lifetime establishes only an instant.
pub struct WritingAttitude {
    pub holder: String,
    pub claim: WritingClaim,
    pub attitude: WritingAttitudeKind,
    /// Required for communication-based knows: the matching local message label from this same delta, or a retrieved opaque message handle. Links actual receipt/interpretation, not a new object or assumed knowledge.
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

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum PlainPropertyType {
    Text,
    Boolean,
    Integer,
    Decimal,
    Object,
    Quantity,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum PlainPersistence {
    Unspecified,
    UntilChanged,
    ExplicitInterval,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingProperty {
    pub name: String,
    #[serde(default)]
    pub introduce: bool,
    pub value_type: PlainPropertyType,
    /// Required for quantity properties; exact authored unit name.
    #[serde(default)]
    pub unit: Option<String>,
    pub single_value: bool,
    pub persistence: PlainPersistence,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RoleValue {
    pub role: String,
    pub property: String,
    pub value: FactValue,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingEffectChange {
    Delta {
        amount: serde_json::Number,
        minimum: serde_json::Number,
        maximum: serde_json::Number,
        /// Required for quantity deltas; matches the property unit exactly. Integer properties omit it.
        #[serde(default)]
        unit: Option<String>,
    },
    Set {
        value: FactValue,
        #[serde(default)]
        negated: bool,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingEffectLifetime {
    UntilChanged,
    Ticks { count: serde_json::Number },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingEffect {
    pub role: String,
    pub property: String,
    pub change: WritingEffectChange,
    pub lifetime: WritingEffectLifetime,
    #[serde(default)]
    pub optional: bool,
    #[serde(default)]
    pub condition: Option<RoleValue>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingAction {
    pub name: String,
    #[serde(default)]
    pub introduce: bool,
    #[serde(default)]
    pub requirements: Vec<RoleValue>,
    #[serde(default)]
    pub effects: Vec<WritingEffect>,
    #[serde(default = "unspecified")]
    pub scope: String,
    #[serde(default)]
    pub at_tick: Option<String>,
    #[serde(default)]
    pub lifetime: FactLifetime,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingConstraint {
    ResourceAccounting {
        name: String,
        property: String,
        scope: String,
    },
    NoOpposingEvidence {
        name: String,
        object: String,
        property: String,
        scope: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingInstanceStart {
    /// Explicit author assertion of an occurred start, not first mention or classification.
    Occurred { event: WritingEvent },
    /// Opaque pinned occurred-event handle returned by factual research.
    Existing { handle: String },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingInitialization {
    pub instance: String,
    /// Selected approved initial-value handles from universe_read_facts. No value overrides.
    pub initial_value_handles: Vec<String>,
    pub start: WritingInstanceStart,
    /// universe or an authored world name; no inferred jurisdiction.
    pub scope: String,
    /// Explicit interval end or until_changed. An instant cannot initialize stock.
    pub lifetime: FactLifetime,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingEventCorrection {
    pub event_handle: String,
    pub reason: String,
    #[serde(default)]
    pub action: Option<String>,
    /// Explicit replacement participants; omitted preserves all, empty replaces with none.
    #[serde(default)]
    pub participants: Option<std::collections::BTreeMap<String, String>>,
    /// Changed coordinate on the event's original authored calendar.
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Replace the event's world with this exact authored world; omitted retains original worlds.
    #[serde(default)]
    pub world: Option<String>,
    /// Omitted retains all authored dependencies; empty explicitly clears direct Knows preconditions only.
    #[serde(default)]
    pub requires_knowledge: Option<Vec<WritingKnowledgeRequirement>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingUnit {
    pub name: String,
    #[serde(default)]
    pub introduce: bool,
    pub dimension: String,
    pub symbol: String,
}

/// Explicit ancestry change, distinct from refining an instance's classification.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingParent {
    Root,
    Definition { name: String },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingDefinitionCorrection {
    pub name: String,
    pub reason: String,
    #[serde(default)]
    pub parent: Option<WritingParent>,
    #[serde(default)]
    pub scope: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingActionCorrection {
    pub name: String,
    pub reason: String,
    #[serde(default)]
    pub requirements: Option<Vec<RoleValue>>,
    #[serde(default)]
    pub effects: Option<Vec<WritingEffect>>,
    #[serde(default)]
    pub scope: Option<String>,
    /// Time revision requires both explicit tick and lifetime; omission preserves existing validity.
    #[serde(default)]
    pub at_tick: Option<String>,
    #[serde(default)]
    pub lifetime: Option<FactLifetime>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingKnowledgePolicy {
    Knowledge {
        name: String,
        mode: universe_domain::records::KnowledgeMode,
    },
    Channel {
        name: String,
        channel: String,
        forward_only: bool,
        minimum_delay: Option<String>,
        maximum_delay: Option<String>,
    },
}
/// Private author-selected knowledge declaration, not an agent acquisition or an implied consequence.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuthorKnowledgeDeclaration {
    pub holder: String,
    pub claim: WritingClaim,
    pub at_tick: String,
    pub lifetime: FactLifetime,
    #[serde(default)]
    pub world: Option<String>,
}
