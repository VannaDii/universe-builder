//! Content-addressed blob storage (spec §6.5).
//!
//! Blobs are stored by SHA-256 digest in a flat directory structure.
//! Atomic writes use staging + rename to prevent partial reads after crash.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum BlobStoreError {
    #[error("blob not found: digest={digest}")]
    NotFound { digest: String },

    #[error("I/O error: {0}")]
    Io(#[from] io::Error),

    #[error("blob too large: {size} bytes (max {max})")]
    TooLarge { size: usize, max: usize },

    #[error("invalid blob digest or unsafe path")]
    InvalidDigest,

    #[error("digest mismatch: expected={expected}, got={actual}")]
    DigestMismatch { expected: String, actual: String },
}

pub type BlobStoreResult<T> = Result<T, BlobStoreError>;

/// Maximum blob size (10 MiB).
const MAX_BLOB_SIZE: usize = 10 * 1024 * 1024;

/// A content-addressed blob store backed by a flat directory.
pub struct BlobStore {
    root: PathBuf,
}

impl BlobStore {
    pub fn new(root: impl Into<PathBuf>) -> BlobStoreResult<Self> {
        let root = crate::ownership::private_dir(&root.into())
            .map_err(|_| BlobStoreError::InvalidDigest)?;
        Ok(Self { root })
    }
    pub fn compute_digest(data: &[u8]) -> String {
        hex::encode(Sha256::digest(data))
    }
    fn path(&self, digest: &str) -> BlobStoreResult<PathBuf> {
        if digest.len() != 64 || !digest.bytes().all(|b| matches!(b,b'0'..=b'9'|b'a'..=b'f')) {
            return Err(BlobStoreError::InvalidDigest);
        }
        let meta = fs::symlink_metadata(&self.root)?;
        if !meta.is_dir() || meta.file_type().is_symlink() {
            return Err(BlobStoreError::InvalidDigest);
        }
        Ok(self.root.join(digest))
    }
    pub fn store(&self, data: &[u8]) -> BlobStoreResult<String> {
        if data.len() > MAX_BLOB_SIZE {
            return Err(BlobStoreError::TooLarge {
                size: data.len(),
                max: MAX_BLOB_SIZE,
            });
        }
        let digest = Self::compute_digest(data);
        let path = self.path(&digest)?;
        if path.symlink_metadata().is_ok() {
            self.get(&digest)?;
            return Ok(digest);
        }
        let mut tmp = tempfile::Builder::new()
            .prefix(".staging-")
            .tempfile_in(&self.root)?;
        tmp.write_all(data)?;
        tmp.as_file().sync_all()?;
        match tmp.persist_noclobber(&path) {
            Ok(_) => {}
            Err(e) if e.error.kind() == io::ErrorKind::AlreadyExists => {
                self.get(&digest)?;
            }
            Err(e) => return Err(e.error.into()),
        }
        fs::File::open(&self.root)?.sync_all()?;
        Ok(digest)
    }
    pub fn get(&self, digest: &str) -> BlobStoreResult<Vec<u8>> {
        use std::io::Read;
        let path = self.path(digest)?;
        if path.symlink_metadata().is_err() {
            return Err(BlobStoreError::NotFound {
                digest: digest.into(),
            });
        }
        let mut file = crate::ownership::protected_file(&path, false)
            .map_err(|_| BlobStoreError::InvalidDigest)?;
        let size = file.metadata()?.len();
        if size > MAX_BLOB_SIZE as u64 {
            return Err(BlobStoreError::TooLarge {
                size: size as usize,
                max: MAX_BLOB_SIZE,
            });
        }
        let mut data = Vec::new();
        std::io::Read::by_ref(&mut file)
            .take(MAX_BLOB_SIZE as u64 + 1)
            .read_to_end(&mut data)?;
        let actual = Self::compute_digest(&data);
        if actual != digest {
            return Err(BlobStoreError::DigestMismatch {
                expected: digest.into(),
                actual,
            });
        }
        Ok(data)
    }
    pub fn contains(&self, digest: &str) -> bool {
        self.get(digest).is_ok()
    }
    /// Internal maintenance only. Production reachability-aware GC is WP10.
    pub fn delete(&self, digest: &str) -> BlobStoreResult<()> {
        let path = self.path(digest)?;
        if path.symlink_metadata().is_ok() {
            self.get(digest)?;
            fs::remove_file(path)?;
            fs::File::open(&self.root)?.sync_all()?;
        }
        Ok(())
    }
    pub fn list(&self) -> BlobStoreResult<Vec<String>> {
        let mut out = Vec::new();
        for e in fs::read_dir(&self.root)? {
            let e = e?;
            let name = e.file_name().to_string_lossy().into_owned();
            if self.path(&name).is_ok() {
                self.get(&name)?;
                out.push(name);
            }
        }
        out.sort();
        Ok(out)
    }
    /// Caller must own the writer/maintenance gate and provide complete roots.
    pub fn gc(&self, referenced: &[String]) -> BlobStoreResult<usize> {
        let mut removed = 0;
        for name in self.list()? {
            if !referenced.contains(&name) {
                self.delete(&name)?;
                removed += 1;
            }
        }
        Ok(removed)
    }
    pub fn root(&self) -> &Path {
        &self.root
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store() -> (BlobStore, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        (
            BlobStore::new(dir.path().join("blobs")).unwrap(),
            dir.keep(),
        )
    }

    #[test]
    fn store_and_retrieve() {
        let (store, _dir) = temp_store();
        let data = b"hello world";
        let digest = store.store(data).unwrap();
        assert_eq!(store.get(&digest).unwrap(), data);
    }

    #[test]
    fn digest_is_deterministic() {
        let (store, _dir) = temp_store();
        let data = b"test";
        let d1 = store.store(data).unwrap();
        let d2 = BlobStore::compute_digest(data);
        assert_eq!(d1, d2);
    }

    #[test]
    fn not_found_returns_error() {
        let (store, _dir) = temp_store();
        assert!(matches!(
            store.get(&"a".repeat(64)),
            Err(BlobStoreError::NotFound { .. })
        ));
    }

    #[test]
    fn contains_works() {
        let (store, _dir) = temp_store();
        assert!(!store.contains("abc"));
        let d = store.store(b"x").unwrap();
        assert!(store.contains(&d));
    }

    #[test]
    fn too_large_is_rejected() {
        let (store, _dir) = temp_store();
        let data = vec![0u8; MAX_BLOB_SIZE + 1];
        assert!(matches!(
            store.store(&data),
            Err(BlobStoreError::TooLarge { .. })
        ));
    }

    #[test]
    fn gc_removes_unreferenced() {
        let (store, _dir) = temp_store();
        let d1 = store.store(b"a").unwrap();
        let d2 = store.store(b"b").unwrap();
        // Keep only d1.
        let removed = store.gc(std::slice::from_ref(&d1)).unwrap();
        assert_eq!(removed, 1);
        assert!(store.contains(&d1));
        assert!(!store.contains(&d2));
    }

    #[test]
    fn list_returns_all() {
        let (store, _dir) = temp_store();
        store.store(b"a").unwrap();
        store.store(b"b").unwrap();
        let digests = store.list().unwrap();
        assert_eq!(digests.len(), 2);
    }
}
