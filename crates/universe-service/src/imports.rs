//! Durable exact import previews. No catalog publication until an author accepts.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    io::{Read, Write},
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
}
impl Preview {
    pub fn digest(&self) -> String {
        hex::encode(Sha256::digest(canonical_serde(self).to_bytes()))
    }
    pub fn report(&self) -> Value {
        json!({"preview_id":self.id,"digest":self.digest(),"source_universe":self.source,"target_universe":self.target,"name":self.name,"complete":self.complete,"omitted_records":self.omitted_records,"record_count":self.records,"record_ids":"preserved within target universe","version_ids":"preserved within target universe","references":"local universe references mapped to target","workflow_and_approvals":"excluded; installation authority is not imported","canonical":false})
    }
    pub fn archive_path(&self, root: &Path) -> PathBuf {
        root.join("imports").join(format!("{}.jsonl", self.id))
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
    let path = directory.join(format!("{id}.jsonl"));
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
    };
    temporary.persist_noclobber(&path)?;
    let mut file = tempfile::NamedTempFile::new_in(&directory)?;
    file.write_all(&serde_json::to_vec(&preview)?)?;
    file.as_file().sync_all()?;
    file.persist_noclobber(directory.join(format!("{}.preview", preview.id)))?;
    std::fs::File::open(directory)?.sync_all()?;
    Ok(preview)
}
pub fn load(
    root: &Path,
    owner: &ProfileId,
    id: &OperationId,
    digest: &str,
) -> anyhow::Result<Preview> {
    let mut bytes = Vec::new();
    protected_file(&root.join("imports").join(format!("{id}.preview")), false)?
        .take(65_537)
        .read_to_end(&mut bytes)?;
    anyhow::ensure!(bytes.len() <= 65_536, "preview size limit");
    let preview: Preview = serde_json::from_slice(&bytes)?;
    if preview.owner != *owner || preview.id != *id {
        return Err(ProtocolError::not_found("import preview").into());
    }
    if preview.digest() != digest {
        return Err(ProtocolError::ApprovalStale.into());
    }
    Ok(preview)
}
