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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
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
    /// Explicit named worlds. Introduce only with author intent; existing visible names reuse their identity. No default world, location or entity association is inferred.
    #[serde(default)]
    pub worlds: Vec<WritingWorld>,
    /// Explicit dreams, accounts or embedded stories. Publish then open by name before adding local facts; parent structure never copies facts.
    #[serde(default)]
    pub story_contexts: Vec<WritingStoryContext>,
    /// Explicit named narrative works; publish before declaring an edition.
    #[serde(default)]
    pub narrative_works: Vec<WritingNarrativeWork>,
    /// Explicit editions of existing works; current binds the exact researched revision, unbound selects none.
    #[serde(default)]
    pub work_editions: Vec<WritingWorkEdition>,
    /// Explicit scenes of an existing edition. Reader order, narration context and depicted events are independent; depiction does not disclose.
    #[serde(default)]
    pub scenes: Vec<WritingScene>,
    /// Only factual deltas; do not restate the universe or unchanged facts.
    #[schemars(length(max = 100))]
    #[serde(default)]
    pub changes: Vec<ObjectChange>,
    /// Explicit contextual names for existing identities, not new objects or inferred knowledge. One new alias per entity per delta.
    #[serde(default)]
    pub aliases: Vec<WritingAlias>,
    /// Explicit reusable definitions, subtype introductions and shared attributes. Independent stock belongs in changes, not here.
    #[serde(default)]
    #[schemars(length(max = 100))]
    pub definitions: Vec<DefinitionChange>,
    /// Explicit property declarations; never inferred single-value resources. Existing definitions cannot be silently changed.
    #[serde(default)]
    pub properties: Vec<WritingProperty>,
    /// Explicit multiplicity/persistence corrections to existing named properties; omitted fields retain authored settings. Private contract review required; types and units cannot change.
    #[serde(default)]
    pub property_corrections: Vec<WritingPropertyCorrection>,
    /// Explicit unit declarations without inferred conversion/scale; private contract review required.
    #[serde(default)]
    pub units: Vec<WritingUnit>,
    #[serde(default)]
    pub actions: Vec<WritingAction>,
    /// Explicit possession-dependent abilities; private contract review required. Possession is the named single-valued object holder property on this item, never inferred from an ownership relation.
    #[serde(default)]
    pub item_powers: Vec<WritingItemPower>,
    /// Version-bound grant corrections/endings. Omitted fields retain authored values; targets cannot change. Private contract review required.
    #[serde(default)]
    pub item_power_corrections: Vec<WritingItemPowerCorrection>,
    #[serde(default)]
    pub policy_corrections: Vec<WritingPolicyCorrection>,
    #[serde(default)]
    pub attitude_corrections: Vec<WritingAttitudeCorrection>,
    #[serde(default)]
    pub message_corrections: Vec<WritingMessageCorrection>,
    #[serde(default)]
    pub interpretation_corrections: Vec<WritingInterpretationCorrection>,
    /// Incremental ancestry/applicability revisions; omitted fields keep authored metadata. Requires private contract review.
    #[serde(default)]
    pub definition_corrections: Vec<WritingDefinitionCorrection>,
    /// Incremental supported action revisions; supplied lists explicitly replace those fields, omitted fields stay unchanged. Requires private contract review.
    #[serde(default)]
    pub action_corrections: Vec<WritingActionCorrection>,
    /// Finite supported policies. Separate private author contract review is required before publication.
    #[serde(default)]
    pub constraints: Vec<WritingConstraint>,
    /// Explicit objective exhaustive object collections. Absence of a declaration stays open/unknown; private contract review required.
    #[serde(default)]
    pub exhaustive_sets: Vec<WritingExhaustiveSet>,
    /// Explicit finite named relation contracts; requires private contract review.
    #[serde(default)]
    pub relation_definitions: Vec<WritingRelationDefinition>,
    /// Authored cross-occurrence maxima, separate from local role multiplicity; private contract review required.
    #[serde(default)]
    pub relation_limits: Vec<WritingRelationLimit>,
    /// Incremental edits to existing role metadata; omitted roles/fields stay unchanged. Private contract review required.
    #[serde(default)]
    pub relation_corrections: Vec<WritingRelationCorrection>,
    /// Incremental existing maximum/grouping/scope/time edits; omitted fields stay unchanged. Private contract review required.
    #[serde(default)]
    pub relation_limit_corrections: Vec<WritingRelationLimitCorrection>,
    /// Objective named relationship deltas using actual declared roles and authored participants.
    #[serde(default)]
    pub relationships: Vec<WritingRelationship>,
    /// Correct only supplied participant roles on a pinned authored relationship; omitted roles and original scope/time remain unchanged.
    #[serde(default)]
    pub relationship_corrections: Vec<WritingRelationshipCorrection>,
    /// Explicit exclusive end of an authored interval relationship; distinct from historical participant correction.
    #[serde(default)]
    pub relationship_endings: Vec<WritingRelationshipEnding>,
    /// Explicit context knowledge modes or communication chronology; private contract review required.
    #[serde(default)]
    pub knowledge_policies: Vec<WritingKnowledgePolicy>,
    /// Explicit absence of knowledge for one holder and claim in the selected context/world/period; protected author contract review required. Missing knowledge remains unknown.
    #[serde(default)]
    pub knowledge_boundaries: Vec<WritingKnowledgeBoundary>,
    /// Apply selected approved initial values once at an explicitly occurred instance start.
    #[serde(default)]
    pub initializations: Vec<WritingInitialization>,
    /// Incremental occurred-event corrections; omitted fields preserve canon. Effects remain engine-derived.
    #[serde(default)]
    pub event_corrections: Vec<WritingEventCorrection>,
    /// Remove support for a pinned occurred-event version; does not assert non-occurrence.
    #[serde(default)]
    pub event_withdrawals: Vec<WritingEventWithdrawal>,
    #[serde(default)]
    pub events: Vec<WritingEvent>,
    #[serde(default)]
    pub messages: Vec<WritingMessage>,
    #[serde(default)]
    pub attitudes: Vec<WritingAttitude>,
    #[serde(default)]
    pub corrections: Vec<WritingCorrection>,
    /// End an authored fact interval at an explicit tick on its original calendar; preserve past support.
    #[serde(default)]
    pub fact_endings: Vec<WritingFactEnding>,
    /// Withdraw authored support without asserting its opposite; historical revisions remain intact.
    #[serde(default)]
    pub fact_withdrawals: Vec<WritingFactWithdrawal>,
    /// Material ambiguities identified in the writing. Any unresolved question holds the entire delta without creating a candidate.
    #[serde(default)]
    /// Neutral material questions only. Do not propose a guessed owner/identity as fact while asking who is intended.
    pub questions: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingWorld {
    pub name: String,
    #[serde(default)]
    pub introduce: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingStoryContext {
    pub name: String,
    #[serde(default)]
    pub introduce: bool,
    pub kind: StoryContextKind,
    /// Existing entity explicitly acting as narrator; required only for narrator contexts.
    #[serde(default)]
    pub narrator: Option<String>,
    pub parent: String,
    pub calendar: String,
    /// Exact fictional coordinate or Gregorian timestamp in the selected authored clock.
    pub story_time: String,
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum StoryContextKind {
    Narrator,
    Dream,
    Account,
    Embedded,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingNarrativeWork {
    pub name: String,
    pub introduce: bool,
    pub kind: universe_domain::records::WorkKind,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingWorkEdition {
    pub work: String,
    pub name: String,
    pub introduce: bool,
    pub binding: WritingEditionBinding,
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum WritingEditionBinding { Current, Unbound }
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingScene {
    pub name: String,
    pub introduce: bool,
    pub work: String,
    pub edition: String,
    pub narration_context: String,
    #[serde(default)]
    pub viewpoint: Option<String>,
    #[serde(default)]
    pub reader_order: Option<u64>,
    /// Opaque pinned occurred-event edit handles retrieved from ordinary factual research; never inferred from reader order/narration time.
    #[serde(default)]
    pub depicted_events: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingItemPower {
    pub item: String,
    pub holder_property: String,
    pub ability_property: String,
    pub value: FactValue,
    /// Explicit universe or authored world name.
    pub scope: String,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    /// Unspecified means the exact instant; a longer duration must be authored explicitly.
    #[serde(default)]
    pub lifetime: FactLifetime,
}
/// Correct this historical message; omitted fields remain authored. Later communication uses messages instead.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingMessageCorrection {
    pub message_edit_handle: String,
    pub reason: String,
    #[serde(default)]
    pub from: Option<String>,
    #[serde(default)]
    pub to: Option<Vec<String>>,
    #[serde(default)]
    pub received_by: Option<Vec<String>>,
    #[serde(default)]
    pub claims: Option<Vec<WritingClaim>>,
    #[serde(default)]
    pub channel: Option<String>,
    #[serde(default)]
    pub clear_channel: bool,
    #[serde(default)]
    pub sent_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_date: Option<String>,
    #[serde(default)]
    pub received_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub received_date: Option<String>,
    #[serde(default)]
    pub clear_receipt: bool,
    #[serde(default)]
    pub distorted: Option<bool>,
}
/// Explicit justified-receipt interpretation correction. No knowledge promotion or automatic acquisition.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingInterpretationCorrection {
    pub attitude_handle: String,
    pub reason: String,
    #[serde(default)]
    pub interpretation: Option<WritingClaim>,
    #[serde(default)]
    pub clear_interpretation: bool,
}
/// Correct the recorded historical attitude, not a later change of mind. Knows allows duration only.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingAttitudeCorrection {
    pub attitude_handle: String,
    pub reason: String,
    #[serde(default)]
    pub value: Option<FactValue>,
    /// Supplied certainty replaces it; clear_certainty explicitly removes it. Non-Knows only.
    #[serde(default)]
    pub certainty: Option<String>,
    #[serde(default)]
    pub clear_certainty: bool,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: Option<FactLifetime>,
    /// Explicit ending only shortens an existing authored interval.
    #[serde(default)]
    pub end_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_date: Option<String>,
}

/// Version-bound protected policy changes; omitted settings stay authored.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingPolicyCorrection {
    pub policy_handle: String,
    pub reason: String,
    #[serde(default)]
    pub mode: Option<universe_domain::records::KnowledgeMode>,
    #[serde(default)]
    pub forward_only: Option<bool>,
    /// Supplied bound replaces it; clear_minimum_delay explicitly removes it.
    #[serde(default)]
    pub minimum_delay: Option<String>,
    #[serde(default)]
    pub maximum_delay: Option<String>,
    #[serde(default)]
    pub clear_minimum_delay: bool,
    #[serde(default)]
    pub clear_maximum_delay: bool,
    /// Resource/conflict policies and explicit knowledge boundaries support scope/time changes; boundary holder/claim/context stay unchanged.
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: Option<FactLifetime>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingItemPowerCorrection {
    pub grant_handle: String,
    pub reason: String,
    #[serde(default)]
    pub value: Option<FactValue>,
    #[serde(default)]
    pub scope: Option<String>,
    /// Explicit new start in the original authored calendar; omitted start stays unchanged.
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: Option<FactLifetime>,
    /// Explicitly shorten an existing interval; separate from historical validity correction.
    #[serde(default)]
    pub end_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_date: Option<String>,
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
    /// Explicit authored world name; absence does not select or infer a world.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "crate::request::present"
    )]
    #[schemars(with = "crate::request::Selector")]
    pub world: Option<String>,
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
        #[serde(default)]
        end_tick: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        end_date: Option<String>,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingKnowledgeBoundary {
    pub name: String,
    pub holder: String,
    pub claim: WritingClaim,
    /// Explicit universe or named world, never inferred.
    pub scope: String,
    #[serde(default)]
    pub at_tick: Option<String>,
    #[serde(default)]
    pub at_date: Option<String>,
    pub lifetime: FactLifetime,
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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_date: Option<String>,
    #[serde(default)]
    pub received_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub received_date: Option<String>,
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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    /// Explicit attitude lifetime; unspecified is an observation at the acquisition time.
    #[serde(default)]
    pub lifetime: FactLifetime,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingCorrection {
    /// Opaque authored assertion-version handle returned by plain factual research. Retrieve the current handle after a correction; generated event facts cannot be corrected directly.
    pub fact_handle: String,
    pub value: FactValue,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingFactEnding {
    /// Current opaque authored assertion-version handle returned by universe_read_facts.
    pub fact_handle: String,
    #[serde(default)]
    pub end_tick: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_date: Option<String>,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingFactWithdrawal {
    /// Current opaque authored assertion-version handle returned by universe_read_facts.
    pub fact_handle: String,
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
pub struct WritingPropertyCorrection {
    pub name: String,
    #[serde(default)]
    pub single_value: Option<bool>,
    #[serde(default)]
    pub persistence: Option<PlainPersistence>,
    pub reason: String,
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
        /// Required for quantity deltas; matches the property unit exactly. Unitless integer/decimal properties omit it.
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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
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
    /// Selected approved assertion-version handles from universe_read_facts initial-value candidates. No value overrides.
    pub initial_value_handles: Vec<String>,
    pub start: WritingInstanceStart,
    /// universe or an authored world name; no inferred jurisdiction.
    pub scope: String,
    /// Explicit interval end or until_changed. An instant cannot initialize stock.
    pub lifetime: FactLifetime,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingEventWithdrawal {
    pub event_handle: String,
    pub reason: String,
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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
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
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
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
    #[serde(default)]
    pub at_tick: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    pub lifetime: FactLifetime,
    #[serde(default)]
    pub world: Option<String>,
}

/// An authored exhaustive collection, never inferred from listed facts.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingExhaustiveSet {
    pub subject: String,
    pub property: String,
    /// Exact existing object names. Required; [] explicitly declares an empty collection.
    pub members: Vec<String>,
    /// Explicit "universe" or authored world name. Unknown scope requires clarification.
    pub scope: String,
    /// Explicit tick on the selected context's authored calendar, or use its pinned scene time.
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: FactLifetime,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationDefinition {
    pub name: String,
    pub introduce: bool,
    pub roles: Vec<WritingRelationRole>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationRole {
    pub name: String,
    /// Only local multiplicity, never a cross-occurrence maximum.
    pub multiple: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WritingRelationGrouping {
    Subject,
    Role { role: String },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationLimit {
    pub name: String,
    pub relation: String,
    pub grouping: WritingRelationGrouping,
    pub counted_role: String,
    pub maximum: u32,
    pub scope: String,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: FactLifetime,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationship {
    pub relation: String,
    pub subject: String,
    /// Actual authored participant names by declared role; preserves list order for ordered roles.
    pub participants: std::collections::BTreeMap<String, Vec<String>>,
    pub scope: String,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: FactLifetime,
    #[serde(default)]
    pub negated: bool,
    #[serde(default = "objective")]
    #[schemars(with = "StatementIntent")]
    pub statement: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationshipCorrection {
    pub relationship_handle: String,
    /// Changed roles only; each supplied list replaces that role. [] explicitly clears it; omitted roles stay unchanged.
    pub participants: std::collections::BTreeMap<String, Vec<String>>,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationshipEnding {
    pub relationship_handle: String,
    /// Exclusive end on the relationship's original authored interval calendar. No clock conversion.
    #[serde(default)]
    pub end_tick: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_date: Option<String>,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationCorrection {
    pub name: String,
    pub roles: Vec<WritingRelationRoleCorrection>,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationRoleCorrection {
    pub name: String,
    #[serde(default)]
    pub multiple: Option<bool>,
    #[serde(default)]
    pub ordered: Option<bool>,
    /// Supplied list explicitly replaces this role's type restrictions; [] removes them. Omission preserves them.
    #[serde(default)]
    pub participant_types: Option<Vec<String>>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingRelationLimitCorrection {
    pub name: String,
    #[serde(default)]
    pub maximum: Option<u32>,
    #[serde(default)]
    pub grouping: Option<WritingRelationGrouping>,
    #[serde(default)]
    pub counted_role: Option<String>,
    #[serde(default)]
    pub scope: Option<String>,
    /// Time edit requires both explicit tick and lifetime; omission preserves existing validity.
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    #[serde(default)]
    pub lifetime: Option<FactLifetime>,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WritingAlias {
    pub object: String,
    pub text: String,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub community: Option<String>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub at_tick: Option<String>,
    /// Date in the selected authored calendar; an explicit tick must agree.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_date: Option<String>,
    /// Omission leaves validity unspecified; explicit lifetime/tick uses the selected authored calendar.
    #[serde(default)]
    pub lifetime: Option<FactLifetime>,
}
