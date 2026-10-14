//! Canonical record families (spec §5.1, §27).
//!
//! Every canonical identity has `universe_id`; there is no mandatory single
//! `world_id` foreign key on records (spec §5.7). World association,
//! location, origin, and applicability are separate typed relationships.

pub use crate::appearance::*;
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::canonical::{payload_digest, Canonical, CanonicalValue, PayloadDigest};
use crate::error::{DomainError, DomainResult};
use crate::expr::Expr;
use crate::ids::{
    CalendarId, ContinuityId, EntityIdAlias, PrincipalId, RecordId, RecordVersionId, RevisionId,
    UnitId, UniverseId, ValueDefinitionId, WorldId,
};
use crate::scope::{
    Applicability, EvidenceBasis, PersistenceSemantics, Polarity, Precision, Scope, Validity,
};
use crate::temporal::TemporalExpression;
use crate::value::{RecordRef, Value, VersionRef};

// ---------------------------------------------------------------------------
// Record kinds
// ---------------------------------------------------------------------------

/// The kind of a canonical record. Identity and kind are immutable: a kind
/// change requires a reviewed migration or a new identity (spec §27.1).
#[derive(
    Debug,
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    PartialOrd,
    Ord,
    Serialize,
    Deserialize,
    schemars::JsonSchema,
)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum RecordKind {
    Entity,
    Appearance,
    ImageAsset,
    World,
    Realm,
    Work,
    WorkVersion,
    SceneRef,
    PassageRef,
    Saga,
    EntityType,
    Property,
    Relation,
    Unit,
    Calendar,
    ValueDefinition,
    DomainPack,
    Proposition,
    Assertion,
    RepresentedContext,
    Completeness,
    Boundary,
    Rule,
    Exception,
    Event,
    ItemPower,
    ActionDefinition,
    EpistemicAttitude,
    Observation,
    Communication,
    Memory,
    Secret,
    Goal,
    Commitment,
    Source,
    SourceVersion,
    Anchor,
    IssueDecision,
}

impl RecordKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            RecordKind::Entity => "entity",
            RecordKind::Appearance => "appearance",
            RecordKind::ImageAsset => "image_asset",
            RecordKind::World => "world",
            RecordKind::Realm => "realm",
            RecordKind::Work => "work",
            RecordKind::WorkVersion => "work_version",
            RecordKind::SceneRef => "scene_ref",
            RecordKind::PassageRef => "passage_ref",
            RecordKind::Saga => "saga",
            RecordKind::EntityType => "entity_type",
            RecordKind::Property => "property",
            RecordKind::Relation => "relation",
            RecordKind::Unit => "unit",
            RecordKind::Calendar => "calendar",
            RecordKind::ValueDefinition => "value_definition",
            RecordKind::DomainPack => "domain_pack",
            RecordKind::Proposition => "proposition",
            RecordKind::Assertion => "assertion",
            RecordKind::RepresentedContext => "represented_context",
            RecordKind::Completeness => "completeness",
            RecordKind::Boundary => "boundary",
            RecordKind::Rule => "rule",
            RecordKind::Exception => "exception",
            RecordKind::Event => "event",
            RecordKind::ItemPower => "item_power",
            RecordKind::ActionDefinition => "action_definition",
            RecordKind::EpistemicAttitude => "epistemic_attitude",
            RecordKind::Observation => "observation",
            RecordKind::Communication => "communication",
            RecordKind::Memory => "memory",
            RecordKind::Secret => "secret",
            RecordKind::Goal => "goal",
            RecordKind::Commitment => "commitment",
            RecordKind::Source => "source",
            RecordKind::SourceVersion => "source_version",
            RecordKind::Anchor => "anchor",
            RecordKind::IssueDecision => "issue_decision",
        }
    }

    pub fn parse(s: &str) -> DomainResult<Self> {
        Ok(match s {
            "entity" => Self::Entity,
            "appearance" => Self::Appearance,
            "image_asset" => Self::ImageAsset,
            "world" => Self::World,
            "realm" => Self::Realm,
            "work" => Self::Work,
            "work_version" => Self::WorkVersion,
            "scene_ref" => Self::SceneRef,
            "passage_ref" => Self::PassageRef,
            "saga" => Self::Saga,
            "entity_type" => Self::EntityType,
            "property" => Self::Property,
            "relation" => Self::Relation,
            "unit" => Self::Unit,
            "calendar" => Self::Calendar,
            "value_definition" => Self::ValueDefinition,
            "domain_pack" => Self::DomainPack,
            "proposition" => Self::Proposition,
            "assertion" => Self::Assertion,
            "represented_context" => Self::RepresentedContext,
            "completeness" => Self::Completeness,
            "boundary" => Self::Boundary,
            "rule" => Self::Rule,
            "exception" => Self::Exception,
            "event" => Self::Event,
            "item_power" => Self::ItemPower,
            "action_definition" => Self::ActionDefinition,
            "epistemic_attitude" => Self::EpistemicAttitude,
            "observation" => Self::Observation,
            "communication" => Self::Communication,
            "memory" => Self::Memory,
            "secret" => Self::Secret,
            "goal" => Self::Goal,
            "commitment" => Self::Commitment,
            "source" => Self::Source,
            "source_version" => Self::SourceVersion,
            "anchor" => Self::Anchor,
            "issue_decision" => Self::IssueDecision,
            other => {
                return Err(DomainError::InvalidValue {
                    reason: format!("unknown record kind `{other}`"),
                })
            }
        })
    }

    /// All kinds, in canonical order.
    pub const fn all() -> &'static [RecordKind] {
        &[
            RecordKind::Entity,
            RecordKind::Appearance,
            RecordKind::ImageAsset,
            RecordKind::World,
            RecordKind::Realm,
            RecordKind::Work,
            RecordKind::WorkVersion,
            RecordKind::SceneRef,
            RecordKind::PassageRef,
            RecordKind::Saga,
            RecordKind::EntityType,
            RecordKind::Property,
            RecordKind::Relation,
            RecordKind::Unit,
            RecordKind::Calendar,
            RecordKind::ValueDefinition,
            RecordKind::DomainPack,
            RecordKind::Proposition,
            RecordKind::Assertion,
            RecordKind::RepresentedContext,
            RecordKind::Completeness,
            RecordKind::Boundary,
            RecordKind::Rule,
            RecordKind::Exception,
            RecordKind::Event,
            RecordKind::ItemPower,
            RecordKind::ActionDefinition,
            RecordKind::EpistemicAttitude,
            RecordKind::Observation,
            RecordKind::Communication,
            RecordKind::Memory,
            RecordKind::Secret,
            RecordKind::Goal,
            RecordKind::Commitment,
            RecordKind::Source,
            RecordKind::SourceVersion,
            RecordKind::Anchor,
            RecordKind::IssueDecision,
        ]
    }
}

// ---------------------------------------------------------------------------
// Identity and version
// ---------------------------------------------------------------------------

/// The identity of a canonical record (spec §27.1 contract table:
/// `universe_id`, `record_id`, `record_kind`). Identity and kind are
/// immutable.
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(deny_unknown_fields)]
pub struct RecordIdentity {
    pub universe_id: UniverseId,
    pub record_id: RecordId,
    pub record_kind: RecordKind,
}

impl RecordIdentity {
    pub fn new(universe_id: UniverseId, record_id: RecordId, record_kind: RecordKind) -> Self {
        Self {
            universe_id,
            record_id,
            record_kind,
        }
    }
}

impl Canonical for RecordIdentity {
    fn to_canonical(&self) -> CanonicalValue {
        crate::canonical::canonical_serde(self)
    }
}

/// An immutable typed record version (spec §27.1 contract table:
/// `record_version_id`, identity, typed
/// `payload`, `payload_digest`).
///
/// Content is immutable; actor/time/decision attribution is linked through
/// the editorial commit that admitted it (spec §27.1).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RecordVersion {
    pub record_version_id: RecordVersionId,
    pub identity: RecordIdentity,
    pub payload: Payload,
    /// SHA-256 over the canonical payload and its kind discriminator
    /// (spec §27.8).
    pub payload_digest: PayloadDigest,
}

impl RecordVersion {
    /// Build a version, computing the canonical digest (spec §27.8).
    pub fn build(
        record_version_id: RecordVersionId,
        identity: RecordIdentity,
        payload: Payload,
    ) -> DomainResult<Self> {
        if payload.kind() != identity.record_kind {
            return Err(DomainError::WrongRecordKind {
                what: identity.record_id.to_owned(),
                kind: identity.record_kind.as_str().to_string(),
                actual: payload.kind().as_str().to_string(),
            });
        }
        let payload_digest = payload_digest(&identity.record_kind, &payload);
        Ok(Self {
            record_version_id,
            identity,
            payload,
            payload_digest,
        })
    }

    /// Verify the stored digest matches the payload (integrity).
    pub fn verify_digest(&self) -> bool {
        payload_digest(&self.identity.record_kind, &self.payload) == self.payload_digest
    }
}

// ---------------------------------------------------------------------------
// Frame records
// ---------------------------------------------------------------------------

/// A named world record within a universe (spec §5.6, §36.1).
///
/// A world can represent a planet, inhabited domain, simulation, or another
/// authored setting type. Realms and planets do not automatically become
/// identical records.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct World {
    /// Administrative selector label: the author-facing name (exact display
    /// spelling preserved; §36.2).
    pub selector: String,
    /// Retained aliases (versioned; renames keep the old label — §36.3).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub aliases: Vec<String>,
    /// Authored setting type label ("planet", "simulation", ...).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub setting_type: Option<String>,
    /// Display labels and authored metadata (Unicode; §1.4).
    #[serde(default)]
    pub labels: BTreeMap<String, String>,
    #[serde(default)]
    pub metadata: BTreeMap<String, Value>,
}

/// A realm: an authored physical/metaphysical domain (spec §36.1).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Realm {
    pub labels: BTreeMap<String, String>,
    pub metadata: BTreeMap<String, Value>,
}

// ---------------------------------------------------------------------------
// Definitions (versioned data — spec §5.5, §27.2)
// ---------------------------------------------------------------------------

/// A named definition with one nullable parent and explicit resolution.
/// An ambiguous parent blocks executable ancestry; it is never chosen silently.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EntityType {
    /// Reserved ("starter:...") or author namespace.
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    pub name: String,
    pub parent: Option<RecordId>,
    pub parent_resolution: ParentResolution,
    pub applicability: Applicability,
    /// Whether subtype traversal may be used by executable rules.
    pub classification_executable: bool,
}

/// Parent knowledge is distinct from the stable identity of a definition.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ParentResolution {
    Root,
    Resolved,
    Ambiguous,
}

/// Classification knowledge does not create a new instance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ClassificationResolution {
    Unclassified,
    Resolved,
    Ambiguous,
}

/// Shared and initial-value definitions do not describe a continuing balance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AttributeMode {
    Instance,
    Shared,
    InitialValue,
}

/// The typed shape of a property value (spec §27.2).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum ValueShape {
    Text,
    Boolean,
    Integer,
    Decimal,
    Rational,
    Quantity {
        unit: UnitId,
    },
    Range {
        unit: Option<UnitId>,
    },
    EntityRef {
        subject_types: Vec<RecordId>,
    },
    Temporal,
    Spatial,
    Enum {
        definition: ValueDefinitionId,
    },
    Sequence {
        item: Box<ValueShape>,
    },
    Structured {
        definition: ValueDefinitionId,
    },
    /// No declared shape (descriptive).
    Unspecified,
}

impl Canonical for ValueShape {
    fn to_canonical(&self) -> CanonicalValue {
        use ValueShape::*;
        match self {
            Text => CanonicalValue::Str("text".into()),
            Boolean => CanonicalValue::Str("boolean".into()),
            Integer => CanonicalValue::Str("integer".into()),
            Decimal => CanonicalValue::Str("decimal".into()),
            Rational => CanonicalValue::Str("rational".into()),
            Quantity { unit } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("quantity".into())),
                ("unit".into(), CanonicalValue::Str(unit.to_owned())),
            ]),
            Range { unit } => {
                let mut f = vec![("kind".into(), CanonicalValue::Str("range".into()))];
                if let Some(u) = unit {
                    f.push(("unit".into(), CanonicalValue::Str(u.to_owned())));
                }
                CanonicalValue::obj(f)
            }
            EntityRef { subject_types } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("entity_ref".into())),
                (
                    "subjectTypes".into(),
                    CanonicalValue::arr(
                        subject_types
                            .iter()
                            .map(|t| CanonicalValue::Str(t.to_owned()))
                            .collect(),
                    ),
                ),
            ]),
            Temporal => CanonicalValue::Str("temporal".into()),
            Spatial => CanonicalValue::Str("spatial".into()),
            Enum { definition } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("enum".into())),
                (
                    "definition".into(),
                    CanonicalValue::Str(definition.to_owned()),
                ),
            ]),
            Sequence { item } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("sequence".into())),
                ("item".into(), item.to_canonical()),
            ]),
            Structured { definition } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("structured".into())),
                (
                    "definition".into(),
                    CanonicalValue::Str(definition.to_owned()),
                ),
            ]),
            Unspecified => CanonicalValue::Str("unspecified".into()),
        }
    }
}

/// A property definition (spec §27.2).
///
/// Inverse, symmetric, transitive, or exclusive behavior is opt-in; no
/// implicit behavior from the display label.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct PropertyDef {
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    /// Allowed subject type ids.
    #[serde(default)]
    pub subject_types: Vec<RecordId>,
    pub value: ValueShape,
    pub multiplicity: Multiplicity,
    pub unit_dimension: Option<String>,
    pub persistence: PersistenceSemantics,
    /// Exclusive: at most one value holder per subject at a time
    /// (opt-in — spec §5.5).
    pub exclusive: bool,
    pub inverse: Option<String>,
    pub symmetric: bool,
    pub transitive: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum Multiplicity {
    Single,
    Multiple,
}

impl Canonical for Multiplicity {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            Multiplicity::Single => "single".into(),
            Multiplicity::Multiple => "multiple".into(),
        })
    }
}

/// A named role in a relation (spec §27.2): supports more than two roles
/// and more than one participant per role where declared.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct RoleDef {
    pub name: String,
    #[serde(default)]
    pub participant_types: Vec<RecordId>,
    pub multiplicity: Multiplicity,
    pub ordered: bool,
}

/// A relation definition: n-ary participant assignments (spec §5.1).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct RelationDef {
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    pub roles: Vec<RoleDef>,
}

/// A unit definition (spec §27.2): conversion must be defined and
/// compatible; unknown exchange rates remain unresolved.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct UnitDef {
    pub namespace: String,
    pub key: String,
    pub dimension: String,
    pub symbol: String,
    pub labels: BTreeMap<String, String>,
    /// Exact scale to a declared base unit.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scale_to_base: Option<crate::value::Value>,
    pub base: Option<UnitId>,
    pub validity: Validity,
}

/// A calendar / temporal reference system (spec §27.2).
///
/// A label-only calendar is storable but cannot support invented
/// arithmetic (S30): `conversions` empty → unsupported capability.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CalendarDef {
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    /// Epoch, if defined (an authored origin).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub epoch: Option<String>,
    /// Unit structure description (free authored structure).
    pub unit_structure: BTreeMap<String, String>,
    /// Authored conversion relationships to other calendars.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub conversions: Vec<CalendarConversion>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CalendarConversion {
    pub target: CalendarId,
    /// Authored conversion expression; empty/unsupported → `unsupported`
    /// capability, never invented arithmetic.
    pub expression: Option<String>,
    pub valid: bool,
}

/// A structured value definition (spec §27.2): no executable field
/// expressions, arbitrary SQL, or unbounded recursive schemas.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ValueDef {
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    pub fields: Vec<ValueDefField>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ValueDefField {
    pub name: String,
    pub shape: ValueShape,
    pub required: bool,
    /// Explicitly permitted unknown alternative (optional data has
    /// explicit states — spec §5.3).
    pub allows_unknown: bool,
}

/// A domain pack: data, not code (spec §16, §27.2).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct DomainPack {
    pub key: String,
    pub version: String,
    /// Dependency versions (other packs).
    pub dependencies: BTreeMap<String, String>,
    /// Evaluator capabilities this pack declares (spec §27.10): a newly
    /// installed pack cannot declare the application capable of evaluating
    /// code that has not been implemented — the registry cross-checks.
    pub capabilities: Vec<String>,
    /// Record ids contributed by this pack.
    pub records: Vec<RecordId>,
}

// ---------------------------------------------------------------------------
// Propositions, assertions, contexts
// ---------------------------------------------------------------------------

/// Quantification over a proposition (spec §27.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum Quantification {
    /// "The gate is in the ruins" — a particular claim.
    Particular,
    /// "All X have Y".
    Universal,
    /// "Some X has Y".
    Exists,
}

impl Canonical for Quantification {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            Quantification::Particular => "particular".into(),
            Quantification::Universal => "universal".into(),
            Quantification::Exists => "exists".into(),
        })
    }
}

/// A claimable statement (spec §5.2, §27.3).
///
/// A proposition describes something that *may be* asserted; its existence
/// does not assert its truth.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Proposition {
    /// A property or relation definition record.
    pub predicate: RecordRef,
    /// The entity claimed about.
    pub subject: RecordRef,
    /// Named role bindings for n-ary relations.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub roles: Vec<PropositionRole>,
    /// The value for property-shaped propositions.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<Value>,
    pub quantification: Quantification,
    /// The represented context this proposition lives in (objective
    /// reality, a character's beliefs, a source narrative, ...).
    pub context: RecordRef,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct PropositionRole {
    pub role: String,
    pub participant: RecordRef,
}

impl Eq for Proposition {}
impl std::hash::Hash for Proposition {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

/// Support or refutation of a proposition in a stated context, time, and
/// scope (spec §5.2, §27.3).
///
/// Approval of the assertion does not erase its context, evidence
/// limitations, or opposing assertions.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Assertion {
    pub attribute_mode: AttributeMode,
    pub proposition: RecordRef,
    pub polarity: Polarity,
    pub scope: Scope,
    pub validity: Validity,
    pub persistence: PersistenceSemantics,
    pub precision: Precision,
    /// Alternatives for `one_of` precision (explicit, not a range guess).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub alternatives: Vec<Value>,
    pub basis: EvidenceBasis,
    /// Set when this assertion was generated by an admitted event effect
    /// (spec §27.5: the compiled assertion is the canonical state
    /// representation; the linkage is structurally checked).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub established_by: Option<EventEffectRef>,
}

impl Eq for Assertion {}
impl std::hash::Hash for Assertion {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

/// The linkage from an event effect slot to the assertion it established
/// (spec §27.5).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EventEffectRef {
    pub event: RecordRef,
    pub slot: String,
}

/// A represented context (spec §27.3): a dream, myth, quotation, or
/// embedded story is not automatically objective reality.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum RepresentedContextKind {
    /// The objective reality of this universe.
    Objective,
    /// A character's represented beliefs/knowledge.
    Character { holder: RecordRef },
    /// A source's depicted narrative.
    Source { source: RecordRef },
    /// A narrator's account.
    Narrator { narrator: RecordRef },
    /// Another authored context (dream, myth, embedded story).
    Authored { label: String },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct RepresentedContext {
    pub universe: UniverseId,
    pub kind: RepresentedContextKind,
    /// Parent context for nested contexts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent: Option<RecordRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chronology: Option<crate::chronology::Chronology>,
    pub labels: BTreeMap<String, String>,
}

/// A scoped completeness declaration (spec §8.2, §27.3).
///
/// A complete empty sibling set establishes no siblings in its scope; an
/// empty search result does not. A list complete for one room does not
/// cover an entire building. Completeness for an observer's known set is
/// not completeness for objective reality.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CompletenessDecl {
    pub subject: RecordRef,
    /// The collection predicate whose membership is declared.
    pub predicate: String,
    /// Exact complete membership (empty = explicitly empty set).
    pub members: Vec<RecordRef>,
    /// Completeness of objective reality vs. an observer's known set.
    pub completeness: CompletenessKind,
    pub validity: Validity,
    pub scope: Scope,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum CompletenessKind {
    ObjectiveReality,
    ObserverKnown { observer: EntityIdAlias },
}

impl Canonical for CompletenessKind {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            CompletenessKind::ObjectiveReality => CanonicalValue::Str("objective".into()),
            CompletenessKind::ObserverKnown { observer } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("observer_known".into())),
                (
                    "observer".into(),
                    CanonicalValue::Str(observer.0.to_owned()),
                ),
            ]),
        }
    }
}

// ---------------------------------------------------------------------------
// Rules, boundaries, exceptions
// ---------------------------------------------------------------------------

/// Rule kinds with distinct semantics and commit policies (spec §9.3).
///
/// Severity, commit-blocking policy, and semantic type are distinct.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum RuleKind {
    /// Invalid record shape: always blocks commit; no author waiver.
    StructuralInvariant,
    /// Cannot occur under established rules: blocks delegated commit
    /// unless a valid scoped exception or authorized revision resolves it.
    PhysicalConstraint,
    /// A specified action requires defined prerequisites.
    OperationalRequirement,
    /// Actors may violate it: a normative departure, not physical
    /// impossibility.
    Law,
    /// Typical rather than universal behavior: advisory only.
    BehavioralTendency,
    /// Controls permitted additions/revisions: enforced by scope and
    /// authorization.
    AuthorialRestriction,
    /// Stored but not executable by this evaluator.
    Descriptive,
}

impl RuleKind {
    /// The default commit effect for this kind (spec §9.3).
    pub fn default_commit_policy(&self) -> CommitPolicy {
        match self {
            RuleKind::StructuralInvariant => CommitPolicy::AlwaysBlock,
            RuleKind::PhysicalConstraint => CommitPolicy::BlockUnlessException,
            RuleKind::OperationalRequirement => CommitPolicy::RecordFinding,
            RuleKind::Law => CommitPolicy::RecordFinding,
            RuleKind::BehavioralTendency => CommitPolicy::Advisory,
            RuleKind::AuthorialRestriction => CommitPolicy::ScopeEnforced,
            RuleKind::Descriptive => CommitPolicy::ReportUnsupported,
        }
    }
}

/// How a rule's finding affects a commit (spec §9.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum CommitPolicy {
    /// Always blocks (structural integrity; no author waiver).
    AlwaysBlock,
    /// Blocks delegated commit unless a valid scoped exception or an
    /// authorized canon revision resolves it.
    BlockUnlessException,
    /// Records a finding; commit proceeds (law/normative).
    RecordFinding,
    /// Advisory: surfaced, never blocks.
    Advisory,
    /// Enforced through scope/authorization rather than evaluation.
    ScopeEnforced,
    /// Reported as unsupported coverage (descriptive/unevaluable).
    ReportUnsupported,
}

impl Canonical for RuleKind {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            RuleKind::StructuralInvariant => "structural_invariant".into(),
            RuleKind::PhysicalConstraint => "physical_constraint".into(),
            RuleKind::OperationalRequirement => "operational_requirement".into(),
            RuleKind::Law => "law".into(),
            RuleKind::BehavioralTendency => "behavioral_tendency".into(),
            RuleKind::AuthorialRestriction => "authorial_restriction".into(),
            RuleKind::Descriptive => "descriptive".into(),
        })
    }
}

impl Canonical for CommitPolicy {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            CommitPolicy::AlwaysBlock => "always_block".into(),
            CommitPolicy::BlockUnlessException => "block_unless_exception".into(),
            CommitPolicy::RecordFinding => "record_finding".into(),
            CommitPolicy::Advisory => "advisory".into(),
            CommitPolicy::ScopeEnforced => "scope_enforced".into(),
            CommitPolicy::ReportUnsupported => "report_unsupported".into(),
        })
    }
}

/// Authored channel chronology on exact integer ticks of the same clock.
/// Bounds are inclusive signed receipt-minus-send delays; false forward_only
/// explicitly permits negative delay. No delivery or clock conversion is inferred.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ChannelChronology {
    pub channel: String,
    pub forward_only: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_delay: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maximum_delay: Option<String>,
}

/// Authored maximum across relation instances, independent of local multiplicity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct RelationCardinality {
    pub relation: RecordRef,
    pub grouping: CardinalityKey,
    pub counted_role: String,
    pub maximum: u32,
    pub scope: Scope,
    pub validity: Validity,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum CardinalityKey {
    Subject,
    Role { role: String },
}

/// Explicit absence of knowledge, never a refutation of the claimed proposition.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct KnowledgeBoundary {
    pub holder: RecordRef,
    pub proposition: RecordRef,
    pub context: RecordRef,
}

/// Authored review choices, never a service assertion that evidence is true.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum EvidenceReviewMethod {
    HumanReview,
    ExternalModelReview,
}

/// Exact source-category packs. No listed review method means no review duty.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct RequiredEvidence {
    pub source_categories: Vec<VersionRef>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub review_methods: Vec<EvidenceReviewMethod>,
}

/// A typed, declarative rule (spec §9.3, §27.2).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Rule {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub required_evidence: Option<RequiredEvidence>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub knowledge_boundary: Option<KnowledgeBoundary>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub relation_cardinality: Option<RelationCardinality>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub knowledge_policy: Option<KnowledgePolicy>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_chronology: Option<ChannelChronology>,
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    pub kind: RuleKind,
    pub commit_policy: CommitPolicy,
    /// Where the rule applies (universe-wide / worlds / conditional /
    /// unspecified).
    pub applicability: Applicability,
    /// Subject types the rule constrains (empty = any).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub subject_types: Vec<RecordId>,
    /// The predicates this rule concerns (for applicability enumeration;
    /// spec §9.5: the evaluator enumerates applicable rules from
    /// structured indexes, never only search matches).
    pub target_predicates: Vec<String>,
    pub expression: Expr,
    /// Evaluator capabilities required; an unevaluable rule lists
    /// unsupported ones (spec §27.10).
    pub capabilities: Vec<String>,
    /// Whether the evaluator can execute this rule (set at compile time).
    pub executable: bool,
    /// Temporal validity of the rule itself (S35: jurisdictional scoping).
    pub validity: Validity,
}

impl Eq for Rule {}
impl std::hash::Hash for Rule {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

/// Supported creative boundary modes (spec §8.4).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum BoundaryMode {
    /// The area is fixed: new material is not allowed.
    Fixed,
    /// Open, but within constraints (the constraints are evaluated).
    OpenWithConstraints,
    /// The default for undefined areas: proposals required, no automatic
    /// permission to invent (spec §8.4).
    ProposalRequired,
    /// Reserved for the author's own discretion.
    AuthorReserved,
    /// Intentionally unresolved (I20): usable data without an invented
    /// answer.
    IntentionallyUnresolved,
    /// New material is prohibited.
    Prohibited,
}

/// An authorial creative boundary over a named area (spec §8.4).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CreativeBoundary {
    pub key: String,
    /// The area: a record or a predicate/subject pattern.
    pub area: BoundaryArea,
    pub mode: BoundaryMode,
    /// Constraints that apply when the mode allows material.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub constraints: Vec<Expr>,
    pub validity: Validity,
    pub scope: Scope,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum BoundaryArea {
    Record(RecordRef),
    Predicate {
        predicate: String,
        subject: Option<RecordRef>,
    },
    /// A whole category (e.g. all entities of a type).
    Category {
        entity_type: RecordId,
    },
}

/// A scoped exception to a rule (spec §9.3, §31.3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Exception {
    pub rule: RecordRef,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rule_version: Option<RecordVersionId>,
    /// The exact affected scope of the exception.
    pub scope: Scope,
    pub validity: Validity,
    /// The author decision that authorized this exception.
    pub authorizing_decision: RecordRef,
    pub rationale: String,
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Explicit dependency: holding this item grants a value while both the
/// possession evidence and this definition apply. It never changes identity.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ItemPower {
    pub item: RecordRef,
    pub holder_predicate: RecordRef,
    pub power_predicate: RecordRef,
    pub value: Value,
    pub scope: Scope,
    pub validity: Validity,
}

/// An action's mandatory attribute, resolved on the entity filling this role.
/// This cannot be replaced by an event's optional prerequisite or another owner.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct AttributeRequirement {
    pub role: String,
    pub predicate: RecordRef,
    pub value: Value,
}

/// Author-controlled action vocabulary, including ordinary actions with no
/// special requirements. Display labels never create executable requirements.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ActionDefinition {
    pub namespace: String,
    pub key: String,
    pub labels: BTreeMap<String, String>,
    pub requirements: Vec<AttributeRequirement>,
    /// Omitted for immutable historical definitions. Declaration only; event
    /// consequence enforcement is not implemented by this domain contract.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "crate::consequences::present_contract"
    )]
    #[schemars(with = "crate::consequences::ConsequenceContract")]
    pub consequence_contract: Option<crate::consequences::ConsequenceContract>,
    pub scope: Scope,
    pub validity: Validity,
}

/// Event occurrence modes (spec §27.5).
///
/// Only an admitted `occurred` event establishes objective state effects
/// by default. A report establishes a report, not the reported
/// occurrence.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum OccurrenceMode {
    Occurred,
    Planned,
    Predicted,
    Hypothetical,
    Reported,
    /// Another declared descriptive mode.
    Descriptive {
        label: String,
    },
}

impl Canonical for OccurrenceMode {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            OccurrenceMode::Occurred => CanonicalValue::Str("occurred".into()),
            OccurrenceMode::Planned => CanonicalValue::Str("planned".into()),
            OccurrenceMode::Predicted => CanonicalValue::Str("predicted".into()),
            OccurrenceMode::Hypothetical => CanonicalValue::Str("hypothetical".into()),
            OccurrenceMode::Reported => CanonicalValue::Str("reported".into()),
            OccurrenceMode::Descriptive { label } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("descriptive".into())),
                ("label".into(), CanonicalValue::Str(label.clone())),
            ]),
        }
    }
}

/// An event participant with a named role (spec §7.3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EventParticipant {
    pub record: RecordRef,
    pub role: String,
}

/// An authored effect: compiled into explicit assertion operations in the
/// same immutable proposal revision (spec §27.5).
///
/// The effect's assertion operations — not a second mutable state object —
/// are the canonical state representation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EntityEffect {
    /// Explicit effect slot id; the generated assertion records it.
    pub slot: String,
    /// The proposition the effect establishes (a local reference is
    /// resolved to a new proposition record during compilation).
    pub proposition: RecordRef,
    pub polarity: Polarity,
    pub validity: Validity,
    pub scope: Scope,
    /// Noncommuting effects on the same resource need an authored order
    /// (spec §27.5): explicit when necessary.
    pub order: usize,
}

impl Eq for EntityEffect {}
impl std::hash::Hash for EntityEffect {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

/// A canonical event record (spec §7.3, §27.5).
///
/// A plan or hypothetical is not an actual occurrence, even when its
/// existence as a plan is canon (S32).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Event {
    pub occurrence: OccurrenceMode,
    /// Mandatory on new/revised events. Optional only to decode historical
    /// events without rewriting immutable sources or their payload digests.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action: Option<RecordRef>,
    #[serde(default)]
    pub worlds: Vec<WorldId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub region: Option<RecordRef>,
    pub time: TemporalExpression,
    /// Explicit within-event sequencing for ordered effects/phases.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sequence: Option<String>,
    /// Occurrence id for repeated events (time loops; S29): recurring
    /// display labels are not unique moments.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub occurrence_id: Option<String>,
    pub participants: Vec<EventParticipant>,
    /// Preconditions are evaluated against the pre-event state.
    #[serde(default)]
    pub preconditions: Vec<Expr>,
    /// Effects are applied atomically to the candidate post-event state.
    #[serde(default)]
    pub effects: Vec<EntityEffect>,
    pub labels: BTreeMap<String, String>,
    /// The expansion version the service recorded when it compiled the
    /// effects (spec §27.5).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expansion_version: Option<String>,
}

impl Eq for Event {}
impl std::hash::Hash for Event {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

// ---------------------------------------------------------------------------
// Perspectives / knowledge
// ---------------------------------------------------------------------------

/// Epistemic attitudes (spec §27.6): `believes`, `suspects`, `rejects`,
/// `remembers`, and authored knowledge stay distinct. Do not silently
/// promote a belief.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum EpistemicAttitudeKind {
    Believes,
    Suspects,
    Rejects,
    Remembers,
    Knows,
}

impl Canonical for EpistemicAttitudeKind {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            EpistemicAttitudeKind::Believes => "believes".into(),
            EpistemicAttitudeKind::Suspects => "suspects".into(),
            EpistemicAttitudeKind::Rejects => "rejects".into(),
            EpistemicAttitudeKind::Remembers => "remembers".into(),
            EpistemicAttitudeKind::Knows => "knows".into(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EpistemicAttitude {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub acquisition: Option<KnowledgeAcquisition>,
    pub holder: RecordRef,
    pub proposition: RecordRef,
    pub attitude: EpistemicAttitudeKind,
    pub certainty: Option<String>,
    pub validity: Validity,
    pub basis: EvidenceBasis,
}

/// Explicit context policy; no knowledge policy is inferred from an attitude.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct KnowledgePolicy {
    pub context: RecordRef,
    pub mode: KnowledgeMode,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum KnowledgeMode {
    AuthorEstablished,
    Justified,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct KnowledgeAcquisition {
    pub truth_context: RecordRef,
    pub time: TemporalExpression,
    /// Optional exact world for truth evaluation. Absence means universe-wide evidence only.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub world: Option<RecordRef>,
    pub basis: KnowledgeBasis,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum KnowledgeBasis {
    AuthorEstablished,
    CommunicationReceipt {
        communication: RecordRef,
        interpretation: Option<RecordRef>,
    },
}

/// An observation: presence alone does not establish perception or
/// understanding (spec §27.6).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Observation {
    pub observer: RecordRef,
    pub observed: RecordRef,
    /// Whether sensory access is established.
    pub sensory_access: bool,
    pub time: TemporalExpression,
    /// The interpreted proposition, if any.
    pub interpretation: Option<RecordRef>,
    pub basis: EvidenceBasis,
}

/// A communication: knowledge changes need receipt and the declared
/// acquisition/interpretation basis (spec §27.6).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Communication {
    pub sender: RecordRef,
    pub intended_recipients: Vec<RecordRef>,
    pub actual_recipients: Vec<RecordRef>,
    pub content: Vec<RecordRef>,
    pub channel: Option<String>,
    pub sent_at: TemporalExpression,
    pub received_at: Option<TemporalExpression>,
    pub distorted: bool,
}

/// A memory: remembered content can be false, incomplete, or detached
/// from objective events (spec §27.6).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Memory {
    pub holder: RecordRef,
    pub content: RecordRef,
    pub alleged: Option<RecordRef>,
    pub accessibility: String,
    pub altered: bool,
    pub validity: Validity,
}

/// A secret/disclosure constraint (spec §27.6).
///
/// Fictional secrecy and application access grants remain separate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Secret {
    pub scope: Vec<RecordRef>,
    pub fictional_knowers: Vec<RecordRef>,
    pub reader_disclosed: bool,
    pub concealment: Option<String>,
    pub validity: Validity,
}

/// A goal/plan: an approved plan does not execute itself or reserve
/// resources automatically (spec §27.6).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Goal {
    pub actor: RecordRef,
    pub desired: Option<RecordRef>,
    pub prerequisites: Vec<Expr>,
    pub steps: Vec<RecordRef>,
    pub status: PlanStatus,
    pub validity: Validity,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum PlanStatus {
    Active,
    Abandoned,
    Achieved,
}

impl Canonical for PlanStatus {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            PlanStatus::Active => "active".into(),
            PlanStatus::Abandoned => "abandoned".into(),
            PlanStatus::Achieved => "achieved".into(),
        })
    }
}

/// A commitment: violations are permitted occurrences; prescribed
/// consequences happen only when established (spec §27.6).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Commitment {
    pub parties: Vec<CommitmentParty>,
    pub obligated: RecordRef,
    pub conditions: Vec<Expr>,
    pub deadline: Option<TemporalExpression>,
    pub status: CommitmentStatus,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CommitmentParty {
    pub record: RecordRef,
    pub role: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum CommitmentStatus {
    Unfulfilled,
    Fulfilled,
    Breached,
    Released,
}

impl Canonical for CommitmentStatus {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            CommitmentStatus::Unfulfilled => "unfulfilled".into(),
            CommitmentStatus::Fulfilled => "fulfilled".into(),
            CommitmentStatus::Breached => "breached".into(),
            CommitmentStatus::Released => "released".into(),
        })
    }
}

// ---------------------------------------------------------------------------
// Provenance
// ---------------------------------------------------------------------------

/// A source identity (spec §27.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Source {
    pub label: String,
    /// External identifier (an identifier, not a fetch — spec §13.1).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub external_id: Option<String>,
    pub origin: OriginMetadata,
    pub versions: Vec<crate::ids::RecordId>,
}

/// Origin metadata for a source or source version (spec §14.1).
#[derive(Debug, Default, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(default)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct OriginMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub externally_asserted_author: Option<String>,
    #[serde(default)]
    pub origin_note: Option<String>,
}

/// An immutable source version (spec §14.1, §27.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SourceVersion {
    pub source: RecordRef,
    /// SHA-256 of the blob content.
    pub digest: String,
    pub media_type: String,
    pub byte_size: u64,
    pub import_actor: PrincipalId,
    /// Editorial time (RFC3339 UTC) — never a fictional time.
    pub import_time: String,
    pub decoding: DecodingDescriptor,
    pub origin: OriginMetadata,
}

/// The decoding descriptor of a text source version (spec §27.7):
/// canonical text offsets are UTF-8 byte offsets in this named
/// representation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct DecodingDescriptor {
    pub encoding: String,
    /// The canonical decoded-text representation name.
    pub representation: String,
    pub byte_length: u64,
}

/// An evidence anchor into an immutable source version (spec §14.1, §27.7).
///
/// Byte boundaries must align to decoded character boundaries.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Anchor {
    pub source_version: VersionRef,
    pub locator: AnchorLocator,
    /// Digest of the exact excerpt.
    pub excerpt_digest: String,
    /// The exact excerpt (preserved for review).
    pub excerpt: String,
    pub context: Option<RecordRef>,
}

/// A precise structural locator (spec §27.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum AnchorLocator {
    /// UTF-8 byte offsets in the declared decoded-text representation.
    ByteRange { start: u64, end: u64 },
    /// Structural path (document sections).
    StructuralPath { path: Vec<String> },
}

impl Canonical for AnchorLocator {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            AnchorLocator::ByteRange { start, end } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("byte_range".into())),
                ("start".into(), CanonicalValue::Num(start.to_string())),
                ("end".into(), CanonicalValue::Num(end.to_string())),
            ]),
            AnchorLocator::StructuralPath { path } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("structural_path".into())),
                (
                    "path".into(),
                    CanonicalValue::arr(
                        path.iter()
                            .map(|p| CanonicalValue::Str(p.clone()))
                            .collect(),
                    ),
                ),
            ]),
        }
    }
}

// ---------------------------------------------------------------------------
// Narrative records (spec §27.7, §36.7)
// ---------------------------------------------------------------------------

/// Narrative work kinds (spec §5.6): a work is universe-owned metadata,
/// never a manuscript store.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum WorkKind {
    Novel,
    Story,
    SeriesChapter,
    Play,
    Film,
    /// Another declared kind: authors use the work's labels/metadata for
    /// the specific kind, not an untyped escape hatch.
    Other,
}

impl Canonical for WorkKind {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            WorkKind::Novel => "novel".into(),
            WorkKind::Story => "story".into(),
            WorkKind::SeriesChapter => "series_chapter".into(),
            WorkKind::Play => "play".into(),
            WorkKind::Film => "film".into(),
            WorkKind::Other => "other".into(),
        })
    }
}

/// An external narrative work owned by a universe (spec §36.7).
///
/// A work can span several worlds; world associations are zero-to-many and
/// do not establish occurrences, travel, knowledge, or location.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Work {
    pub kind: WorkKind,
    pub title: String,
    pub labels: BTreeMap<String, String>,
    /// External document/source references (evidence anchors, spec §5.1).
    pub source_refs: Vec<RecordRef>,
    /// Version record ids.
    pub versions: Vec<RecordId>,
    /// World associations (zero-to-many; many-to-many overall).
    pub world_associations: Vec<WorldAssociation>,
}

/// A version of a work with an explicit canon binding (spec §36.7).
///
/// Being included in a saga does not select an alternate continuity or
/// give that work a private head.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct WorkVersion {
    pub work: RecordRef,
    pub version_label: String,
    /// The continuity + revision this version depicts, or explicitly
    /// unbound/under review.
    pub binding: WorkBinding,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum WorkBinding {
    /// Bound to an explicit continuity/revision.
    Bound {
        continuity: ContinuityId,
        revision: RevisionId,
    },
    /// Explicitly unbound / under review.
    Unbound,
    /// Depicts several continuities: segment-level bindings instead of
    /// merging contradictory facts.
    Segments { segments: Vec<WorkSegment> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct WorkSegment {
    pub segment: String,
    pub continuity: ContinuityId,
    pub revision: RevisionId,
}

/// A scene reference: reader order, narration time, depicted event time,
/// and local world time stay separate (spec §36.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SceneRef {
    pub work_version: VersionRef,
    pub scene_id: String,
    /// Explicit reader disclosures; depicted events alone do not establish knowledge.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub disclosed_records: Vec<RecordRef>,
    pub viewpoint: Option<RecordRef>,
    pub narrative_position: Option<u64>,
    pub depicted_events: Vec<RecordRef>,
    pub narration_frame: Option<RecordRef>,
    pub world_associations: Vec<WorldAssociation>,
}

/// A passage reference with a source locator.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct PassageRef {
    pub work_version: VersionRef,
    pub passage_id: String,
    pub anchor: Option<RecordRef>,
}

/// A saga/series: typed membership and ordering, non-exclusive (spec §5.6,
/// §36.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Saga {
    pub title: String,
    pub labels: BTreeMap<String, String>,
    pub memberships: Vec<SagaMembership>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SagaMembership {
    pub work: RecordRef,
    pub role: String,
    /// Authored ordering position (nullable = unordered).
    pub order: Option<u64>,
}

/// A world association with optional qualifiers (spec §5.7, §36.7):
/// changing associations and changing physical location are separate
/// operations.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct WorldAssociation {
    pub world: WorldId,
    /// The role of the association ("setting", "visit", "origin", ...).
    pub role: String,
    pub validity: Validity,
    pub qualifiers: BTreeMap<String, Value>,
}

impl Eq for WorldAssociation {}
impl std::hash::Hash for WorldAssociation {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

// ---------------------------------------------------------------------------
// Identity records
// ---------------------------------------------------------------------------

/// A contextual name (spec §5.4): language, community, time, optional
/// role. Original Unicode spelling preserved; a separate normalized search
/// form is maintained by the service (normalization helps search, not
/// identity).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ContextualName {
    pub text: String,
    pub language: Option<String>,
    pub community: Option<String>,
    pub role: Option<String>,
    pub validity: Validity,
}

/// A canonical entity (spec §5.1, §5.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Entity {
    pub names: Vec<ContextualName>,
    pub classification: Option<RecordId>,
    pub classification_resolution: ClassificationResolution,
    /// World associations (separate from location).
    pub world_associations: Vec<WorldAssociation>,
    pub labels: BTreeMap<String, String>,
    pub metadata: BTreeMap<String, Value>,
}

// ---------------------------------------------------------------------------
// Editorial records
// ---------------------------------------------------------------------------

/// An author decision on a finding (spec §10.6, §31.7).
///
/// A resolution names the particular finding fingerprint and scope; it
/// must not suppress a materially different future problem.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct IssueDecision {
    pub fingerprints: Vec<crate::ids::FindingFingerprint>,
    pub mode: IssueDecisionMode,
    pub scope: String,
    pub rationale: String,
    pub principal: PrincipalId,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum IssueDecisionMode {
    /// Explicitly accept a scoped unresolved issue/inconsistency (I20).
    Accept,
    /// Defer: keep the finding open.
    Defer,
    /// Resolve: the issue is closed in the named scope.
    Resolve,
}

impl Canonical for IssueDecisionMode {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            IssueDecisionMode::Accept => "accept".into(),
            IssueDecisionMode::Defer => "defer".into(),
            IssueDecisionMode::Resolve => "resolve".into(),
        })
    }
}

// ---------------------------------------------------------------------------
// The payload enum
// ---------------------------------------------------------------------------

/// The closed set of canonical payloads.
///
/// The discriminator key is `record_kind` (spec §27.1 contract naming):
/// several payload structs carry their *own* `kind` field (work, rule,
/// represented context), so a `kind` discriminator would collide with a
/// payload field in the canonical object (duplicate key — spec §27.8).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "record_kind", rename_all = "snake_case")]
// Closed tagged union: the largest variant (Rule) is not boxable without
// re-firing this lint for the next-largest (Assertion), and canonical bytes
// — not the in-memory representation — are the storage/identity form.
#[allow(clippy::large_enum_variant)]
pub enum Payload {
    Entity(Entity),
    Appearance(Appearance),
    ImageAsset(ImageAsset),
    World(World),
    Realm(Realm),
    Work(Work),
    WorkVersion(WorkVersion),
    SceneRef(SceneRef),
    PassageRef(PassageRef),
    Saga(Saga),
    EntityType(EntityType),
    Property(PropertyDef),
    Relation(RelationDef),
    Unit(UnitDef),
    Calendar(CalendarDef),
    ValueDefinition(ValueDef),
    DomainPack(DomainPack),
    Proposition(Proposition),
    Assertion(Assertion),
    RepresentedContext(RepresentedContext),
    Completeness(CompletenessDecl),
    Boundary(CreativeBoundary),
    Rule(Rule),
    Exception(Exception),
    Event(Event),
    ItemPower(ItemPower),
    ActionDefinition(ActionDefinition),
    EpistemicAttitude(EpistemicAttitude),
    Observation(Observation),
    Communication(Communication),
    Memory(Memory),
    Secret(Secret),
    Goal(Goal),
    Commitment(Commitment),
    Source(Source),
    SourceVersion(SourceVersion),
    Anchor(Anchor),
    IssueDecision(IssueDecision),
}

impl Payload {
    pub fn kind(&self) -> RecordKind {
        match self {
            Payload::Entity(_) => RecordKind::Entity,
            Payload::Appearance(_) => RecordKind::Appearance,
            Payload::ImageAsset(_) => RecordKind::ImageAsset,
            Payload::World(_) => RecordKind::World,
            Payload::Realm(_) => RecordKind::Realm,
            Payload::Work(_) => RecordKind::Work,
            Payload::WorkVersion(_) => RecordKind::WorkVersion,
            Payload::SceneRef(_) => RecordKind::SceneRef,
            Payload::PassageRef(_) => RecordKind::PassageRef,
            Payload::Saga(_) => RecordKind::Saga,
            Payload::EntityType(_) => RecordKind::EntityType,
            Payload::Property(_) => RecordKind::Property,
            Payload::Relation(_) => RecordKind::Relation,
            Payload::Unit(_) => RecordKind::Unit,
            Payload::Calendar(_) => RecordKind::Calendar,
            Payload::ValueDefinition(_) => RecordKind::ValueDefinition,
            Payload::DomainPack(_) => RecordKind::DomainPack,
            Payload::Proposition(_) => RecordKind::Proposition,
            Payload::Assertion(_) => RecordKind::Assertion,
            Payload::RepresentedContext(_) => RecordKind::RepresentedContext,
            Payload::Completeness(_) => RecordKind::Completeness,
            Payload::Boundary(_) => RecordKind::Boundary,
            Payload::Rule(_) => RecordKind::Rule,
            Payload::Exception(_) => RecordKind::Exception,
            Payload::Event(_) => RecordKind::Event,
            Payload::ItemPower(_) => RecordKind::ItemPower,
            Payload::ActionDefinition(_) => RecordKind::ActionDefinition,
            Payload::EpistemicAttitude(_) => RecordKind::EpistemicAttitude,
            Payload::Observation(_) => RecordKind::Observation,
            Payload::Communication(_) => RecordKind::Communication,
            Payload::Memory(_) => RecordKind::Memory,
            Payload::Secret(_) => RecordKind::Secret,
            Payload::Goal(_) => RecordKind::Goal,
            Payload::Commitment(_) => RecordKind::Commitment,
            Payload::Source(_) => RecordKind::Source,
            Payload::SourceVersion(_) => RecordKind::SourceVersion,
            Payload::Anchor(_) => RecordKind::Anchor,
            Payload::IssueDecision(_) => RecordKind::IssueDecision,
        }
    }

    /// All record references embedded in this payload (for reference
    /// index extraction and universe-isolation checks).
    pub fn referenced_records(&self) -> Vec<RecordRef> {
        let mut out = Vec::new();
        fn collect(refs: &mut Vec<RecordRef>, v: &CanonicalValue) {
            use CanonicalValue::*;
            match v {
                Str(s) => {
                    if crate::ids::Id::is_known(s) {
                        // Only RecordId-shaped ids are record references.
                        if let Ok(id) = RecordId::parse(s) {
                            refs.push(RecordRef::local(id));
                        }
                    }
                }
                Arr(items) => {
                    for i in items {
                        collect(refs, i);
                    }
                }
                Obj(fields) => {
                    for (k, val) in fields {
                        if k == "record" {
                            if let Str(s) = val {
                                if let Ok(id) = RecordId::parse(s) {
                                    refs.push(RecordRef::local(id));
                                }
                            }
                        } else if k == "universe" {
                            // handled together with `record` above
                        } else {
                            collect(refs, val);
                        }
                    }
                }
                _ => {}
            }
        }
        collect(&mut out, &self.to_canonical());
        out
    }
}

/// One canonical form for the whole payload family: the serde bridge with
/// canonically sorted keys. The `record_kind` discriminator key (from the
/// enum tag) cannot collide with any payload struct field, so every
/// payload canonical object is key-unique and round-trips through the
/// strict parser (spec §27.8).
impl Canonical for Payload {
    fn to_canonical(&self) -> CanonicalValue {
        crate::canonical::canonical_serde(self)
    }
}

/// Implement `Canonical` for closed payload structs through the single
/// versioned serde bridge (spec §27.8). Types with hand-verified manual
/// impls (small tagged enums, value/temporal families) are intentionally
/// not listed here.
macro_rules! canonical_via_serde {
    ($($ty:ty),+ $(,)?) => {
        $(
            impl crate::canonical::Canonical for $ty {
                fn to_canonical(&self) -> crate::canonical::CanonicalValue {
                    crate::canonical::canonical_serde(self)
                }
            }
        )+
    };
}

canonical_via_serde!(
    Appearance,
    ImageAsset,
    World,
    Realm,
    EntityType,
    PropertyDef,
    RoleDef,
    RelationDef,
    UnitDef,
    CalendarDef,
    CalendarConversion,
    ValueDef,
    ValueDefField,
    DomainPack,
    Proposition,
    PropositionRole,
    Assertion,
    EventEffectRef,
    RepresentedContext,
    CompletenessDecl,
    CreativeBoundary,
    Rule,
    Exception,
    Event,
    EventParticipant,
    EntityEffect,
    ActionDefinition,
    AttributeRequirement,
    EpistemicAttitude,
    Observation,
    Communication,
    Memory,
    Secret,
    Goal,
    Commitment,
    CommitmentParty,
    Source,
    OriginMetadata,
    SourceVersion,
    DecodingDescriptor,
    Anchor,
    Work,
    WorkVersion,
    WorkSegment,
    SceneRef,
    PassageRef,
    Saga,
    SagaMembership,
    ContextualName,
    Entity,
    WorldAssociation,
    IssueDecision,
);

// ---------------------------------------------------------------------------
// Domain operations (proposal catalog — spec §10.1, §27.9)
// ---------------------------------------------------------------------------

/// Explicit evidence for an incremental attribute. No event linkage or inferred
/// time, polarity, precision, or source truth is introduced by this convenience.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct AttributeEvidence {
    pub attribute_mode: AttributeMode,
    pub polarity: Polarity,
    pub scope: Scope,
    pub validity: Validity,
    pub persistence: PersistenceSemantics,
    pub precision: Precision,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub alternatives: Vec<Value>,
    pub basis: EvidenceBasis,
}

/// The versioned domain operation catalog underlying proposal batches
/// (spec §27.9). Each operation carries a closed typed payload and, for
/// replacement, the exact expected prior version.
/// Each newly created record needs its own unique, nonempty client_ref; target
/// and source identities belong in RecordRef fields, not reused client_ref names.
/// For new records referenced within the same batch, reserve a fresh valid rec_
/// identity as client_ref and use that identity in RecordRef.record. Friendly
/// client_ref names allocate opaque identities and cannot be used as record refs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum DomainOperation {
    CreateAppearance {
        client_ref: String,
        record: Appearance,
    },
    ReviseAppearance {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: Appearance,
    },
    AddImageAsset {
        client_ref: String,
        record: ImageAsset,
    },
    SetStoryTime {
        record: RecordRef,
        expected_version: RecordVersionId,
        value: String,
        mode: crate::chronology::TimeChangeKind,
        reason: String,
    },
    // Identity
    CreateEntity {
        client_ref: String,
        record: Entity,
    },
    AddName {
        record: RecordRef,
        expected_version: RecordVersionId,
        name: ContextualName,
    },
    AddTypeMembership {
        record: RecordRef,
        expected_version: RecordVersionId,
        entity_type: RecordId,
    },
    // World / narrative selectors
    CreateWorld {
        client_ref: String,
        record: World,
    },
    RenameWorldSelector {
        record: RecordRef,
        expected_version: RecordVersionId,
        new_selector: String,
    },
    AddWorldAlias {
        record: RecordRef,
        expected_version: RecordVersionId,
        alias: String,
    },
    CreateWork {
        client_ref: String,
        record: Work,
    },
    CreateSaga {
        client_ref: String,
        record: Saga,
    },
    SetWorkBinding {
        record: RecordRef,
        expected_version: RecordVersionId,
        binding: WorkBinding,
    },
    AssociateWorkWorld {
        record: RecordRef,
        expected_version: RecordVersionId,
        association: WorldAssociation,
    },
    SetSagaMembership {
        record: RecordRef,
        expected_version: RecordVersionId,
        membership: SagaMembership,
    },
    // Propositions and assertions
    AssertProposition {
        client_ref: String,
        proposition: Proposition,
        assertion: Assertion,
    },
    RecordRelation {
        client_ref: String,
        proposition: Proposition,
        assertion: Assertion,
    },
    EndAssertionAt {
        record: RecordRef,
        expected_version: RecordVersionId,
        at: TemporalExpression,
        basis: EvidenceBasis,
    },
    SupersedeAssertion {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: Assertion,
        rationale: String,
    },
    RetractAssertion {
        record: RecordRef,
        expected_version: RecordVersionId,
        rationale: String,
    },
    // A proposition may be mentioned by an event without asserting it.
    DefineProposition {
        client_ref: String,
        record: Proposition,
    },
    DefineItemPower {
        client_ref: String,
        record: ItemPower,
    },
    DefineAction {
        client_ref: String,
        record: ActionDefinition,
    },
    // Events
    RecordEvent {
        client_ref: String,
        record: Event,
    },
    ReviseEvent {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: Event,
    },
    // Knowledge
    AddBelief {
        client_ref: String,
        record: EpistemicAttitude,
    },
    RecordObservation {
        client_ref: String,
        record: Observation,
    },
    RecordCommunication {
        client_ref: String,
        record: Communication,
    },
    RecordMemory {
        client_ref: String,
        record: Memory,
    },
    RecordPlan {
        client_ref: String,
        record: Goal,
    },
    RecordCommitment {
        client_ref: String,
        record: Commitment,
    },
    // Definitions
    DefineType {
        client_ref: String,
        record: EntityType,
    },
    DefineProperty {
        client_ref: String,
        record: PropertyDef,
    },
    DefineRelation {
        client_ref: String,
        record: RelationDef,
    },
    DefineUnit {
        client_ref: String,
        record: UnitDef,
    },
    DefineCalendar {
        client_ref: String,
        record: CalendarDef,
    },
    DefineValue {
        client_ref: String,
        record: ValueDef,
    },
    DefineRule {
        client_ref: String,
        record: Rule,
    },
    // Protected
    SetCompleteness {
        client_ref: String,
        record: CompletenessDecl,
    },
    SetCreativeBoundary {
        client_ref: String,
        record: CreativeBoundary,
    },
    AddException {
        client_ref: String,
        record: Exception,
    },
    // Evidence
    AddSourceAnchor {
        client_ref: String,
        record: Anchor,
    },
    RecordNarrativeReference {
        client_ref: String,
        record: RecordKind,
        payload: Payload,
    },
    // Decisions
    RecordIssueDecision {
        client_ref: String,
        record: IssueDecision,
    },
    /// Adopt an existing immutable historical version through exact review.
    AdoptRecordVersion {
        source: Box<RecordVersion>,
        expected_version: Option<RecordVersionId>,
    },
    // Privileged
    TombstoneRecord {
        record: RecordRef,
        expected_version: RecordVersionId,
        rationale: String,
    },
    MergeEntities {
        source: RecordRef,
        source_version: RecordVersionId,
        target: RecordRef,
        target_version: RecordVersionId,
        rationale: String,
    },
    InstallPack {
        client_ref: String,
        record: DomainPack,
    },
    /// Withdraw support for an incorrectly recorded occurrence; immutable history remains.
    WithdrawEvent {
        record: RecordRef,
        expected_version: RecordVersionId,
        rationale: String,
    },
    /// Exact historical communication correction; does not declare a later message.
    ReviseCommunication {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: Communication,
        rationale: String,
    },
    /// Explicit correction of justified receipt interpretation; preserves holder, acquisition time/context/message and evidence basis.
    ReviseInterpretation {
        record: RecordRef,
        expected_version: RecordVersionId,
        interpretation: Option<RecordRef>,
        rationale: String,
    },
    /// Exact scene correction; scene identity, immutable edition and world associations stay unchanged.
    ReviseScene {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: SceneRef,
        rationale: String,
    },
    /// Historical attitude correction; stance, holder, acquisition and basis stay unchanged. Knows permits duration edits only.
    ReviseAttitude {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: EpistemicAttitude,
        rationale: String,
    },
    /// Version-bound grant correction; item, possession predicate, ability predicate and represented context remain unchanged.
    ReviseItemPower {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: ItemPower,
        rationale: String,
    },
    ReviseDefinition {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: Box<Payload>,
    },
    UpgradePack {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: DomainPack,
    },
    /// Minimal definition; absent parent means an authored root, not ambiguity.
    IntroduceDefinition {
        client_ref: String,
        namespace: String,
        key: String,
        name: String,
        parent: Option<RecordId>,
        applicability: Applicability,
        classification_executable: bool,
    },
    /// Name and stable identity; classification and world association are explicit.
    IntroduceInstance {
        client_ref: String,
        name: ContextualName,
        classification: Option<RecordId>,
        world_associations: Vec<WorldAssociation>,
    },
    /// Creates/reuses the named property and asserts a typed value atomically.
    AddNamedAttribute {
        client_ref: String,
        subject: RecordRef,
        namespace: String,
        key: String,
        value_shape: ValueShape,
        subject_types: Vec<RecordId>,
        multiplicity: Multiplicity,
        value: Value,
        evidence: AttributeEvidence,
    },
    /// Apply an approved initial-value definition once at this authored start.
    /// The chosen source is explicit; conflicting or unresolved sources block it.
    InitializeInstance {
        client_ref: String,
        instance: RecordRef,
        start: RecordRef,
        definition: VersionRef,
        scope: Scope,
        validity: Validity,
    },
    /// Knowledge refinement only: never a correction or physical transformation.
    RefineClassification {
        record: RecordRef,
        expected_version: RecordVersionId,
        entity_type: RecordId,
    },
    CreateSecret {
        client_ref: String,
        record: Secret,
    },
    ReviseSecret {
        record: RecordRef,
        expected_version: RecordVersionId,
        replacement: Secret,
    },
}

impl DomainOperation {
    /// The authority classification of this operation family
    /// (spec §27.9): used by grant evaluation and the review UI.
    pub fn authority(&self) -> OperationAuthority {
        use DomainOperation::*;
        match self {
            InitializeInstance { .. }
            | IntroduceInstance { .. }
            | RefineClassification { .. }
            | CreateEntity { .. }
            | CreateSecret { .. }
            | ReviseSecret { .. }
            | CreateAppearance { .. }
            | ReviseAppearance { .. }
            | AddImageAsset { .. }
            | AddName { .. }
            | AddTypeMembership { .. }
            | AssertProposition { .. }
            | RecordRelation { .. }
            | DefineProposition { .. }
            | RecordEvent { .. }
            | ReviseEvent { .. }
            | AddBelief { .. }
            | RecordObservation { .. }
            | RecordCommunication { .. }
            | RecordMemory { .. }
            | RecordPlan { .. }
            | RecordCommitment { .. }
            | AddSourceAnchor { .. }
            | RecordNarrativeReference { .. }
            | RecordIssueDecision { .. }
            | CreateWorld { .. }
            | CreateWork { .. }
            | CreateSaga { .. }
            | RenameWorldSelector { .. }
            | AddWorldAlias { .. }
            | SetWorkBinding { .. }
            | AssociateWorkWorld { .. }
            | SetSagaMembership { .. } => OperationAuthority::Ordinary,
            SetStoryTime { .. }
            | EndAssertionAt { .. }
            | SupersedeAssertion { .. }
            | RetractAssertion { .. }
            | WithdrawEvent { .. }
            | ReviseAttitude { .. }
            | ReviseCommunication { .. }
            | ReviseInterpretation { .. }
            | ReviseScene { .. } => OperationAuthority::Historical,
            IntroduceDefinition { .. }
            | AddNamedAttribute { .. }
            | DefineItemPower { .. }
            | ReviseItemPower { .. }
            | DefineAction { .. }
            | DefineType { .. }
            | DefineProperty { .. }
            | DefineRelation { .. }
            | DefineUnit { .. }
            | DefineCalendar { .. }
            | DefineValue { .. }
            | DefineRule { .. }
            | SetCompleteness { .. }
            | SetCreativeBoundary { .. }
            | AddException { .. }
            | InstallPack { .. }
            | UpgradePack { .. }
            | ReviseDefinition { .. } => OperationAuthority::Definition,
            AdoptRecordVersion { .. } | TombstoneRecord { .. } | MergeEntities { .. } => {
                OperationAuthority::Privileged
            }
        }
    }
}

/// Coarse authority families for operation classification (spec §27.9).
///
/// Grant evaluation follows *actual* effects and referenced definitions,
/// not a supplied friendly label (E11).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum OperationAuthority {
    /// Ordinary detail creation (still content- and scope-checked).
    Ordinary,
    /// Historical/protected assertion changes.
    Historical,
    /// Definition, boundary, exception, completeness editing.
    Definition,
    /// Privileged: tombstone, merge.
    Privileged,
}

impl Canonical for OperationAuthority {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            OperationAuthority::Ordinary => "ordinary".into(),
            OperationAuthority::Historical => "historical".into(),
            OperationAuthority::Definition => "definition".into(),
            OperationAuthority::Privileged => "privileged".into(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::{UniverseId, WorldId};

    fn univ() -> UniverseId {
        UniverseId::parse("unv_000000000000000000000001").unwrap()
    }
    fn rec(n: u32) -> RecordId {
        RecordId::parse(&format!("rec_{:024x}", n)).unwrap()
    }
    fn ref_(n: u32) -> RecordRef {
        RecordRef::new(univ(), rec(n))
    }

    fn context_rec() -> RecordRef {
        ref_(1)
    }

    #[test]
    fn entity_round_trips_with_world_associations() {
        let w = WorldId::parse("wld_000000000000000000000001").unwrap();
        let e = Entity {
            names: vec![ContextualName {
                text: "Iven".into(),
                language: None,
                community: None,
                role: None,
                validity: Validity::Unspecified,
            }],
            classification: None,
            classification_resolution: ClassificationResolution::Unclassified,
            world_associations: vec![WorldAssociation {
                world: w,
                role: "setting".into(),
                validity: Validity::Unspecified,
                qualifiers: BTreeMap::new(),
            }],
            labels: BTreeMap::new(),
            metadata: BTreeMap::new(),
        };
        let p = Payload::Entity(e.clone());
        let s = serde_json::to_string(&p).unwrap();
        let back: Payload = serde_json::from_str(&s).unwrap();
        assert_eq!(p, back);
        assert_eq!(p.kind(), RecordKind::Entity);
    }

    #[test]
    fn assertion_and_proposition_are_distinct_records() {
        let a = Assertion {
            attribute_mode: AttributeMode::Instance,
            proposition: ref_(2),
            polarity: Polarity::Support,
            scope: Scope {
                applicability: Applicability::Unspecified,
                context: context_rec(),
                realm: None,
            },
            validity: Validity::Unspecified,
            persistence: PersistenceSemantics::Unspecified,
            precision: Precision::Exact,
            alternatives: vec![],
            basis: EvidenceBasis::AuthorDecision {
                note: "test".into(),
            },
            established_by: None,
        };
        let prop = Proposition {
            predicate: ref_(3),
            subject: ref_(4),
            roles: vec![],
            value: None,
            quantification: Quantification::Particular,
            context: context_rec(),
        };
        let p1 = Payload::Assertion(a);
        let p2 = Payload::Proposition(prop);
        assert_ne!(p1.kind(), p2.kind());
        // A version for the wrong payload kind is rejected.
        let v = RecordVersion::build(
            crate::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(univ(), rec(10), RecordKind::Assertion),
            p2,
        );
        assert!(v.is_err());
    }

    #[test]
    fn digest_covers_kind_and_content() {
        let make = |note: &str| Assertion {
            attribute_mode: AttributeMode::Instance,
            proposition: ref_(2),
            polarity: Polarity::Support,
            scope: Scope {
                applicability: Applicability::Unspecified,
                context: context_rec(),
                realm: None,
            },
            validity: Validity::Unspecified,
            persistence: PersistenceSemantics::Unspecified,
            precision: Precision::Exact,
            alternatives: vec![],
            basis: EvidenceBasis::AuthorDecision { note: note.into() },
            established_by: None,
        };
        let a1 = RecordVersion::build(
            crate::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(univ(), rec(10), RecordKind::Assertion),
            Payload::Assertion(make("one")),
        )
        .unwrap();
        let a2 = RecordVersion::build(
            crate::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(univ(), rec(10), RecordKind::Assertion),
            Payload::Assertion(make("two")),
        )
        .unwrap();
        assert_ne!(a1.payload_digest, a2.payload_digest);
        assert!(a1.verify_digest());
    }

    #[test]
    fn all_kind_strings_round_trip() {
        let schema = serde_json::to_value(schemars::schema_for!(RecordKind)).unwrap();
        let declared = schema["enum"].as_array().unwrap();
        let kinds = RecordKind::all();
        assert_eq!(kinds.len(), declared.len());
        let unique: std::collections::BTreeSet<_> = kinds.iter().collect();
        assert_eq!(unique.len(), declared.len());
        for k in kinds {
            assert_eq!(RecordKind::parse(k.as_str()).unwrap(), *k);
            assert!(declared.contains(&serde_json::json!(k.as_str())));
        }
    }

    #[test]
    fn operation_authority_classification() {
        let tomb = DomainOperation::TombstoneRecord {
            record: ref_(5),
            expected_version: crate::ids::RecordVersionId::parse("ver_000000000000000000000001")
                .unwrap(),
            rationale: "x".into(),
        };
        assert_eq!(tomb.authority(), OperationAuthority::Privileged);
        let rule = DomainOperation::DefineRule {
            client_ref: "r".into(),
            record: Rule {
                required_evidence: None,
                relation_cardinality: None,
                knowledge_boundary: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "author".into(),
                key: "k".into(),
                labels: BTreeMap::new(),
                kind: crate::records::RuleKind::Descriptive,
                commit_policy: crate::records::CommitPolicy::Advisory,
                applicability: Applicability::Unspecified,
                subject_types: vec![],
                target_predicates: vec![],
                expression: Expr::Lit { value: true },
                capabilities: vec![],
                executable: false,
                validity: Validity::Unspecified,
            },
        };
        assert_eq!(rule.authority(), OperationAuthority::Definition);
    }

    #[test]
    fn work_and_saga_memberships_are_nonexclusive() {
        let w1 = WorldId::parse("wld_000000000000000000000001").unwrap();
        let w2 = WorldId::parse("wld_000000000000000000000002").unwrap();
        let work = Work {
            kind: WorkKind::Novel,
            title: "T".into(),
            labels: BTreeMap::new(),
            source_refs: vec![],
            versions: vec![],
            world_associations: vec![
                WorldAssociation {
                    world: w1,
                    role: "setting".into(),
                    validity: Validity::Unspecified,
                    qualifiers: BTreeMap::new(),
                },
                WorldAssociation {
                    world: w2,
                    role: "visit".into(),
                    validity: Validity::Unspecified,
                    qualifiers: BTreeMap::new(),
                },
            ],
        };
        let p = Payload::Work(work.clone());
        let s = serde_json::to_string(&p).unwrap();
        let back: Payload = serde_json::from_str(&s).unwrap();
        assert_eq!(p, back);
        assert_eq!(work.world_associations.len(), 2);
    }

    /// Guards the `record_kind` discriminator decision: Work, Rule, and
    /// RepresentedContext carry their *own* `kind` fields, so the payload
    /// tag must not be `kind` — a duplicate canonical key would be rejected
    /// by the strict parser and would break the serde round trip.
    #[test]
    fn payload_tag_record_kind_coexists_with_payload_kind_fields() {
        let payloads = [
            Payload::Work(Work {
                kind: WorkKind::Other,
                title: "T".into(),
                labels: BTreeMap::new(),
                source_refs: vec![],
                versions: vec![],
                world_associations: vec![],
            }),
            Payload::Rule(Rule {
                required_evidence: None,
                relation_cardinality: None,
                knowledge_boundary: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "author".into(),
                key: "k".into(),
                labels: BTreeMap::new(),
                kind: RuleKind::Descriptive,
                commit_policy: CommitPolicy::Advisory,
                applicability: Applicability::Unspecified,
                subject_types: vec![],
                target_predicates: vec![],
                expression: Expr::Lit { value: true },
                capabilities: vec![],
                executable: false,
                validity: Validity::Unspecified,
            }),
            Payload::RepresentedContext(RepresentedContext {
                universe: univ(),
                kind: RepresentedContextKind::Objective,
                parent: None,
                chronology: None,
                labels: BTreeMap::new(),
            }),
        ];
        for p in &payloads {
            let json = serde_json::to_string(p).unwrap();
            assert_eq!(json.matches("\"record_kind\"").count(), 1);
            let back: Payload = serde_json::from_str(&json).unwrap();
            assert_eq!(p, &back);
            let canon = p.to_canonical();
            // Strict round-trip: if the tag were `kind`, the duplicate key
            // would be rejected here.
            let bytes = canon.to_bytes();
            assert_eq!(CanonicalValue::parse(&bytes).unwrap(), canon);
            let CanonicalValue::Obj(fields) = &canon else {
                panic!("payload must canonicalize to an object");
            };
            assert_eq!(fields.iter().filter(|(k, _)| k == "kind").count(), 1);
            assert_eq!(fields.iter().filter(|(k, _)| k == "record_kind").count(), 1);
        }
    }
}

/// Immutable admission evidence; corrections do not issue another receipt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct InitializationReceipt {
    pub instance: RecordId,
    pub start: RecordId,
    pub property: RecordId,
    pub definition: RecordVersionId,
    pub assertion: RecordVersionId,
    pub revision: RevisionId,
    pub source_revision: RevisionId,
}
