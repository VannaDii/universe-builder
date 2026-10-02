//! Schema migrations (WP05, spec §28).
//!
//! Each migration is a versioned SQL batch that transforms the database
//! from one schema version to the next. Migrations are applied in order
//! during database initialization (spec §6.2, §14.5).

use crate::StoreResult;

/// A single schema migration.
pub struct Migration {
    pub version: i64,
    pub sql: &'static str,
}

/// All schema migrations in order.
pub const MIGRATIONS: &[Migration] = &[Migration {
    version: 1,
    sql: include_str!("schema_v1.sql"),
}];

/// Generate the initial schema SQL for testing or documentation.
pub fn generate_schema() -> StoreResult<String> {
    Ok(MIGRATIONS[0].sql.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_are_non_empty() {
        assert!(!MIGRATIONS.is_empty());
    }

    #[test]
    fn migration_0_sql_is_non_empty() {
        assert!(!MIGRATIONS[0].sql.trim().is_empty());
    }

    #[test]
    fn generate_schema_returns_sql() {
        let sql = generate_schema().unwrap();
        assert!(sql.contains("CREATE TABLE"));
    }
}
