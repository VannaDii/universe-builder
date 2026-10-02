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
pub use archive::{convert_legacy, ArchiveManifest, LogicalArchive, MAX_ARCHIVE_BYTES};
#[path = "media.rs"]
mod media;
pub use media::{validate_image_metadata, MAX_IMAGE_BYTES};
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
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelStatus {
    pub universe: UniverseId,
    pub sqlite_version: String,
    pub schema_version: i64,
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
            schema_version: 2,
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
        let old:Option<(String,String)>=tx.query_row("SELECT payload_digest,revision_id FROM operation_receipts WHERE universe_id=?1 AND principal=?2 AND operation_kind='commit' AND idempotency_key=?3",params![uid,input.principal.as_str(),input.idempotency_key],|r|Ok((r.get(0)?,r.get(1)?))).optional()?;
        if let Some((prior, revision)) = old {
            if prior != hash {
                return Err(invalid("idempotency key reused"));
            }
            return RevisionId::parse(&revision).map_err(|_| invalid("invalid receipt"));
        }
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
                    || !v.supported_schema()
                    || !v.verify_digest()
                {
                    return Err(invalid("record universe/kind/schema/digest mismatch"));
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
                tx.prepare_cached("INSERT INTO record_versions VALUES(?1,?2,?3,?4,?5,?6,?7)")?
                    .execute(params![
                        uid,
                        v.record_version_id.as_str(),
                        rid,
                        v.payload.kind().as_str(),
                        v.payload_schema_version,
                        bytes,
                        v.payload_digest.as_str()
                    ])?;
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
    pub fn workflow_get(&self, key: &str) -> StoreResult<Option<Value>> {
        let row: Option<(Vec<u8>, String)> = self
            .conn
            .query_row(
                "SELECT payload,digest FROM workflow_entries WHERE key=?1",
                [key],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        row.map(|(bytes, hash)| {
            let value: Value =
                serde_json::from_slice(&bytes).map_err(|_| invalid("invalid workflow JSON"))?;
            if digest(&value) != hash {
                return Err(invalid("workflow integrity failure"));
            }
            Ok(value)
        })
        .transpose()
    }
    /// Publish proposal, request receipt and operation index together.
    pub fn workflow_put(&mut self, entries: &[(String, Value)]) -> StoreResult<()> {
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        for (key, value) in entries {
            let bytes = canonical_serde(value).to_bytes();
            if bytes.len() > 4 * 1_048_576 {
                return Err(invalid("workflow entry too large"));
            }
            let old: Option<String> = tx
                .query_row(
                    "SELECT digest FROM workflow_entries WHERE key=?1",
                    [key],
                    |r| r.get(0),
                )
                .optional()?;
            let hash = digest(value);
            if let Some(old) = old {
                if old != hash {
                    return Err(invalid("immutable workflow key conflict"));
                }
            } else {
                tx.prepare_cached("INSERT INTO workflow_entries VALUES(?1,?2,?3)")?
                    .execute(params![key, bytes, hash])?;
            }
        }
        tx.commit()?;
        Ok(())
    }
    pub fn workflow_keys(&self, prefix: &str) -> StoreResult<Vec<String>> {
        Ok(self.conn.prepare("SELECT key FROM workflow_entries WHERE substr(key,1,?1)=?2 ORDER BY key LIMIT 10001")?
            .query_map(params![prefix.len() as i64,prefix], |r| r.get(0))?.collect::<Result<_,_>>()?)
    }
    pub fn receipt(&self, input: &CommitInput) -> StoreResult<Option<RevisionId>> {
        let row: Option<(String,String)> = self.conn.query_row(
            "SELECT payload_digest,revision_id FROM operation_receipts WHERE universe_id=?1 AND principal=?2 AND operation_kind='commit' AND idempotency_key=?3",
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
        let mut input = crate::ownership::protected_file(source, false)?;
        if input.metadata()?.len() > MAX_RESTORE_BYTES {
            return Err(invalid("restore package exceeds 8 GiB limit"));
        }
        let temporary = tempfile::Builder::new()
            .prefix(".restore-")
            .tempdir_in(scratch)?;
        let path = temporary.path().join("package.sqlite");
        use std::os::unix::fs::OpenOptionsExt;
        let mut output = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        std::io::copy(&mut input, &mut output)?;
        output.sync_all()?;
        drop(output);
        Ok((Self::open(&path)?, temporary))
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
        let bytes = canonical_serde(&map).to_bytes();
        let hash = digest(&map);
        let tx = self.conn.transaction()?;
        hook(FaultPoint::SnapshotRows)?;
        tx.prepare_cached("INSERT OR REPLACE INTO snapshot_membership VALUES(?1,?2,?3,?4)")?
            .execute(params![self.universe.as_str(), r.as_str(), bytes, hash])?;
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
        Ok(())
    }
}
fn verify_canonical(c: &Connection, universe: &str) -> StoreResult<()> {
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
    let mut workflow = c.prepare("SELECT payload,digest FROM workflow_entries")?;
    let rows = workflow.query_map([], |r| {
        Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, String>(1)?))
    })?;
    for row in rows {
        let (bytes, expected) = row?;
        let value: Value =
            serde_json::from_slice(&bytes).map_err(|_| invalid("invalid workflow data"))?;
        if digest(&value) != expected {
            return Err(invalid("workflow integrity failure"));
        }
    }
    Ok(())
}
fn load(c: &Connection, u: &str, v: &str) -> StoreResult<RecordVersion> {
    let (bytes, rid, kind, stored): (Vec<u8>, String, String, String) = c.prepare_cached(
        "SELECT payload,record_id,kind,digest FROM record_versions WHERE universe_id=?1 AND id=?2")?.query_row(
        params![u, v],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
    )?;
    let record: RecordVersion =
        serde_json::from_slice(&bytes).map_err(|_| invalid("invalid stored payload"))?;
    if !record.verify_digest()
        || record.identity.universe_id.as_str() != u
        || record.record_version_id.as_str() != v
        || record.identity.record_id.as_str() != rid
        || record.identity.record_kind != record.payload.kind()
        || !record.supported_schema()
        || record.payload.kind().as_str() != kind
        || record.payload_digest.as_str() != stored
    {
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
                    "parents"
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
    let mut names = BTreeMap::new();
    let kinds: BTreeMap<_, _> = records
        .iter()
        .map(|r| (r.identity.record_id.as_str(), r.payload.kind()))
        .collect();
    for r in records {
        let rid = r.identity.record_id.as_str();
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
        let impact = serde_json::json!({"universe_id":self.universe,"heads":self.status()?.heads,"revisions":count("commits")?,"record_versions":count("record_versions")?,"workflow_entries":count("workflow_entries")?,"commit_receipts":count("operation_receipts")?,"scope":"entire registered universe package: all continuities, history, sources, images, drafts, approvals and operation logs","retained":"installation audit records only the universe identity and purge action; external backups, exports, client transcripts and filesystem snapshots remain outside this operation","erasure":"removes owned package files; does not promise forensic erasure"});
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
        let workflows = count("workflow_entries")?;
        let caches = count("snapshot_membership")?;
        let sources: i64 = self.conn.query_row(
            "SELECT count(*) FROM workflow_entries WHERE key LIKE 'source:%'",
            [],
            |r| r.get(0),
        )?;
        if collect {
            // Called on the sole universe worker: publication and backup cannot
            // interleave with collection. No authoritative retention root is removed.
            self.conn.execute("DELETE FROM snapshot_membership", [])?;
            self.conn
                .execute_batch("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")?;
            self.integrity()?;
        }
        Ok(
            serde_json::json!({"retention_policy":"retain-all-history-v1","retained_record_versions":versions,"retained_revisions":revisions,"retained_commit_receipts":receipts,"retained_workflow_entries":workflows,"retained_source_assets":sources,"eligible_snapshot_caches":caches,"collected_snapshot_caches":if collect{caches}else{0},"source_assets_collected":0,"backup_pins":"source bytes are embedded in each complete SQLite snapshot","canonical":false}),
        )
    }
}
