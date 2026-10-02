//! Immutable assessment contracts only: no attachment admission or semantic proof.
//! Digests bind declarations; authentication, frozen candidate resolution, visibility
//! and retained-byte lookup belong to the service and are not implied by decoding.
use crate::{request::ProposalRef, validation_scope::*};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use universe_domain::{
    canonical::{canonical_serde, Canonical, CanonicalValue},
    ids::PrincipalId,
    scope::Polarity,
    temporal::TemporalExpression,
    value::Value,
    Frame,
};

fn required_nullable<'de, D: serde::Deserializer<'de>, T: Deserialize<'de>>(
    d: D,
) -> Result<Option<T>, D::Error> {
    Option::<T>::deserialize(d)
}
// Workflow hashes use owning typed field serialization (including existing
// Frame/Value wire shapes), then the single domain canonical JSON writer.
// New nullable workflow members always serialize explicitly as null.
macro_rules! canonical_fields {
    ($ty:ty, $($field:ident),+ $(,)?) => {
        impl Canonical for $ty {
            fn to_canonical(&self) -> CanonicalValue {
                CanonicalValue::obj(vec![$((stringify!($field).into(), canonical_serde(&self.$field))),+])
            }
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AssessmentKind {
    SourceAssessmentV1,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Method {
    HumanReview,
    ExternalModelReview,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum MaterialKind {
    Fact,
    Action,
    Prerequisite,
    Effect,
    Knowledge,
    Description,
    Disclosure,
    UnchangedState,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum InventoryKind {
    MaterialInventoryDeclared,
    NoMaterialClaims,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Occurrence {
    Occurred,
    Planned,
    Hypothetical,
    Reported,
    Unknown,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Modality {
    Asserted,
    Negated,
    Possible,
    Counterfactual,
    Attributed,
    Unknown,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum MappingJudgment {
    Supported,
    Contradicted,
    Unresolved,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum UnresolvedReason {
    AmbiguousReferent,
    AmbiguousModality,
    UnsupportedSemantics,
    MissingEvidence,
    UnrepresentedMaterial,
    InterpretationDisagreement,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum CandidateLinkKind {
    ProposedRecord,
    UnchangedRecord,
    HistoricalEvidence,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Depiction {
    Factual,
    Subjective,
    Inspiration,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ToolIdentity {
    #[schemars(length(min = 1, max = 16384))]
    pub name: String,
    #[schemars(length(min = 1, max = 16384))]
    pub version: String,
    #[schemars(length(min = 1, max = 16384))]
    pub model_revision: String,
    pub procedure_digest: Sha256Hex,
}
canonical_fields!(
    ToolIdentity,
    name,
    version,
    model_revision,
    procedure_digest
);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Assessor {
    pub principal: PrincipalId,
    pub method: Method,
    #[serde(deserialize_with = "required_nullable")]
    #[schemars(required, schema_with = "nullable_tool_schema")]
    pub tool: Option<ToolIdentity>,
    #[schemars(length(min = 1, max = 16384))]
    pub assessed_at: String,
}
canonical_fields!(Assessor, principal, method, tool, assessed_at);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct MaterialItem {
    #[schemars(length(min = 1, max = 16384))]
    pub item_id: String,
    #[schemars(length(min = 1, max = 16384))]
    pub source_key: String,
    pub range: ByteRange,
    pub material_kind: MaterialKind,
    #[schemars(length(min = 1, max = 16384))]
    pub statement: String,
    pub mapping_ids: Vec<String>,
    pub unresolved_ids: Vec<String>,
}
canonical_fields!(
    MaterialItem,
    item_id,
    source_key,
    range,
    material_kind,
    statement,
    mapping_ids,
    unresolved_ids
);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Exclusion {
    #[schemars(length(min = 1, max = 16384))]
    pub source_key: String,
    pub range: ByteRange,
    #[schemars(length(min = 1, max = 16384))]
    pub reason: String,
}
canonical_fields!(Exclusion, source_key, range, reason);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct InventoryDeclaration {
    pub kind: InventoryKind,
    #[schemars(length(min = 1, max = 16384))]
    pub rationale: String,
    pub exclusions: Vec<Exclusion>,
}
canonical_fields!(InventoryDeclaration, kind, rationale, exclusions);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RoleParticipant {
    #[schemars(length(min = 1, max = 16384))]
    pub role: String,
    pub participant: AssessmentVersionRef,
}
canonical_fields!(RoleParticipant, role, participant);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Position {
    NotApplicable {},
    Unknown {
        reason: String,
    },
    WorkPosition {
        work_edition: AssessmentVersionRef,
        scene_id: String,
        ordinal: u64,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum SemanticMapping {
    Claim {
        predicate: AssessmentVersionRef,
        subject: AssessmentVersionRef,
        value: Value,
        roles: Vec<RoleParticipant>,
        polarity: Polarity,
    },
    Action {
        action: AssessmentVersionRef,
        participants: Vec<RoleParticipant>,
        prerequisites: Vec<AssessmentVersionRef>,
        effects: Vec<AssessmentVersionRef>,
    },
    Knowledge {
        holder: AssessmentVersionRef,
        content: AssessmentVersionRef,
        acquisition: Vec<AssessmentVersionRef>,
    },
    SourceDescription {
        subject: AssessmentVersionRef,
        depiction: Depiction,
        implied_claims: Vec<AssessmentVersionRef>,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CandidateLink {
    pub kind: CandidateLinkKind,
    pub version: AssessmentVersionRef,
}
canonical_fields!(CandidateLink, kind, version);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ClaimMapping {
    #[schemars(length(min = 1, max = 16384))]
    pub mapping_id: String,
    pub item_ids: Vec<String>,
    pub referents: Vec<AssessmentVersionRef>,
    pub context: AssessmentVersionRef,
    #[serde(deserialize_with = "required_nullable")]
    #[schemars(required, schema_with = "nullable_version_schema")]
    pub world: Option<AssessmentVersionRef>,
    #[serde(deserialize_with = "required_nullable")]
    #[schemars(required, schema_with = "nullable_version_schema")]
    pub realm: Option<AssessmentVersionRef>,
    pub story_time: TemporalExpression,
    pub narration_position: Position,
    pub reader_position: Position,
    pub occurrence: Occurrence,
    pub modality: Modality,
    pub semantic: SemanticMapping,
    pub candidate_links: Vec<CandidateLink>,
    pub judgment: MappingJudgment,
    #[schemars(length(min = 1, max = 16384))]
    pub rationale: String,
}
canonical_fields!(
    ClaimMapping,
    mapping_id,
    item_ids,
    referents,
    context,
    world,
    realm,
    story_time,
    narration_position,
    reader_position,
    occurrence,
    modality,
    semantic,
    candidate_links,
    judgment,
    rationale
);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct UnresolvedDisposition {
    #[schemars(length(min = 1, max = 16384))]
    pub unresolved_id: String,
    pub item_ids: Vec<String>,
    pub reason: UnresolvedReason,
    #[schemars(length(min = 1, max = 16384))]
    pub detail: String,
}
canonical_fields!(
    UnresolvedDisposition,
    unresolved_id,
    item_ids,
    reason,
    detail
);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceAssessmentV1 {
    pub kind: AssessmentKind,
    #[schemars(schema_with = "proposal_schema")]
    pub proposal: ProposalRef,
    pub base_frame: Frame,
    pub assessor: Assessor,
    #[schemars(length(min = 1, max = 64))]
    pub sources: Vec<SourceBinding>,
    #[schemars(length(max = 16384))]
    pub dependencies: Vec<AssessmentVersionRef>,
    #[schemars(length(max = 4096))]
    pub declared_inventory: Vec<MaterialItem>,
    pub inventory_declaration: InventoryDeclaration,
    #[schemars(length(max = 4096))]
    pub claim_mappings: Vec<ClaimMapping>,
    #[schemars(length(max = 4096))]
    pub unresolved: Vec<UnresolvedDisposition>,
    pub conclusion: DeclaredConclusion,
}
canonical_fields!(
    SourceAssessmentV1,
    kind,
    proposal,
    base_frame,
    assessor,
    sources,
    dependencies,
    declared_inventory,
    inventory_declaration,
    claim_mappings,
    unresolved,
    conclusion
);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AssessmentEnvelope {
    pub assessment_id: AssessmentId,
    pub digest: Sha256Hex,
    pub body: SourceAssessmentV1,
}
canonical_fields!(AssessmentEnvelope, assessment_id, digest, body);
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AssessmentSelection {
    #[schemars(schema_with = "proposal_schema")]
    pub proposal: ProposalRef,
    pub generation: u64,
    #[serde(deserialize_with = "required_nullable")]
    #[schemars(required, schema_with = "nullable_assessment_ref_schema")]
    pub selected: Option<AssessmentRef>,
}
canonical_fields!(AssessmentSelection, proposal, generation, selected);

pub type AssessmentResult<T> = Result<T, String>;
fn ensure(ok: bool, message: &str) -> AssessmentResult<()> {
    if ok {
        Ok(())
    } else {
        Err(message.into())
    }
}
fn bytes<T: Serialize>(v: &T) -> Vec<u8> {
    canonical_serde(v).to_bytes()
}
fn digest(prefix: &[u8], payload: &[u8]) -> Sha256Hex {
    let mut h = Sha256::new();
    h.update(prefix);
    h.update(payload);
    Sha256Hex::parse(h.finalize().iter().map(|b| format!("{b:02x}")).collect()).expect("SHA256")
}
fn unique<T: Serialize>(items: &[T]) -> AssessmentResult<()> {
    let mut seen = BTreeSet::new();
    for item in items {
        ensure(seen.insert(bytes(item)), "duplicate list entry")?;
    }
    Ok(())
}
fn range_valid(range: &ByteRange, size: u64) -> bool {
    range.start < range.end && range.end <= size
}
fn contains(outer: &ByteRange, inner: &ByteRange) -> bool {
    outer.start <= inner.start && inner.end <= outer.end
}

impl SourceAssessmentV1 {
    /// Strict import boundary: rejects duplicate keys before typed decoding and
    /// validates internal accounting. This does not resolve stored records.
    pub fn decode(input: &[u8]) -> AssessmentResult<Self> {
        ensure(
            input.len() <= crate::MAX_FRAME_BYTES,
            "assessment exceeds frame limit",
        )?;
        let body: Self = crate::wire::decode(input)?;
        body.validate()?;
        Ok(body)
    }
    pub fn canonical_bytes(&self) -> AssessmentResult<Vec<u8>> {
        self.validate()?;
        Ok(self.to_canonical().to_bytes())
    }
    pub fn digest(&self) -> AssessmentResult<Sha256Hex> {
        Ok(digest(b"source-assessment:v1:", &self.canonical_bytes()?))
    }
    /// Inventory digest hashes the ordered declared items. Exclusions are bound
    /// separately by the complete assessment body digest.
    pub fn inventory_digest(&self) -> AssessmentResult<Sha256Hex> {
        self.validate()?;
        Ok(digest(b"", &bytes(&self.declared_inventory)))
    }
    /// Verify bytes supplied by a trusted retained-material lookup. Lookup,
    /// access, candidate activity and assessor authentication remain external.
    pub fn verify_source_bytes(
        &self,
        lookup: impl Fn(&AssessmentVersionRef) -> Option<Vec<u8>>,
    ) -> AssessmentResult<()> {
        self.validate()?;
        for source in &self.sources {
            let raw = lookup(&source.source_version).ok_or("missing retained source bytes")?;
            let text = std::str::from_utf8(&raw).map_err(|_| "source is not UTF-8")?;
            ensure(
                raw.len() as u64 == source.byte_size
                    && bytes(&digest(b"", &raw)) == bytes(&source.blob_digest),
                "source byte binding mismatch",
            )?;
            let aligned = |r: &ByteRange| {
                text.is_char_boundary(r.start as usize) && text.is_char_boundary(r.end as usize)
            };
            for r in &source.ranges {
                ensure(aligned(r), "source range splits UTF-8")?;
            }
            for item in self
                .declared_inventory
                .iter()
                .filter(|i| i.source_key == source.key)
            {
                ensure(aligned(&item.range), "item range splits UTF-8")?;
            }
            for ex in self
                .inventory_declaration
                .exclusions
                .iter()
                .filter(|e| e.source_key == source.key)
            {
                ensure(aligned(&ex.range), "exclusion range splits UTF-8")?;
            }
        }
        Ok(())
    }
    /// Bind an externally established frozen proposal and its exact frame.
    /// No assessment identity or digest is inserted into proposal operations.
    pub fn bind_frozen_proposal(
        &self,
        proposal: &ProposalRef,
        frame: &Frame,
    ) -> AssessmentResult<Sha256Hex> {
        ensure(
            &self.proposal == proposal && bytes(&self.base_frame) == bytes(frame),
            "frozen proposal/frame mismatch",
        )?;
        self.digest()
    }
    pub fn validate(&self) -> AssessmentResult<()> {
        let encoded = bytes(self);
        ensure(
            encoded.len() <= crate::MAX_FRAME_BYTES,
            "assessment exceeds frame limit",
        )?;
        Sha256Hex::parse(self.proposal.digest.clone()).map_err(str::to_string)?;
        ensure(
            self.proposal.version > 0,
            "proposal version must be positive",
        )?;
        ensure(
            !self.sources.is_empty() && self.sources.len() <= 64,
            "source count outside limits",
        )?;
        ensure(
            self.dependencies.len() <= 16384
                && self.declared_inventory.len() <= 4096
                && self.claim_mappings.len() <= 4096
                && self.unresolved.len() <= 4096,
            "assessment list limit exceeded",
        )?;
        let timestamp = chrono::DateTime::parse_from_rfc3339(&self.assessor.assessed_at)
            .map_err(|_| "invalid assessment timestamp")?;
        ensure(
            timestamp.offset().local_minus_utc() == 0,
            "assessment timestamp must be UTC",
        )?;
        ensure(
            matches!(
                (&self.assessor.method, &self.assessor.tool),
                (Method::HumanReview, None) | (Method::ExternalModelReview, Some(_))
            ),
            "assessor method/tool mismatch",
        )?;
        let tree = serde_json::to_value(self).map_err(|e| e.to_string())?;
        fn text_limits(v: &serde_json::Value) -> AssessmentResult<()> {
            match v {
                serde_json::Value::String(s) => ensure(
                    !s.trim().is_empty() && s.len() <= 16384,
                    "empty or oversized text",
                )?,
                serde_json::Value::Array(a) => {
                    for v in a {
                        text_limits(v)?;
                    }
                }
                serde_json::Value::Object(o) => {
                    for (k, v) in o {
                        if k != "value" && k != "base_frame" {
                            text_limits(v)?;
                        }
                    }
                }
                _ => {}
            }
            Ok(())
        }
        text_limits(&tree)?;
        unique(&self.dependencies)?;
        let mut declared = BTreeSet::new();
        for dep in &self.dependencies {
            declared.insert(bytes(dep));
        }
        let mut sources = BTreeMap::new();
        for source in &self.sources {
            ensure(
                sources.insert(source.key.clone(), source).is_none(),
                "duplicate source key",
            )?;
            ensure(!source.ranges.is_empty(), "source requires ranges")?;
            unique(&source.ranges)?;
            for r in &source.ranges {
                ensure(range_valid(r, source.byte_size), "invalid source range")?;
            }
            declared.insert(bytes(&source.source_version));
            if let Some(edition) = &source.work_edition {
                declared.insert(bytes(edition));
            }
        }
        // All exact references must be explicit, same-universe and declared.
        fn references(
            v: &serde_json::Value,
            universe: &str,
            declared: &BTreeSet<Vec<u8>>,
        ) -> AssessmentResult<()> {
            match v {
                serde_json::Value::Object(o) => {
                    if o.contains_key("record") && o.contains_key("version") {
                        ensure(
                            o.get("universe").and_then(|v| v.as_str()) == Some(universe),
                            "cross-universe reference",
                        )?;
                        ensure(declared.contains(&bytes(v)), "undeclared exact reference")?;
                    }
                    for v in o.values() {
                        references(v, universe, declared)?;
                    }
                }
                serde_json::Value::Array(a) => {
                    for v in a {
                        references(v, universe, declared)?;
                    }
                }
                _ => {}
            }
            Ok(())
        }
        references(&tree, self.base_frame.universe.as_str(), &declared)?;
        ensure(
            self.base_frame
                .context
                .universe
                .as_ref()
                .is_none_or(|u| u == &self.base_frame.universe),
            "cross-universe frame context",
        )?;
        // Conflicting active references cannot be smuggled through dependencies.
        let mut active = BTreeMap::new();
        for dep in self.dependencies.iter().chain(
            self.sources
                .iter()
                .flat_map(|s| std::iter::once(&s.source_version).chain(s.work_edition.iter())),
        ) {
            let historical = self
                .claim_mappings
                .iter()
                .flat_map(|m| &m.candidate_links)
                .any(|l| {
                    l.kind == CandidateLinkKind::HistoricalEvidence
                        && bytes(&l.version) == bytes(dep)
                });
            if !historical {
                ensure(
                    active
                        .insert(dep.record.as_str(), dep.version.as_str())
                        .is_none_or(|v| v == dep.version.as_str()),
                    "conflicting active versions",
                )?;
            }
        }
        let in_scope = |key: &str, range: &ByteRange| {
            sources.get(key).is_some_and(|s| {
                range_valid(range, s.byte_size) && s.ranges.iter().any(|r| contains(r, range))
            })
        };
        let mut items = BTreeMap::new();
        for item in &self.declared_inventory {
            ensure(
                items.insert(item.item_id.as_str(), item).is_none(),
                "duplicate item ID",
            )?;
            ensure(
                in_scope(&item.source_key, &item.range),
                "inventory range outside source scope",
            )?;
            unique(&item.mapping_ids)?;
            unique(&item.unresolved_ids)?;
            ensure(
                !item.mapping_ids.is_empty() || !item.unresolved_ids.is_empty(),
                "unaccounted material item",
            )?;
        }
        unique(&self.inventory_declaration.exclusions)?;
        for ex in &self.inventory_declaration.exclusions {
            ensure(
                in_scope(&ex.source_key, &ex.range),
                "exclusion outside source scope",
            )?;
        }
        ensure(
            match self.inventory_declaration.kind {
                InventoryKind::NoMaterialClaims => {
                    items.is_empty() && self.claim_mappings.is_empty() && self.unresolved.is_empty()
                }
                InventoryKind::MaterialInventoryDeclared => !items.is_empty(),
            },
            "inventory declaration mismatch",
        )?;
        let mut mappings = BTreeMap::new();
        let mut unresolved = BTreeMap::new();
        for u in &self.unresolved {
            ensure(
                unresolved.insert(u.unresolved_id.as_str(), u).is_none(),
                "duplicate unresolved ID",
            )?;
            unique(&u.item_ids)?;
            ensure(!u.item_ids.is_empty(), "unresolved disposition lacks items")?;
            for id in &u.item_ids {
                ensure(
                    items
                        .get(id.as_str())
                        .is_some_and(|i| i.unresolved_ids.contains(&u.unresolved_id)),
                    "unresolved/item links disagree",
                )?;
            }
            let scopes: BTreeSet<_> = u
                .item_ids
                .iter()
                .map(|id| &items[id.as_str()].source_key)
                .collect();
            ensure(
                scopes.len() == 1,
                "unresolved disposition crosses source scopes",
            )?;
        }
        for m in &self.claim_mappings {
            ensure(
                mappings.insert(m.mapping_id.as_str(), m).is_none(),
                "duplicate mapping ID",
            )?;
            unique(&m.item_ids)?;
            unique(&m.referents)?;
            unique(&m.candidate_links)?;
            ensure(!m.item_ids.is_empty(), "mapping lacks items")?;
            for id in &m.item_ids {
                ensure(
                    items
                        .get(id.as_str())
                        .is_some_and(|i| i.mapping_ids.contains(&m.mapping_id)),
                    "mapping/item links disagree",
                )?;
            }
            let scope: BTreeSet<_> = m
                .item_ids
                .iter()
                .filter_map(|id| items.get(id.as_str()).map(|i| &i.source_key))
                .collect();
            ensure(scope.len() == 1, "mapping crosses source scopes")?;
            m.story_time.validate().map_err(|e| e.to_string())?;
            let unknown = matches!(m.story_time, TemporalExpression::Unspecified)
                || matches!(&m.story_time, TemporalExpression::Interval { start, end, .. } if !start.is_known() || !end.is_known())
                || matches!(m.narration_position, Position::Unknown { .. })
                || matches!(m.reader_position, Position::Unknown { .. })
                || m.occurrence == Occurrence::Unknown
                || m.modality == Modality::Unknown;
            ensure(
                !unknown || m.judgment == MappingJudgment::Unresolved,
                "unknown material must be unresolved",
            )?;
            if m.judgment == MappingJudgment::Unresolved {
                ensure(
                    m.item_ids.iter().all(|id| {
                        items[id.as_str()].unresolved_ids.iter().any(|u| {
                            unresolved
                                .get(u.as_str())
                                .is_some_and(|u| u.item_ids.contains(id))
                        })
                    }),
                    "unresolved mapping lacks disposition",
                )?;
            }
            match &m.semantic {
                SemanticMapping::Claim { value, roles, .. } => {
                    universe_domain::value::validate_value(value).map_err(|e| e.to_string())?;
                    unique(roles)?;
                }
                SemanticMapping::Action {
                    participants,
                    prerequisites,
                    effects,
                    ..
                } => {
                    unique(participants)?;
                    unique(prerequisites)?;
                    unique(effects)?;
                }
                SemanticMapping::Knowledge { acquisition, .. } => unique(acquisition)?,
                SemanticMapping::SourceDescription { implied_claims, .. } => {
                    unique(implied_claims)?
                }
            }
        }
        for item in items.values() {
            for id in &item.mapping_ids {
                ensure(
                    mappings
                        .get(id.as_str())
                        .is_some_and(|m| m.item_ids.contains(&item.item_id)),
                    "dangling mapping link",
                )?;
            }
            for id in &item.unresolved_ids {
                ensure(
                    unresolved
                        .get(id.as_str())
                        .is_some_and(|u| u.item_ids.contains(&item.item_id)),
                    "dangling unresolved link",
                )?;
            }
        }
        let contradicted = self
            .claim_mappings
            .iter()
            .any(|m| m.judgment == MappingJudgment::Contradicted);
        let pending = !self.unresolved.is_empty()
            || self
                .claim_mappings
                .iter()
                .any(|m| m.judgment == MappingJudgment::Unresolved);
        ensure(
            match self.conclusion {
                DeclaredConclusion::ConsistentWithDeclaredInventory => !contradicted && !pending,
                DeclaredConclusion::Inconsistent => contradicted,
                DeclaredConclusion::Unresolved => !contradicted && pending,
            },
            "conclusion disagrees with accounting",
        )?;
        Ok(())
    }
}
impl AssessmentEnvelope {
    pub fn verify(&self) -> AssessmentResult<()> {
        ensure(
            bytes(&self.digest) == bytes(&self.body.digest()?),
            "assessment envelope digest mismatch",
        )
    }
}

/// Acyclic final binding, independently hashed from the frozen candidate.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceValidationBindingV1 {
    pub kind: ValidationBindingKind,
    #[schemars(schema_with = "proposal_schema")]
    pub proposal: ProposalRef,
    pub base_frame: Frame,
    pub selection: AssessmentSelection,
    pub submitted_input: SubmittedInput,
    pub assessment_state: AssessmentState,
    pub execution_result_digest: Sha256Hex,
    #[schemars(length(min = 1, max = 16384))]
    pub evaluator_version: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum ValidationBindingKind {
    #[serde(rename = "source_validation_binding_v1")]
    SourceValidationBindingV1,
}
canonical_fields!(
    SourceValidationBindingV1,
    kind,
    proposal,
    base_frame,
    selection,
    submitted_input,
    assessment_state,
    execution_result_digest,
    evaluator_version
);
impl SourceValidationBindingV1 {
    pub fn digest(&self) -> AssessmentResult<Sha256Hex> {
        Sha256Hex::parse(self.proposal.digest.clone()).map_err(str::to_string)?;
        ensure(
            self.proposal.version > 0 && self.selection.proposal == self.proposal,
            "selection proposal mismatch",
        )?;
        ensure(
            !self.evaluator_version.trim().is_empty() && self.evaluator_version.len() <= 16384,
            "invalid evaluator version",
        )?;
        let input = match &self.submitted_input {
            SubmittedInput::Query { .. } => return Err("query has no proposal binding".into()),
            SubmittedInput::RecordCandidate { proposal, .. }
            | SubmittedInput::SourceAssessedCandidate { proposal, .. } => proposal,
        };
        ensure(input == &self.proposal, "submitted proposal mismatch")?;
        match &self.assessment_state {
            AssessmentState::Bound {
                assessment_reference,
                selection_generation,
                inventory_digest,
                ..
            } => {
                ensure(
                    self.selection
                        .selected
                        .as_ref()
                        .is_some_and(|s| bytes(s) == bytes(assessment_reference))
                        && *selection_generation == self.selection.generation,
                    "selected assessment mismatch",
                )?;
                ensure(
                    matches!(&self.submitted_input, SubmittedInput::SourceAssessedCandidate { inventory_digest: d, .. } if bytes(d) == bytes(inventory_digest)),
                    "bound assessment scope mismatch",
                )?;
            }
            AssessmentState::Stale {
                assessment_reference,
                ..
            } => {
                ensure(
                    self.selection
                        .selected
                        .as_ref()
                        .is_some_and(|s| bytes(s) == bytes(assessment_reference)),
                    "stale selection mismatch",
                )?;
                ensure(
                    matches!(self.submitted_input, SubmittedInput::RecordCandidate { .. }),
                    "stale assessment cannot promote scope",
                )?;
            }
            AssessmentState::Absent {} | AssessmentState::UnavailableLegacy {} => {
                ensure(
                    self.selection.selected.is_none()
                        && matches!(self.submitted_input, SubmittedInput::RecordCandidate { .. }),
                    "absent assessment selection/scope mismatch",
                )?;
            }
            AssessmentState::Unavailable { .. } => ensure(
                matches!(self.submitted_input, SubmittedInput::RecordCandidate { .. }),
                "unavailable assessment cannot promote scope",
            )?,
        }
        Ok(digest(
            b"source-validation:v1:",
            &self.to_canonical().to_bytes(),
        ))
    }
}
/// Hash the complete unpaged validation core using its owning serializer.
/// Omitted legacy fields remain omitted; the assessment wrapper is excluded.
pub fn execution_result_digest(execution: &crate::response::Validation) -> Sha256Hex {
    digest(b"", &bytes(execution))
}

/// Standalone contracts, deliberately absent from the public tool catalog.
pub fn schemas() -> serde_json::Value {
    serde_json::json!({
        "body": schemars::schema_for!(SourceAssessmentV1),
        "envelope": schemars::schema_for!(AssessmentEnvelope),
        "selection": schemars::schema_for!(AssessmentSelection),
        "binding": schemars::schema_for!(SourceValidationBindingV1),
    })
}

fn nullable_tool_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<ToolIdentity>>()
}
fn nullable_assessment_ref_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<AssessmentRef>>()
}
fn nullable_version_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<AssessmentVersionRef>>()
}
fn proposal_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    serde_json::from_value(serde_json::json!({
        "type":"object", "additionalProperties":false,
        "required":["proposal_id","version","digest"],
        "properties":{
            "proposal_id":generator.subschema_for::<universe_domain::ids::ProposalId>(),
            "version":{"type":"integer","minimum":1,"maximum":u64::MAX},
            "digest":generator.subschema_for::<Sha256Hex>(),
        }
    }))
    .expect("static schema")
}

macro_rules! canonical_enum {
    ($ty:ty, $($variant:ident => $name:literal),+ $(,)?) => {
        impl Canonical for $ty {
            fn to_canonical(&self) -> CanonicalValue {
                CanonicalValue::Str(match self { $(Self::$variant => $name),+ }.into())
            }
        }
    }
}
canonical_enum!(AssessmentKind, SourceAssessmentV1 => "source_assessment_v1");
canonical_enum!(Method, HumanReview => "human_review", ExternalModelReview => "external_model_review");
canonical_enum!(MaterialKind, Fact => "fact", Action => "action", Prerequisite => "prerequisite", Effect => "effect", Knowledge => "knowledge", Description => "description", Disclosure => "disclosure", UnchangedState => "unchanged_state");
canonical_enum!(InventoryKind, MaterialInventoryDeclared => "material_inventory_declared", NoMaterialClaims => "no_material_claims");
canonical_enum!(Occurrence, Occurred => "occurred", Planned => "planned", Hypothetical => "hypothetical", Reported => "reported", Unknown => "unknown");
canonical_enum!(Modality, Asserted => "asserted", Negated => "negated", Possible => "possible", Counterfactual => "counterfactual", Attributed => "attributed", Unknown => "unknown");
canonical_enum!(MappingJudgment, Supported => "supported", Contradicted => "contradicted", Unresolved => "unresolved");
canonical_enum!(UnresolvedReason, AmbiguousReferent => "ambiguous_referent", AmbiguousModality => "ambiguous_modality", UnsupportedSemantics => "unsupported_semantics", MissingEvidence => "missing_evidence", UnrepresentedMaterial => "unrepresented_material", InterpretationDisagreement => "interpretation_disagreement");
canonical_enum!(CandidateLinkKind, ProposedRecord => "proposed_record", UnchangedRecord => "unchanged_record", HistoricalEvidence => "historical_evidence");
canonical_enum!(Depiction, Factual => "factual", Subjective => "subjective", Inspiration => "inspiration");
canonical_enum!(ValidationBindingKind, SourceValidationBindingV1 => "source_validation_binding_v1");

macro_rules! tagged {
    ($kind:literal $(, $field:ident)*) => {
        CanonicalValue::obj(vec![("kind".into(), CanonicalValue::Str($kind.into())) $(,(stringify!($field).into(), canonical_serde($field)))*])
    }
}
impl Canonical for Position {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            Self::NotApplicable {} => tagged!("not_applicable"),
            Self::Unknown { reason } => tagged!("unknown", reason),
            Self::WorkPosition {
                work_edition,
                scene_id,
                ordinal,
            } => tagged!("work_position", work_edition, scene_id, ordinal),
        }
    }
}
impl Canonical for SemanticMapping {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            Self::Claim {
                predicate,
                subject,
                value,
                roles,
                polarity,
            } => tagged!("claim", predicate, subject, value, roles, polarity),
            Self::Action {
                action,
                participants,
                prerequisites,
                effects,
            } => tagged!("action", action, participants, prerequisites, effects),
            Self::Knowledge {
                holder,
                content,
                acquisition,
            } => tagged!("knowledge", holder, content, acquisition),
            Self::SourceDescription {
                subject,
                depiction,
                implied_claims,
            } => tagged!("source_description", subject, depiction, implied_claims),
        }
    }
}
