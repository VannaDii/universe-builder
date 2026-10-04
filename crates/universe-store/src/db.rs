//! SQLite connection policy and atomic schema installation.
use crate::{StoreError, StoreResult};
pub use rusqlite::Connection;
use rusqlite::Transaction as RusqliteTransaction;
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
    fn check_schema(conn: &Connection) -> StoreResult<()> {
        let columns: Vec<String> = conn
            .prepare("PRAGMA table_info(record_versions)")?
            .query_map([], |r| r.get(1))?
            .collect::<Result<_, _>>()?;
        if columns
            != [
                "universe_id",
                "id",
                "record_id",
                "kind",
                "payload_row",
                "digest",
            ]
        {
            return Err(StoreError::Migration("package requires explicit conversion to the normative relational model; original preserved".into()));
        }
        let workflow_columns: Vec<String> = conn
            .prepare("PRAGMA table_info(workflow_entries)")?
            .query_map([], |r| r.get(1))?
            .collect::<Result<_, _>>()?;
        if workflow_columns.iter().any(|name| name == "payload")
            || !workflow_columns.iter().any(|name| name == "StoredProposal")
        {
            return Err(StoreError::Migration(
                "package requires explicit relational workflow conversion; original preserved"
                    .into(),
            ));
        }
        let boundary:bool=conn.query_row("SELECT count(*)=4 FROM sqlite_master WHERE name IN ('historical_workflow','historical_receipt','active_workflow_index','import_workflow_digest')",[],|r|r.get(0))?;
        if !boundary {
            return Err(StoreError::Migration("package requires explicit historical-authority boundary conversion; original preserved".into()));
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
    fn initialize(conn: &mut Connection, _path: &Path) -> StoreResult<()> {
        let populated: bool = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%')", [], |r| r.get(0))?;
        // Inspect before journal/policy changes. Opening an existing package
        // never converts data or installs an alternate pre-release layout.
        if populated {
            Self::check_schema(conn)?;
            Self::policy(conn)?;
            conn.execute_batch("PRAGMA journal_mode=WAL;")?;
            return Ok(());
        }
        Self::policy(conn)?;
        conn.execute_batch("PRAGMA journal_mode=WAL;")?;
        let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
        tx.execute_batch(crate::relational::SQL)?;
        tx.execute_batch(include_str!(
            "../../../docs/decisions/relational-storage/kernel.sql"
        ))?;
        tx.execute_batch(include_str!(
            "../../../docs/decisions/relational-storage/semantic.sql"
        ))?;
        tx.execute_batch(include_str!(
            "../../../docs/decisions/relational-storage/workflow.sql"
        ))?;
        tx.commit()?;
        Ok(())
    }
    pub fn connect(&self) -> StoreResult<Connection> {
        let c =
            Connection::open_with_flags(&self.path, rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE)?;
        Self::check_schema(&c)?;
        Self::policy(&c)?;
        Ok(c)
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn apply_migration(&self, sql: &str) -> StoreResult<()> {
        let mut c = self.connect()?;
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
    fn new_database_has_one_normative_body_pointer() {
        let (db, _dir) = temp_db();
        Database::check_schema(&db.connect().unwrap()).unwrap();
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
    fn unrecognized_existing_package_is_refused_unchanged() {
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
