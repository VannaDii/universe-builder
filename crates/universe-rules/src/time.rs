//! Basic authored-clock validity. Unknown boundaries never become infinity.
use universe_domain::{
    frame::FrameTime,
    scope::Validity,
    temporal::{TemporalBound, TemporalExpression, TemporalRelation},
};

pub fn expression(validity: &Validity) -> Option<TemporalExpression> {
    match validity {
        Validity::Instant { at } => Some(at.clone()),
        Validity::CalendarInterval {
            calendar,
            start,
            end,
        } => Some(TemporalExpression::Interval {
            calendar: calendar.clone(),
            start: start.clone(),
            end: end.clone(),
        }),
        _ => None,
    }
}
/// None means unresolved, not false. Timeless is explicitly all validities.
pub fn applies(validity: &Validity, frame: &FrameTime) -> Option<bool> {
    match frame {
        FrameTime::Timeless => Some(true),
        FrameTime::At { time } => relation(time, TemporalRelation::During, &expression(validity)?),
        FrameTime::AtEvent { .. } => None,
    }
}
pub fn overlaps(a: &Validity, b: &Validity) -> Option<bool> {
    if matches!((a, b), (Validity::Unspecified, Validity::Unspecified)) {
        return Some(true);
    }
    relation(&expression(a)?, TemporalRelation::Overlaps, &expression(b)?)
}
/// Reject contradictory strict-before/after cycles within one declared clock.
/// No date or cross-clock conversion is synthesized by this graph check.
pub fn check_orderings(
    records: &[universe_domain::records::RecordVersion],
) -> Result<(), &'static str> {
    use std::collections::{BTreeMap, BTreeSet, VecDeque};
    use universe_domain::{
        records::Payload,
        scope::{Polarity, Precision},
        value::Value,
    };
    let mut edges = BTreeMap::new();
    let mut degree = BTreeMap::new();
    let propositions: BTreeMap<_, _> = records
        .iter()
        .filter_map(|r| {
            if let Payload::Proposition(p) = &r.payload {
                Some((r.identity.record_id.clone(), p))
            } else {
                None
            }
        })
        .collect();
    for r in records {
        let Payload::Assertion(assertion) = &r.payload else {
            continue;
        };
        if assertion.polarity != Polarity::Support
            || assertion.precision != Precision::Exact
            || !assertion.alternatives.is_empty()
        {
            continue;
        }
        let Some(p) = propositions.get(&assertion.proposition.record) else {
            continue;
        };
        let Some(Value::Temporal {
            temporal:
                TemporalExpression::Relative {
                    calendar,
                    relation,
                    target,
                },
        }) = &p.value
        else {
            continue;
        };
        if !matches!(relation, TemporalRelation::Before | TemporalRelation::After) {
            continue;
        }
        // Only combine evidence in the same declared scope, validity and predicate.
        // Mentioned propositions, negatives and independent contexts are not constraints.
        let partition = serde_json::to_string(&(
            calendar,
            &assertion.scope,
            &assertion.validity,
            &p.predicate,
        ))
        .map_err(|_| "invalid temporal scope")?;
        let mut from = (partition.clone(), p.subject.record.clone());
        let mut to = (partition, target.record.clone());
        if *relation == TemporalRelation::After {
            std::mem::swap(&mut from, &mut to);
        }
        degree.entry(from.clone()).or_insert(0usize);
        degree.entry(to.clone()).or_insert(0usize);
        if degree.len() > 10_000 {
            return Err("relative-order work budget exhausted");
        }
        if edges
            .entry(from)
            .or_insert_with(BTreeSet::new)
            .insert(to.clone())
        {
            *degree.get_mut(&to).unwrap() += 1;
        }
    }
    let mut ready: VecDeque<_> = degree
        .iter()
        .filter(|(_, d)| **d == 0)
        .map(|(n, _)| n.clone())
        .collect();
    let mut visited = 0;
    while let Some(node) = ready.pop_front() {
        visited += 1;
        for next in edges.get(&node).into_iter().flatten() {
            let n = degree.get_mut(next).unwrap();
            *n -= 1;
            if *n == 0 {
                ready.push_back(next.clone());
            }
        }
    }
    if visited != degree.len() {
        Err("strict relative ordering contains a cycle in one calendar")
    } else {
        Ok(())
    }
}
#[derive(Clone, Copy)]
struct Window {
    lo: i128,
    hi: i128,
}
fn bound(b: &TemporalBound, start: bool) -> Option<Window> {
    match b {
        TemporalBound::Exact { value } => {
            let n = value.parse::<i128>().ok()?;
            if n == i128::MIN || n == i128::MAX {
                return None;
            }
            Some(Window { lo: n, hi: n })
        }
        TemporalBound::Unbounded => {
            let n = if start { i128::MIN } else { i128::MAX };
            Some(Window { lo: n, hi: n })
        }
        TemporalBound::BoundedUncertainty { lower, upper } => {
            let (lo, hi) = (lower.parse().ok()?, upper.parse().ok()?);
            (lo <= hi && lo > i128::MIN && hi < i128::MAX).then_some(Window { lo, hi })
        }
        // An uncertainty amount needs a declared unit interpretation; do not guess.
        _ => None,
    }
}
fn windows(
    t: &TemporalExpression,
) -> Option<(&universe_domain::ids::CalendarId, Window, Window, bool)> {
    match t {
        TemporalExpression::Exact { calendar, value } => {
            let n = value.parse::<i128>().ok()?;
            if n == i128::MIN || n == i128::MAX {
                return None;
            }
            let w = Window { lo: n, hi: n };
            Some((calendar, w, w, true))
        }
        TemporalExpression::Interval {
            calendar,
            start,
            end,
        } => {
            let (a, b) = (bound(start, true)?, bound(end, false)?);
            // If any possible start is after an end, the interval is unresolved.
            (a.hi <= b.lo).then_some((calendar, a, b, false))
        }
        _ => None,
    }
}
/// Evaluate every extremal interpretation of bounded uncertainty. Agreement is
/// a definite answer; disagreement stays unknown. Work is always <=16 cases.
pub fn relation(
    left: &TemporalExpression,
    relation: TemporalRelation,
    right: &TemporalExpression,
) -> Option<bool> {
    let (ac, a, b, ap) = windows(left)?;
    let (bc, c, d, bp) = windows(right)?;
    if ac != bc {
        return None;
    }
    let mut answer = None;
    for a in [a.lo, a.hi] {
        for b in [b.lo, b.hi] {
            for c in [c.lo, c.hi] {
                for d in [d.lo, d.hi] {
                    if ap && a != b || bp && c != d {
                        continue;
                    }
                    let v = match relation {
                        TemporalRelation::Before => {
                            if ap {
                                b < c
                            } else {
                                b <= c
                            }
                        }
                        TemporalRelation::After => {
                            if bp {
                                d < a
                            } else {
                                d <= a
                            }
                        }
                        TemporalRelation::Simultaneous => ap && bp && a == c,
                        TemporalRelation::During => {
                            if bp {
                                ap && a == c
                            } else if ap {
                                c <= a && a < d
                            } else {
                                c <= a && b <= d
                            }
                        }
                        TemporalRelation::Overlaps => {
                            if ap && bp {
                                a == c
                            } else if ap {
                                c <= a && a < d
                            } else if bp {
                                a <= c && c < b
                            } else {
                                a < b && c < d && a < d && c < b
                            }
                        }
                    };
                    if answer.is_some_and(|old| old != v) {
                        return None;
                    }
                    answer = Some(v);
                }
            }
        }
    }
    answer
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn strict_order_cycles_require_positive_evidence_in_the_same_clock_and_scope() {
        use serde_json::json;
        use universe_domain::{ids::*, records::*};
        let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
        let rr = |n| json!({"universe":u,"record":format!("rec_{n:024x}")});
        let record = |n, payload: Payload| {
            RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                RecordIdentity::new(
                    u.clone(),
                    RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
                    payload.kind(),
                ),
                payload,
            )
            .unwrap()
        };
        let edge = |n, from, to, clock, polarity: &str, context| {
            vec![
            record(n,serde_json::from_value(json!({"record_kind":"proposition","predicate":rr(10),"subject":rr(from),"value":{"kind":"temporal","temporal":{"kind":"relative","calendar":cal(clock),"relation":"before","target":rr(to)}},"quantification":"particular","context":rr(context)})).unwrap()),
            record(n+100,serde_json::from_value(json!({"record_kind":"assertion","attributeMode":"instance","proposition":rr(n),"polarity":polarity,"scope":{"applicability":{"kind":"universe_wide"},"context":rr(context)},"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","basis":{"kind":"author_decision","note":"order"}})).unwrap())
        ]
        };
        let mut records = edge(20, 1, 2, 1, "support", 3);
        assert!(check_orderings(&records).is_ok());
        records.extend(edge(21, 2, 1, 1, "refutation", 3));
        assert!(check_orderings(&records).is_ok());
        records.extend(edge(22, 2, 1, 2, "support", 3));
        records.extend(edge(23, 2, 1, 1, "support", 4));
        assert!(check_orderings(&records).is_ok());
        records.extend(edge(24, 2, 1, 1, "support", 3));
        assert!(check_orderings(&records).is_err());
        records.retain(|r| matches!(r.payload, Payload::Proposition(_)));
        assert!(check_orderings(&records).is_ok());
    }
    fn cal(n: u8) -> universe_domain::ids::CalendarId {
        universe_domain::ids::CalendarId::parse(&format!("cal_{n:024x}")).unwrap()
    }
    fn at(n: i32) -> FrameTime {
        FrameTime::At {
            time: TemporalExpression::Exact {
                calendar: cal(1),
                value: n.to_string(),
            },
        }
    }
    #[test]
    fn half_open_validity_and_unknown_clock() {
        let v = Validity::CalendarInterval {
            calendar: cal(1),
            start: TemporalBound::Exact { value: "10".into() },
            end: TemporalBound::Exact { value: "20".into() },
        };
        for (n, result) in [(9, false), (10, true), (19, true), (20, false)] {
            assert_eq!(applies(&v, &at(n)), Some(result));
        }
        assert_eq!(applies(&Validity::Unspecified, &at(10)), None);
        assert_eq!(applies(&Validity::Unknown, &at(10)), None);
        assert_eq!(
            applies(
                &v,
                &FrameTime::At {
                    time: TemporalExpression::Exact {
                        calendar: cal(2),
                        value: "10".into()
                    }
                }
            ),
            None
        );
    }
    #[test]
    fn uncertain_boundary_never_silently_selects_a_date() {
        let v = Validity::CalendarInterval {
            calendar: cal(1),
            start: TemporalBound::BoundedUncertainty {
                lower: "10".into(),
                upper: "12".into(),
            },
            end: TemporalBound::Exact { value: "20".into() },
        };
        assert_eq!(applies(&v, &at(9)), Some(false));
        assert_eq!(applies(&v, &at(11)), None);
        assert_eq!(applies(&v, &at(12)), Some(true));
        let unknown = Validity::CalendarInterval {
            calendar: cal(1),
            start: TemporalBound::Unknown,
            end: TemporalBound::Unbounded,
        };
        assert_eq!(applies(&unknown, &at(12)), None);
        let forever = Validity::CalendarInterval {
            calendar: cal(1),
            start: TemporalBound::Unbounded,
            end: TemporalBound::Unbounded,
        };
        assert_eq!(applies(&forever, &at(-42)), Some(true));
    }
}
