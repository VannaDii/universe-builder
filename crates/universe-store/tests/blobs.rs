use universe_store::blob::BlobStore;
#[test]
fn concurrent_publication_and_path_confinement() {
    let d = tempfile::tempdir().unwrap();
    let store = std::sync::Arc::new(BlobStore::new(d.path().join("blobs")).unwrap());
    let threads: Vec<_> = (0..8)
        .map(|_| {
            let s = store.clone();
            std::thread::spawn(move || s.store(b"canonical bytes").unwrap())
        })
        .collect();
    let digests: Vec<_> = threads.into_iter().map(|t| t.join().unwrap()).collect();
    assert!(digests.iter().all(|d| d == &digests[0]));
    assert_eq!(store.list().unwrap().len(), 1);
    for bad in ["../outside", "ABC", "/tmp/file", ""] {
        assert!(store.get(bad).is_err());
        assert!(store.delete(bad).is_err());
    }
    let fake = "a".repeat(64);
    let external = d.path().join("external");
    std::fs::write(&external, b"untouched").unwrap();
    std::os::unix::fs::symlink(&external, store.root().join(&fake)).unwrap();
    assert!(store.get(&fake).is_err());
    assert!(store.delete(&fake).is_err());
    assert_eq!(std::fs::read(&external).unwrap(), b"untouched");
    std::fs::write(store.root().join(&digests[0]), b"corrupt").unwrap();
    assert!(store.get(&digests[0]).is_err());
    assert!(store.store(b"canonical bytes").is_err());
}
