//! Internal immutable storage API. Never exposed as an application commit bypass.
use crate::{
    ownership::FileLock, selector::selector_key, Connection, Database, StoreError, StoreResult,
};
use rusqlite::{params, OptionalExtension, TransactionBehavior};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
};
use universe_domain::{canonical::canonical_serde, ids::*, records::*};
#[path = "archive.rs"]
mod archive;
pub use archive::{ArchiveManifest, LogicalArchive, MAX_ARCHIVE_BYTES};
#[path = "media.rs"]
mod media;
pub use media::{validate_image_metadata, MAX_IMAGE_BYTES};
#[path = "initialization.rs"]
mod initialization;
pub use universe_domain::records::InitializationReceipt;
pub type Membership = BTreeMap<String, String>;
// Includes propositions and evidence, not just discoverable entities.
const MAX_RECORDS: usize = 500_000;
const MAX_CHAIN: usize = 10_000;
const MAX_VERSIONS: usize = 1_000_000;
const MAX_RESTORE_BYTES: u64 = crate::db::MAX_PACKAGE_BYTES;
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Assignment {
    pub record_id: RecordId,
    pub expected: Option<RecordVersionId>,
    pub next: Option<RecordVersion>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitInput {
    pub universe: UniverseId,
    pub continuity: ContinuityId,
    pub expected_head: RevisionId,
    pub principal: PrincipalId,
    pub decision: String,
    pub reason: String,
    pub idempotency_key: String,
    pub changes: Vec<Assignment>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FaultPoint {
    Versions,
    Changes,
    Head,
    Projections,
    Receipt,
    BeforeCommit,
    SnapshotRows,
    SnapshotPublish,
    BackupCopied,
    BackupVerified,
    RestoreRows,
    RestoreVerified,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelStatus {
    pub universe: UniverseId,
    pub sqlite_version: String,
    pub journal_mode: String,
    pub synchronous: i64,
    pub foreign_keys: bool,
    pub heads: Vec<(String, String)>,
}
pub struct Kernel {
    conn: Connection,
    _lock: FileLock,
    _package: std::fs::File,
    universe: UniverseId,
}
fn invalid(s: &str) -> StoreError {
    StoreError::StorageFailure(s.into())
}
fn digest<T: Serialize>(v: &T) -> String {
    hex::encode(Sha256::digest(canonical_serde(v).to_bytes()))
}
fn new_revision() -> RevisionId {
    RevisionId::generate(&mut rand::rng())
}
fn compare_workflow(
    conn: &rusqlite::Connection,
    expected: &[(String, Option<String>)],
) -> StoreResult<()> {
    for (prefix, expected_key) in expected {
        let latest: Option<String> = conn.query_row(
            "SELECT key FROM active_workflow_index WHERE substr(key,1,length(?1))=?1 ORDER BY key DESC LIMIT 1",
            [prefix], |r| r.get(0),
        ).optional()?;
        if &latest != expected_key {
            return Err(invalid("workflow comparison conflict"));
        }
    }
    Ok(())
}
impl Kernel {
    pub fn create(
        path: &Path,
        universe: UniverseId,
        name: &str,
        continuity: ContinuityId,
        principal: &PrincipalId,
    ) -> StoreResult<Self> {
        selector_key(name)?;
        let _lock = FileLock::acquire(&path.with_extension("writer.lock"))?;
        if path.exists() {
            return Err(invalid("package already exists"));
        }
        use std::os::unix::fs::OpenOptionsExt;
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path)?;
        let _package = crate::ownership::protected_file(path, false)?;
        let db = Database::open(path)?;
        let mut conn = db.connect()?;
        let revision = new_revision();
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.prepare_cached("INSERT INTO universes(id,name) VALUES(?1,?2)")?
            .execute(params![universe.as_str(), name])?;
        tx.prepare_cached("INSERT INTO continuities VALUES(?1,?2,?3,NULL)")?
            .execute(params![
                universe.as_str(),
                continuity.as_str(),
                revision.as_str()
            ])?;
        tx.prepare_cached("INSERT INTO commits VALUES(?1,?2,?3,NULL,0,?4,'genesis','genesis',?5)")?
            .execute(params![
                universe.as_str(),
                revision.as_str(),
                continuity.as_str(),
                principal.as_str(),
                digest(&Membership::new())
            ])?;
        set_head_projection(
            &tx,
            universe.as_str(),
            continuity.as_str(),
            revision.as_str(),
            &Membership::new(),
        )?;
        tx.commit()?;
        std::fs::File::open(path.parent().unwrap_or(Path::new(".")))?.sync_all()?;
        Ok(Self {
            conn,
            _lock,
            _package,
            universe,
        })
    }
    pub fn open(path: &Path) -> StoreResult<Self> {
        if std::fs::symlink_metadata(path)?.file_type().is_symlink() {
            return Err(invalid("package path is a symlink"));
        }
        let canonical = path.canonicalize()?;
        let _lock = FileLock::acquire(&canonical.with_extension("writer.lock"))?;
        let _package = crate::ownership::protected_file(&canonical, false)?;
        let conn = Database::open_existing(canonical)?.connect()?;
        let uid: String = conn.query_row("SELECT id FROM universes", [], |r| r.get(0))?;
        let universe = UniverseId::parse(&uid).map_err(|_| invalid("invalid package identity"))?;
        let mut kernel = Self {
            conn,
            _lock,
            _package,
            universe,
        };
        kernel.integrity()?;
        // Projections are disposable, never authority on recovery.
        kernel.rebuild_projections(|_| Ok(()))?;
        Ok(kernel)
    }
    pub fn universe(&self) -> &UniverseId {
        &self.universe
    }
    pub fn head(&self, c: &ContinuityId) -> StoreResult<RevisionId> {
        let s: String = self.conn.query_row(
            "SELECT head_commit FROM continuities WHERE universe_id=?1 AND id=?2",
            params![self.universe.as_str(), c.as_str()],
            |r| r.get(0),
        )?;
        RevisionId::parse(&s).map_err(|_| invalid("invalid head"))
    }
    pub fn status(&self) -> StoreResult<KernelStatus> {
        let heads = self
            .conn
            .prepare("SELECT id,head_commit FROM continuities ORDER BY id")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<Result<_, _>>()?;
        Ok(KernelStatus {
            universe: self.universe.clone(),
            sqlite_version: rusqlite::version().into(),
            journal_mode: self
                .conn
                .query_row("PRAGMA journal_mode", [], |r| r.get(0))?,
            synchronous: self
                .conn
                .query_row("PRAGMA synchronous", [], |r| r.get(0))?,
            foreign_keys: self
                .conn
                .query_row("PRAGMA foreign_keys", [], |r| r.get(0))?,
            heads,
        })
    }
    pub fn snapshot(&self, c: &ContinuityId, r: &RevisionId) -> StoreResult<Membership> {
        let map = resolve(
            &self.conn,
            self.universe.as_str(),
            c.as_str(),
            r.as_str(),
            &mut BTreeSet::new(),
        )?;
        validate_candidate(&self.conn, self.universe.as_str(), &map)?;
        Ok(map)
    }
    pub fn records(&self, c: &ContinuityId, r: &RevisionId) -> StoreResult<Vec<RecordVersion>> {
        let map = resolve(
            &self.conn,
            self.universe.as_str(),
            c.as_str(),
            r.as_str(),
            &mut BTreeSet::new(),
        )?;
        let records = map
            .values()
            .map(|v| load(&self.conn, self.universe.as_str(), v))
            .collect::<StoreResult<Vec<_>>>()?;
        validate_records(&self.conn, self.universe.as_str(), &map, &records)?;
        Ok(records)
    }
    pub fn commit(&mut self, input: &CommitInput) -> StoreResult<RevisionId> {
        self.commit_with_hook(input, |_| Ok(()))
    }
    pub fn commit_with_hook(
        &mut self,
        input: &CommitInput,
        hook: impl FnMut(FaultPoint) -> StoreResult<()>,
    ) -> StoreResult<RevisionId> {
        self.commit_compared_with_hook(input, &[], hook)
    }
    /// Compare immutable workflow selection/proposal keys in the same write
    /// transaction as canonical publication. Exact receipt retries remain historical.
    pub fn commit_compared(
        &mut self,
        input: &CommitInput,
        expected: &[(String, Option<String>)],
    ) -> StoreResult<RevisionId> {
        self.commit_compared_with_hook(input, expected, |_| Ok(()))
    }
    pub fn commit_compared_with_hook(
        &mut self,
        input: &CommitInput,
        expected: &[(String, Option<String>)],
        mut hook: impl FnMut(FaultPoint) -> StoreResult<()>,
    ) -> StoreResult<RevisionId> {
        if input.universe != self.universe
            || input.changes.is_empty()
            || input.changes.len() > 100
            || input.idempotency_key.trim().is_empty()
            || input.decision.trim().is_empty()
        {
            return Err(invalid("invalid commit scope, size, key, or decision"));
        }
        let hash = digest(input);
        let uid = self.universe.as_str();
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let old:Option<(String,String)>=tx.query_row("SELECT payload_digest,revision_id FROM operation_receipts WHERE universe_id=?1 AND principal=?2 AND operation_kind='commit' AND idempotency_key=?3 AND NOT EXISTS(SELECT 1 FROM historical_receipt h WHERE h.universe_id=operation_receipts.universe_id AND h.principal=operation_receipts.principal AND h.operation_kind=operation_receipts.operation_kind AND h.idempotency_key=operation_receipts.idempotency_key)",params![uid,input.principal.as_str(),input.idempotency_key],|r|Ok((r.get(0)?,r.get(1)?))).optional()?;
        if let Some((prior, revision)) = old {
            if prior != hash {
                return Err(invalid("idempotency key reused"));
            }
            return RevisionId::parse(&revision).map_err(|_| invalid("invalid receipt"));
        }
        compare_workflow(&tx, expected)?;
        let head: String = tx.query_row(
            "SELECT head_commit FROM continuities WHERE universe_id=?1 AND id=?2",
            params![uid, input.continuity.as_str()],
            |r| r.get(0),
        )?;
        if head != input.expected_head.as_str() {
            return Err(StoreError::RevisionConflict {
                expected: input.expected_head.0.clone(),
                actual: head,
            });
        }
        let mut map = resolve(
            &tx,
            uid,
            input.continuity.as_str(),
            &head,
            &mut BTreeSet::new(),
        )?;
        let base = map.clone();
        let mut changed = BTreeSet::new();
        for change in &input.changes {
            let rid = change.record_id.as_str();
            if !changed.insert(rid)
                || map.get(rid).map(String::as_str) != change.expected.as_ref().map(|v| v.as_str())
            {
                return Err(invalid("duplicate assignment or prior-version conflict"));
            }
            if let Some(v) = &change.next {
                if v.identity.universe_id != input.universe
                    || v.identity.record_id != change.record_id
                    || v.identity.record_kind != v.payload.kind()
                    || !v.verify_digest()
                {
                    return Err(invalid("record universe/kind/digest mismatch"));
                }
                if let Payload::ImageAsset(asset) = &v.payload {
                    let bytes = media::image_bytes_from(&tx, asset)?;
                    media::validate_image_bytes(asset, &bytes)?;
                }
                let bytes = canonical_serde(v).to_bytes();
                if bytes.len() > 1_048_576 {
                    return Err(invalid("record too large"));
                }
                tx.prepare_cached("INSERT INTO record_identities VALUES(?1,?2,?3) ON CONFLICT(universe_id,id) DO NOTHING")?.execute(params![uid,rid,v.payload.kind().as_str()])?;
                insert_version(&tx, v)?;
                map.insert(rid.into(), v.record_version_id.0.clone());
            } else {
                if change.expected.is_none() {
                    return Err(invalid("cannot tombstone an absent record"));
                }
                map.remove(rid);
            }
        }
        if map.len() > MAX_RECORDS {
            return Err(invalid("record budget exceeded"));
        }
        let versions: i64 =
            tx.query_row("SELECT count(*) FROM record_versions", [], |r| r.get(0))?;
        if versions > MAX_VERSIONS as i64 {
            return Err(invalid(
                "history budget exceeded; existing canon remains intact",
            ));
        }

        hook(FaultPoint::Versions)?;
        validate_candidate(&tx, uid, &map)?;
        for record in input
            .changes
            .iter()
            .filter_map(|change| change.next.as_ref())
        {
            index_definition(&tx, record, &map)?;
        }
        let initialization = initialization::pending(&tx, input, &base, &map)?;
        let revision = new_revision();
        let seq: i64 = tx.query_row(
            "SELECT sequence+1 FROM commits WHERE universe_id=?1 AND id=?2",
            params![uid, head],
            |r| r.get(0),
        )?;
        if seq >= MAX_CHAIN as i64 {
            return Err(invalid(
                "continuity history budget reached; fork a pinned continuation before writing",
            ));
        }
        tx.prepare_cached("INSERT INTO commits VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)")?
            .execute(params![
                uid,
                revision.as_str(),
                input.continuity.as_str(),
                head,
                seq,
                input.principal.as_str(),
                input.decision,
                input.reason,
                hash
            ])?;
        for change in &input.changes {
            tx.prepare_cached("INSERT INTO commit_changes VALUES(?1,?2,?3,?4,?5)")?
                .execute(params![
                    uid,
                    revision.as_str(),
                    change.record_id.as_str(),
                    change.expected.as_ref().map(|v| v.as_str()),
                    change.next.as_ref().map(|v| v.record_version_id.as_str())
                ])?;
            if let Some(RecordVersion {
                payload: Payload::World(w),
                ..
            }) = &change.next
            {
                for name in std::iter::once(&w.selector).chain(w.aliases.iter()) {
                    let key = selector_key(name)?;
                    let reserved:Option<String>=tx.query_row("SELECT record_id FROM world_name_reservations WHERE universe_id=?1 AND name=?2",params![uid,key],|r|r.get(0)).optional()?;
                    if reserved
                        .as_deref()
                        .is_some_and(|r| r != change.record_id.as_str())
                    {
                        return Err(invalid("world selector name reserved to another identity"));
                    }
                    tx.prepare_cached("INSERT INTO world_name_reservations VALUES(?1,?2,?3,?4) ON CONFLICT DO NOTHING")?.execute(params![uid,key,change.record_id.as_str(),revision.as_str()])?;
                }
            }
        }
        for mut receipt in initialization {
            receipt.revision = revision.clone();
            initialization::insert(&tx, uid, &receipt)?;
        }
        hook(FaultPoint::Changes)?;
        tx.prepare_cached("UPDATE continuities SET head_commit=?3 WHERE universe_id=?1 AND id=?2")?
            .execute(params![uid, input.continuity.as_str(), revision.as_str()])?;
        set_head_projection(&tx, uid, input.continuity.as_str(), revision.as_str(), &map)?;
        hook(FaultPoint::Head)?;
        let generation: i64 =
            tx.query_row("SELECT generation FROM projection_state", [], |r| r.get(0))?;
        for v in input.changes.iter().filter_map(|a| a.next.as_ref()) {
            project(&tx, generation, v)?;
        }
        hook(FaultPoint::Projections)?;
        tx.prepare_cached("INSERT INTO operation_receipts VALUES(?1,?2,'commit',?3,?4,?5)")?
            .execute(params![
                uid,
                input.principal.as_str(),
                input.idempotency_key,
                hash,
                revision.as_str()
            ])?;
        hook(FaultPoint::Receipt)?;
        hook(FaultPoint::BeforeCommit)?;
        tx.commit()?;
        Ok(revision)
    }
    /// Validate with precisely the same structural and reservation gates as commit.
    /// The transaction is always rolled back before returning the candidate.
    pub fn identity_exists(&self, id: &RecordId) -> StoreResult<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM record_identities WHERE universe_id=?1 AND id=?2)",
            params![self.universe.as_str(), id.as_str()],
            |r| r.get(0),
        )?)
    }
    /// Newest-first history reachable from this exact continuity/revision, including fork ancestry.
    pub fn record_history(
        &self,
        continuity: &ContinuityId,
        revision: &RevisionId,
        record: &RecordId,
    ) -> StoreResult<Vec<Value>> {
        self.snapshot(continuity, revision)?;
        let mut next = Some(revision.to_string());
        let mut seen = BTreeSet::new();
        let mut entries = Vec::new();
        while let Some(id) = next {
            if !seen.insert(id.clone()) || seen.len() > MAX_CHAIN {
                return Err(invalid("history chain budget exceeded"));
            }
            let (parent, branch, principal, reason): (Option<String>, String, String, String) = self.conn.query_row(
                "SELECT parent_id,continuity_id,principal,reason FROM commits WHERE universe_id=?1 AND id=?2",
                params![self.universe.as_str(), id], |r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?)))?;
            let version: Option<Option<String>> = self.conn.query_row(
                "SELECT version_id FROM commit_changes WHERE universe_id=?1 AND revision_id=?2 AND record_id=?3",
                params![self.universe.as_str(),id,record.as_str()], |r|r.get(0)).optional()?;
            if let Some(version) = version {
                let value = version
                    .map(|v| load(&self.conn, self.universe.as_str(), &v))
                    .transpose()?;
                entries.push(serde_json::json!({"record_id":record,"revision":id,"continuity":branch,"principal":principal,"reason":reason,"record":value}));
                if entries.len() > 100 {
                    return Err(invalid(
                        "record history exceeds 100 changes; select an earlier pinned revision",
                    ));
                }
            }
            next = if parent.is_some() {
                parent
            } else {
                self.conn.query_row(
                    "SELECT baseline_commit FROM continuities WHERE universe_id=?1 AND id=?2",
                    params![self.universe.as_str(), branch],
                    |r| r.get(0),
                )?
            };
        }
        Ok(entries)
    }
    pub fn record_version(&self, version: &RecordVersionId) -> StoreResult<RecordVersion> {
        load(&self.conn, self.universe.as_str(), version.as_str())
    }
    pub fn preview(&mut self, input: &CommitInput) -> StoreResult<Vec<RecordVersion>> {
        let mut probe = input.clone();
        probe.idempotency_key = format!("preview:{}", new_revision());
        let mut reached = false;
        let result = self.commit_with_hook(&probe, |point| {
            if point == FaultPoint::BeforeCommit {
                reached = true;
                return Err(invalid("preview rollback"));
            }
            Ok(())
        });
        if !reached {
            result?;
            return Err(invalid("preview did not run"));
        }
        let mut records: BTreeMap<_, _> = self
            .records(&input.continuity, &input.expected_head)?
            .into_iter()
            .map(|r| (r.identity.record_id.clone(), r))
            .collect();
        for a in &input.changes {
            if let Some(v) = &a.next {
                records.insert(a.record_id.clone(), v.clone());
            } else {
                records.remove(&a.record_id);
            }
        }
        Ok(records.into_values().collect())
    }
    /// Explicit read of immutable historical evidence; never used for authority admission.
    pub fn workflow_evidence_get(&self, key: &str) -> StoreResult<Option<Value>> {
        crate::workflow_storage::evidence(&self.conn, key)
    }
    pub fn workflow_get(&self, key: &str) -> StoreResult<Option<Value>> {
        crate::workflow_storage::get(&self.conn, key)
    }

    /// Publish proposal, request receipt and operation index together.
    pub fn workflow_put(&mut self, entries: &[(String, Value)]) -> StoreResult<()> {
        self.workflow_compare_append(&[], entries)
    }
    /// Compare the latest immutable key in each namespace and append all evidence
    /// in one immediate transaction. No mutable selection pointer is needed.
    pub fn workflow_compare_append(
        &mut self,
        expected: &[(String, Option<String>)],
        entries: &[(String, Value)],
    ) -> StoreResult<()> {
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        compare_workflow(&tx, expected)?;
        for (key, value) in entries {
            crate::workflow_storage::put(&tx, key, value)?;
        }
        tx.commit()?;
        Ok(())
    }
    pub fn workflow_latest_key(&self, prefix: &str) -> StoreResult<Option<String>> {
        Ok(self.conn.query_row(
            "SELECT key FROM active_workflow_index WHERE substr(key,1,length(?1))=?1 ORDER BY key DESC LIMIT 1",
            [prefix], |r| r.get(0),
        ).optional()?)
    }
    pub fn workflow_keys(&self, prefix: &str) -> StoreResult<Vec<String>> {
        Ok(self
            .conn
            .prepare(
                "SELECT key FROM active_workflow_index WHERE substr(key,1,?1)=?2 ORDER BY key LIMIT 10001",
            )?
            .query_map(params![prefix.len() as i64, prefix], |r| r.get(0))?
            .collect::<Result<_, _>>()?)
    }
    pub fn receipt(&self, input: &CommitInput) -> StoreResult<Option<RevisionId>> {
        let row: Option<(String,String)> = self.conn.query_row(
            "SELECT payload_digest,revision_id FROM operation_receipts WHERE universe_id=?1 AND principal=?2 AND operation_kind='commit' AND idempotency_key=?3 AND NOT EXISTS(SELECT 1 FROM historical_receipt h WHERE h.universe_id=operation_receipts.universe_id AND h.principal=operation_receipts.principal AND h.operation_kind=operation_receipts.operation_kind AND h.idempotency_key=operation_receipts.idempotency_key)",
            params![self.universe.as_str(),input.principal.as_str(),input.idempotency_key], |r| Ok((r.get(0)?,r.get(1)?))).optional()?;
        row.map(|(hash, id)| {
            if hash != digest(input) {
                return Err(invalid("idempotency key reused"));
            }
            RevisionId::parse(&id).map_err(|_| invalid("invalid receipt"))
        })
        .transpose()
    }
    /// Consistent SQLite snapshot, verified before atomic, no-clobber publication.
    /// Source text and workflow evidence live in the same transactional package.
    pub fn stage_restore(source: &Path, scratch: &Path) -> StoreResult<(Self, tempfile::TempDir)> {
        Self::stage_restore_with_hook(source, scratch, |_| Ok(()))
    }
    pub fn stage_restore_with_hook(
        source: &Path,
        scratch: &Path,
        mut hook: impl FnMut(FaultPoint) -> StoreResult<()>,
    ) -> StoreResult<(Self, tempfile::TempDir)> {
        let input = crate::ownership::protected_file(source, false)?;
        if input.metadata()?.len() > MAX_RESTORE_BYTES {
            return Err(invalid("restore package exceeds 8 GiB limit"));
        }
        let temporary = tempfile::Builder::new()
            .prefix(".restore-")
            .tempdir_in(scratch)?;
        let path = temporary.path().join("package.sqlite");
        crate::ownership::protected_file(&path, true)?;
        crate::transfer::trusted_copy(source, &path, false, || hook(FaultPoint::RestoreRows))?;
        let c = Database::open_existing(&path)?.connect()?;
        archive::mark_historical(&c)?;
        drop(c);
        let kernel = Self::open(&path)?;
        verify_content_links(&kernel.conn)?;
        verify_history(&kernel.conn, kernel.universe.as_str())?;
        hook(FaultPoint::RestoreVerified)?;
        Ok((kernel, temporary))
    }
    pub fn backup(&self, destination: &Path) -> StoreResult<()> {
        self.backup_with_hook(destination, |_| Ok(()))
    }
    pub fn backup_with_hook(
        &self,
        destination: &Path,
        mut hook: impl FnMut(FaultPoint) -> StoreResult<()>,
    ) -> StoreResult<()> {
        let parent = destination
            .parent()
            .ok_or_else(|| invalid("backup parent required"))?;
        let temporary = tempfile::Builder::new()
            .prefix(".universe-backup-")
            .tempfile_in(parent)?;
        let path = temporary
            .path()
            .to_str()
            .ok_or_else(|| invalid("backup path must be UTF-8"))?;
        self.conn.execute("VACUUM INTO ?1", [path])?;
        temporary.as_file().sync_all()?;
        hook(FaultPoint::BackupCopied)?;
        if temporary.as_file().metadata()?.len() > MAX_RESTORE_BYTES {
            return Err(invalid(
                "backup exceeds restore budget; original is unchanged",
            ));
        }
        let copy = Connection::open_with_flags(
            temporary.path(),
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )?;
        let check: String = copy.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
        if check != "ok" {
            return Err(invalid("backup integrity failure"));
        }
        let violations: i64 =
            copy.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| {
                r.get(0)
            })?;
        if violations != 0 {
            return Err(invalid("backup foreign key failure"));
        }
        // Verify canonical data, workflow/source bytes and historical chains in
        // the actual copy before publishing a backup as successful.
        verify_canonical(&copy, self.universe.as_str())?;
        verify_content_links(&copy)?;
        let heads: Vec<(String, String)> = copy
            .prepare("SELECT id,head_commit FROM continuities")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<Result<_, _>>()?;
        let mut verified_memberships = BTreeSet::new();
        for (continuity, revision) in heads {
            let map = resolve(
                &copy,
                self.universe.as_str(),
                &continuity,
                &revision,
                &mut BTreeSet::new(),
            )?;
            // Identical immutable memberships need one content check within
            // this verified copy; every continuity chain still resolves.
            if verified_memberships.insert(digest(&map)) {
                validate_candidate(&copy, self.universe.as_str(), &map)?;
            }
        }
        verify_history(&copy, self.universe.as_str())?;
        hook(FaultPoint::BackupVerified)?;
        drop(copy);
        temporary
            .persist_noclobber(destination)
            .map_err(|e| StoreError::Io(e.error))?;
        std::fs::File::open(parent)?.sync_all()?;
        Ok(())
    }
    pub fn branch(
        &mut self,
        id: &ContinuityId,
        from: &ContinuityId,
        base: &RevisionId,
        principal: &PrincipalId,
    ) -> StoreResult<RevisionId> {
        let map = self.snapshot(from, base)?;
        let existing: Option<Option<String>> = self
            .conn
            .query_row(
                "SELECT baseline_commit FROM continuities WHERE universe_id=?1 AND id=?2",
                params![self.universe.as_str(), id.as_str()],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(existing) = existing {
            if existing.as_deref() != Some(base.as_str()) {
                return Err(invalid("continuity identity already has another baseline"));
            }
            return self.conn.query_row("SELECT id FROM commits WHERE universe_id=?1 AND continuity_id=?2 AND sequence=0",params![self.universe.as_str(),id.as_str()],|r|r.get::<_,String>(0)).map_err(StoreError::from).and_then(|s|RevisionId::parse(&s).map_err(|_|invalid("invalid branch revision")));
        }
        let revision = new_revision();
        let uid = self.universe.as_str();
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.prepare_cached("INSERT INTO continuities VALUES(?1,?2,?3,?4)")?
            .execute(params![uid, id.as_str(), revision.as_str(), base.as_str()])?;
        tx.prepare_cached(
            "INSERT INTO commits VALUES(?1,?2,?3,NULL,0,?4,'branch','pinned branch',?5)",
        )?
        .execute(params![
            uid,
            revision.as_str(),
            id.as_str(),
            principal.as_str(),
            digest(&map)
        ])?;
        // Admission must satisfy the same ancestry budget as recovery. A new
        // branch must never make an otherwise healthy package unopenable.
        let recovered = resolve(
            &tx,
            uid,
            id.as_str(),
            revision.as_str(),
            &mut BTreeSet::new(),
        )?;
        if recovered != map {
            return Err(invalid("branch baseline reconstruction mismatch"));
        }
        set_head_projection(&tx, uid, id.as_str(), revision.as_str(), &map)?;
        tx.commit()?;
        Ok(revision)
    }
    pub fn cache_snapshot(
        &mut self,
        c: &ContinuityId,
        r: &RevisionId,
        mut hook: impl FnMut(FaultPoint) -> StoreResult<()>,
    ) -> StoreResult<()> {
        let map = self.snapshot(c, r)?;
        let hash = digest(&map);
        let tx = self.conn.transaction()?;
        tx.execute(
            "DELETE FROM snapshot_member WHERE universe_id=?1 AND revision_id=?2",
            params![self.universe.as_str(), r.as_str()],
        )?;
        tx.prepare_cached("INSERT OR REPLACE INTO snapshot_membership VALUES(?1,?2,?3)")?
            .execute(params![self.universe.as_str(), r.as_str(), hash])?;
        for (record, version) in &map {
            tx.prepare_cached("INSERT INTO snapshot_member VALUES(?1,?2,?3,?4)")?
                .execute(params![self.universe.as_str(), r.as_str(), record, version])?;
        }
        hook(FaultPoint::SnapshotRows)?;
        hook(FaultPoint::SnapshotPublish)?;
        tx.commit()?;
        Ok(())
    }
    pub fn rebuild_projections(
        &mut self,
        mut hook: impl FnMut(FaultPoint) -> StoreResult<()>,
    ) -> StoreResult<()> {
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let generation: i64 =
            tx.query_row("SELECT generation+1 FROM projection_state", [], |r| {
                r.get(0)
            })?;
        let ids: Vec<String> = tx
            .prepare("SELECT id FROM record_versions ORDER BY id")?
            .query_map([], |r| r.get(0))?
            .collect::<Result<_, _>>()?;
        if ids.len() > MAX_VERSIONS {
            return Err(invalid("projection rebuild budget exceeded"));
        }
        for id in ids {
            project(&tx, generation, &load(&tx, self.universe.as_str(), &id)?)?;
            hook(FaultPoint::Projections)?;
        }
        let heads: Vec<(String, String)> = tx
            .prepare("SELECT id,head_commit FROM continuities")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<Result<_, _>>()?;
        let mut verified_memberships = BTreeSet::new();
        for (c, r) in heads {
            let map = resolve(&tx, self.universe.as_str(), &c, &r, &mut BTreeSet::new())?;
            if verified_memberships.insert(digest(&map)) {
                validate_candidate(&tx, self.universe.as_str(), &map)?;
            }
            set_head_projection(&tx, self.universe.as_str(), &c, &r, &map)?;
        }
        tx.prepare_cached("UPDATE projection_state SET generation=?1")?
            .execute([generation])?;
        for table in [
            "reference_index",
            "typed_projection",
            "world_projection",
            "narrative_projection",
            "search_index",
        ] {
            tx.execute(
                &format!("DELETE FROM {table} WHERE generation!=?1"),
                [generation],
            )?;
        }
        hook(FaultPoint::BeforeCommit)?;
        tx.commit()?;
        Ok(())
    }
    pub fn search(
        &self,
        c: &ContinuityId,
        r: &RevisionId,
        query: &str,
    ) -> StoreResult<Vec<RecordVersion>> {
        if query.len() > 1024 {
            return Err(invalid("search too long"));
        }
        let map = self.snapshot(c, r)?;
        if query.is_empty() {
            return self.records(c, r);
        }
        let escaped = format!("\"{}\"", query.replace('"', "\"\""));
        let versions:BTreeSet<String>=self.conn.prepare("SELECT version_id FROM search_index WHERE search_index MATCH ?1 AND generation=(SELECT generation FROM projection_state)")?.query_map([escaped],|r|r.get(0))?.collect::<Result<_,_>>()?;
        map.values()
            .filter(|v| versions.contains(*v))
            .map(|v| load(&self.conn, self.universe.as_str(), v))
            .collect()
    }
    pub fn integrity(&self) -> StoreResult<()> {
        let result: String = self
            .conn
            .query_row("PRAGMA quick_check", [], |r| r.get(0))?;
        if result != "ok" {
            return Err(invalid("SQLite integrity failure"));
        }
        if self.conn.prepare("PRAGMA foreign_key_check")?.exists([])? {
            return Err(invalid("foreign key integrity failure"));
        }
        verify_canonical(&self.conn, self.universe.as_str())?;
        initialization::verify(&self.conn, self.universe.as_str())?;
        Ok(())
    }
}
fn verify_canonical(c: &Connection, universe: &str) -> StoreResult<()> {
    let provenance:Vec<(String,String,String)>=c.prepare("SELECT p.source_digest,p.normalized_digest,v.digest FROM import_record_digest p JOIN record_versions v ON v.universe_id=p.universe_id AND v.id=p.version_id")?.query_map([],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?)))?.collect::<Result<_,_>>()?;
    for (source, normalized, current) in provenance {
        if normalized != current
            || source.len() != 64
            || !source
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        {
            return Err(invalid("import digest provenance mismatch"));
        }
    }
    let mut records = c.prepare("SELECT id FROM record_versions")?;
    let ids = records.query_map([], |r| r.get::<_, String>(0))?;
    let mut images = BTreeSet::new();
    for id in ids {
        let record = load(c, universe, &id?)?;
        if let Payload::ImageAsset(asset) = &record.payload {
            media::validate_image_metadata(asset)?;
            if images.insert(asset.digest.clone()) {
                media::image_bytes_from(c, asset)?;
            }
        }
    }
    let mut workflow = c.prepare("SELECT key FROM workflow_index")?;
    for key in workflow.query_map([], |r| r.get::<_, String>(0))? {
        crate::workflow_storage::evidence(c, &key?)?
            .ok_or_else(|| invalid("missing workflow evidence"))?;
    }
    Ok(())
}
// Complete transfer must reject lost staged content. Normal startup retains the
// existing missing-material reporting path for author repair.
pub(super) fn verify_content_links(c: &Connection) -> StoreResult<()> {
    let universe: String = c.query_row("SELECT id FROM universes", [], |r| r.get(0))?;
    let ids: Vec<String> = c
        .prepare("SELECT id FROM record_versions")?
        .query_map([], |r| r.get(0))?
        .collect::<Result<_, _>>()?;
    for id in ids {
        let record = load(c, &universe, &id)?;
        verify_content_payload(c, &universe, &record.payload)?;
        if let Payload::World(world) = &record.payload {
            for name in std::iter::once(&world.selector).chain(world.aliases.iter()) {
                let reserved:Option<String>=c.query_row("SELECT record_id FROM world_name_reservations WHERE universe_id=?1 AND name=?2",params![universe,selector_key(name)?],|r|r.get(0)).optional()?;
                if reserved.as_deref() != Some(record.identity.record_id.as_str()) {
                    return Err(invalid("archive omits a historical world name reservation"));
                }
            }
        }
    }
    let keys:Vec<String>=c.prepare("SELECT key FROM workflow_index WHERE key LIKE 'image-asset:%' OR key LIKE 'source-version:%'")?.query_map([],|r|r.get(0))?.collect::<Result<_,_>>()?;
    for key in keys {
        let value = crate::workflow_storage::evidence(c, &key)?
            .ok_or_else(|| invalid("missing staged content metadata"))?;
        let payload: Payload = serde_json::from_value(value)
            .map_err(|_| invalid("invalid staged content metadata"))?;
        if !matches!(payload, Payload::ImageAsset(_) | Payload::SourceVersion(_)) {
            return Err(invalid("wrong staged content family"));
        }
        verify_content_payload(c, &universe, &payload)?;
    }
    Ok(())
}
fn verify_content_payload(c: &Connection, universe: &str, payload: &Payload) -> StoreResult<()> {
    let source_text = |source: &SourceVersion| -> StoreResult<String> {
        let text = crate::workflow_storage::evidence(c, &format!("source:{}", source.digest))?
            .and_then(|v| v.as_str().map(str::to_owned))
            .ok_or_else(|| invalid("missing retained source bytes"))?;
        if text.len() as u64 != source.byte_size
            || source.decoding.byte_length != source.byte_size
            || source.decoding.encoding != "UTF-8"
            || source.decoding.representation != "exact-utf8-v1"
        {
            return Err(invalid("source decoding mismatch"));
        }
        Ok(text)
    };
    match payload {
        Payload::ImageAsset(asset) => {
            media::validate_image_metadata(asset)?;
            let bytes = media::image_bytes_from(c, asset)?;
            media::validate_image_bytes(asset, &bytes)?;
        }
        Payload::SourceVersion(source) => {
            source_text(source)?;
        }
        Payload::Anchor(anchor) => {
            let record = load(c, universe, anchor.source_version.version.as_str())?;
            if record.identity.record_id != anchor.source_version.record {
                return Err(invalid("archive anchor source identity mismatch"));
            }
            let Payload::SourceVersion(source) = record.payload else {
                return Err(invalid("archive anchor source kind"));
            };
            let text = source_text(&source)?;
            let AnchorLocator::ByteRange { start, end } = anchor.locator else {
                return Err(invalid("archive anchor locator unsupported"));
            };
            let excerpt = text
                .get(start as usize..end as usize)
                .ok_or_else(|| invalid("archive anchor UTF-8 boundaries"))?;
            if excerpt != anchor.excerpt
                || hex::encode(Sha256::digest(excerpt.as_bytes())) != anchor.excerpt_digest
            {
                return Err(invalid("archive anchor excerpt mismatch"));
            }
        }
        _ => (),
    }
    Ok(())
}
fn verify_history(c: &Connection, universe: &str) -> StoreResult<()> {
    let revisions: Vec<(String, String)> = c
        .prepare("SELECT id,continuity_id FROM commits ORDER BY id")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<_, _>>()?;
    let mut work = 0usize;
    let mut validated = BTreeSet::new();
    for (revision, continuity) in revisions {
        let map = resolve(c, universe, &continuity, &revision, &mut BTreeSet::new())?;
        work += map.len() + 1;
        if work > 10_000_000 {
            return Err(invalid("historical restoration validation budget exceeded"));
        }
        if validated.insert(digest(&map)) {
            validate_candidate(c, universe, &map)?;
        }
    }
    Ok(())
}
fn insert_version(tx: &rusqlite::Transaction<'_>, record: &RecordVersion) -> StoreResult<()> {
    let value = serde_json::to_value(&record.payload).map_err(|_| invalid("payload encoding"))?;
    let row = crate::relational::put(tx, "Payload", &value)?;
    tx.prepare_cached("INSERT INTO record_versions VALUES(?1,?2,?3,?4,?5,?6)")?
        .execute(params![
            record.identity.universe_id.as_str(),
            record.record_version_id.as_str(),
            record.identity.record_id.as_str(),
            record.identity.record_kind.as_str(),
            row,
            record.payload_digest.as_str()
        ])?;
    Ok(())
}
fn load(c: &Connection, u: &str, v: &str) -> StoreResult<RecordVersion> {
    let (row, rid, kind, stored): (i64, String, String, String) = c.prepare_cached(
        "SELECT payload_row,record_id,kind,digest FROM record_versions WHERE universe_id=?1 AND id=?2")?.query_row(
        params![u, v], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
    )?;
    let value = crate::relational::get(c, "Payload", rusqlite::types::Value::Integer(row))?;
    let payload: Payload =
        serde_json::from_value(value).map_err(|_| invalid("invalid stored payload"))?;
    let record = RecordVersion::build(
        RecordVersionId::parse(v).map_err(|_| invalid("invalid version identity"))?,
        RecordIdentity::new(
            UniverseId::parse(u).map_err(|_| invalid("invalid universe identity"))?,
            RecordId::parse(&rid).map_err(|_| invalid("invalid record identity"))?,
            RecordKind::parse(&kind).map_err(|_| invalid("invalid kind"))?,
        ),
        payload,
    )
    .map_err(|_| invalid("stored record kind mismatch"))?;
    // Comparison is mandatory: never replace historical evidence with a newly
    // calculated digest and call a mismatching body successful.
    if record.payload_digest.as_str() != stored {
        return Err(invalid("stored record integrity failure"));
    }
    Ok(record)
}
fn resolve(
    c: &Connection,
    u: &str,
    continuity: &str,
    revision: &str,
    visited: &mut BTreeSet<String>,
) -> StoreResult<Membership> {
    if visited.len() > 64 || !visited.insert(continuity.into()) {
        return Err(invalid("branch ancestry cycle or depth limit"));
    }
    let baseline: Option<String> = c.query_row(
        "SELECT baseline_commit FROM continuities WHERE universe_id=?1 AND id=?2",
        params![u, continuity],
        |r| r.get(0),
    )?;
    let mut map = if let Some(base) = baseline {
        let parent: String = c.query_row(
            "SELECT continuity_id FROM commits WHERE universe_id=?1 AND id=?2",
            params![u, base],
            |r| r.get(0),
        )?;
        resolve(c, u, &parent, &base, visited)?
    } else {
        Membership::new()
    };
    let mut chain = Vec::new();
    let mut next = Some(revision.to_owned());
    let mut seen = BTreeSet::new();
    let mut expected = None;
    while let Some(r) = next {
        if chain.len() >= MAX_CHAIN || !seen.insert(r.clone()) {
            return Err(invalid("revision chain cycle or budget exceeded"));
        }
        let(parent,seq):(Option<String>,i64)=c.query_row("SELECT parent_id,sequence FROM commits WHERE universe_id=?1 AND continuity_id=?2 AND id=?3",params![u,continuity,r],|row|Ok((row.get(0)?,row.get(1)?)))?;
        if expected.is_some_and(|n| n != seq) || (parent.is_none() && seq != 0) {
            return Err(invalid("broken revision chain"));
        }
        expected = Some(seq - 1);
        next = parent;
        chain.push(r);
    }
    for r in chain.iter().rev() {
        let changes:Vec<(String,Option<String>,Option<String>)>=c.prepare("SELECT record_id,prior_version,version_id FROM commit_changes WHERE universe_id=?1 AND revision_id=?2 ORDER BY record_id")?.query_map(params![u,r],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?)))?.collect::<Result<_,_>>()?;
        for (rid, prior, next) in changes {
            if map.get(&rid) != prior.as_ref() {
                return Err(invalid("historical prior-version mismatch"));
            }
            if let Some(v) = next {
                map.insert(rid, v);
            } else {
                map.remove(&rid);
            }
        }
        if map.len() > MAX_RECORDS {
            return Err(invalid("snapshot budget exceeded"));
        }
    }
    visited.remove(continuity);
    Ok(map)
}
fn set_head_projection(
    c: &Connection,
    u: &str,
    cont: &str,
    revision: &str,
    map: &Membership,
) -> StoreResult<()> {
    c.prepare_cached("DELETE FROM head_membership WHERE universe_id=?1 AND continuity_id=?2")?
        .execute(params![u, cont])?;
    for (r, v) in map {
        c.prepare_cached("INSERT INTO head_membership VALUES(?1,?2,?3,?4)")?
            .execute(params![u, cont, r, v])?;
    }
    c.prepare_cached("INSERT OR REPLACE INTO projection_heads VALUES(?1,?2,?3,?4)")?
        .execute(params![u, cont, revision, digest(map)])?;
    Ok(())
}
// Typed ID aliases share the opaque identity body with their canonical RecordId.
pub fn world_record(id: &WorldId) -> String {
    format!("rec_{}", &id.as_str()[4..])
}
pub fn record_world(id: &RecordId) -> WorldId {
    WorldId(format!("wld_{}", &id.as_str()[4..]))
}
#[derive(Default)]
struct References {
    records: Vec<(String, Option<String>, String)>,
    worlds: Vec<String>,
    typed: Vec<(String, RecordKind)>,
    scalars: Vec<(String, String)>,
}
/// Typed dependencies, using the same closed traversal as integrity validation.
pub fn record_dependencies(record: &RecordVersion) -> StoreResult<BTreeSet<RecordId>> {
    let value = serde_json::to_value(&record.payload).map_err(|_| invalid("payload encoding"))?;
    let refs = references(&value, record.identity.universe_id.as_str())?;
    refs.records
        .into_iter()
        .map(|(id, _, _)| id)
        .chain(refs.typed.into_iter().map(|(id, _)| id))
        .chain(refs.worlds.into_iter().map(|id| world_record(&WorldId(id))))
        .map(|id| RecordId::parse(&id).map_err(|_| invalid("invalid dependency identity")))
        .collect()
}
fn references(value: &Value, u: &str) -> StoreResult<References> {
    fn walk(v: &Value, u: &str, path: &str, key: &str, out: &mut References) -> StoreResult<()> {
        // Authored prose is not a reference, even when it resembles an ID.
        if matches!(
            key,
            "labels"
                | "text"
                | "title"
                | "selector"
                | "aliases"
                | "rationale"
                | "excerpt"
                | "description"
                | "note"
                | "symbol"
                | "client_ref"
                | "originNote"
                | "externallyAssertedAuthor"
                | "unitStructure"
                | "unit_structure"
                | "dependencies"
        ) {
            return Ok(());
        }
        match v {
            Value::Object(m) => {
                if let Some(owner) = m.get("universe").and_then(Value::as_str) {
                    if owner != u {
                        return Err(invalid("cross-universe reference"));
                    }
                }
                if let Some(r) = m
                    .get("record")
                    .and_then(Value::as_str)
                    .filter(|s| s.starts_with("rec_"))
                {
                    if m.get("universe").and_then(Value::as_str) != Some(u) {
                        return Err(invalid("canonical reference requires explicit universe"));
                    }
                    out.records.push((
                        r.into(),
                        m.get("version").and_then(Value::as_str).map(str::to_owned),
                        path.into(),
                    ));
                    // Do not turn a historical version reference into a current dependency.
                    for (k, v) in m {
                        if !matches!(k.as_str(), "record" | "universe" | "version") {
                            walk(v, u, &format!("{path}/{k}"), k, out)?;
                        }
                    }
                    return Ok(());
                }
                for (k, v) in m {
                    // Keys in typed-value maps are authored names, not DTO field
                    // names. A field called "text" may still contain a reference.
                    let field = if matches!(key, "metadata" | "qualifiers" | "fields") {
                        ""
                    } else {
                        k
                    };
                    walk(v, u, &format!("{path}/{k}"), field, out)?;
                }
            }
            Value::Array(a) => {
                for (i, v) in a.iter().enumerate() {
                    let field = if v.is_string() { key } else { "" };
                    walk(v, u, &format!("{path}/{i}"), field, out)?;
                }
            }
            Value::String(s) => {
                if matches!(
                    key,
                    "parent"
                        | "classification"
                        | "subjectTypes"
                        | "subject_types"
                        | "participantTypes"
                        | "participant_types"
                        | "records"
                        | "types"
                        | "versions"
                        | "entityType"
                        | "entity_type"
                        | "referenced_records"
                        | "referencedRecords"
                        | "observer"
                ) && RecordId::parse(s).is_ok()
                {
                    out.records.push((s.clone(), None, path.into()));
                }
                if let Ok(w) = WorldId::parse(s) {
                    if matches!(key, "world" | "world_ids" | "worldIds") {
                        out.worlds.push(w.0.clone());
                        out.records.push((world_record(&w), None, path.into()));
                    }
                }
                let alias =
                    if !matches!(key, "unit" | "base" | "calendar" | "target" | "definition") {
                        None
                    } else if let Ok(id) = UnitId::parse(s) {
                        Some((id.to_record_id(), RecordKind::Unit))
                    } else if let Ok(id) = CalendarId::parse(s) {
                        Some((id.to_record_id(), RecordKind::Calendar))
                    } else if let Ok(id) = ValueDefinitionId::parse(s) {
                        Some((id.to_record_id(), RecordKind::ValueDefinition))
                    } else if let Ok(id) = PropositionId::parse(s) {
                        Some((id.to_record_id(), RecordKind::Proposition))
                    } else if let Ok(id) = RuleId::parse(s) {
                        Some((id.to_record_id(), RecordKind::Rule))
                    } else {
                        None
                    };
                if let Some((id, kind)) = alias {
                    let id = id.map_err(|_| invalid("invalid typed record reference"))?;
                    out.typed.push((id.0.clone(), kind));
                    out.records.push((id.0, None, path.into()));
                }
                out.scalars.push((path.into(), s.clone()));
            }
            Value::Bool(_) | Value::Number(_) => out.scalars.push((path.into(), v.to_string())),
            _ => {}
        }
        Ok(())
    }
    let mut refs = References::default();
    walk(value, u, "", "", &mut refs)?;
    Ok(refs)
}
fn validate_candidate(c: &Connection, u: &str, map: &Membership) -> StoreResult<()> {
    let records = map
        .values()
        .map(|v| load(c, u, v))
        .collect::<StoreResult<Vec<_>>>()?;
    validate_records(c, u, map, &records)
}
fn validate_records(
    c: &Connection,
    u: &str,
    map: &Membership,
    records: &[RecordVersion],
) -> StoreResult<()> {
    validate_foundation(records)?;
    let mut names = BTreeMap::new();
    let kinds: BTreeMap<_, _> = records
        .iter()
        .map(|r| (r.identity.record_id.as_str(), r.payload.kind()))
        .collect();
    for r in records {
        let rid = r.identity.record_id.as_str();
        if let Payload::WorkVersion(work) = &r.payload {
            let check_binding = |continuity: &ContinuityId, revision: &RevisionId| {
                let exists = c.query_row(
                    "SELECT EXISTS(SELECT 1 FROM commits WHERE universe_id=?1 AND continuity_id=?2 AND id=?3)",
                    params![u, continuity.as_str(), revision.as_str()],
                    |row| row.get::<_, bool>(0),
                )?;
                if !exists {
                    return Err(invalid(
                        "work binding must name an existing revision in its continuity",
                    ));
                }
                Ok(())
            };
            match &work.binding {
                WorkBinding::Bound {
                    continuity,
                    revision,
                } => check_binding(continuity, revision)?,
                WorkBinding::Segments { segments } => {
                    for segment in segments {
                        check_binding(&segment.continuity, &segment.revision)?;
                    }
                }
                WorkBinding::Unbound => (),
            }
        }
        let edition = match &r.payload {
            Payload::SceneRef(scene) => Some(&scene.work_version),
            Payload::PassageRef(passage) => Some(&passage.work_version),
            _ => None,
        };
        if let Some(edition) = edition {
            if load(c, u, edition.version.as_str())?.payload.kind() != RecordKind::WorkVersion {
                return Err(invalid(
                    "editorial edition reference must pin a work version",
                ));
            }
        }
        let refs = references(
            &serde_json::to_value(&r.payload).map_err(|_| invalid("payload encoding"))?,
            u,
        )?;
        for (target, exact, _) in refs.records {
            if let Some(v) = exact {
                let r = load(c, u, &v)?;
                if r.identity.record_id.as_str() != target {
                    return Err(invalid("version reference identity mismatch"));
                }
            } else if !map.contains_key(&target) {
                return Err(invalid("missing current record dependency"));
            }
        }
        for (target, kind) in refs.typed {
            if kinds.get(target.as_str()) != Some(&kind) {
                return Err(invalid("typed definition has wrong kind"));
            }
        }
        for world in refs.worlds {
            let rid = world_record(&WorldId(world));
            if kinds.get(rid.as_str()) != Some(&RecordKind::World) {
                return Err(invalid("world reference has wrong kind"));
            }
        }
        if let Payload::World(w) = &r.payload {
            for name in std::iter::once(&w.selector).chain(&w.aliases) {
                let key = selector_key(name)?;
                if names.insert(key, rid).is_some_and(|old| old != rid) {
                    return Err(invalid("duplicate world selector"));
                }
            }
        }
    }
    Ok(())
}

/// Definition ancestry and attribute subjects resolve in this exact candidate
/// membership, including a requested historical revision or fork baseline.
fn validate_foundation(records: &[RecordVersion]) -> StoreResult<()> {
    use universe_domain::scope::EvidenceBasis;
    use universe_domain::value::validate_value;
    let bodies: BTreeMap<_, _> = records
        .iter()
        .map(|r| (&r.identity.record_id, &r.payload))
        .collect();
    let has_kind =
        |id: &RecordId, kind: RecordKind| bodies.get(id).is_some_and(|p| p.kind() == kind);
    let check_values =
        |values: &BTreeMap<String, universe_domain::value::Value>| -> StoreResult<()> {
            for value in values.values() {
                validate_value(value).map_err(|_| invalid("invalid typed value"))?;
            }
            Ok(())
        };
    let mut finished = BTreeSet::new();
    for record in records {
        match &record.payload {
            Payload::EntityType(t) => {
                if (t.parent_resolution == ParentResolution::Resolved) != t.parent.is_some() {
                    return Err(invalid("parent resolution disagrees with parent identity"));
                }
                let mut path = BTreeSet::new();
                let mut next = Some(&record.identity.record_id);
                while let Some(id) = next {
                    if finished.contains(id) {
                        break;
                    }
                    if !path.insert(id) {
                        return Err(invalid("cyclic definition ancestry"));
                    }
                    let Some(Payload::EntityType(definition)) = bodies.get(id).copied() else {
                        return Err(invalid("parent is not a type in the selected revision"));
                    };
                    next = definition.parent.as_ref();
                }
                finished.extend(path);
            }
            Payload::Entity(e) => {
                if (e.classification_resolution == ClassificationResolution::Resolved)
                    != e.classification.is_some()
                {
                    return Err(invalid(
                        "classification resolution disagrees with type identity",
                    ));
                }
                if e.classification
                    .as_ref()
                    .is_some_and(|id| !has_kind(id, RecordKind::EntityType))
                {
                    return Err(invalid(
                        "classification is not a type in the selected revision",
                    ));
                }
                check_values(&e.metadata)?;
                for association in &e.world_associations {
                    check_values(&association.qualifiers)?;
                }
            }
            Payload::World(w) => check_values(&w.metadata)?,
            Payload::Realm(r) => check_values(&r.metadata)?,
            Payload::Proposition(p) => {
                if !has_kind(&p.context.record, RecordKind::RepresentedContext) {
                    return Err(invalid("proposition context has wrong kind"));
                }
                if !has_kind(&p.subject.record, RecordKind::Entity)
                    && !has_kind(&p.subject.record, RecordKind::EntityType)
                {
                    return Err(invalid("proposition subject has wrong kind"));
                }
                if !has_kind(&p.predicate.record, RecordKind::Property)
                    && !has_kind(&p.predicate.record, RecordKind::Relation)
                {
                    return Err(invalid("proposition predicate has wrong kind"));
                }
                if let Some(value) = &p.value {
                    validate_value(value).map_err(|_| invalid("invalid property value"))?;
                }
            }
            Payload::Assertion(a) => {
                let Some(Payload::Proposition(p)) = bodies.get(&a.proposition.record).copied()
                else {
                    return Err(invalid("assertion must reference a proposition"));
                };
                let kind = if a.attribute_mode == AttributeMode::Instance {
                    RecordKind::Entity
                } else {
                    RecordKind::EntityType
                };
                if !has_kind(&p.subject.record, kind) {
                    return Err(invalid("attribute mode disagrees with subject kind"));
                }
                if !has_kind(&a.scope.context.record, RecordKind::RepresentedContext)
                    || a.scope
                        .realm
                        .as_ref()
                        .is_some_and(|realm| !has_kind(&realm.record, RecordKind::Realm))
                {
                    return Err(invalid("attribute scope has wrong reference kind"));
                }
                if let EvidenceBasis::SourceAnchor { anchor, .. } = &a.basis {
                    if !has_kind(&anchor.record, RecordKind::Anchor) {
                        return Err(invalid("evidence is not an anchor"));
                    }
                }
                for value in &a.alternatives {
                    validate_value(value).map_err(|_| invalid("invalid precision alternative"))?;
                }
            }
            _ => (),
        }
    }
    Ok(())
}

fn index_definition(
    tx: &rusqlite::Transaction<'_>,
    record: &RecordVersion,
    membership: &Membership,
) -> StoreResult<()> {
    use universe_domain::scope::Applicability;
    let u = record.identity.universe_id.as_str();
    let v = record.record_version_id.as_str();
    let id = record.identity.record_id.as_str();
    match &record.payload {
        Payload::EntityType(t) => {
            let resolution = match t.parent_resolution {
                ParentResolution::Root => "root",
                ParentResolution::Resolved => "resolved",
                ParentResolution::Ambiguous => "ambiguous",
            };
            let applicability = match &t.applicability {
                Applicability::UniverseWide => "universe",
                Applicability::Worlds { .. } => "worlds",
                Applicability::Unspecified => "unspecified",
                Applicability::Conditional => "conditional",
            };
            tx.prepare_cached("INSERT INTO type_definition VALUES(?,?,?,?,?,?,?)")?
                .execute(params![
                    u,
                    v,
                    id,
                    t.name,
                    t.parent.as_ref().map(RecordId::as_str),
                    resolution,
                    applicability
                ])?;
            if let Applicability::Worlds { world_ids } = &t.applicability {
                for (ordinal, world) in world_ids.iter().enumerate() {
                    tx.prepare_cached("INSERT INTO type_world VALUES(?,?,?,?)")?
                        .execute(params![u, v, ordinal as i64, world_record(world)])?;
                }
            }
        }
        Payload::Entity(e) => {
            let resolution = match e.classification_resolution {
                ClassificationResolution::Resolved => "resolved",
                ClassificationResolution::Unclassified => "unclassified",
                ClassificationResolution::Ambiguous => "ambiguous",
            };
            tx.prepare_cached("INSERT INTO instance_classification VALUES(?,?,?,?,?)")?
                .execute(params![
                    u,
                    v,
                    id,
                    e.classification.as_ref().map(RecordId::as_str),
                    resolution
                ])?;
        }
        Payload::Assertion(a) if a.attribute_mode != AttributeMode::Instance => {
            let version = membership
                .get(a.proposition.record.as_str())
                .ok_or_else(|| invalid("missing definition proposition"))?;
            let Payload::Proposition(p) = load(tx, u, version)?.payload else {
                return Err(invalid("invalid definition proposition"));
            };
            let mode = if a.attribute_mode == AttributeMode::Shared {
                "shared"
            } else {
                "initial_value"
            };
            tx.prepare_cached("INSERT INTO definition_attribute VALUES(?,?,?,?,?)")?
                .execute(params![
                    u,
                    v,
                    p.subject.record.as_str(),
                    p.predicate.record.as_str(),
                    mode
                ])?;
        }
        _ => (),
    }
    Ok(())
}
fn project(c: &Connection, generation: i64, r: &RecordVersion) -> StoreResult<()> {
    let value = serde_json::to_value(&r.payload).map_err(|_| invalid("payload encoding"))?;
    let refs = references(&value, r.identity.universe_id.as_str())?;
    let v = r.record_version_id.as_str();
    for (target, exact, path) in &refs.records {
        c.prepare_cached("INSERT INTO reference_index VALUES(?1,?2,?3,?4,?5)")?
            .execute(params![generation, v, target, exact, path])?;
        if matches!(
            r.payload.kind(),
            RecordKind::Work
                | RecordKind::WorkVersion
                | RecordKind::Saga
                | RecordKind::SceneRef
                | RecordKind::PassageRef
        ) {
            c.prepare_cached("INSERT INTO narrative_projection VALUES(?1,?2,?3,?4)")?
                .execute(params![generation, v, target, path])?;
        }
    }
    for world in refs.worlds {
        c.prepare_cached("INSERT INTO world_projection VALUES(?1,?2,?3)")?
            .execute(params![generation, v, world])?;
    }
    for (path, value) in refs.scalars {
        c.prepare_cached("INSERT INTO typed_projection VALUES(?1,?2,?3,?4)")?
            .execute(params![generation, v, path, value])?;
    }
    let text = match &r.payload {
        Payload::Entity(e) => e
            .labels
            .values()
            .cloned()
            .chain(e.names.iter().map(|n| n.text.clone()))
            .collect::<Vec<_>>()
            .join(" "),
        Payload::World(w) => std::iter::once(w.selector.clone())
            .chain(w.aliases.clone())
            .collect::<Vec<_>>()
            .join(" "),
        Payload::Work(w) => w.title.clone(),
        Payload::Saga(s) => s.title.clone(),
        Payload::Appearance(a) => a.label.clone(),
        Payload::ImageAsset(a) => a.original_name.clone(),
        Payload::Source(s) => s.label.clone(),
        _ => String::new(),
    };
    c.prepare_cached("INSERT INTO search_index(generation,version_id,text) VALUES(?1,?2,?3)")?
        .execute(params![generation, v, text])?;
    Ok(())
}

impl Kernel {
    /// v1 retention policy pins all canonical history, source text, drafts, exact
    /// approvals and idempotency receipts. Source bytes live inside this SQLite
    /// transaction domain, so a backup pins its own complete source snapshot.
    /// Only reconstructible snapshot caches are eligible for collection.
    /// Whole-package purge preview, never a normal record deletion.
    pub fn purge_preview(&self) -> StoreResult<Value> {
        let count = |table: &str| -> StoreResult<i64> {
            Ok(self
                .conn
                .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))?)
        };
        let impact = serde_json::json!({"universe_id":self.universe,"heads":self.status()?.heads,"revisions":count("commits")?,"record_versions":count("record_versions")?,"workflow_entries":count("workflow_index")?,"commit_receipts":count("operation_receipts")?,"scope":"entire registered universe package: all continuities, history, sources, images, drafts, approvals and operation logs","retained":"installation audit records only the universe identity and purge action; external backups, exports, client transcripts and filesystem snapshots remain outside this operation","erasure":"removes owned package files; does not promise forensic erasure"});
        Ok(serde_json::json!({"digest":digest(&impact),"impact":impact}))
    }
    pub fn prepare_purge(&self, expected: &str) -> StoreResult<()> {
        if self.purge_preview()?["digest"] != expected {
            return Err(invalid("purge preview is stale; review current impact"));
        }
        self.conn
            .execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
        Ok(())
    }
    pub fn maintain(&mut self, collect: bool) -> StoreResult<Value> {
        self.integrity()?;
        let count = |table: &str| -> StoreResult<i64> {
            Ok(self
                .conn
                .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))?)
        };
        let versions = count("record_versions")?;
        let revisions = count("commits")?;
        let receipts = count("operation_receipts")?;
        let workflows = count("workflow_index")?;
        let caches = count("snapshot_membership")?;
        let sources: i64 = self
            .conn
            .query_row("SELECT count(*) FROM source_content", [], |r| r.get(0))?;
        if collect {
            // Called on the sole universe worker: publication and backup cannot
            // interleave with collection. No authoritative retention root is removed.
            let tx = self.conn.transaction()?;
            tx.execute("DELETE FROM snapshot_member", [])?;
            tx.execute("DELETE FROM snapshot_membership", [])?;
            tx.commit()?;
            self.conn
                .execute_batch("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")?;
            self.integrity()?;
        }
        Ok(
            serde_json::json!({"retention_policy":"retain-all-history-v1","retained_record_versions":versions,"retained_revisions":revisions,"retained_commit_receipts":receipts,"retained_workflow_entries":workflows,"retained_source_assets":sources,"eligible_snapshot_caches":caches,"collected_snapshot_caches":if collect{caches}else{0},"source_assets_collected":0,"backup_pins":"source bytes are embedded in each complete SQLite snapshot","canonical":false}),
        )
    }
}

#[cfg(test)]
mod consequence_reference_tests {
    use super::*;
    #[test]
    fn consequence_references_use_existing_indexes_and_namespace_guards() {
        let fixtures: Value = serde_json::from_str(include_str!(
            "../../../fixtures/normalized-foundation/historical-digests.json"
        ))
        .unwrap();
        let u = "unv_000000000000000000000001";
        let grant = &fixtures[5]["payload"];
        let found = references(grant, u).unwrap();
        for path in [
            "/consequenceContract/slots/0/target/predicate",
            "/consequenceContract/slots/0/condition/predicate",
        ] {
            assert!(found.records.iter().any(|(_, _, p)| p == path));
            for replacement in [
                Value::Null,
                serde_json::json!("unv_000000000000000000000002"),
            ] {
                let mut bad = grant.clone();
                bad.pointer_mut(path).unwrap()["universe"] = replacement;
                assert!(references(&bad, u).is_err());
            }
        }
        let transfer = &fixtures[4]["payload"];
        let found = references(transfer, u).unwrap();
        assert_eq!(
            found
                .typed
                .iter()
                .filter(
                    |(id, kind)| id == "rec_000000000000000000000007" && *kind == RecordKind::Unit
                )
                .count(),
            2
        );
        // References inside declared values remain references, not prose.
        let mut value_ref = grant.clone();
        value_ref["consequenceContract"]["slots"][0]["change"]["value"] = serde_json::json!({"kind":"entity_ref","ref":{"universe":u,"record":"rec_00000000000000000000000f"}});
        let _: Payload = serde_json::from_value(value_ref.clone()).unwrap();
        assert!(references(&value_ref, u)
            .unwrap()
            .records
            .iter()
            .any(|(id, _, _)| id == "rec_00000000000000000000000f"));
        value_ref["consequenceContract"]["slots"][0]["change"]["value"]["ref"]["universe"] =
            serde_json::json!("unv_000000000000000000000002");
        assert!(references(&value_ref, u).is_err());
    }
}
