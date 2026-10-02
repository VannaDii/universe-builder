//! Store-layer error types (WP05, spec §11.6).

use thiserror::Error;

use crate::blob::BlobStoreError;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("blob store error: {0}")]
    Blob(#[from] BlobStoreError),

    #[error("migration failed: {0}")]
    Migration(String),

    #[error("transaction conflict at revision {expected}, got {actual}")]
    RevisionConflict { expected: String, actual: String },

    #[error("blob not found: digest={digest}")]
    BlobNotFound { digest: String },

    #[error("database is in maintenance mode")]
    MaintenanceRequired,

    #[error("storage failure: {0}")]
    StorageFailure(String),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

pub type StoreResult<T> = Result<T, StoreError>;
