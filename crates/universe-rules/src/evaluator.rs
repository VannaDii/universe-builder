use universe_domain::ids::RecordId;
use universe_domain::records::RecordVersion;
use universe_domain::scope::Applicability;

use crate::compiler::CompiledRule;
use crate::evidence::{Evidence, EvidenceOutcome};

pub struct EvaluationContext<'a> {
    pub index: Option<&'a crate::EvaluationIndex<'a>>,
    pub frame: Option<&'a universe_domain::Frame>,
    pub base_snapshot: &'a [RecordVersion],
    pub candidate_changes: Vec<(&'a RecordId, Option<&'a RecordVersion>)>,
    pub world_scope: Option<Vec<RecordId>>,
}
pub struct EvaluationResult {
    pub rule_id: RecordId,
    pub outcome: EvidenceOutcome,
    pub evidence: Evidence,
    pub coverage: EvaluationCoverage,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EvaluationCoverage {
    Complete,
    Partial,
    Failed,
    Unsupported,
}

pub fn evaluate_rule(compiled: &CompiledRule, ctx: &EvaluationContext<'_>) -> EvaluationResult {
    // Until frame/applicability evaluation is implemented, scoped rules cannot
    // truthfully claim a completed check even when their body is a literal.
    let (evidence, supported) = if compiled.executable
        && match &compiled.applicability {
            Applicability::UniverseWide => true,
            Applicability::Worlds { world_ids } => ctx.world_scope.as_ref().is_some_and(|scope| {
                world_ids.iter().any(|w| {
                    scope
                        .iter()
                        .any(|r| r.as_str().strip_prefix("rec_") == w.as_str().strip_prefix("wld_"))
                })
            }),
            _ => false,
        } {
        crate::basic::evaluate(&compiled.expression, ctx)
    } else {
        (Evidence::not_established(), false)
    };
    EvaluationResult {
        rule_id: compiled.id.clone(),
        outcome: evidence.outcome(),
        evidence,
        coverage: if supported {
            EvaluationCoverage::Complete
        } else {
            EvaluationCoverage::Unsupported
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiler::compile_rule;
    use universe_domain::expr::{Expr, Operand};
    use universe_domain::ids::RecordId;
    use universe_domain::records::CommitPolicy;
    use universe_domain::records::{Payload, RecordIdentity, RecordKind, RecordVersion};
    fn rid(n: u8) -> RecordId {
        RecordId::parse(&format!("rec_{:024x}", n)).unwrap()
    }
    #[test]
    fn exact_text_comparison_is_supported() {
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
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::Supported);
        assert_eq!(result.coverage, EvaluationCoverage::Complete);
    }
    #[test]
    fn lit_true_is_supported() {
        let e = Expr::Lit { value: true };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::Supported);
    }
    #[test]
    fn lit_false_is_refuted() {
        let e = Expr::Lit { value: false };
        let v = RecordVersion::build(
            universe_domain::ids::RecordVersionId::parse("ver_000000000000000000000001").unwrap(),
            RecordIdentity::new(
                universe_domain::ids::UniverseId::parse("unv_000000000000000000000001").unwrap(),
                rid(1),
                RecordKind::Rule,
            ),
            Payload::Rule(universe_domain::records::Rule {
                relation_cardinality: None,
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::Refuted);
    }
    #[test]
    fn not_inverts() {
        let e = Expr::Not {
            expr: Box::new(Expr::Lit { value: true }),
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
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::Refuted);
    }
    #[test]
    fn all_with_true_and_false() {
        let e = Expr::All {
            exprs: vec![Expr::Lit { value: true }, Expr::Lit { value: false }],
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
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::Refuted);
    }
    #[test]
    fn any_with_one_true() {
        let e = Expr::Any {
            exprs: vec![Expr::Lit { value: false }, Expr::Lit { value: true }],
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
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::Supported);
    }
    #[test]
    fn quantification_is_explicitly_unsupported() {
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
                knowledge_boundary: None,
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
        let c = compile_rule(&v).unwrap();
        let ctx = EvaluationContext {
            frame: None,
            base_snapshot: &[],
            candidate_changes: Vec::new(),
            index: None,
            world_scope: None,
        };
        let result = evaluate_rule(&c, &ctx);
        assert_eq!(result.outcome, EvidenceOutcome::NotEstablished);
        assert_eq!(result.coverage, EvaluationCoverage::Unsupported);
    }
}
