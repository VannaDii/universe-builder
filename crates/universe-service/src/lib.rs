//! Shared application service: authenticated persistent authoring and a separate
//! disposable feasibility backend. All canon changes use validated exact approvals.
pub mod fixture;
pub mod ipc;

pub mod conversion;
pub mod registry;
pub mod runtime;

mod initialization;
mod operations;
mod workflow;

mod drafts;
mod imports;
mod provenance;
mod validation;

mod actions;
mod communications;
mod consequences;
mod events;
mod resources;

mod powers;

mod boundary_checks;
mod rule_checks;

#[cfg(test)]
mod object_rule_capability_checks;

#[cfg(test)]
mod ancestor_checks;

mod objects;
