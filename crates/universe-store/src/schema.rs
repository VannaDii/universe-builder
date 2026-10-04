//! Single normative relational package schema.
//! Existing author packages require a separately authorized conversion.

use crate::StoreResult;

/// Generate the initial schema SQL for testing or documentation.
pub fn generate_schema() -> StoreResult<String> {
    Ok([
        crate::relational::SQL,
        include_str!("../../../docs/decisions/relational-storage/kernel.sql"),
        include_str!("../../../docs/decisions/relational-storage/semantic.sql"),
        include_str!("workflow.sql"),
    ]
    .join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normative_schema_has_relational_bodies() {
        assert!(generate_schema().unwrap().contains("payload_row INTEGER"));
    }

    #[test]
    fn generate_schema_returns_sql() {
        let sql = generate_schema().unwrap();
        assert!(sql.contains("CREATE TABLE"));
    }
}
