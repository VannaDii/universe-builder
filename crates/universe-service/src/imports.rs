//! Durable exact import previews. No catalog publication until an author accepts.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    io::Read,
    path::{Path, PathBuf},
};
use universe_domain::{canonical::canonical_serde, ids::*};
use universe_protocol::{installation::ImportMode, ProtocolError};
use universe_store::{
    kernel::LogicalArchive,
    ownership::{private_dir, protected_file},
};
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Preview {
    pub id: OperationId,
    pub owner: ProfileId,
    pub source_digest: String,
    pub target: UniverseId,
    pub source: UniverseId,
    pub name: String,
    pub complete: bool,
    pub omitted_records: usize,
    pub records: usize,
    pub includes_workflow: bool,
}
impl Preview {
    pub fn digest(&self) -> String {
        hex::encode(Sha256::digest(canonical_serde(self).to_bytes()))
    }
    pub fn report(&self) -> Value {
        json!({"preview_id":self.id,"digest":self.digest(),"source_universe":self.source,"target_universe":self.target,"name":self.name,"complete":self.complete,"omitted_records":self.omitted_records,"record_count":self.records,"record_ids":"preserved within target universe","version_ids":"preserved within target universe","references":"canonical references mapped to target; historical workflow bindings preserved as written","includes_history":true,"includes_workflow":self.includes_workflow,"workflow_and_approvals":if self.includes_workflow {"preserved as historical evidence; authority remains inactive"} else {"omitted by canon-only export"},"canonical":false})
    }
    pub fn archive_path(&self, root: &Path) -> PathBuf {
        root.join("imports").join(format!("{}.sqlite", self.id))
    }
}
pub fn prepare(
    root: &Path,
    owner: &ProfileId,
    source: &Path,
    name: String,
    mode: ImportMode,
) -> anyhow::Result<Preview> {
    universe_store::selector::selector_key(&name)?;
    let directory = private_dir(&root.join("imports"))?;
    let id = OperationId::generate(&mut rand::rng());
    let path = directory.join(format!("{id}.sqlite"));
    let limit = universe_store::kernel::MAX_ARCHIVE_BYTES as u64;
    let mut original = protected_file(source, false)?.take(limit + 1);
    let mut temporary = tempfile::NamedTempFile::new_in(&directory)?;
    let bytes = std::io::copy(&mut original, &mut temporary)?;
    anyhow::ensure!(bytes <= limit, "archive size limit exceeded");
    temporary.as_file().sync_all()?;
    let archive = LogicalArchive::read(temporary.path())?;
    let target = match mode {
        ImportMode::Restore => archive.manifest.universe.clone(),
        ImportMode::Clone => UniverseId::generate(&mut rand::rng()),
    };
    // Complete structural/history/source validation precedes the reviewable preview.
    let (kernel, staging) = archive.stage(&root.join("packages"), target.clone(), &name)?;
    drop(kernel);
    drop(staging);
    let preview = Preview {
        id,
        owner: owner.clone(),
        source_digest: archive.digest.clone(),
        target,
        source: archive.manifest.universe.clone(),
        name,
        complete: archive.manifest.complete,
        omitted_records: archive.manifest.omitted_records,
        records: archive.record_count(),
        includes_workflow: archive.manifest.includes_workflow,
    };
    temporary.persist_noclobber(&path)?;
    let database = protected_file(&root.join("installation.sqlite"), false)?;
    let db = rusqlite::Connection::open(root.join("installation.sqlite"))?;
    db.busy_timeout(std::time::Duration::from_secs(2))?;
    db.execute_batch("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")?;
    let saved=db.execute("INSERT INTO import_preview(id,owner,source_digest,target,source,name,complete,omitted_records,records,includes_workflow,preview_digest,staged_path) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",rusqlite::params![preview.id.as_str(),preview.owner.as_str(),preview.source_digest,preview.target.as_str(),preview.source.as_str(),preview.name,preview.complete,preview.omitted_records as i64,preview.records as i64,preview.includes_workflow,preview.digest(),path.to_str().ok_or_else(||anyhow::anyhow!("archive path must be UTF-8"))?]);
    if let Err(error) = saved {
        std::fs::remove_file(&path)?;
        return Err(error.into());
    }
    database.sync_all()?;
    std::fs::File::open(directory)?.sync_all()?;
    Ok(preview)
}
pub fn load(
    root: &Path,
    owner: &ProfileId,
    id: &OperationId,
    digest: &str,
) -> anyhow::Result<Preview> {
    protected_file(&root.join("installation.sqlite"), false)?;
    let db = rusqlite::Connection::open_with_flags(
        root.join("installation.sqlite"),
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )?;
    db.execute_batch("PRAGMA trusted_schema=OFF;")?;
    let row=db.query_row("SELECT id,owner,source_digest,target,source,name,complete,omitted_records,records,includes_workflow,preview_digest,staged_path FROM import_preview WHERE id=?1 AND owner=?2",rusqlite::params![id.as_str(),owner.as_str()],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?,r.get::<_,String>(3)?,r.get::<_,String>(4)?,r.get::<_,String>(5)?,r.get::<_,bool>(6)?,r.get::<_,i64>(7)?,r.get::<_,i64>(8)?,r.get::<_,bool>(9)?,r.get::<_,String>(10)?,r.get::<_,String>(11)?)))?;
    let preview = Preview {
        id: OperationId::parse(&row.0)?,
        owner: ProfileId::parse(&row.1)?,
        source_digest: row.2,
        target: UniverseId::parse(&row.3)?,
        source: UniverseId::parse(&row.4)?,
        name: row.5,
        complete: row.6,
        omitted_records: usize::try_from(row.7)?,
        records: usize::try_from(row.8)?,
        includes_workflow: row.9,
    };
    anyhow::ensure!(
        preview.digest() == row.10 && preview.archive_path(root) == Path::new(&row.11),
        "import preview integrity mismatch"
    );
    if preview.owner != *owner || preview.id != *id {
        return Err(ProtocolError::not_found("import preview").into());
    }
    if preview.digest() != digest {
        return Err(ProtocolError::ApprovalStale.into());
    }
    Ok(preview)
}
