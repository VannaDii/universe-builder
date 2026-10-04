mod compiler;
mod evaluator;
mod evidence;

pub use compiler::{compile_rule, CompiledRule, RuleCompileError};
pub use evaluator::{evaluate_rule, EvaluationContext, EvaluationCoverage, EvaluationResult};
pub use evidence::{Evidence, EvidenceBit, EvidenceOutcome};

pub mod basic;
pub mod definitions;
pub mod time;

pub mod events;
pub mod powers;

pub mod index;
pub use index::EvaluationIndex;

/// Internal candidate comparison kernel; no public protocol changes.
pub mod opposing;
