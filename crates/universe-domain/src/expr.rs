//! The versioned declarative rule expression language (spec §9.4, §31.1).
//!
//! The AST lives in the domain crate so event payloads can carry
//! preconditions/effects and the `universe-rules` crate can compile and
//! evaluate them without a domain→rules dependency cycle (ADR-0001).
//!
//! v1 operator families (spec §9.4):
//! - equality/inequality with defined exact or interval comparisons
//! - numeric comparisons on unit-compatible quantities
//! - boolean composition with unknown/conflict propagation (§31.2)
//! - temporal relations with indeterminate results when unresolved
//! - membership and cardinality (negative conclusions require completeness)
//! - existence (missing matches alone do not prove absence)
//! - bounded reference traversal
//! - preconditions and effects
//!
//! Excluded: arbitrary functions, SQL, shell, unbounded recursion, general
//! theorem proving, negation-as-failure over incomplete data (§9.4).

use serde::{Deserialize, Serialize};

use crate::canonical::{Canonical, CanonicalValue};
use crate::error::{DomainError, DomainResult};
use crate::ids::{RecordId, UniverseId};
use crate::scope::Polarity;
use crate::temporal::TemporalRelation;
use crate::value::{limits, RecordRef, Value};

/// A named binding in an expression environment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum Quantifier {
    ForAll,
    Exists,
}

/// Three-way comparator for numeric and exact comparisons.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum Comparator {
    Eq,
    Neq,
    Lt,
    LtEq,
    Gt,
    GtEq,
}

impl Canonical for Comparator {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            Comparator::Eq => "eq".into(),
            Comparator::Neq => "neq".into(),
            Comparator::Lt => "lt".into(),
            Comparator::LtEq => "lte".into(),
            Comparator::Gt => "gt".into(),
            Comparator::GtEq => "gte".into(),
        })
    }
}

/// An operand of an expression node.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum Operand {
    /// A variable bound by the rule scope or a quantifier.
    Variable {
        name: String,
    },
    /// Struct variants keep one canonical form per operand: the referenced
    /// record/value is nested under a named key, never inlined into the
    /// tagged map (see `Canonical for Operand` below).
    Record {
        #[serde(rename = "ref")]
        record: RecordRef,
    },
    Value {
        value: Value,
    },
    /// The frame's current time (a temporal operand).
    FrameTime,
    /// A participant of the candidate event, by role.
    EventParticipant {
        role: String,
    },
    /// The occurrence of the candidate event itself.
    EventRef,
}

impl Eq for Operand {}
impl std::hash::Hash for Operand {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

impl Canonical for Operand {
    fn to_canonical(&self) -> CanonicalValue {
        use Operand::*;
        match self {
            Variable { name } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("variable".into())),
                ("name".into(), CanonicalValue::Str(name.clone())),
            ]),
            Record { record: r } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("record".into())),
                ("ref".into(), r.to_canonical()),
            ]),
            Value { value: v } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("value".into())),
                ("value".into(), v.to_canonical()),
            ]),
            FrameTime => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("frame_time".into()),
            )]),
            EventParticipant { role } => CanonicalValue::obj(vec![
                (
                    "kind".into(),
                    CanonicalValue::Str("event_participant".into()),
                ),
                ("role".into(), CanonicalValue::Str(role.clone())),
            ]),
            EventRef => CanonicalValue::obj(vec![(
                "kind".into(),
                CanonicalValue::Str("event_ref".into()),
            )]),
        }
    }
}

/// The declarative expression tree (spec §9.4).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields, tag = "kind", rename_all = "snake_case")]
pub enum Expr {
    /// Scoped absence of opposing evidence in this exact candidate; never a truth claim.
    NoOpposingEvidence {
        subject: Operand,
        predicate: String,
        context: Operand,
    },
    /// Authored attitude evidence only; observation/presence never implies knowledge.
    Attitude {
        holder: crate::value::RecordRef,
        proposition: crate::value::RecordRef,
        attitude: crate::records::EpistemicAttitudeKind,
    },
    /// `true` / `false` literals (boolean composition — spec §9.4).
    ///
    /// Struct variants (not newtype) for all boolean forms: serde's
    /// internally-tagged newtype representation wraps the serializer in a
    /// new `TaggedSerializer` per recursion level (recursion limit), and
    /// would emit a duplicate `kind` key when the content is itself tagged.
    /// Field names match the canonical impl below.
    Lit {
        value: bool,
    },
    Not {
        expr: Box<Expr>,
    },
    /// All children must hold (`and` with unknown/conflict propagation).
    All {
        exprs: Vec<Expr>,
    },
    /// At least one child holds (`or`).
    Any {
        exprs: Vec<Expr>,
    },

    /// A claim about the state in the current frame: is `subject` related
    /// to `predicate`/`value` (or `roles` for n-ary relations) with
    /// `polarity` in `context`? Evaluates to the two evidence bits.
    Claim {
        subject: Operand,
        /// Namespaced property or relation key, resolved to a definition
        /// record at compile time (spec §27.2).
        predicate: String,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        roles: Vec<(String, Operand)>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        value: Option<Operand>,
        polarity: Polarity,
        /// The represented context of the claim; `None` = the frame's
        /// context.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        context: Option<Operand>,
    },

    /// Negation of a state claim: the refutation side of the same evidence.
    /// (Provided for rule authoring convenience; `Not(claim)` is equivalent.)
    NegatedClaim {
        subject: Operand,
        predicate: String,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        roles: Vec<(String, Operand)>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        value: Option<Operand>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        context: Option<Operand>,
    },

    /// Equality/inequality of two operands with defined comparisons
    /// (spec §9.4). Exact values compare exactly; quantities require
    /// unit-compatible definitions; intervals only when definite.
    Compare {
        left: Operand,
        op: Comparator,
        right: Operand,
    },

    /// Temporal relation between two time-bearing operands
    /// (spec §9.4). Indeterminate when the data cannot decide it.
    Temporal {
        left: Operand,
        relation: TemporalRelation,
        right: Operand,
    },

    /// Membership of an element in a finite collection. Refutation of
    /// membership additionally requires the collection to be complete
    /// (spec §9.4).
    Membership {
        element: Operand,
        collection: Operand,
        /// Whether the collection is declared complete in the frame.
        /// `None` = unknown completeness (negative result is indeterminate).
        complete: Option<bool>,
    },

    /// Cardinality of a finite collection (spec §9.4). Negative
    /// conclusions require completeness.
    Cardinality {
        collection: Operand,
        op: Comparator,
        count: Value,
        complete: Option<bool>,
    },

    /// Existence of at least one matching state claim (spec §9.4):
    /// positive evidence only.
    Existence {
        subject: Operand,
        predicate: String,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        roles: Vec<(String, Operand)>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        value: Option<Operand>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        context: Option<Operand>,
    },

    /// Bounded quantification over a collection (spec §9.4, §31.2):
    /// one witness establishes existence even if incomplete; a universal
    /// over an incomplete domain cannot be proved.
    Quantify {
        variable: String,
        over: Operand,
        complete: bool,
        quantifier: Quantifier,
        body: Box<Expr>,
    },

    /// Bounded traversal of a declared relationship role (spec §9.4).
    /// The traversed record is bound as the result of this node for
    /// composition (used inside larger expressions via variables in
    /// practice; the node itself is a structural check that the relation
    /// holds).
    RoleHolds {
        subject: Operand,
        predicate: String,
        role: String,
        participant: Operand,
    },
    // Exception application is *not* an expression node: exceptions are
    // evaluated by the validator with exact rule, scope, validity, and
    // authorizing decision (spec §9.4, §31.3). Kept out of the tree.
}

impl Eq for Expr {}
impl std::hash::Hash for Expr {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

impl Canonical for Quantifier {
    fn to_canonical(&self) -> CanonicalValue {
        CanonicalValue::Str(match self {
            Quantifier::ForAll => "forall".into(),
            Quantifier::Exists => "exists".into(),
        })
    }
}

impl Canonical for Expr {
    fn to_canonical(&self) -> CanonicalValue {
        use Expr::*;
        let kind = |s: &str| CanonicalValue::Str(s.to_string());
        match self {
            NoOpposingEvidence { .. } | Attitude { .. } => crate::canonical::canonical_serde(self),
            Lit { value: b } => CanonicalValue::obj(vec![
                ("kind".into(), kind("lit")),
                ("value".into(), CanonicalValue::Bool(*b)),
            ]),
            Not { expr: e } => CanonicalValue::obj(vec![
                ("kind".into(), kind("not")),
                ("expr".into(), e.to_canonical()),
            ]),
            All { exprs: items } => CanonicalValue::obj(vec![
                ("kind".into(), kind("all")),
                (
                    "exprs".into(),
                    CanonicalValue::arr(items.iter().map(|e| e.to_canonical()).collect()),
                ),
            ]),
            Any { exprs: items } => CanonicalValue::obj(vec![
                ("kind".into(), kind("any")),
                (
                    "exprs".into(),
                    CanonicalValue::arr(items.iter().map(|e| e.to_canonical()).collect()),
                ),
            ]),
            Claim {
                subject,
                predicate,
                roles,
                value,
                polarity,
                context,
            } => {
                let mut f = vec![
                    ("kind".into(), kind("claim")),
                    ("subject".into(), subject.to_canonical()),
                    ("predicate".into(), CanonicalValue::Str(predicate.clone())),
                    ("polarity".into(), polarity.to_canonical()),
                ];
                if !roles.is_empty() {
                    let r = roles
                        .iter()
                        .map(|(k, v)| {
                            CanonicalValue::obj(vec![
                                ("role".into(), CanonicalValue::Str(k.clone())),
                                ("operand".into(), v.to_canonical()),
                            ])
                        })
                        .collect();
                    f.push(("roles".into(), CanonicalValue::arr(r)));
                }
                if let Some(v) = value {
                    f.push(("value".into(), v.to_canonical()));
                }
                if let Some(c) = context {
                    f.push(("context".into(), c.to_canonical()));
                }
                CanonicalValue::obj(f)
            }
            NegatedClaim {
                subject,
                predicate,
                roles,
                value,
                context,
            } => {
                let mut f = vec![
                    ("kind".into(), kind("negated_claim")),
                    ("subject".into(), subject.to_canonical()),
                    ("predicate".into(), CanonicalValue::Str(predicate.clone())),
                ];
                if !roles.is_empty() {
                    let r = roles
                        .iter()
                        .map(|(k, v)| {
                            CanonicalValue::obj(vec![
                                ("role".into(), CanonicalValue::Str(k.clone())),
                                ("operand".into(), v.to_canonical()),
                            ])
                        })
                        .collect();
                    f.push(("roles".into(), CanonicalValue::arr(r)));
                }
                if let Some(v) = value {
                    f.push(("value".into(), v.to_canonical()));
                }
                if let Some(c) = context {
                    f.push(("context".into(), c.to_canonical()));
                }
                CanonicalValue::obj(f)
            }
            Compare { left, op, right } => CanonicalValue::obj(vec![
                ("kind".into(), kind("compare")),
                ("left".into(), left.to_canonical()),
                ("op".into(), op.to_canonical()),
                ("right".into(), right.to_canonical()),
            ]),
            Temporal {
                left,
                relation,
                right,
            } => CanonicalValue::obj(vec![
                ("kind".into(), kind("temporal")),
                ("left".into(), left.to_canonical()),
                ("relation".into(), relation.to_canonical()),
                ("right".into(), right.to_canonical()),
            ]),
            Membership {
                element,
                collection,
                complete,
            } => {
                let mut f = vec![
                    ("kind".into(), kind("membership")),
                    ("element".into(), element.to_canonical()),
                    ("collection".into(), collection.to_canonical()),
                ];
                if let Some(c) = complete {
                    f.push(("complete".into(), CanonicalValue::Bool(*c)));
                }
                CanonicalValue::obj(f)
            }
            Cardinality {
                collection,
                op,
                count,
                complete,
            } => {
                let mut f = vec![
                    ("kind".into(), kind("cardinality")),
                    ("collection".into(), collection.to_canonical()),
                    ("op".into(), op.to_canonical()),
                    ("count".into(), count.to_canonical()),
                ];
                if let Some(c) = complete {
                    f.push(("complete".into(), CanonicalValue::Bool(*c)));
                }
                CanonicalValue::obj(f)
            }
            Existence {
                subject,
                predicate,
                roles,
                value,
                context,
            } => {
                let mut f = vec![
                    ("kind".into(), kind("existence")),
                    ("subject".into(), subject.to_canonical()),
                    ("predicate".into(), CanonicalValue::Str(predicate.clone())),
                ];
                if !roles.is_empty() {
                    let r = roles
                        .iter()
                        .map(|(k, v)| {
                            CanonicalValue::obj(vec![
                                ("role".into(), CanonicalValue::Str(k.clone())),
                                ("operand".into(), v.to_canonical()),
                            ])
                        })
                        .collect();
                    f.push(("roles".into(), CanonicalValue::arr(r)));
                }
                if let Some(v) = value {
                    f.push(("value".into(), v.to_canonical()));
                }
                if let Some(c) = context {
                    f.push(("context".into(), c.to_canonical()));
                }
                CanonicalValue::obj(f)
            }
            Quantify {
                variable,
                over,
                complete,
                quantifier,
                body,
            } => CanonicalValue::obj(vec![
                ("kind".into(), kind("quantify")),
                ("variable".into(), CanonicalValue::Str(variable.clone())),
                ("over".into(), over.to_canonical()),
                ("complete".into(), CanonicalValue::Bool(*complete)),
                ("quantifier".into(), quantifier.to_canonical()),
                ("body".into(), body.to_canonical()),
            ]),
            RoleHolds {
                subject,
                predicate,
                role,
                participant,
            } => CanonicalValue::obj(vec![
                ("kind".into(), kind("role_holds")),
                ("subject".into(), subject.to_canonical()),
                ("predicate".into(), CanonicalValue::Str(predicate.clone())),
                ("role".into(), CanonicalValue::Str(role.clone())),
                ("participant".into(), participant.to_canonical()),
            ]),
        }
    }
}

/// Bounded structural analysis of an expression tree (spec §31.1):
/// depth, node count, variable collection, and referenced records.
pub struct ExprAnalysis {
    pub depth: usize,
    pub nodes: usize,
    pub variables: Vec<String>,
    pub predicates: Vec<String>,
    pub referenced_records: Vec<RecordId>,
}

fn universe_of(ref_: &RecordRef) -> Option<&UniverseId> {
    ref_.universe.as_ref()
}

impl Expr {
    /// Analyze and structurally validate the expression under the
    /// language bounds (spec §11.7): depth ≤ 32, nodes ≤ 1000, no
    /// unbound variables, no duplicate quantifier shadowing.
    pub fn analyze(&self) -> DomainResult<ExprAnalysis> {
        use std::collections::BTreeSet;
        fn walk(
            e: &Expr,
            in_scope: &mut BTreeSet<String>,
            depth: usize,
            nodes: &mut usize,
            out: &mut ExprAnalysis,
        ) -> DomainResult<()> {
            if depth > limits::MAX_RULE_DEPTH {
                return Err(DomainError::Expression {
                    reason: format!(
                        "expression depth {depth} exceeds bound {}",
                        limits::MAX_RULE_DEPTH
                    ),
                });
            }
            *nodes += 1;
            if *nodes > limits::MAX_RULE_AST_NODES {
                return Err(DomainError::Expression {
                    reason: format!(
                        "expression node count exceeds bound {}",
                        limits::MAX_RULE_AST_NODES
                    ),
                });
            }
            out.depth = depth.max(out.depth);
            use Expr::*;
            let mut check_op = |o: &Operand| -> DomainResult<()> {
                if let Operand::Variable { name } = o {
                    if !in_scope.contains(name) {
                        return Err(DomainError::Expression {
                            reason: format!("unbound variable `{name}`"),
                        });
                    }
                    if !out.variables.contains(name) {
                        out.variables.push(name.clone());
                    }
                } else if let Operand::Record { record: r } = o {
                    if !out.referenced_records.contains(&r.record) {
                        out.referenced_records.push(r.record.clone());
                    }
                    if let Some(u) = universe_of(r) {
                        let _ = u; // namespace checked by the compiler
                    }
                }
                Ok(())
            };
            match self_ref(e) {
                NoOpposingEvidence {
                    subject,
                    predicate,
                    context,
                } => {
                    check_op(subject)?;
                    check_op(context)?;
                    out.predicates.push(predicate.clone());
                }
                Attitude {
                    holder,
                    proposition,
                    ..
                } => {
                    out.referenced_records.push(holder.record.clone());
                    out.referenced_records.push(proposition.record.clone());
                }
                Lit { .. } => {}
                Not { expr: inner } => walk(inner, in_scope, depth + 1, nodes, out)?,
                All { exprs: items } | Any { exprs: items } => {
                    for i in items {
                        walk(i, in_scope, depth + 1, nodes, out)?;
                    }
                }
                Claim {
                    subject,
                    predicate,
                    roles,
                    value,
                    context,
                    ..
                } => {
                    check_op(subject)?;
                    out.predicates.push(predicate.clone());
                    for (_, r) in roles {
                        check_op(r)?;
                    }
                    if let Some(v) = value {
                        check_op(v)?;
                    }
                    if let Some(c) = context {
                        check_op(c)?;
                    }
                }
                NegatedClaim {
                    subject,
                    predicate,
                    roles,
                    value,
                    context,
                } => {
                    check_op(subject)?;
                    out.predicates.push(predicate.clone());
                    for (_, r) in roles {
                        check_op(r)?;
                    }
                    if let Some(v) = value {
                        check_op(v)?;
                    }
                    if let Some(c) = context {
                        check_op(c)?;
                    }
                }
                Compare { left, right, .. } => {
                    check_op(left)?;
                    check_op(right)?;
                }
                Temporal { left, right, .. } => {
                    check_op(left)?;
                    check_op(right)?;
                }
                Membership {
                    element,
                    collection,
                    ..
                } => {
                    check_op(element)?;
                    check_op(collection)?;
                }
                Cardinality { collection, .. } => {
                    check_op(collection)?;
                }
                Existence {
                    subject,
                    predicate,
                    roles,
                    value,
                    context,
                } => {
                    check_op(subject)?;
                    out.predicates.push(predicate.clone());
                    for (_, r) in roles {
                        check_op(r)?;
                    }
                    if let Some(v) = value {
                        check_op(v)?;
                    }
                    if let Some(c) = context {
                        check_op(c)?;
                    }
                }
                Quantify {
                    variable,
                    over,
                    body,
                    ..
                } => {
                    check_op(over)?;
                    if in_scope.contains(variable) {
                        return Err(DomainError::Expression {
                            reason: format!("duplicate quantifier binding `{variable}`"),
                        });
                    }
                    in_scope.insert(variable.clone());
                    if !out.variables.contains(variable) {
                        out.variables.push(variable.clone());
                    }
                    walk(body, in_scope, depth + 1, nodes, out)?;
                    in_scope.remove(variable);
                }
                RoleHolds {
                    subject,
                    predicate,
                    participant,
                    ..
                } => {
                    check_op(subject)?;
                    out.predicates.push(predicate.clone());
                    check_op(participant)?;
                }
            }
            Ok(())
        }
        let mut in_scope = BTreeSet::new();
        let mut out = ExprAnalysis {
            depth: 0,
            nodes: 0,
            variables: Vec::new(),
            predicates: Vec::new(),
            referenced_records: Vec::new(),
        };
        let mut nodes = 0usize;
        walk(self, &mut in_scope, 1, &mut nodes, &mut out)?;
        if !in_scope.is_empty() {
            // Quantifier variables are removed during walk; leftovers
            // would indicate a structural defect.
            return Err(DomainError::Expression {
                reason: "unbalanced quantifier scope".into(),
            });
        }
        Ok(out)
    }
}

fn self_ref(e: &Expr) -> &Expr {
    e
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::{RecordId, UniverseId};

    fn univ() -> UniverseId {
        UniverseId::parse("unv_000000000000000000000001").unwrap()
    }
    fn rec(n: &str) -> RecordRef {
        RecordRef::new(univ(), RecordId::parse(&format!("rec_{n}")).unwrap())
    }

    #[test]
    fn expression_round_trips() {
        let e = Expr::All {
            exprs: vec![
                Expr::Claim {
                    subject: Operand::Variable {
                        name: "actor".into(),
                    },
                    predicate: "starter:property:physically_held_by".into(),
                    roles: Vec::new(),
                    value: Some(Operand::Record {
                        record: rec("aaaaaaaaaaaaaaaaaaaaaaaa"),
                    }),
                    polarity: Polarity::Support,
                    context: None,
                },
                Expr::Temporal {
                    left: Operand::FrameTime,
                    relation: TemporalRelation::Before,
                    right: Operand::FrameTime,
                },
            ],
        };
        let s = serde_json::to_string(&e).unwrap();
        let back: Expr = serde_json::from_str(&s).unwrap();
        assert_eq!(e, back);
        assert_eq!(e.to_canonical(), back.to_canonical());
    }

    #[test]
    fn unbound_variables_are_rejected() {
        let e = Expr::Not {
            expr: Box::new(Expr::Claim {
                subject: Operand::Variable {
                    name: "missing".into(),
                },
                predicate: "p".into(),
                roles: Vec::new(),
                value: None,
                polarity: Polarity::Support,
                context: None,
            }),
        };
        assert!(matches!(e.analyze(), Err(DomainError::Expression { .. })));
    }

    #[test]
    fn deep_expressions_hit_the_depth_bound() {
        let mut e = Expr::Lit { value: true };
        for _ in 0..(limits::MAX_RULE_DEPTH + 1) {
            e = Expr::Not { expr: Box::new(e) };
        }
        assert!(matches!(e.analyze(), Err(DomainError::Expression { .. })));
    }

    #[test]
    fn quantifier_binding_scopes_correctly() {
        let e = Expr::Quantify {
            variable: "x".into(),
            over: Operand::Record {
                record: rec("bbbbbbbbbbbbbbbbbbbbbbbb"),
            },
            complete: true,
            quantifier: Quantifier::ForAll,
            body: Box::new(Expr::Claim {
                subject: Operand::Variable { name: "x".into() },
                predicate: "p".into(),
                roles: Vec::new(),
                value: None,
                polarity: Polarity::Support,
                context: None,
            }),
        };
        let a = e.analyze().unwrap();
        assert_eq!(a.variables, vec!["x".to_string()]);
        // shadowing is rejected
        let bad = Expr::Quantify {
            variable: "x".into(),
            over: Operand::Record {
                record: rec("bbbbbbbbbbbbbbbbbbbbbbbb"),
            },
            complete: true,
            quantifier: Quantifier::ForAll,
            body: Box::new(Expr::Quantify {
                variable: "x".into(),
                over: Operand::Record {
                    record: rec("cccccccccccccccccccccccc"),
                },
                complete: true,
                quantifier: Quantifier::ForAll,
                body: Box::new(Expr::Lit { value: true }),
            }),
        };
        assert!(matches!(bad.analyze(), Err(DomainError::Expression { .. })));
    }
}

impl Expr {
    pub fn uses_opposing_evidence(&self) -> bool {
        match self {
            Self::NoOpposingEvidence { .. } => true,
            Self::Not { expr } => expr.uses_opposing_evidence(),
            Self::All { exprs } | Self::Any { exprs } => {
                exprs.iter().any(Self::uses_opposing_evidence)
            }
            Self::Quantify { body, .. } => body.uses_opposing_evidence(),
            _ => false,
        }
    }
}
