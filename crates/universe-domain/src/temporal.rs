//! Temporal expressions and clocks (spec §7.1).
//!
//! Fictional time, personal experienced sequence, narration time,
//! narrative position, and editorial time are separate concepts. Editorial
//! time (RFC3339 UTC strings on commits) never appears here.
//!
//! Two worlds in one universe do not automatically share clocks: a
//! `TemporalExpression` always names its calendar/reference system, and
//! comparisons across calendars require an authored conversion definition
//! (spec §7.4, §7.5).

use serde::{Deserialize, Serialize};

use crate::canonical::{Canonical, CanonicalValue};
use crate::error::{DomainError, DomainResult};
use crate::ids::CalendarId;
use crate::value::{limits, RecordRef};

/// How a boundary of an interval is known (spec §27.2).
///
/// `Unknown` and `Unbounded` are deliberately distinct (S27): an undefined
/// endpoint is not silently infinite or zero-length.
#[derive(
    Debug, Clone, Default, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum TemporalBound {
    /// No bound: the interval extends without limit in that direction.
    Unbounded,
    /// The author has not established the endpoint.
    #[default]
    Unknown,
    /// Exact point, as a string in the named calendar's unit structure.
    Exact { value: String },
    /// Approximate point with declared uncertainty.
    Approximate {
        value: String,
        /// Boxed: `Value` may embed `TemporalExpression`, so one side of
        /// the mutual recursion must be indirect (infinite-size rule).
        uncertainty: Box<crate::value::Value>,
    },
    /// Bounded but not exact: the endpoint lies within this range of points.
    BoundedUncertainty { lower: String, upper: String },
}

impl TemporalBound {
    pub fn is_known(&self) -> bool {
        !matches!(self, TemporalBound::Unknown)
    }
}

/// A relation between two times without inventing dates (spec §7.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum TemporalRelation {
    /// Strict before. Cycles within one declared acyclic ordering are invalid (S28).
    Before,
    /// Strict after.
    After,
    /// Starts and ends within.
    During,
    /// Time ranges overlap (may be definite, indeterminate, or refuted).
    Overlaps,
    /// Same instant (exact only).
    Simultaneous,
}

/// The temporal value type (spec §5.3, §7.1).
///
/// Intervals are half-open `[start, end)` where exact interval algebra
/// applies (spec §7.1); the author-facing display must explain boundary
/// meaning (S26).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum TemporalExpression {
    /// Exact instant in a named calendar.
    Exact { calendar: CalendarId, value: String },
    /// Interval. Where both endpoints are exact, semantics are half-open
    /// `[start, end)`.
    Interval {
        calendar: CalendarId,
        start: TemporalBound,
        end: TemporalBound,
    },
    /// Approximate moment ("about ten days in" is not an exact ten-day
    /// duration without an author definition — spec §5.3).
    Approximate {
        calendar: CalendarId,
        value: String,
        /// Boxed: breaks the `Value` ↔ `TemporalExpression` recursion.
        uncertainty: Box<crate::value::Value>,
    },
    /// A duration in the calendar's own unit structure.
    Duration {
        calendar: CalendarId,
        /// Boxed: breaks the `Value` ↔ `TemporalExpression` recursion.
        amount: Box<crate::value::Value>,
    },
    /// Relative ordering constraint against another record's time.
    Relative {
        calendar: CalendarId,
        relation: TemporalRelation,
        target: RecordRef,
    },
    /// No temporal claim: the author did not define one.
    Unspecified,
}

impl TemporalExpression {
    /// Structural validation: bounds must be internally consistent
    /// (spec §7.1: strict order cycles are invalid; unknown vs. unbounded
    /// must be distinguishable; lengths bounded).
    pub fn validate(&self) -> DomainResult<()> {
        use TemporalExpression::*;
        match self {
            Exact { value, .. } => check_temporal_value(value)?,
            Interval { start, end, .. } => {
                if let TemporalBound::Exact { value } = start {
                    check_temporal_value(value)?;
                }
                if let TemporalBound::Exact { value } = end {
                    check_temporal_value(value)?;
                }
                // An interval whose exact endpoints are equal is the
                // degenerate empty interval; that is legal (a zero-length
                // claim), not an error.
            }
            Approximate {
                value, uncertainty, ..
            } => {
                check_temporal_value(value)?;
                crate::value::validate_value(uncertainty)?;
            }
            Duration { amount, .. } => {
                crate::value::validate_value(amount)?;
            }

            Relative { .. } => {}
            Unspecified => {}
        }
        Ok(())
    }

    /// Whether this expression carries enough information to support
    /// exact temporal comparison.
    pub fn is_exact(&self) -> bool {
        matches!(
            self,
            TemporalExpression::Exact { .. } | TemporalExpression::Duration { .. }
        )
    }
}

fn check_temporal_value(v: &str) -> DomainResult<()> {
    if v.is_empty() || v.len() > limits::MAX_NAME_UTF8_BYTES {
        return Err(DomainError::InvalidTemporal {
            reason: "empty or oversized calendar value".into(),
        });
    }
    if v.chars().any(|c| c.is_control()) {
        return Err(DomainError::InvalidTemporal {
            reason: "calendar value contains control characters".into(),
        });
    }
    Ok(())
}

impl Eq for TemporalExpression {}
impl std::hash::Hash for TemporalExpression {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

impl Canonical for TemporalBound {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            TemporalBound::Unbounded => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("unbounded".into()),
            )]),
            TemporalBound::Unknown => {
                CanonicalValue::obj(vec![("kind".into(), CanonicalValue::Str("unknown".into()))])
            }
            TemporalBound::Exact { value } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("exact".into())),
                ("value".into(), CanonicalValue::Str(value.clone())),
            ]),
            TemporalBound::Approximate { value, uncertainty } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("approximate".into())),
                ("value".into(), CanonicalValue::Str(value.clone())),
                ("uncertainty".into(), uncertainty.to_canonical()),
            ]),
            TemporalBound::BoundedUncertainty { lower, upper } => CanonicalValue::obj(vec![
                (
                    "kind".into(),
                    CanonicalValue::Str("bounded_uncertainty".into()),
                ),
                ("lower".into(), CanonicalValue::Str(lower.clone())),
                ("upper".into(), CanonicalValue::Str(upper.clone())),
            ]),
        }
    }
}

impl Canonical for TemporalRelation {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            TemporalRelation::Before => "before".into(),
            TemporalRelation::After => "after".into(),
            TemporalRelation::During => "during".into(),
            TemporalRelation::Overlaps => "overlaps".into(),
            TemporalRelation::Simultaneous => "simultaneous".into(),
        })
    }
}

impl Canonical for TemporalExpression {
    fn to_canonical(&self) -> CanonicalValue {
        use TemporalExpression::*;
        match self {
            Exact { calendar, value } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("exact".into())),
                ("calendar".into(), CanonicalValue::Str(calendar.to_owned())),
                ("value".into(), CanonicalValue::Str(value.clone())),
            ]),
            Interval {
                calendar,
                start,
                end,
            } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("interval".into())),
                ("calendar".into(), CanonicalValue::Str(calendar.to_owned())),
                ("start".into(), start.to_canonical()),
                ("end".into(), end.to_canonical()),
            ]),
            Approximate {
                calendar,
                value,
                uncertainty,
            } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("approximate".into())),
                ("calendar".into(), CanonicalValue::Str(calendar.to_owned())),
                ("value".into(), CanonicalValue::Str(value.clone())),
                ("uncertainty".into(), uncertainty.to_canonical()),
            ]),
            Duration { calendar, amount } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("duration".into())),
                ("calendar".into(), CanonicalValue::Str(calendar.to_owned())),
                ("amount".into(), amount.to_canonical()),
            ]),
            Relative {
                calendar,
                relation,
                target,
            } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("relative".into())),
                ("calendar".into(), CanonicalValue::Str(calendar.to_owned())),
                ("relation".into(), relation.to_canonical()),
                ("target".into(), target.to_canonical()),
            ]),
            Unspecified => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("unspecified".into()),
            )]),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::RecordId;

    fn cal() -> CalendarId {
        CalendarId::from_id(RecordId::parse("rec_000000000000000000000001").unwrap()).unwrap()
    }

    #[test]
    fn undefined_endpoint_is_not_unbounded() {
        let t = TemporalExpression::Interval {
            calendar: cal(),
            start: TemporalBound::Unknown,
            end: TemporalBound::Exact {
                value: "day-20".into(),
            },
        };
        t.validate().unwrap();
        // S27: unknown endpoint must round-trip distinctly from unbounded.
        let a = t.to_canonical();
        let b = TemporalExpression::Interval {
            calendar: cal(),
            start: TemporalBound::Unbounded,
            end: TemporalBound::Exact {
                value: "day-20".into(),
            },
        }
        .to_canonical();
        assert_ne!(a, b);
    }

    #[test]
    fn interval_round_trips() {
        let t = TemporalExpression::Interval {
            calendar: cal(),
            start: TemporalBound::Exact {
                value: "E12".into(),
            },
            end: TemporalBound::Exact {
                value: "E20".into(),
            },
        };
        let s = serde_json::to_string(&t).unwrap();
        let back: TemporalExpression = serde_json::from_str(&s).unwrap();
        assert_eq!(t, back);
        assert_eq!(t.to_canonical(), back.to_canonical());
    }

    #[test]
    fn cross_calendar_values_are_not_comparable_implicitly() {
        // Two calendars with same-looking labels remain distinct expressions.
        let c1 = cal();
        let c2 = CalendarId::from_id(
            crate::ids::RecordId::parse("rec_000000000000000000000002").unwrap(),
        )
        .unwrap();
        let a = TemporalExpression::Exact {
            calendar: c1,
            value: "Day 3".into(),
        };
        let b = TemporalExpression::Exact {
            calendar: c2,
            value: "Day 3".into(),
        };
        assert_ne!(a.to_canonical(), b.to_canonical());
    }
}
