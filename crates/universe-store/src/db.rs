//! SQLite connection policy and atomic schema installation.
use crate::{StoreError, StoreResult};
pub use rusqlite::Connection;
use rusqlite::{OptionalExtension, Transaction as RusqliteTransaction};
use std::path::{Path, PathBuf};
/// Writes and physical restore share one bound. SQLite rejects growth before a
/// transaction can publish a package that our restore path cannot accept.
pub const MAX_PACKAGE_BYTES: u64 = 8 * 1024 * 1024 * 1024;
#[derive(Clone)]
pub struct Database {
    path: PathBuf,
}
impl Database {
    pub fn open(path: impl Into<PathBuf>) -> StoreResult<Self> {
        let path = path.into();
        if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent)?;
        }
        let mut conn = Connection::open(&path)?;
        Self::initialize(&mut conn, &path)?;
        Ok(Self { path })
    }
    pub fn open_existing(path: impl Into<PathBuf>) -> StoreResult<Self> {
        let path = path.into();
        let mut conn =
            Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE)?;
        Self::initialize(&mut conn, &path)?;
        Self::policy(&conn)?;
        Ok(Self { path })
    }
    fn check_version(conn: &Connection) -> StoreResult<()> {
        let version: i64 = conn.query_row(
            "SELECT value FROM schema_meta WHERE key='schema_version'",
            [],
            |r| r.get(0),
        )?;
        if version != 2 {
            return Err(StoreError::Migration(format!(
                "unsupported schema version {version}"
            )));
        }
        Ok(())
    }
    pub(crate) fn policy(conn: &Connection) -> StoreResult<()> {
        conn.busy_timeout(std::time::Duration::from_secs(2))?;
        conn.execute_batch("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")?;
        let page_size: i64 = conn.query_row("PRAGMA page_size", [], |r| r.get(0))?;
        conn.pragma_update(None, "max_page_count", MAX_PACKAGE_BYTES as i64 / page_size)?;
        let version = rusqlite::version_number();
        if version < 3_051_003 {
            return Err(StoreError::Migration(
                "SQLite WAL patch baseline not met".into(),
            ));
        }
        conn.execute_batch("CREATE VIRTUAL TABLE IF NOT EXISTS temp.fts_probe USING fts5(text); DROP TABLE temp.fts_probe;")?;
        Ok(())
    }
    fn initialize(conn: &mut Connection, path: &Path) -> StoreResult<()> {
        // Reject future versions before changing journal mode or schema.
        let exists: bool = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='schema_meta')",
            [],
            |r| r.get(0),
        )?;
        let current = if exists {
            conn.query_row(
                "SELECT value FROM schema_meta WHERE key='schema_version'",
                [],
                |r| r.get::<_, i64>(0),
            )
            .optional()?
        } else {
            None
        };
        if current.is_some_and(|v| !(0..=2).contains(&v)) {
            return Err(StoreError::Migration(
                "unsupported schema version; original preserved".into(),
            ));
        }
        Self::policy(conn)?;
        if current == Some(2) {
            conn.execute_batch("PRAGMA journal_mode=WAL;")?;
            return Ok(());
        }
        if current == Some(1) {
            Self::pre_migration_snapshot(conn, path, 1)?;
            let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
            tx.execute_batch(include_str!("schema_v2.sql"))?;
            tx.execute(
                "UPDATE schema_meta SET value=2 WHERE key='schema_version'",
                [],
            )?;
            tx.commit()?;
            return Ok(());
        }
        // v0 never implemented canon. Do not guess how to convert populated scaffolds.
        let tables:Vec<String>=conn.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='schema_meta'")?.query_map([],|r|r.get(0))?.collect::<Result<_,_>>()?;
        if current.is_none() && !tables.is_empty() {
            return Err(StoreError::Migration(
                "unversioned existing database; original preserved".into(),
            ));
        }
        let virtuals:Vec<String>=conn.prepare("SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE 'CREATE VIRTUAL TABLE%'")?.query_map([],|r|r.get(0))?.collect::<Result<_,_>>()?;
        if virtuals.iter().any(|v| {
            !matches!(
                v.as_str(),
                "fts_universes" | "fts_entities" | "fts_worlds" | "fts_sources"
            )
        }) {
            return Err(StoreError::Migration(
                "unknown legacy virtual table; original preserved".into(),
            ));
        }
        for table in &tables {
            if virtuals.contains(table) {
                continue;
            }
            let quoted = table.replace('"', "\"\"");
            let count: i64 =
                conn.query_row(&format!("SELECT count(*) FROM \"{quoted}\""), [], |r| {
                    r.get(0)
                })?;
            let shadow = virtuals.iter().any(|v| {
                ["data", "idx", "content", "docsize", "config"]
                    .iter()
                    .any(|suffix| *table == format!("{v}_{suffix}"))
            });
            if count > 0 && !shadow {
                return Err(StoreError::Migration(
                    "populated legacy scaffold needs explicit conversion; original preserved"
                        .into(),
                ));
            }
        }
        if current == Some(0) {
            Self::pre_migration_snapshot(conn, path, 0)?;
        }
        conn.execute_batch("PRAGMA journal_mode=WAL;")?;
        let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
        tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
        // Remove virtual tables before their shadow tables.
        let virtuals:Vec<String>=tx.prepare("SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE 'CREATE VIRTUAL TABLE%'")?.query_map([],|r|r.get(0))?.collect::<Result<_,_>>()?;
        for table in virtuals.iter().chain(tables.iter()) {
            tx.execute_batch(&format!(
                "DROP TABLE IF EXISTS \"{}\"",
                table.replace('"', "\"\"")
            ))?;
        }
        tx.execute_batch(
            "CREATE TABLE IF NOT EXISTS schema_meta(key TEXT PRIMARY KEY,value INTEGER NOT NULL);",
        )?;
        tx.execute_batch(include_str!("schema_v1.sql"))?;
        tx.execute_batch(include_str!("schema_v2.sql"))?;
        tx.execute(
            "INSERT OR REPLACE INTO schema_meta VALUES('schema_version',2)",
            [],
        )?;
        tx.commit()?;
        Ok(())
    }
    /// Retain a verified, private rollback copy before touching a supported old
    /// schema. Random names preserve earlier copies; failure aborts the upgrade.
    fn pre_migration_snapshot(conn: &Connection, path: &Path, version: i64) -> StoreResult<()> {
        let parent = path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        let stem = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("universe");
        let backup = tempfile::Builder::new()
            .prefix(&format!(".{stem}.before-schema-{version}-"))
            .suffix(".sqlite")
            .tempfile_in(parent)?;
        let destination = backup
            .path()
            .to_str()
            .ok_or_else(|| StoreError::Migration("backup path must be UTF-8".into()))?;
        conn.execute("VACUUM INTO ?1", [destination])?;
        backup.as_file().sync_all()?;
        let copy =
            Connection::open_with_flags(backup.path(), rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        let integrity: String = copy.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
        let foreign_keys: i64 =
            copy.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| {
                r.get(0)
            })?;
        let schema: i64 = copy.query_row(
            "SELECT value FROM schema_meta WHERE key='schema_version'",
            [],
            |r| r.get(0),
        )?;
        if integrity != "ok" || foreign_keys != 0 || schema != version {
            return Err(StoreError::Migration(
                "pre-migration snapshot verification failed; original schema retained".into(),
            ));
        }
        drop(copy);
        // The temporary file already has a unique, private path; retaining it
        // cannot overwrite an older rollback copy.
        backup.keep().map_err(|e| StoreError::Io(e.error))?;
        std::fs::File::open(parent)?.sync_all()?;
        Ok(())
    }
    pub fn connect(&self) -> StoreResult<Connection> {
        let c =
            Connection::open_with_flags(&self.path, rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE)?;
        Self::check_version(&c)?;
        Self::policy(&c)?;
        Ok(c)
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn schema_version(&self) -> StoreResult<i64> {
        let c = self.connect()?;
        Ok(c.query_row(
            "SELECT value FROM schema_meta WHERE key='schema_version'",
            [],
            |r| r.get(0),
        )?)
    }
    pub fn apply_migration(&self, sql: &str) -> StoreResult<()> {
        let mut c = self.connect()?;
        Self::pre_migration_snapshot(&c, &self.path, 2)?;
        let t = c.transaction()?;
        t.execute_batch(sql)?;
        t.commit()?;
        Ok(())
    }
    pub fn close(&self) -> StoreResult<()> {
        Ok(())
    }
}

/// A transaction wrapper for atomic operations.
pub struct Txn<'a> {
    inner: RusqliteTransaction<'a>,
}

impl<'a> Txn<'a> {
    pub fn from_conn(conn: &'a mut Connection) -> Self {
        let inner = conn.transaction().expect("transaction start");
        Self { inner }
    }

    /// Commit the transaction.
    pub fn commit(self) -> StoreResult<()> {
        self.inner.commit().map_err(StoreError::Database)?;
        Ok(())
    }

    /// Roll back the transaction.
    pub fn rollback(self) -> StoreResult<()> {
        self.inner.rollback().map_err(StoreError::Database)?;
        Ok(())
    }

    /// Execute SQL within the transaction.
    pub fn execute(&self, sql: &str) -> StoreResult<usize> {
        self.inner.execute(sql, []).map_err(StoreError::Database)
    }

    /// Execute SQL with parameters within the transaction.
    pub fn execute_params(&self, sql: &str, params: impl rusqlite::Params) -> StoreResult<usize> {
        self.inner
            .execute(sql, params)
            .map_err(StoreError::Database)
    }

    /// Query a single row.
    pub fn query_row<T, F>(&self, sql: &str, f: F) -> StoreResult<T>
    where
        F: FnOnce(&rusqlite::Row<'_>) -> rusqlite::Result<T>,
    {
        self.inner
            .query_row(sql, [], f)
            .map_err(StoreError::Database)
    }

    /// Query multiple rows.
    pub fn query_map<T, F>(&self, sql: &str, f: F) -> StoreResult<Vec<T>>
    where
        F: FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<T>,
    {
        let mut stmt = self.inner.prepare(sql).map_err(StoreError::Database)?;
        let rows = stmt.query_map([], f).map_err(StoreError::Database)?;
        let mut results = Vec::new();
        for row in rows {
            results.push(row?);
        }
        Ok(results)
    }

    /// Inner connection reference.
    pub fn inner(&self) -> &RusqliteTransaction<'a> {
        &self.inner
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db() -> (Database, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.db");
        let db = Database::open(&path).unwrap();
        (db, dir)
    }

    #[test]
    fn open_creates_database() {
        let (db, _dir) = temp_db();
        assert!(db.path().exists());
    }

    #[test]
    fn schema_version_is_current_on_new_db() {
        let (db, _dir) = temp_db();
        assert_eq!(db.schema_version().unwrap(), 2);
    }

    #[test]
    fn can_execute_sql() {
        let (db, _dir) = temp_db();
        let conn = db.connect().unwrap();
        conn.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)", [])
            .unwrap();

        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM test", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 0);
    }

    #[test]
    fn transaction_commits() {
        let (db, _dir) = temp_db();
        let mut conn = db.connect().unwrap();

        {
            let tx = Txn::from_conn(&mut conn);
            tx.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
                .unwrap();
            tx.commit().unwrap();
        }

        // Table persists after transaction.
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE name='t'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn wal_mode_is_enabled() {
        let (db, _dir) = temp_db();
        let conn = db.connect().unwrap();
        let mode: String = conn
            .query_row("PRAGMA journal_mode", [], |row| row.get(0))
            .unwrap();
        assert_eq!(mode.to_uppercase(), "WAL");
    }

    #[test]
    fn every_writer_uses_the_physical_restore_size_bound() {
        let (db, _directory) = temp_db();
        for _ in 0..2 {
            let conn = db.connect().unwrap();
            let page_size: i64 = conn
                .query_row("PRAGMA page_size", [], |r| r.get(0))
                .unwrap();
            let max_pages: i64 = conn
                .query_row("PRAGMA max_page_count", [], |r| r.get(0))
                .unwrap();
            assert_eq!((page_size * max_pages) as u64, MAX_PACKAGE_BYTES);
        }
    }

    #[test]
    fn foreign_keys_are_enforced() {
        let (db, _dir) = temp_db();
        let conn = db.connect().unwrap();

        conn.execute("CREATE TABLE parent (id INTEGER PRIMARY KEY)", [])
            .unwrap();

        conn.execute(
            "CREATE TABLE child (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parent(id))",
            [],
        )
        .unwrap();

        // This should fail because FK is enabled.
        let result = conn.execute("INSERT INTO child (id, parent_id) VALUES (1, 999)", []);
        assert!(result.is_err());
    }

    #[test]
    fn failed_snapshot_verification_prevents_schema_upgrade() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("invalid-old.sqlite");
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch(
            "PRAGMA foreign_keys=OFF;
            CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value INTEGER NOT NULL);
            INSERT INTO schema_meta VALUES('schema_version',1);
            CREATE TABLE parent(id INTEGER PRIMARY KEY);
            CREATE TABLE child(id INTEGER PRIMARY KEY,parent_id INTEGER REFERENCES parent(id));
            INSERT INTO child VALUES(1,999);",
        )
        .unwrap();
        drop(conn);
        assert!(Database::open_existing(&path).is_err());
        let conn = Connection::open(&path).unwrap();
        assert_eq!(
            conn.query_row(
                "SELECT value FROM schema_meta WHERE key='schema_version'",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            1
        );
        assert_eq!(
            conn.query_row("SELECT parent_id FROM child", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            999
        );
        assert_eq!(
            conn.query_row(
                "SELECT count(*) FROM sqlite_master WHERE name='workflow_entries'",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            0
        );
        assert!(!std::fs::read_dir(directory.path())
            .unwrap()
            .filter_map(Result::ok)
            .any(|e| e.file_name().to_string_lossy().contains("before-schema")));
    }
}
