//! Reporting axes. Engine completion is never a manuscript continuity certificate.
use crate::{
    request::{CheckScope, ProposalRef},
    response::{OperationStatus, Validation},
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use universe_domain::{
    ids::{RecordId, RecordVersionId, UniverseId},
    Frame,
};

fn required_nullable<'de, D: serde::Deserializer<'de>, T: Deserialize<'de>>(
    d: D,
) -> Result<Option<T>, D::Error> {
    Option::<T>::deserialize(d)
}

fn nullable_digest_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<Sha256Hex>>()
}

/// Owning decoder enforces the same exact digest shape as the JSON schema.
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(transparent)]
pub struct Sha256Hex(#[schemars(regex(pattern = r"^[0-9a-f]{64}$"))] String);
impl Sha256Hex {
    pub fn parse(value: String) -> Result<Self, &'static str> {
        if value.len() == 64
            && value
                .bytes()
                .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        {
            Ok(Self(value))
        } else {
            Err("expected 64 lower-case hexadecimal characters")
        }
    }
}
impl<'de> Deserialize<'de> for Sha256Hex {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        Self::parse(String::deserialize(d)?).map_err(serde::de::Error::custom)
    }
}

/// Exact workflow evidence references use the existing domain wire keys and IDs.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AssessmentVersionRef {
    pub universe: UniverseId,
    pub record: RecordId,
    pub version: RecordVersionId,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ByteRange {
    pub start: u64,
    pub end: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum SourceRepresentation {
    #[serde(rename = "exact-utf8-v1")]
    ExactUtf8V1,
}
fn nullable_version_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<AssessmentVersionRef>>()
}
fn nullable_string_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    generator.subschema_for::<Option<String>>()
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceBinding {
    pub key: String,
    pub source_version: AssessmentVersionRef,
    pub blob_digest: Sha256Hex,
    pub byte_size: u64,
    pub representation: SourceRepresentation,
    pub ranges: Vec<ByteRange>,
    #[serde(deserialize_with = "required_nullable")]
    #[schemars(required, schema_with = "nullable_version_schema")]
    pub work_edition: Option<AssessmentVersionRef>,
    #[serde(deserialize_with = "required_nullable")]
    #[schemars(required, schema_with = "nullable_string_schema")]
    pub passage_id: Option<String>,
}
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(transparent)]
pub struct AssessmentId(#[schemars(regex(pattern = r"^asm_[0-9a-f]{24}$"))] String);
impl<'de> Deserialize<'de> for AssessmentId {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let value = String::deserialize(d)?;
        if value.len() == 28
            && value.starts_with("asm_")
            && value[4..]
                .bytes()
                .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        {
            Ok(Self(value))
        } else {
            Err(serde::de::Error::custom(
                "expected asm_ plus 24 lower-case hex characters",
            ))
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AssessmentRef {
    pub assessment_id: AssessmentId,
    pub digest: Sha256Hex,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum DeclaredConclusion {
    ConsistentWithDeclaredInventory,
    Inconsistent,
    Unresolved,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ByteVerification {
    Verified,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum StaleReason {
    CandidateChanged,
    SourceChanged,
    EditionChanged,
    DependencyChanged,
    SelectionChanged,
    EvaluatorChanged,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum UnavailableReason {
    MissingRetainedMaterial,
    UnsupportedRepresentation,
    FailedOrCancelledCheck,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum SubmittedInput {
    Query {
        frame: Frame,
        check_scope: CheckScope,
    },
    RecordCandidate {
        proposal: ProposalRef,
        includes_sources: bool,
    },
    SourceAssessedCandidate {
        proposal: ProposalRef,
        sources: Vec<SourceBinding>,
        inventory_digest: Sha256Hex,
    },
}
/// Assessment declarations are bound to verified recorded evidence and exact
/// selection generations; execution coverage remains a separate reporting axis.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum AssessmentState {
    Absent {},
    UnavailableLegacy {},
    Unavailable {
        reason: UnavailableReason,
    },
    Stale {
        assessment_reference: AssessmentRef,
        reasons: Vec<StaleReason>,
    },
    Bound {
        assessment_reference: AssessmentRef,
        selection_generation: u64,
        byte_verification: ByteVerification,
        declared_conclusion: DeclaredConclusion,
        inventory_count: u64,
        mapping_count: u64,
        unresolved_count: u64,
        inventory_digest: Sha256Hex,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum RestrictedCoverage {
    Restricted,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum RestrictedInput {
    Restricted {},
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum RestrictedAssessment {
    Restricted {},
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum ValidationV3 {
    Evaluated {
        execution: Validation,
        submitted_input: SubmittedInput,
        assessment: AssessmentState,
        #[serde(deserialize_with = "required_nullable")]
        #[schemars(required, schema_with = "nullable_digest_schema")]
        final_binding_digest: Option<Sha256Hex>,
    },
    Restricted {
        execution_coverage: RestrictedCoverage,
        submitted_input: RestrictedInput,
        assessment: RestrictedAssessment,
    },
}
impl ValidationV3 {
    pub fn restricted() -> Self {
        Self::Restricted {
            execution_coverage: RestrictedCoverage::Restricted,
            submitted_input: RestrictedInput::Restricted {},
            assessment: RestrictedAssessment::Restricted {},
        }
    }
    pub fn execution(&self) -> Option<&Validation> {
        match self {
            Self::Evaluated { execution, .. } => Some(execution),
            Self::Restricted { .. } => None,
        }
    }
}
/// Public operation view; durable v2 operation bytes retain their original shape.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OperationStatusV3 {
    pub validation: Option<Box<ValidationV3>>,
    pub failure: Option<String>,
    pub operation_id: universe_domain::ids::OperationId,
    pub kind: crate::request::OperationKind,
    pub state: crate::response::OperationState,
    pub proposal: Option<crate::response::Proposal>,
    pub receipt: Option<crate::response::CommitReceipt>,
    pub cancellation_requested: bool,
}
impl OperationStatusV3 {
    pub fn from_stored(s: OperationStatus, validation: Option<ValidationV3>) -> Self {
        Self {
            validation: validation.map(Box::new),
            failure: s.failure,
            operation_id: s.operation_id,
            kind: s.kind,
            state: s.state,
            proposal: s.proposal,
            receipt: s.receipt,
            cancellation_requested: s.cancellation_requested,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    fn restricted_fixture() -> Value {
        serde_json::from_str::<Value>(include_str!(
            "../../../fixtures/validation-scope/expected.json"
        ))
        .unwrap()["restricted"]
            .clone()
    }
    #[test]
    fn restricted_matches_independent_fixture_and_rejects_disclosure() {
        let expected = restricted_fixture();
        assert_eq!(
            serde_json::to_value(ValidationV3::restricted()).unwrap(),
            expected
        );
        for key in [
            "execution",
            "run_id",
            "input_digest",
            "proposal",
            "source_id",
            "assessment_reference",
            "final_binding_digest",
            "inventory_count",
            "reason",
            "cursor",
        ] {
            let mut bad = expected.clone();
            bad[key] = json!("private");
            assert!(
                serde_json::from_value::<ValidationV3>(bad).is_err(),
                "{key}"
            );
        }
        for key in ["submitted_input", "assessment"] {
            let mut bad = expected.clone();
            bad[key]["digest"] = json!("private");
            assert!(serde_json::from_value::<ValidationV3>(bad).is_err());
        }
    }
    #[test]
    fn legacy_wire_shape_is_not_silently_upgraded() {
        assert!(serde_json::from_value::<ValidationV3>(json!({"run_id":"run_000000000000000000000001","coverage":"complete","findings":[],"unsupported_capabilities":[],"input_digest":"private","evaluator_version":"v2"})).is_err());
    }
    #[test]
    fn approved_query_fixture_requires_explicit_nullable_binding() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../docs/decisions/d03-d08/examples.json"
        ))
        .unwrap();
        let query = fixture["query_result"].clone();
        let parsed: ValidationV3 = serde_json::from_value(query.clone()).unwrap();
        assert!(parsed.execution().is_some());
        let mut missing = query.clone();
        missing
            .as_object_mut()
            .unwrap()
            .remove("final_binding_digest");
        assert!(serde_json::from_value::<ValidationV3>(missing).is_err());
        let mut bad = query;
        bad["final_binding_digest"] = json!("not-a-digest");
        assert!(serde_json::from_value::<ValidationV3>(bad).is_err());
    }
    #[test]
    fn approved_assessed_reporting_fixture_decodes_without_enabling_submission() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../docs/decisions/d03-d08/examples.json"
        ))
        .unwrap();
        let assessed = fixture["validation_v3"].clone();
        let parsed: ValidationV3 = serde_json::from_value(assessed.clone()).unwrap();
        assert_eq!(serde_json::to_value(parsed).unwrap(), assessed);
        let mut bad = assessed;
        bad["submitted_input"]["sources"][0]["source_version"]
            .as_object_mut()
            .unwrap()
            .remove("universe");
        assert!(serde_json::from_value::<ValidationV3>(bad).is_err());
    }
    #[test]
    fn exact_digest_decoder() {
        assert!(Sha256Hex::parse("a".repeat(64)).is_ok());
        for bad in ["A".repeat(64), "0".repeat(63), "g".repeat(64)] {
            assert!(Sha256Hex::parse(bad).is_err());
        }
    }
}
