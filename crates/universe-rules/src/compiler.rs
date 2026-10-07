use universe_domain::expr::{Expr, Operand};
use universe_domain::ids::RecordId;
use universe_domain::records::RecordVersion;
use universe_domain::scope::Applicability;

pub const MAX_RULE_DEPTH: usize = 32;
pub const MAX_RULE_NODES: usize = 1_000;

#[derive(Debug, Clone)]
pub struct CompiledRule {
    pub id: RecordId,
    pub applicability: Applicability,
    pub executable: bool,
    pub expression: Expr,
    pub referenced_records: Vec<RecordId>,
    pub node_count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuleCompileError {
    NotARule,
    DepthExceeded { current_depth: usize },
    NodeCountExceeded { current_count: usize },
}

impl std::fmt::Display for RuleCompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotARule => write!(f, "expected a rule record"),
            RuleCompileError::DepthExceeded { current_depth } => {
                write!(f, "depth {} exceeds {}", current_depth, MAX_RULE_DEPTH)
            }
            RuleCompileError::NodeCountExceeded { current_count } => {
                write!(f, "nodes {} exceeds {}", current_count, MAX_RULE_NODES)
            }
        }
    }
}

pub fn compile_rule(version: &RecordVersion) -> Result<CompiledRule, RuleCompileError> {
    let rule = match &version.payload {
        universe_domain::records::Payload::Rule(r) => r,
        _ => return Err(RuleCompileError::NotARule),
    };
    let expr = rule.expression.clone();
    let nodes = count_nodes(&expr);
    if nodes > MAX_RULE_NODES {
        return Err(RuleCompileError::NodeCountExceeded {
            current_count: nodes,
        });
    }
    let depth = max_depth(&expr);
    if depth > MAX_RULE_DEPTH {
        return Err(RuleCompileError::DepthExceeded {
            current_depth: depth,
        });
    }
    let (records, _) = extract_refs(&expr);
    Ok(CompiledRule {
        id: version.identity.record_id.clone(),
        applicability: rule.applicability.clone(),
        executable: rule.executable && rule.kind != universe_domain::records::RuleKind::Descriptive,
        expression: expr,
        referenced_records: records,
        node_count: nodes,
    })
}

fn count_nodes(e: &Expr) -> usize {
    match e {
        Expr::NoOpposingEvidence {
            subject, context, ..
        } => 1 + count_op(subject) + count_op(context),
        Expr::Attitude { .. } | Expr::Lit { .. } => 1,
        Expr::Not { expr } => 1 + count_nodes(expr),
        Expr::All { exprs } => 1 + exprs.iter().map(count_nodes).sum::<usize>(),
        Expr::Any { exprs } => 1 + exprs.iter().map(count_nodes).sum::<usize>(),
        Expr::Claim {
            subject,
            roles,
            value,
            ..
        } => {
            1 + count_op(subject)
                + roles.iter().map(|(_, o)| count_op(o)).sum::<usize>()
                + value.as_ref().map_or(0, count_op)
        }
        Expr::NegatedClaim {
            subject,
            roles,
            value,
            ..
        } => {
            1 + count_op(subject)
                + roles.iter().map(|(_, o)| count_op(o)).sum::<usize>()
                + value.as_ref().map_or(0, count_op)
        }
        Expr::Compare { left, right, .. } => 1 + count_op(left) + count_op(right),
        Expr::Temporal { left, right, .. } => 1 + count_op(left) + count_op(right),
        Expr::Membership {
            element,
            collection,
            ..
        } => 1 + count_op(element) + count_op(collection),
        Expr::Cardinality { collection, .. } => 1 + count_op(collection),
        Expr::Existence {
            subject,
            roles,
            value,
            ..
        } => {
            1 + count_op(subject)
                + roles.iter().map(|(_, o)| count_op(o)).sum::<usize>()
                + value.as_ref().map_or(0, count_op)
        }
        Expr::Quantify { over, body, .. } => 1 + count_op(over) + count_nodes(body),
        Expr::RoleHolds { .. } => 1,
    }
}
fn count_op(_o: &Operand) -> usize {
    1
}
fn max_depth(e: &Expr) -> usize {
    match e {
        Expr::NoOpposingEvidence {
            subject, context, ..
        } => 1 + max_o(subject) + max_o(context),
        Expr::Attitude { .. } | Expr::Lit { .. } => 1,
        Expr::Not { expr } => 1 + max_d(expr),
        Expr::All { exprs } => 1 + exprs.iter().map(max_d).max().unwrap_or(0),
        Expr::Any { exprs } => 1 + exprs.iter().map(max_d).max().unwrap_or(0),
        Expr::Claim {
            subject,
            roles,
            value,
            ..
        } => {
            1 + max_o(subject)
                + roles.iter().map(|(_, o)| max_o(o)).max().unwrap_or(0)
                + value.as_ref().map_or(0, max_o)
        }
        Expr::NegatedClaim {
            subject,
            roles,
            value,
            ..
        } => {
            1 + max_o(subject)
                + roles.iter().map(|(_, o)| max_o(o)).max().unwrap_or(0)
                + value.as_ref().map_or(0, max_o)
        }
        Expr::Compare { left, right, .. } => 1 + max_o(left) + max_o(right),
        Expr::Temporal { left, right, .. } => 1 + max_o(left) + max_o(right),
        Expr::Membership {
            element,
            collection,
            ..
        } => 1 + max_o(element) + max_o(collection),
        Expr::Cardinality { collection, .. } => 1 + max_o(collection),
        Expr::Existence {
            subject,
            roles,
            value,
            ..
        } => {
            1 + max_o(subject)
                + roles.iter().map(|(_, o)| max_o(o)).max().unwrap_or(0)
                + value.as_ref().map_or(0, max_o)
        }
        Expr::Quantify { over, body, .. } => 1 + max_o(over) + max_d(body),
        Expr::RoleHolds { .. } => 1,
    }
}
fn max_d(e: &Expr) -> usize {
    max_depth(e)
}
fn max_o(_o: &Operand) -> usize {
    1
}

fn extract_refs(e: &Expr) -> (Vec<RecordId>, Vec<RecordId>) {
    let mut records = Vec::new();
    fn visit(e: &Expr, r: &mut Vec<RecordId>) {
        match e {
            Expr::Attitude {
                holder,
                proposition,
                ..
            } => {
                r.push(holder.record.clone());
                r.push(proposition.record.clone());
            }
            Expr::NoOpposingEvidence {
                subject, context, ..
            } => {
                visit_op(subject, r);
                visit_op(context, r);
            }
            Expr::Lit { .. } => {}
            Expr::Not { expr } => visit(expr, r),
            Expr::All { exprs } => {
                for ex in exprs {
                    visit(ex, r);
                }
            }
            Expr::Any { exprs } => {
                for ex in exprs {
                    visit(ex, r);
                }
            }
            Expr::Claim {
                subject,
                roles,
                value,
                ..
            } => {
                visit_op(subject, r);
                for (_, o) in roles {
                    visit_op(o, r);
                }
                if let Some(v) = value {
                    visit_op(v, r);
                }
            }
            Expr::NegatedClaim {
                subject,
                roles,
                value,
                ..
            } => {
                visit_op(subject, r);
                for (_, o) in roles {
                    visit_op(o, r);
                }
                if let Some(v) = value {
                    visit_op(v, r);
                }
            }
            Expr::Compare { left, right, .. } => {
                visit_op(left, r);
                visit_op(right, r);
            }
            Expr::Temporal { left, right, .. } => {
                visit_op(left, r);
                visit_op(right, r);
            }
            Expr::Membership {
                element,
                collection,
                ..
            } => {
                visit_op(element, r);
                visit_op(collection, r);
            }
            Expr::Cardinality { collection, .. } => {
                visit_op(collection, r);
            }
            Expr::Existence {
                subject,
                roles,
                value,
                ..
            } => {
                visit_op(subject, r);
                for (_, o) in roles {
                    visit_op(o, r);
                }
                if let Some(v) = value {
                    visit_op(v, r);
                }
            }
            Expr::Quantify { over, body, .. } => {
                visit_op(over, r);
                visit(body, r);
            }
            Expr::RoleHolds {
                subject,
                participant,
                ..
            } => {
                visit_op(subject, r);
                visit_op(participant, r);
            }
        }
    }
    fn visit_op(o: &Operand, r: &mut Vec<RecordId>) {
        if let Operand::Record { record } = o {
            r.push(record.record.clone())
        }
    }
    visit(e, &mut records);
    records.sort();
    records.dedup();
    (records, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;
    use universe_domain::expr::{Expr, Operand};
    use universe_domain::ids::RecordId;
    use universe_domain::records::CommitPolicy;
    use universe_domain::records::{Payload, RecordIdentity, RecordKind, RecordVersion};
    fn rid(n: u8) -> RecordId {
        RecordId::parse(&format!("rec_{:024x}", n)).unwrap()
    }
    #[test]
    fn simple_compiles() {
        let e = Expr::Compare {
            left: Operand::Value {
                value: universe_domain::value::Value::Text { text: "a".into() },
            },
            op: universe_domain::expr::Comparator::Eq,
            right: Operand::Value {
                value: universe_domain::value::Value::Text { text: "a".into() },
            },
        };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "t".into(),
                key: "k".into(),
                labels: Default::default(),
                kind: universe_domain::records::RuleKind::StructuralInvariant,
                commit_policy: CommitPolicy::AlwaysBlock,
                applicability: Applicability::UniverseWide,
                subject_types: vec![],
                target_predicates: vec![],
                expression: e,
                capabilities: vec![],
                executable: true,
                validity: Default::default(),
            }),
        )
        .unwrap();
        assert!(compile_rule(&v).is_ok());
    }
    #[test]
    fn depth_exceeded() {
        let mut e = Expr::Compare {
            left: Operand::Value {
                value: universe_domain::value::Value::Text { text: "a".into() },
            },
            op: universe_domain::expr::Comparator::Eq,
            right: Operand::Value {
                value: universe_domain::value::Value::Text { text: "a".into() },
            },
        };
        for _ in 0..33 {
            e = Expr::Not { expr: Box::new(e) };
        }
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "t".into(),
                key: "d".into(),
                labels: Default::default(),
                kind: universe_domain::records::RuleKind::StructuralInvariant,
                commit_policy: CommitPolicy::AlwaysBlock,
                applicability: Applicability::UniverseWide,
                subject_types: vec![],
                target_predicates: vec![],
                expression: e,
                capabilities: vec![],
                executable: true,
                validity: Default::default(),
            }),
        )
        .unwrap();
        assert!(matches!(
            compile_rule(&v),
            Err(RuleCompileError::DepthExceeded { .. })
        ));
    }
    #[test]
    fn nodes_exceeded() {
        let ops: Vec<Expr> = (0..1_001)
            .map(|i| Expr::Compare {
                left: Operand::Value {
                    value: universe_domain::value::Value::Text {
                        text: format!("a{}", i),
                    },
                },
                op: universe_domain::expr::Comparator::Eq,
                right: Operand::Value {
                    value: universe_domain::value::Value::Text {
                        text: format!("a{}", i),
                    },
                },
            })
            .collect();
        let e = Expr::All { exprs: ops };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "t".into(),
                key: "w".into(),
                labels: Default::default(),
                kind: universe_domain::records::RuleKind::StructuralInvariant,
                commit_policy: CommitPolicy::AlwaysBlock,
                applicability: Applicability::UniverseWide,
                subject_types: vec![],
                target_predicates: vec![],
                expression: e,
                capabilities: vec![],
                executable: true,
                validity: Default::default(),
            }),
        )
        .unwrap();
        assert!(matches!(
            compile_rule(&v),
            Err(RuleCompileError::NodeCountExceeded { .. })
        ));
    }
    #[test]
    fn references_extracted() {
        let e = Expr::Claim {
            subject: Operand::Record {
                record: universe_domain::value::RecordRef {
                    universe: None,
                    record: rid(1),
                },
            },
            predicate: "test".into(),
            roles: vec![],
            value: None,
            polarity: universe_domain::scope::Polarity::Support,
            context: None,
        };
        let (records, _) = extract_refs(&e);
        assert_eq!(records.len(), 1);
    }
    #[test]
    fn all_with_no_exprs() {
        let e = Expr::All { exprs: vec![] };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "t".into(),
                key: "k".into(),
                labels: Default::default(),
                kind: universe_domain::records::RuleKind::StructuralInvariant,
                commit_policy: CommitPolicy::AlwaysBlock,
                applicability: Applicability::UniverseWide,
                subject_types: vec![],
                target_predicates: vec![],
                expression: e,
                capabilities: vec![],
                executable: true,
                validity: Default::default(),
            }),
        )
        .unwrap();
        assert!(compile_rule(&v).is_ok());
    }
    #[test]
    fn quantify_compiles() {
        let e = Expr::Quantify {
            variable: "x".into(),
            over: Operand::Value {
                value: universe_domain::value::Value::Text { text: "a".into() },
            },
            complete: true,
            quantifier: universe_domain::expr::Quantifier::Exists,
            body: Box::new(Expr::Lit { value: true }),
        };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "t".into(),
                key: "k".into(),
                labels: Default::default(),
                kind: universe_domain::records::RuleKind::StructuralInvariant,
                commit_policy: CommitPolicy::AlwaysBlock,
                applicability: Applicability::UniverseWide,
                subject_types: vec![],
                target_predicates: vec![],
                expression: e,
                capabilities: vec![],
                executable: true,
                validity: Default::default(),
            }),
        )
        .unwrap();
        assert!(compile_rule(&v).is_ok());
    }
    #[test]
    fn claim_compiles() {
        let e = Expr::Claim {
            subject: Operand::Value {
                value: universe_domain::value::Value::Text { text: "a".into() },
            },
            predicate: "test".into(),
            roles: vec![],
            value: None,
            polarity: universe_domain::scope::Polarity::Support,
            context: None,
        };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_policy: None,
                channel_chronology: None,
                namespace: "t".into(),
                key: "k".into(),
                labels: Default::default(),
                kind: universe_domain::records::RuleKind::StructuralInvariant,
                commit_policy: CommitPolicy::AlwaysBlock,
                applicability: Applicability::UniverseWide,
                subject_types: vec![],
                target_predicates: vec![],
                expression: e,
                capabilities: vec![],
                executable: true,
                validity: Default::default(),
            }),
        )
        .unwrap();
        assert!(compile_rule(&v).is_ok());
    }
}
