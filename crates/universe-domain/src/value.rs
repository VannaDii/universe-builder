//! The discriminated value type (spec §5.3).
//!
//! Arbitrary JSON is never the value model. Exact integers and decimal
//! quantities are encoded as strings at the JSON boundary when precision may
//! exceed host-language number handling. NaN, infinity, and impossible
//! rationals are rejected.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::canonical::{self, Canonical, CanonicalValue};
use crate::error::{DomainError, DomainResult};
use crate::ids::{RecordId, UnitId, UniverseId, ValueDefinitionId};
use crate::temporal::TemporalExpression;

/// A canonical record reference with an explicit universe namespace
/// (spec §27.1). The namespace may be omitted in *wire* input where the
/// required `universe` argument supplies it; the service expands and rejects
/// conflicting namespaces before storage. Canonical payloads always carry it.
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct RecordRef {
    /// Universe namespace. `None` only in wire input pending expansion.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub universe: Option<UniverseId>,
    /// Stable record identity (resolved through the requested revision's
    /// membership map — spec §27.1).
    pub record: RecordId,
}

impl RecordRef {
    pub fn new(universe: UniverseId, record: RecordId) -> Self {
        Self {
            universe: Some(universe),
            record,
        }
    }

    pub fn local(record: RecordId) -> Self {
        Self {
            universe: None,
            record,
        }
    }

    /// Expand an omitted namespace from the required request scope
    /// (spec §27.1: nested references may omit the repeated universe ID).
    /// A conflicting namespace is a structural error, never silent.
    pub fn resolve_namespace(&self, universe: &UniverseId) -> DomainResult<RecordRef> {
        match &self.universe {
            None => Ok(Self {
                universe: Some(universe.clone()),
                record: self.record.clone(),
            }),
            Some(u) if u == universe => Ok(self.clone()),
            Some(u) => Err(DomainError::CrossUniverseReference {
                kind: "record reference".into(),
                value: self.record.to_owned(),
                expected: universe.to_owned(),
                actual: u.to_owned(),
            }),
        }
    }
}

/// An exact reference to a specific immutable record *version*
/// (spec §27.1). The two reference kinds are not interchangeable:
/// record references resolve through the requested snapshot; version
/// references pin exact immutable evidence.
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct VersionRef {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub universe: Option<UniverseId>,
    pub record: RecordId,
    pub version: crate::ids::RecordVersionId,
}

/// A client-local reference used inside a single proposal batch
/// (spec §10.1, §28.4): resolved by the service into assigned persistent IDs.
#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct LocalRef {
    pub client_ref: String,
}

/// Canonical forms of the reference types bridge through serde so that a
/// reference canonicalizes identically whether called directly or nested
/// inside any payload: an omitted (`None`) universe is a *missing key*,
/// never an explicit null, in every context (spec §27.1, §27.8).
impl Canonical for RecordRef {
    fn to_canonical(&self) -> CanonicalValue {
        canonical::canonical_serde(self)
    }
}

impl Canonical for VersionRef {
    fn to_canonical(&self) -> CanonicalValue {
        canonical::canonical_serde(self)
    }
}

impl Canonical for LocalRef {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::obj(vec![(
            "clientRef".into(),
            CanonicalValue::Str(self.client_ref.clone()),
        )])
    }
}

/// The discriminated value type (spec §5.3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Value {
    /// Preserves the author's exact Unicode string content (spec §27.8).
    Text {
        text: String,
    },
    Boolean {
        value: bool,
    },
    /// Exact integers are decimal digit strings, never host floats.
    Integer {
        digits: String,
    },
    /// Exact decimal quantities, preserved at authored precision.
    Decimal {
        digits: String,
    },
    Rational {
        numerator: String,
        denominator: String,
    },
    /// `Quantity(value, unit_id)`. Conversion requires an explicit
    /// compatible unit definition (spec §5.3).
    Quantity {
        value: Box<Value>,
        unit: UnitId,
    },
    Range {
        lower: Box<Value>,
        upper: Box<Value>,
        lower_inclusive: bool,
        upper_inclusive: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        unit: Option<UnitId>,
    },
    /// Struct variants (not newtype) for the reference/expression forms:
    /// serde's internally-tagged newtype form would inline the content's
    /// fields into the tagged map (duplicate `kind` key when the content is
    /// itself tagged) and hit the recursion limit for recursive content.
    /// Field keys match the canonical impl below.
    EntityRef {
        #[serde(rename = "ref")]
        record: RecordRef,
    },
    RecordRef {
        #[serde(rename = "ref")]
        record: RecordRef,
    },
    PropositionRef {
        #[serde(rename = "ref")]
        record: RecordRef,
    },
    Temporal {
        temporal: TemporalExpression,
    },
    Spatial {
        spatial: SpatialExpression,
    },
    Enum {
        definition: ValueDefinitionId,
        key: String,
    },
    /// Ordered; authored sequence order is canonical (spec §27.2).
    Sequence {
        items: Vec<Value>,
    },
    /// Set semantics: normalized by stable identity at the service.
    Set {
        items: Vec<Value>,
    },
    Structured {
        definition: ValueDefinitionId,
        fields: BTreeMap<String, Value>,
    },
}

impl Value {
    pub fn text(s: impl Into<String>) -> Self {
        Value::Text { text: s.into() }
    }
    pub fn bool_(b: bool) -> Self {
        Value::Boolean { value: b }
    }
    pub fn record(ref_: RecordRef) -> Self {
        Value::RecordRef { record: ref_ }
    }
}

impl Eq for Value {}

impl std::hash::Hash for Value {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        // Length-prefixed canonical bytes: numeric equality never depends
        // on display formatting (spec §27.2), and distinct values cannot
        // collide on the hasher stream.
        canonical::hash_canonical(state, self);
    }
}

/// Structural validation of a `Value` (spec §5.3, §27.2).
///
/// Rejects NaN, infinity, impossible rationals, and ambiguous numeric
/// coercions. Returns the value on success.
pub fn validate_value(v: &Value) -> DomainResult<&Value> {
    match v {
        Value::Integer { digits } => {
            if !is_exact_decimal_digits(digits, false) {
                return Err(DomainError::InvalidNumeric {
                    value: digits.clone(),
                    reason: "not exact decimal digits".into(),
                });
            }
        }
        Value::Decimal { digits } => {
            if !is_exact_decimal_digits(digits, true) {
                return Err(DomainError::InvalidNumeric {
                    value: digits.clone(),
                    reason: "not a finite decimal".into(),
                });
            }
        }
        Value::Rational {
            numerator,
            denominator,
        } => {
            if !is_exact_decimal_digits(numerator, false) {
                return Err(DomainError::InvalidNumeric {
                    value: numerator.clone(),
                    reason: "numerator not exact digits".into(),
                });
            }
            if !is_exact_decimal_digits(denominator, false) || denominator == "0" {
                return Err(DomainError::InvalidNumeric {
                    value: denominator.clone(),
                    reason: "denominator must be a nonzero exact integer".into(),
                });
            }
        }
        Value::Quantity { value, .. } => {
            validate_value(value)?;
            if !matches!(
                value.as_ref(),
                Value::Integer { .. } | Value::Decimal { .. } | Value::Rational { .. }
            ) {
                return Err(DomainError::InvalidValue {
                    reason: "quantity inner value must be integer, decimal, or rational".into(),
                });
            }
        }
        Value::Range {
            lower,
            upper,
            lower_inclusive,
            upper_inclusive,
            ..
        } => {
            let _ = (lower_inclusive, upper_inclusive);
            if let (Value::Integer { digits: a }, Value::Integer { digits: b }) =
                (lower.as_ref(), upper.as_ref())
            {
                if let Some(ord) = compare_exact_digits(a, b) {
                    if ord > 0 {
                        return Err(DomainError::InvalidValue {
                            reason: "range lower exceeds upper".into(),
                        });
                    }
                }
            }
            validate_value(lower)?;
            validate_value(upper)?;
        }
        Value::Sequence { items } | Value::Set { items } => {
            if items.len() > crate::limits::MAX_SEQUENCE_ITEMS {
                return Err(DomainError::InvalidValue {
                    reason: format!(
                        "sequence exceeds bound of {} items",
                        crate::limits::MAX_SEQUENCE_ITEMS
                    ),
                });
            }
            for i in items {
                validate_value(i)?;
            }
        }
        Value::Structured { fields, .. } => {
            if fields.len() > crate::limits::MAX_STRUCTURED_FIELDS {
                return Err(DomainError::InvalidValue {
                    reason: format!(
                        "structured value exceeds bound of {} fields",
                        crate::limits::MAX_STRUCTURED_FIELDS
                    ),
                });
            }
            for f in fields.values() {
                validate_value(f)?;
            }
        }
        Value::Enum { .. } | Value::Text { .. } | Value::Boolean { .. } => {}
        Value::EntityRef { .. } | Value::RecordRef { .. } | Value::PropositionRef { .. } => {}
        Value::Temporal { temporal: t } => {
            t.validate()?;
        }
        Value::Spatial { .. } => {}
    }
    Ok(v)
}

/// `true` for exact digit strings. `allow_fraction` permits one decimal point.
/// Leading zeros are allowed (they are exact); `+`/`-` signs are allowed.
pub fn is_exact_decimal_digits(s: &str, allow_fraction: bool) -> bool {
    let bytes = s.as_bytes();
    if bytes.is_empty() || bytes.len() > crate::limits::MAX_DIGIT_RUN {
        return false;
    }
    let mut seen_digit = false;
    let mut seen_fraction = false;
    for (i, b) in bytes.iter().enumerate() {
        match b {
            b'0'..=b'9' => seen_digit = true,
            b'+' | b'-' => {
                if i != 0 {
                    return false;
                }
            }
            b'.' if allow_fraction => {
                if seen_fraction {
                    return false;
                }
                seen_fraction = true;
            }
            _ => return false,
        }
    }
    seen_digit
}

/// Magnitude of an exact integer digit string (sign removed, leading
/// zeroes trimmed) as a subslice of the input; `None` when not a plain
/// integer. Free function so input/output lifetimes elide to one.
fn magnitude_of(s: &str) -> Option<&str> {
    let bytes = s.as_bytes();
    let start = usize::from(bytes.first() == Some(&b'-'));
    let rest = &bytes[start..];
    if rest.is_empty() || !rest.iter().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let mut first_digit = start;
    while first_digit < bytes.len() && bytes[first_digit] == b'0' {
        first_digit += 1;
    }
    if first_digit == bytes.len() {
        Some("0")
    } else {
        // Safe: `first_digit` is a byte index on an ASCII-only span.
        Some(&s[first_digit..])
    }
}

/// Compare two exact decimal digit strings (integers). Returns a three-way
/// order, or `None` when either is not a plain integer.
pub fn compare_exact_digits(a: &str, b: &str) -> Option<i8> {
    let (na, nb) = match (magnitude_of(a), magnitude_of(b)) {
        (Some(x), Some(y)) => (x, y),
        _ => return None,
    };
    let sa = a.starts_with('-');
    let sb = b.starts_with('-');
    let cmp_mag = na.len().cmp(&nb.len()).then_with(|| na.cmp(nb));
    use std::cmp::Ordering;
    match (sa, sb) {
        (false, false) => match cmp_mag {
            Ordering::Equal => Some(0),
            Ordering::Less => Some(-1),
            Ordering::Greater => Some(1),
        },
        (true, true) => match cmp_mag {
            Ordering::Equal => Some(0),
            Ordering::Less => Some(1),
            Ordering::Greater => Some(-1),
        },
        (true, _) => Some(-1),
        (_, true) => Some(1),
    }
}

/// A qualitative spatial expression (spec §7.4).
///
/// Ownership, custody, containment, control, occupancy, legal access,
/// physical access, and knowledge of an entrance are separate predicates:
/// only the qualitative relations below live in values; the predicates
/// themselves are definitions.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum SpatialExpression {
    ContainedIn {
        target: RecordRef,
    },
    AdjacentTo {
        target: RecordRef,
    },
    ConnectedTo {
        target: RecordRef,
    },
    Coordinates {
        reference: String,
        values: Vec<Value>,
    },
    Distance {
        from: RecordRef,
        value: Box<Value>,
        unit: UnitId,
    },
    Unspecified,
}

impl Canonical for Value {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            Value::Text { text } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("text".into())),
                ("text".into(), CanonicalValue::Str(text.clone())),
            ]),
            Value::Boolean { value } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("boolean".into())),
                ("value".into(), CanonicalValue::Bool(*value)),
            ]),
            Value::Integer { digits } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("integer".into())),
                // Exact digit string: no host float is ever introduced.
                ("digits".into(), CanonicalValue::Str(digits.clone())),
            ]),
            Value::Decimal { digits } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("decimal".into())),
                ("digits".into(), CanonicalValue::Str(digits.clone())),
            ]),
            Value::Rational {
                numerator,
                denominator,
            } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("rational".into())),
                ("numerator".into(), CanonicalValue::Str(numerator.clone())),
                (
                    "denominator".into(),
                    CanonicalValue::Str(denominator.clone()),
                ),
            ]),
            Value::Quantity { value, unit } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("quantity".into())),
                ("value".into(), value.to_canonical()),
                ("unit".into(), CanonicalValue::Str(unit.to_owned())),
            ]),
            Value::Range {
                lower,
                upper,
                lower_inclusive,
                upper_inclusive,
                unit,
            } => CanonicalValue::obj({
                let mut f = vec![
                    ("kind".into(), CanonicalValue::Str("range".into())),
                    ("lower".into(), lower.to_canonical()),
                    (
                        "lowerInclusive".into(),
                        CanonicalValue::Bool(*lower_inclusive),
                    ),
                    ("upper".into(), upper.to_canonical()),
                    (
                        "upperInclusive".into(),
                        CanonicalValue::Bool(*upper_inclusive),
                    ),
                ];
                if let Some(u) = unit {
                    f.push(("unit".into(), CanonicalValue::Str(u.to_owned())));
                }
                f
            }),
            Value::EntityRef { record: r } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("entity_ref".into())),
                ("ref".into(), r.to_canonical()),
            ]),
            Value::RecordRef { record: r } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("record_ref".into())),
                ("ref".into(), r.to_canonical()),
            ]),
            Value::PropositionRef { record: r } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("proposition_ref".into())),
                ("ref".into(), r.to_canonical()),
            ]),
            Value::Temporal { temporal: t } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("temporal".into())),
                ("temporal".into(), t.to_canonical()),
            ]),
            Value::Spatial { spatial: s } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("spatial".into())),
                ("spatial".into(), s.to_canonical()),
            ]),
            Value::Enum { definition, key } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("enum".into())),
                (
                    "definition".into(),
                    CanonicalValue::Str(definition.to_owned()),
                ),
                ("key".into(), CanonicalValue::Str(key.clone())),
            ]),
            Value::Sequence { items } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("sequence".into())),
                (
                    "items".into(),
                    CanonicalValue::arr(items.iter().map(|v| v.to_canonical()).collect()),
                ),
            ]),
            Value::Set { items } => {
                // Sets normalize by stable identity: canonical items are
                // sorted by their canonical bytes, so the same members in
                // any authored order share one canonical form (spec §27.2,
                // §27.8). Sequences, in contrast, keep authored order.
                let mut norm = items
                    .iter()
                    .map(|v| {
                        let c = v.to_canonical();
                        (c.to_bytes(), c)
                    })
                    .collect::<Vec<_>>();
                norm.sort_by(|a, b| a.0.cmp(&b.0));
                CanonicalValue::obj(vec![
                    ("kind".into(), CanonicalValue::Str("set".into())),
                    (
                        "items".into(),
                        CanonicalValue::arr(norm.into_iter().map(|(_, c)| c).collect()),
                    ),
                ])
            }
            Value::Structured { definition, fields } => {
                let mut f = vec![
                    ("kind".into(), CanonicalValue::Str("structured".into())),
                    (
                        "definition".into(),
                        CanonicalValue::Str(definition.to_owned()),
                    ),
                ];
                let mut entries: Vec<(String, CanonicalValue)> = fields
                    .iter()
                    .map(|(k, v)| (k.clone(), v.to_canonical()))
                    .collect();
                entries.sort_by(|a, b| a.0.cmp(&b.0));
                f.push(("fields".into(), CanonicalValue::obj(entries)));
                CanonicalValue::obj(f)
            }
        }
    }
}

impl Canonical for SpatialExpression {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            SpatialExpression::ContainedIn { target } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("contained_in".into())),
                ("target".into(), target.to_canonical()),
            ]),
            SpatialExpression::AdjacentTo { target } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("adjacent_to".into())),
                ("target".into(), target.to_canonical()),
            ]),
            SpatialExpression::ConnectedTo { target } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("connected_to".into())),
                ("target".into(), target.to_canonical()),
            ]),
            SpatialExpression::Coordinates { reference, values } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("coordinates".into())),
                ("reference".into(), CanonicalValue::Str(reference.clone())),
                (
                    "values".into(),
                    CanonicalValue::arr(values.iter().map(|v| v.to_canonical()).collect()),
                ),
            ]),
            SpatialExpression::Distance { from, value, unit } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("distance".into())),
                ("from".into(), from.to_canonical()),
                ("value".into(), value.to_canonical()),
                ("unit".into(), CanonicalValue::Str(unit.to_owned())),
            ]),
            SpatialExpression::Unspecified => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("unspecified".into()),
            )]),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(rec: &str) -> RecordRef {
        RecordRef::new(
            UniverseId::parse("unv_000000000000000000000001").unwrap(),
            RecordId::parse(&format!("rec_{rec}")).unwrap(),
        )
    }

    #[test]
    fn value_round_trips_through_serde() {
        let v = Value::Quantity {
            value: Box::new(Value::Decimal {
                digits: "12.345678901234567890123456789".into(),
            }),
            unit: UnitId::parse("unit_0123456789abcdef01234567").unwrap(),
        };
        let s = serde_json::to_string(&v).unwrap();
        let back: Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v, back);
        validate_value(&v).unwrap();
    }

    #[test]
    fn large_integer_survives_without_float_coercion() {
        let v = Value::Integer {
            digits: "123456789012345678901234567890".into(),
        };
        let s = serde_json::to_string(&v).unwrap();
        let back: Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v, back);
        assert_eq!(
            back,
            Value::Integer {
                digits: "123456789012345678901234567890".into()
            }
        );
    }

    #[test]
    fn malformed_numerics_are_rejected() {
        for digits in ["", "12.3.4", "1e5", "NaN", "Infinity", "-", "12a", "1 2"] {
            assert!(!is_exact_decimal_digits(digits, true), "accepted {digits}");
        }
        assert!(matches!(
            validate_value(&Value::Rational {
                numerator: "1".into(),
                denominator: "0".into()
            }),
            Err(DomainError::InvalidNumeric { .. })
        ));
    }

    #[test]
    fn exact_digit_comparison_is_independent_of_representation() {
        assert_eq!(compare_exact_digits("007", "7"), Some(0));
        assert_eq!(compare_exact_digits("-1", "1"), Some(-1));
        assert_eq!(compare_exact_digits("120", "33"), Some(1));
        assert_eq!(compare_exact_digits("10", "9.5"), None);
    }

    #[test]
    fn false_zero_empty_and_unspecified_are_distinct_values() {
        // E07: false, zero, empty text, and *no value* (None) are four
        // distinct meanings. `Value` cannot express absence — absence is the
        // absence of a field — but the three present forms must not collide.
        let f = Value::bool_(false);
        let z = Value::Integer { digits: "0".into() };
        let e = Value::text("");
        assert_ne!(f.to_canonical(), z.to_canonical());
        assert_ne!(z.to_canonical(), e.to_canonical());
        assert_ne!(f.to_canonical(), e.to_canonical());
    }

    #[test]
    fn sequence_order_and_set_normalization_are_distinct() {
        let one = Value::Integer { digits: "1".into() };
        let two = Value::Integer { digits: "2".into() };
        let a = Value::Sequence {
            items: vec![one.clone(), two.clone()],
        };
        let b = Value::Sequence {
            items: vec![two.clone(), one.clone()],
        };
        assert_ne!(a.to_canonical(), b.to_canonical()); // sequences keep order
        let s1 = Value::Set {
            items: vec![one.clone(), two.clone()],
        };
        let s2 = Value::Set {
            items: vec![two.clone(), one.clone()],
        };
        // sets normalize by stable identity — canonical form sorts
        assert_eq!(s1.to_canonical(), s2.to_canonical());
        let _ = r("aaaaaaaaaaaaaaaaaaaaaaaa");
    }

    /// An omitted universe is a *missing key* in every context (never an
    /// explicit null): one canonical form per reference.
    #[test]
    fn record_ref_omits_universe_key_when_unresolved() {
        let rec = RecordId::parse("rec_0123456789abcdef01234567").unwrap();
        let local = RecordRef::local(rec.clone());
        let canon = local.to_canonical();
        let keys: Vec<String> = match &canon {
            CanonicalValue::Obj(fields) => fields.iter().map(|(k, _)| k.clone()).collect(),
            _ => panic!("reference must canonicalize to an object"),
        };
        assert!(keys.contains(&"record".to_string()));
        assert!(!keys.contains(&"universe".to_string()));
        // Strict round-trip: the missing key stays missing.
        let bytes = canon.to_bytes();
        assert_eq!(CanonicalValue::parse(&bytes).unwrap(), canon);
        // An explicit namespace is a distinct canonical form.
        let u = UniverseId::parse("unv_0123456789abcdef01234567").unwrap();
        let resolved = RecordRef::new(u, rec);
        assert_ne!(resolved.to_canonical(), local.to_canonical());
    }

    #[test]
    fn record_ref_namespace_resolution() {
        let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
        let u2 = UniverseId::parse("unv_000000000000000000000002").unwrap();
        let rec = RecordId::parse("rec_000000000000000000000003").unwrap();
        let open = RecordRef::local(rec.clone());
        let resolved = open.resolve_namespace(&u).unwrap();
        assert_eq!(resolved.universe, Some(u.clone()));
        let alien = RecordRef::new(u2.clone(), rec.clone());
        assert!(matches!(
            alien.resolve_namespace(&u),
            Err(DomainError::CrossUniverseReference { .. })
        ));
    }
}

/// Bounds shared across the domain (spec §11.7 initial limits).
pub mod limits {
    pub const MAX_SEQUENCE_ITEMS: usize = 1_000;
    pub const MAX_STRUCTURED_FIELDS: usize = 512;
    pub const MAX_DIGIT_RUN: usize = 1_024;
    pub const MAX_NESTED_BELIEF_DEPTH: usize = 8;
    pub const MAX_RULE_DEPTH: usize = 32;
    pub const MAX_RULE_AST_NODES: usize = 1_000;
    pub const MAX_RELATION_HOPS_DEFAULT: usize = 3;
    pub const MAX_RELATION_HOPS: usize = 6;
    pub const MAX_NAME_SCALAR_VALUES: usize = 160;
    pub const MAX_NAME_UTF8_BYTES: usize = 640;
    pub const MAX_PROPOSAL_OPERATIONS: usize = 100;
    pub const MAX_PROPOSAL_BYTES: usize = 1_048_576;
    pub const MAX_BATCH_RECORDS: usize = 50;
    pub const RESEARCH_BRIEF_DEFAULT_BYTES: usize = 24 * 1024;
    pub const RESEARCH_BRIEF_MAX_BYTES: usize = 256 * 1024;
}
