//! OS ownership, not PID-file authority. Private runtime paths never follow symlinks.
use crate::{StoreError, StoreResult};
use std::{
    fs::{File, OpenOptions},
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
};
pub fn private_dir(path: &Path) -> StoreResult<PathBuf> {
    if !path.exists() {
        std::fs::DirBuilder::new().recursive(true).create(path)?;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
    }
    let m = std::fs::symlink_metadata(path)?;
    if !m.is_dir()
        || m.file_type().is_symlink()
        || m.uid() != unsafe { libc::geteuid() }
        || m.mode() & 0o077 != 0
    {
        return Err(StoreError::StorageFailure(
            "private directory ownership/mode required".into(),
        ));
    }
    Ok(path.canonicalize()?)
}
pub fn protected_file(path: &Path, create: bool) -> StoreResult<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(create)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)?;
    let m = file.metadata()?;
    if !m.is_file()
        || m.nlink() != 1
        || m.uid() != unsafe { libc::geteuid() }
        || m.mode() & 0o077 != 0
    {
        return Err(StoreError::StorageFailure(
            "protected file ownership/mode required".into(),
        ));
    }
    Ok(file)
}
pub struct FileLock {
    _file: File,
}
impl FileLock {
    pub fn acquire(path: &Path) -> StoreResult<Self> {
        let f = protected_file(path, true)?;
        f.try_lock()
            .map_err(|_| StoreError::StorageFailure("writer already owned".into()))?;
        Ok(Self { _file: f })
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        // Explicit unlock avoids a transient inherited descriptor in a concurrent
        // fork/exec keeping our lock alive after the owner has closed the package.
        let _ = self._file.unlock();
    }
}
