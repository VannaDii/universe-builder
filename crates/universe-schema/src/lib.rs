//! Universe Builder closed payload schemas, validation, and canonical digests.
//!
//! A registry holds the *definitions* of one universe — entity types,
//! property/relation definitions, units, calendars, structured value
//! definitions, and domain packs — resolved from their record versions,
//! so that validation and value conformance can cross-reference them
//! (spec §27.2: "Definitions are versioned at the same canon snapshot as
//! their use").
//!
//! It is deliberately not a record store: only the seven definition
//! families are accepted. Instance records live in the canon revisions
//! (WP05), and the service resolves them at the requested snapshot.

pub mod error;
mod registry;
mod validation;

pub use error::{SchemaError, SchemaResult};
pub use registry::DefinitionRegistry;
pub use validation::{known_capabilities, validate, MAX_VALUE_DEF_DEPTH};

// Re-export DomainPack for test code that constructs it directly.
pub use registry::DomainPack;
