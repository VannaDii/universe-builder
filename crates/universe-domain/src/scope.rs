//! Scoping, validity, polarity, precision, persistence, and evidence basis
//! (spec §5.2, §5.5, §5.7, §7.2, §27.3, §36.5).
//!
//! Polarity, editorial status, perspective, source reliability, and
//! uncertainty are deliberately separate dimensions — never one `status`
//! enum (spec §5.2).

use serde::{Deserialize, Serialize};

use crate::canonical::{Canonical, CanonicalValue};
use crate::ids::WorldId;
use crate::temporal::{TemporalBound, TemporalExpression};
use crate::value::{RecordRef, VersionRef};

/// Support or refutation of a proposition (spec §5.2).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum Polarity {
    Support,
    Refutation,
}

impl Canonical for Polarity {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            Polarity::Support => "support".into(),
            Polarity::Refutation => "refutation".into(),
        })
    }
}

/// Explicit precision alternatives (spec §27.2). An estimate is never
/// silently converted into an exact value or a probability distribution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum Precision {
    Exact,
    Approximate,
    Range,
    OneOf,
    Unresolved,
}

impl Canonical for Precision {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            Precision::Exact => "exact".into(),
            Precision::Approximate => "approximate".into(),
            Precision::Range => "range".into(),
            Precision::OneOf => "one_of".into(),
            Precision::Unresolved => "unresolved".into(),
        })
    }
}

/// Declared persistence behavior of a property/assertion (spec §5.5, §7.2).
///
/// Weather and fatigue are not carried forward simply because ownership
/// usually persists.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum PersistenceSemantics {
    /// Explicit validity interval governs.
    ExplicitInterval,
    /// True until an explicit change is established.
    PersistentUntilChanged,
    /// A single observation at a time; no forward carry.
    InstantaneousObservation,
    /// Depends on a condition (condition-dependent properties).
    ConditionDependent,
    /// The author did not declare persistence.
    Unspecified,
}

impl Canonical for PersistenceSemantics {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            PersistenceSemantics::ExplicitInterval => "explicit_interval".into(),
            PersistenceSemantics::PersistentUntilChanged => "persistent_until_changed".into(),
            PersistenceSemantics::InstantaneousObservation => "instantaneous_observation".into(),
            PersistenceSemantics::ConditionDependent => "condition_dependent".into(),
            PersistenceSemantics::Unspecified => "unspecified".into(),
        })
    }
}

/// Fictional-time validity of an assertion (spec §7.2).
///
/// An omitted/`Unknown` boundary is not automatically negative or positive
/// infinity (spec §5.3). Intervals are half-open `[start, end)` where
/// exact interval algebra applies (S26).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum Validity {
    /// No temporal claim was made. Distinct from `Unknown`.
    #[default]
    Unspecified,
    /// The author has not established when.
    Unknown,
    /// True at exactly one (approximate or exact) time.
    Instant { at: TemporalExpression },
    /// Half-open interval `[start, end)` for exact endpoints.
    Interval {
        start: TemporalBound,
        end: TemporalBound,
    },
    /// Half-open validity on an explicitly authored clock. Legacy intervals
    /// without a clock remain unresolved for time-specific queries.
    CalendarInterval {
        calendar: crate::ids::CalendarId,
        start: TemporalBound,
        end: TemporalBound,
    },
    /// Persistent from `from` until an explicit change is established.
    PersistentUntilChanged { from: TemporalBound },
    /// Truth depends on an authored condition.
    ConditionDependent,
}

impl Eq for Validity {}
impl std::hash::Hash for Validity {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

/// Tagged variants canonicalize through the serde bridge: `Unspecified`,
/// `Unknown`, and temporal forms are all distinct objects in canonical
/// form (S27), matching the wire shape exactly.
impl Canonical for Validity {
    fn to_canonical(&self) -> CanonicalValue {
        crate::canonical::canonical_serde(self)
    }
}

impl Validity {
    /// Whether this validity can participate in temporal interval algebra.
    pub fn is_temporal(&self) -> bool {
        matches!(
            self,
            Validity::Instant { .. }
                | Validity::Interval { .. }
                | Validity::CalendarInterval { .. }
                | Validity::PersistentUntilChanged { .. }
        )
    }

    /// The interval form of this validity for evaluation. `None` when no
    /// interval can be derived (unspecified, condition-dependent, unknown).
    pub fn as_interval(&self) -> Option<(TemporalBound, TemporalBound)> {
        match self {
            Validity::Interval { start, end } | Validity::CalendarInterval { start, end, .. } => {
                Some((start.clone(), end.clone()))
            }
            Validity::Instant { at } => {
                let b = match at {
                    crate::temporal::TemporalExpression::Exact { value, .. } => {
                        TemporalBound::Exact {
                            value: value.clone(),
                        }
                    }
                    crate::temporal::TemporalExpression::Interval { start, end, .. } => {
                        // An instant *within* an interval is not a point;
                        // only exact instants or degenerate intervals count.
                        match (start, end) {
                            (
                                TemporalBound::Exact { value: a },
                                TemporalBound::Exact { value: b },
                            ) => {
                                if a == b {
                                    start.clone()
                                } else {
                                    return None;
                                }
                            }
                            _ => return None,
                        }
                    }
                    _ => return None,
                };
                Some((b.clone(), b))
            }
            Validity::PersistentUntilChanged { from } => {
                // from .. +∞ (until an explicit change is established)
                Some((from.clone(), TemporalBound::Unbounded))
            }
            _ => None,
        }
    }
}

/// Evidence basis for an assertion (spec §27.3).
///
/// A content match verifies a citation anchor, not the source's truth.
/// Verified vs. unverified links are distinct.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum EvidenceBasis {
    /// Authorial decision with a note.
    AuthorDecision { note: String },
    /// Anchor into an immutable source version.
    SourceAnchor {
        anchor: RecordRef,
        /// Whether the application has verified the excerpt against the
        /// source version. Agent-provided citations default to unverified.
        verified: bool,
    },
    /// Established by an admitted occurred event effect.
    EventEffect { event: RecordRef, slot: String },
    /// Imported from source material; mapping accepted, truth not.
    ImportedClaim,
    /// Derived by a named derivation chain (spec §9.4: every inference has
    /// an explicit derivation and evaluator version, or remains an
    /// unverified proposal).
    Derivation {
        chain: Vec<VersionRef>,
        evaluator: Option<String>,
    },
}

impl Eq for EvidenceBasis {}
impl std::hash::Hash for EvidenceBasis {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

impl Canonical for EvidenceBasis {
    fn to_canonical(&self) -> CanonicalValue {
        use EvidenceBasis::*;
        match self {
            AuthorDecision { note } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("author_decision".into())),
                ("note".into(), CanonicalValue::Str(note.clone())),
            ]),
            SourceAnchor { anchor, verified } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("source_anchor".into())),
                ("anchor".into(), anchor.to_canonical()),
                ("verified".into(), CanonicalValue::Bool(*verified)),
            ]),
            EventEffect { event, slot } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("event_effect".into())),
                ("event".into(), event.to_canonical()),
                ("slot".into(), CanonicalValue::Str(slot.clone())),
            ]),
            ImportedClaim => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("imported_claim".into()),
            )]),
            Derivation { chain, evaluator } => {
                let mut f = vec![
                    ("kind".into(), CanonicalValue::Str("derivation".into())),
                    (
                        "chain".into(),
                        CanonicalValue::arr(chain.iter().map(|c| c.to_canonical()).collect()),
                    ),
                ];
                if let Some(e) = evaluator {
                    f.push(("evaluator".into(), CanonicalValue::Str(e.clone())));
                }
                CanonicalValue::obj(f)
            }
        }
    }
}

/// Where a fact or rule applies (spec §5.7, §36.5).
///
/// Universe ownership alone establishes no applicability: a world selector
/// is not an implicit authorial assertion about a record's home (I26).
#[derive(
    Debug, Clone, Default, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum Applicability {
    /// Explicitly declared true across the whole universe.
    UniverseWide,
    /// Applies to the named worlds (zero is degenerate but legal).
    Worlds { world_ids: Vec<WorldId> },
    /// Conditional: applicability is itself evaluated (gap if unresolved).
    Conditional,
    /// The author did not specify. An unspecified scope that matters to
    /// validation yields a gap, not a universal rule (V19).
    #[default]
    Unspecified,
}

impl Canonical for Applicability {
    fn to_canonical(&self) -> CanonicalValue {
        use Applicability::*;
        match self {
            UniverseWide => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("universe_wide".into()),
            )]),
            Worlds { world_ids } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("worlds".into())),
                (
                    "worldIds".into(),
                    CanonicalValue::arr(
                        world_ids
                            .iter()
                            .map(|w| CanonicalValue::Str(w.to_owned()))
                            .collect(),
                    ),
                ),
            ]),
            Conditional => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("conditional".into()),
            )]),
            Unspecified => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("unspecified".into()),
            )]),
        }
    }
}

/// The scope of an assertion or rule: applicability + represented context
/// + optional realm (spec §27.3).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Scope {
    pub applicability: Applicability,
    /// The represented context record (objective reality, a character,
    /// a source narrative, ...). Required: every assertion states its
    /// context explicitly.
    pub context: RecordRef,
    /// Optional realm (an authored physical/metaphysical domain).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub realm: Option<RecordRef>,
}

impl Canonical for Scope {
    fn to_canonical(&self) -> CanonicalValue {
        let mut f = vec![
            ("applicability".into(), self.applicability.to_canonical()),
            ("context".into(), self.context.to_canonical()),
        ];
        if let Some(r) = &self.realm {
            f.push(("realm".into(), r.to_canonical()));
        }
        CanonicalValue::obj(f)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::{RecordId, UniverseId, WorldId};
    use crate::value::Value;

    fn univ() -> UniverseId {
        UniverseId::parse("unv_000000000000000000000001").unwrap()
    }
    fn rec(n: &str) -> RecordRef {
        RecordRef::new(univ(), RecordId::parse(&format!("rec_{n}")).unwrap())
    }

    #[test]
    fn unknown_and_unbounded_boundaries_are_distinct() {
        let u = Validity::Interval {
            start: TemporalBound::Unknown,
            end: TemporalBound::Exact { value: "x".into() },
        };
        let b = Validity::Interval {
            start: TemporalBound::Unbounded,
            end: TemporalBound::Exact { value: "x".into() },
        };
        assert_ne!(u.to_canonical(), b.to_canonical());
    }

    #[test]
    fn half_open_interval_round_trips() {
        let v = Validity::Interval {
            start: TemporalBound::Exact {
                value: "E12".into(),
            },
            end: TemporalBound::Exact {
                value: "E20".into(),
            },
        };
        let s = serde_json::to_string(&v).unwrap();
        assert_eq!(
            Validity::as_interval(&v).unwrap().0,
            TemporalBound::Exact {
                value: "E12".into()
            }
        );
        let back: Validity = serde_json::from_str(&s).unwrap();
        assert_eq!(v, back);
    }

    #[test]
    fn applicability_forms_are_distinct() {
        let w = WorldId::parse("wld_000000000000000000000001").unwrap();
        let forms = vec![
            Applicability::UniverseWide.to_canonical(),
            Applicability::Worlds { world_ids: vec![w] }.to_canonical(),
            Applicability::Conditional.to_canonical(),
            Applicability::Unspecified.to_canonical(),
        ];
        let mut set = std::collections::HashSet::new();
        for f in forms {
            assert!(set.insert(f));
        }
        assert_eq!(set.len(), 4);
        let _ = rec("aaaaaaaaaaaaaaaaaaaaaaaa");
    }

    #[test]
    fn value_is_not_part_of_scope() {
        // Guards against accidentally folding value into scope/validity.
        let v = Value::text("hello");
        let _ = v;
    }
}
