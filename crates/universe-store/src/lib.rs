//! Universe Builder SQLite persistence layer (WP05, spec §6.2, §28).
//!
//! This crate provides:
//! - Database initialization with WAL mode, FTS5, foreign keys (spec §6.2)
//! - Schema migrations with version tracking
//! - Immutable record versions and editorial commits
//! - Continuity heads and head membership projections
//! - Content-addressed blob storage (spec §6.5)
//! - Operation receipts for idempotency/recovery (spec §10.5)

pub mod blob;
mod db;
mod error;
mod migrations;
mod projections;
mod relational;

pub use blob::{BlobStore, BlobStoreError};
pub use db::{Connection, Database, Txn};
pub use error::{StoreError, StoreResult};
pub use migrations::{generate_schema, MIGRATIONS};
pub use projections::read_heads;

/// Minimum SQLite version with WAL-reset fix (spec §6.2).
pub const MIN_SQLITE_VERSION: &str = "3.51.3";

pub mod kernel;
pub mod ownership;
pub mod selector;
