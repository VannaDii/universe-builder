//! Head membership projection (spec §6.3).
//!
//! Materializes head membership and caches selected historical snapshots
//! from the commits table for fast reads.

#[cfg(test)]
use crate::db::Database;
use crate::error::StoreResult;

/// Read the current head commit IDs for a universe's continuities.
pub fn read_heads(conn: &rusqlite::Connection, universe_id: &str) -> StoreResult<Vec<String>> {
    let mut stmt =
        conn.prepare("SELECT head_commit FROM continuities WHERE universe_id = ? ORDER BY id")?;
    let rows = stmt.query_map([universe_id], |row| row.get::<_, String>(0))?;
    let mut heads = Vec::new();
    for h in rows {
        heads.push(h?);
    }
    Ok(heads)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_heads_empty_returns_empty() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.db");
        let db = Database::open(&path).unwrap();
        let conn = db.connect().unwrap();

        let heads = read_heads(&conn, "unv_000000000000000000000000").unwrap();
        assert!(heads.is_empty());
    }
}
