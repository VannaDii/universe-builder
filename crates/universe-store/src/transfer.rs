//! Trusted relational row transfer. Input SQL is compared, never installed.
use crate::{Connection, Database, StoreError, StoreResult};
use rusqlite::{params_from_iter, types::Value};
use sha2::{Digest, Sha256};
use std::path::Path;

pub(crate) const EXPORT_SQL: &str =
    include_str!("../../../docs/decisions/relational-storage/export.sql");
fn invalid(s: &str) -> StoreError {
    StoreError::StorageFailure(s.into())
}
fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('"', "\"\""))
}
pub(crate) fn schema(c: &Connection) -> StoreResult<Vec<(String, String, String, String)>> {
    Ok(c.prepare("SELECT type,name,tbl_name,coalesce(sql,'') FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name")?
        .query_map([], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?)))?.collect::<Result<_,_>>()?)
}
pub(crate) fn tables(c: &Connection) -> StoreResult<Vec<String>> {
    Ok(c.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search_index%' ORDER BY name")?
        .query_map([], |r| r.get(0))?.collect::<Result<_,_>>()?)
}
fn columns(c: &Connection, table: &str) -> StoreResult<(Vec<String>, Vec<String>)> {
    let info: Vec<(String, i64)> = c
        .prepare(&format!("PRAGMA table_info({})", quote(table)))?
        .query_map([], |r| Ok((r.get(1)?, r.get(5)?)))?
        .collect::<Result<_, _>>()?;
    let cols = info.iter().map(|r| r.0.clone()).collect::<Vec<_>>();
    let mut pk: Vec<_> = info.into_iter().filter(|r| r.1 > 0).collect();
    pk.sort_by_key(|r| r.1);
    let order = if pk.is_empty() {
        cols.clone()
    } else {
        pk.into_iter().map(|r| r.0).collect()
    };
    Ok((cols, order))
}
pub(crate) fn checksum(c: &Connection) -> StoreResult<(String, usize)> {
    // Exactly the approved typed-row-stream recipe; JSON exists transiently for hashing only.
    let mut hash = Sha256::new();
    hash.update(b"[");
    let mut count = 0usize;
    for table in tables(c)? {
        if matches!(table.as_str(), "archive_integrity" | "r_archive_manifest") {
            continue;
        }
        let (cols, order) = columns(c, &table)?;
        let sql = format!(
            "SELECT {} FROM {} ORDER BY {}",
            cols.iter().map(|s| quote(s)).collect::<Vec<_>>().join(","),
            quote(&table),
            order.iter().map(|s| quote(s)).collect::<Vec<_>>().join(",")
        );
        let mut stmt = c.prepare(&sql)?;
        let mut query = stmt.query([])?;
        while let Some(row) = query.next()? {
            count += 1;
            if count > 2_000_000 {
                return Err(invalid("archive row budget exceeded"));
            }
            let cells = (0..cols.len())
                .map(|i| {
                    Ok(match row.get::<_, Value>(i)? {
                        Value::Null => serde_json::json!(["null", null]),
                        Value::Integer(n) => serde_json::json!(["integer", n]),
                        Value::Text(s) => serde_json::json!(["text", s]),
                        Value::Blob(b) => serde_json::json!(["bytes", hex::encode(b)]),
                        Value::Real(_) => return Err(invalid("unsupported archive real cell")),
                    })
                })
                .collect::<StoreResult<Vec<_>>>()?;
            if count > 1 {
                hash.update(b",");
            }
            hash.update(
                serde_json::to_vec(&serde_json::json!([table, cols, cells]))
                    .map_err(|_| invalid("checksum encoding"))?,
            );
        }
    }
    hash.update(b"]");
    Ok((hex::encode(hash.finalize()), count))
}
pub(crate) fn copy_rows(
    source: &Connection,
    target: &mut Connection,
    mut hook: impl FnMut() -> StoreResult<()>,
) -> StoreResult<()> {
    let tx = target.transaction()?;
    tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
    let is_archive: bool = tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='archive_integrity')",
        [],
        |r| r.get(0),
    )?;
    for table in tables(&tx)? {
        if !is_archive && table == "r_archive_manifest" {
            continue;
        }
        let (cols, _) = columns(&tx, &table)?;
        let sql = format!(
            "SELECT {} FROM {}",
            cols.iter().map(|s| quote(s)).collect::<Vec<_>>().join(","),
            quote(&table)
        );
        // projection_state is the only seeded row in a trusted new schema.
        if table == "projection_state" {
            tx.execute("DELETE FROM projection_state", [])?;
        }
        let insert = format!(
            "INSERT INTO {} ({}) VALUES ({})",
            quote(&table),
            cols.iter().map(|s| quote(s)).collect::<Vec<_>>().join(","),
            (0..cols.len()).map(|_| "?").collect::<Vec<_>>().join(",")
        );
        let mut write = tx.prepare(&insert)?;
        let mut read = source.prepare(&sql)?;
        let mut query = read.query([])?;
        while let Some(row) = query.next()? {
            let values = (0..cols.len())
                .map(|i| row.get::<_, Value>(i))
                .collect::<Result<Vec<_>, _>>()?;
            write.execute(params_from_iter(values))?;
            hook()?;
        }
    }
    // Rebuildable FTS rows are deliberately excluded; Kernel::open rebuilds projections.
    tx.commit()?;
    Ok(())
}
pub(crate) fn trusted_copy(
    source: &Path,
    destination: &Path,
    archive: bool,
    hook: impl FnMut() -> StoreResult<()>,
) -> StoreResult<()> {
    crate::ownership::protected_file(source, false)?;
    let input = Connection::open_with_flags(
        source,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    input.execute_batch("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; BEGIN;")?;
    let db = Database::open(destination)?;
    let mut output = db.connect()?;
    if archive {
        output.execute_batch(EXPORT_SQL)?;
    }
    if schema(&input)? != schema(&output)? {
        return Err(invalid("untrusted or incompatible archive schema"));
    }
    let check: String = input.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
    if check != "ok" {
        return Err(invalid("input SQLite integrity failure"));
    }
    copy_rows(&input, &mut output, hook)?;
    Ok(())
}
