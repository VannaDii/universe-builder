//! Private per-profile credentials, never universe storage or exports.
use crate::{
    ownership::{private_dir, protected_file},
    StoreError, StoreResult,
};
use std::path::Path;
use universe_domain::ids::ProfileId;

pub fn write(root: &Path, profile: &ProfileId, credential: &str) -> StoreResult<()> {
    let directory = private_dir(&root.join("profiles"))?;
    let path = directory.join(format!("{profile}.sqlite"));
    use std::os::unix::fs::OpenOptionsExt;
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&path)?;
    let db = rusqlite::Connection::open(&path)?;
    db.execute_batch("PRAGMA synchronous=FULL; BEGIN IMMEDIATE;")?;
    db.execute_batch(include_str!(
        "../../../docs/decisions/relational-storage/credential.sql"
    ))?;
    db.execute(
        "INSERT INTO credential VALUES(?1,?2)",
        rusqlite::params![profile.as_str(), credential],
    )?;
    db.execute_batch("COMMIT;")?;
    db.close().map_err(|(_, e)| e)?;
    file.sync_all()?;
    std::fs::File::open(directory)?.sync_all()?;
    Ok(())
}

pub fn read(root: &Path, profile: &ProfileId) -> StoreResult<String> {
    let directory = private_dir(&root.join("profiles"))?;
    let path = directory.join(format!("{profile}.sqlite"));
    let _file = protected_file(&path, false)?;
    let db = rusqlite::Connection::open_with_flags(
        &path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    db.execute_batch("PRAGMA trusted_schema=OFF;")?;
    let count: i64 = db.query_row("SELECT count(*) FROM credential", [], |r| r.get(0))?;
    let (id, secret): (String, String) =
        db.query_row("SELECT profile_id,credential FROM credential", [], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })?;
    if count != 1 || id != profile.as_str() {
        return Err(StoreError::StorageFailure(
            "profile identity mismatch".into(),
        ));
    }
    Ok(secret)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn exact_credentials_identity_and_private_paths() {
        let dir = tempfile::tempdir().unwrap();
        let profile = ProfileId::generate(&mut rand::rng());
        let other = ProfileId::generate(&mut rand::rng());
        let secret = "Synthetic exact credential: punctuation, spaces, café\n";
        write(dir.path(), &profile, secret).unwrap();
        assert!(read(dir.path(), &profile).unwrap() == secret);
        assert!(write(dir.path(), &profile, "replacement").is_err());
        let path = dir.path().join(format!("profiles/{profile}.sqlite"));
        let copied = dir.path().join(format!("profiles/{other}.sqlite"));
        std::fs::copy(&path, &copied).unwrap();
        assert!(read(dir.path(), &other).is_err());
        std::fs::remove_file(&copied).unwrap();
        std::os::unix::fs::symlink(&path, &copied).unwrap();
        assert!(read(dir.path(), &other).is_err());
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(read(dir.path(), &profile).is_err());
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        std::fs::set_permissions(
            path.parent().unwrap(),
            std::fs::Permissions::from_mode(0o755),
        )
        .unwrap();
        assert!(read(dir.path(), &profile).is_err());
    }
}
