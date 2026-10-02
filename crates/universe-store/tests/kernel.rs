use std::{collections::BTreeMap, path::Path};
use universe_domain::{ids::*, records::*};
use universe_store::{kernel::*, selector::selector_key, Database, StoreError};
fn id(p: &str, n: u64) -> String {
    format!("{p}_{n:024x}")
}
fn uid() -> UniverseId {
    UniverseId::parse(&id("unv", 1)).unwrap()
}
fn cont() -> ContinuityId {
    ContinuityId::parse(&id("cont", 1)).unwrap()
}
fn principal() -> PrincipalId {
    PrincipalId::parse(&id("prn", 1)).unwrap()
}
fn record(r: u64, v: u64, label: &str) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::parse(&id("ver", v)).unwrap(),
        RecordIdentity::new(
            uid(),
            RecordId::parse(&id("rec", r)).unwrap(),
            RecordKind::Entity,
        ),
        Payload::Entity(Entity {
            names: vec![],
            types: vec![],
            world_associations: vec![],
            labels: BTreeMap::from([("en".into(), label.into())]),
            metadata: BTreeMap::new(),
        }),
    )
    .unwrap()
}
fn create(path: &Path) -> Kernel {
    Kernel::create(path, uid(), "The Ashen Cycle", cont(), &principal()).unwrap()
}
fn input(k: &Kernel, r: RecordVersion, prior: Option<u64>, key: &str) -> CommitInput {
    CommitInput {
        universe: uid(),
        continuity: cont(),
        expected_head: k.head(&cont()).unwrap(),
        principal: principal(),
        decision: "test authorization".into(),
        reason: "fixture".into(),
        idempotency_key: key.into(),
        changes: vec![Assignment {
            record_id: r.identity.record_id.clone(),
            expected: prior.map(|v| RecordVersionId::parse(&id("ver", v)).unwrap()),
            next: Some(r),
        }],
    }
}
#[test]
fn restart_history_rebuild_and_retry() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("u.db");
    let mut k = create(&path);
    let first = input(&k, record(1, 1, "Mara"), None, "first");
    let r1 = k.commit(&first).unwrap();
    let second = input(&k, record(1, 2, "Mara revised"), Some(1), "second");
    let r2 = k.commit(&second).unwrap();
    assert_eq!(k.commit(&first).unwrap(), r1);
    let mut conflicting = first.clone();
    conflicting.reason = "changed request".into();
    assert!(k.commit(&conflicting).is_err());
    drop(k);
    let mut k = Kernel::open(&path).unwrap();
    assert_eq!(k.records(&cont(), &r1).unwrap()[0], record(1, 1, "Mara"));
    assert_eq!(
        k.records(&cont(), &r2).unwrap()[0],
        record(1, 2, "Mara revised")
    );
    let db = Database::open_existing(&path).unwrap();
    let conn = db.connect().unwrap();
    conn.execute_batch(
        "DELETE FROM head_membership; DELETE FROM search_index; DELETE FROM reference_index;",
    )
    .unwrap();
    k.rebuild_projections(|_| Ok(())).unwrap();
    assert_eq!(k.search(&cont(), &r1, "Mara").unwrap().len(), 1);
    assert!(k.search(&cont(), &r1, "revised").unwrap().is_empty());
    assert_eq!(k.search(&cont(), &r2, "revised").unwrap().len(), 1);
}
#[test]
fn all_commit_faults_roll_back() {
    for point in [
        FaultPoint::Versions,
        FaultPoint::Changes,
        FaultPoint::Head,
        FaultPoint::Projections,
        FaultPoint::Receipt,
        FaultPoint::BeforeCommit,
    ] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("u.db");
        let mut k = create(&path);
        let initial = k.head(&cont()).unwrap();
        let change = input(&k, record(1, 1, "Mara"), None, "first");
        assert!(k
            .commit_with_hook(&change, |p| if p == point {
                Err(StoreError::StorageFailure(
                    "injected disk/full failure".into(),
                ))
            } else {
                Ok(())
            })
            .is_err());
        drop(k);
        let mut k = Kernel::open(&path).unwrap();
        assert_eq!(k.head(&cont()).unwrap(), initial);
        assert!(k.records(&cont(), &initial).unwrap().is_empty());
        let r = k.commit(&change).unwrap();
        assert_eq!(k.records(&cont(), &r).unwrap().len(), 1);
    }
}
#[test]
fn constraints_reject_identity_mismatch_and_mutation() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    let a = input(&k, record(1, 1, "Mara"), None, "one");
    k.commit(&a).unwrap();
    let c = Database::open_existing(&path).unwrap().connect().unwrap();
    assert!(c
        .execute("UPDATE record_versions SET digest='wrong'", [])
        .is_err());
    assert!(c.execute("DELETE FROM commits", []).is_err());
    assert!(c.execute("INSERT INTO record_versions SELECT universe_id,'ver_bad',record_id,'world',schema_version,payload,digest FROM record_versions",[]).is_err());
    let mut bad = record(2, 2, "foreign");
    bad.identity.universe_id = UniverseId::parse(&id("unv", 2)).unwrap();
    let a = input(&k, bad, None, "bad");
    assert!(k.commit(&a).is_err());
}
#[test]
fn branch_is_pinned_and_tombstones_preserve_history() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    let a = input(&k, record(1, 1, "Mara"), None, "one");
    let r1 = k.commit(&a).unwrap();
    let branch = ContinuityId::parse(&id("cont", 2)).unwrap();
    let fork = k.branch(&branch, &cont(), &r1, &principal()).unwrap();
    let mut a = input(&k, record(1, 2, "unused"), Some(1), "delete");
    a.changes[0].next = None;
    let r2 = k.commit(&a).unwrap();
    assert!(k.records(&cont(), &r2).unwrap().is_empty());
    assert_eq!(k.records(&branch, &fork).unwrap().len(), 1);
    assert_eq!(k.records(&cont(), &r1).unwrap().len(), 1);
}
#[test]
fn future_version_is_rejected_without_modification() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let db = Database::open(&path).unwrap();
    db.connect()
        .unwrap()
        .execute("UPDATE schema_meta SET value=999", [])
        .unwrap();
    assert!(Database::open(&path).is_err());
    assert!(Database::open_existing(&path).is_err());
    let c = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(
        c.query_row("SELECT value FROM schema_meta", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        999
    );
}
#[test]
fn selector_normalization_is_exact_and_non_rebinding() {
    assert_eq!(
        selector_key(" Straße ").unwrap(),
        selector_key("STRASSE").unwrap()
    );
    assert_eq!(
        selector_key("café").unwrap(),
        selector_key("cafe\u{301}").unwrap()
    );
    assert_ne!(selector_key("A B").unwrap(), selector_key("A  B").unwrap());
    assert!(selector_key("bad\u{202e}name").is_err());
}
#[test]
fn snapshot_publication_is_atomic() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    let r = k.head(&cont()).unwrap();
    assert!(k
        .cache_snapshot(&cont(), &r, |p| if p == FaultPoint::SnapshotPublish {
            Err(StoreError::StorageFailure("interrupt".into()))
        } else {
            Ok(())
        })
        .is_err());
    let c = Database::open_existing(&path).unwrap().connect().unwrap();
    assert_eq!(
        c.query_row("SELECT count(*) FROM snapshot_membership", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
    k.cache_snapshot(&cont(), &r, |_| Ok(())).unwrap();
}

fn world(r: u64, v: u64, name: &str) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::parse(&id("ver", v)).unwrap(),
        RecordIdentity::new(
            uid(),
            RecordId::parse(&id("rec", r)).unwrap(),
            RecordKind::World,
        ),
        Payload::World(World {
            selector: name.into(),
            aliases: vec![],
            setting_type: None,
            labels: BTreeMap::new(),
            metadata: BTreeMap::new(),
        }),
    )
    .unwrap()
}
#[test]
fn world_namespace_constraints_and_cross_world_references() {
    use universe_domain::scope::Validity;
    use universe_domain::value::{RecordRef, Value};
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    let mut a = input(&k, world(1, 1, "Earth"), None, "worlds");
    let second = world(2, 2, "Mars");
    a.changes.push(Assignment {
        record_id: second.identity.record_id.clone(),
        expected: None,
        next: Some(second),
    });
    let r = k.commit(&a).unwrap();
    let mut entity = match record(3, 3, "Traveler").payload {
        Payload::Entity(e) => e,
        _ => unreachable!(),
    };
    for n in [1, 2] {
        entity.world_associations.push(WorldAssociation {
            world: WorldId::parse(&id("wld", n)).unwrap(),
            role: "visit".into(),
            validity: Validity::Unspecified,
            qualifiers: BTreeMap::new(),
        });
    }
    let rv = RecordVersion::build(
        RecordVersionId::parse(&id("ver", 3)).unwrap(),
        RecordIdentity::new(
            uid(),
            RecordId::parse(&id("rec", 3)).unwrap(),
            RecordKind::Entity,
        ),
        Payload::Entity(entity.clone()),
    )
    .unwrap();
    let a = input(&k, rv, None, "cross-world");
    k.commit(&a).unwrap();
    assert!(k
        .commit(&input(&k, world(4, 4, "EARTH"), None, "duplicate"))
        .is_err());
    // A historical name is permanently reserved, even after rename.
    k.commit(&input(&k, world(1, 5, "Terra"), Some(1), "rename"))
        .unwrap();
    assert!(k
        .commit(&input(&k, world(4, 6, "earth"), None, "rebind"))
        .is_err());
    assert_eq!(k.records(&cont(), &r).unwrap().len(), 2);
    entity.metadata.insert(
        "foreign".into(),
        Value::record(RecordRef::new(
            UniverseId::parse(&id("unv", 2)).unwrap(),
            RecordId::parse(&id("rec", 1)).unwrap(),
        )),
    );
    let foreign = RecordVersion::build(
        RecordVersionId::parse(&id("ver", 7)).unwrap(),
        RecordIdentity::new(
            uid(),
            RecordId::parse(&id("rec", 3)).unwrap(),
            RecordKind::Entity,
        ),
        Payload::Entity(entity),
    )
    .unwrap();
    assert!(k.commit(&input(&k, foreign, Some(3), "foreign")).is_err());
}
#[test]
fn rebuild_failure_preserves_previous_generation() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    let r = k
        .commit(&input(&k, record(1, 1, "Mara"), None, "one"))
        .unwrap();
    assert!(k
        .rebuild_projections(|p| if p == FaultPoint::BeforeCommit {
            Err(StoreError::StorageFailure("interrupt".into()))
        } else {
            Ok(())
        })
        .is_err());
    assert_eq!(k.search(&cont(), &r, "Mara").unwrap().len(), 1);
}
#[test]
fn package_locks_reject_duplicate_and_link_paths() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let k = create(&path);
    assert!(Kernel::open(&path).is_err());
    let link = d.path().join("link.db");
    std::os::unix::fs::symlink(&path, &link).unwrap();
    assert!(Kernel::open(&link).is_err());
    let hard = d.path().join("hard.db");
    std::fs::hard_link(&path, &hard).unwrap();
    assert!(Kernel::open(&hard).is_err());
    drop(k);
    assert!(Kernel::open(&path).is_err());
    std::fs::remove_file(hard).unwrap();
    Kernel::open(&path).unwrap();
}
#[test]
fn failed_migration_is_atomic_and_populated_legacy_is_preserved() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let db = Database::open(&path).unwrap();
    assert!(db
        .apply_migration("CREATE TABLE partial(x); INSERT INTO missing VALUES(1);")
        .is_err());
    assert!(!db
        .connect()
        .unwrap()
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='partial')",
            [],
            |r| r.get::<_, bool>(0)
        )
        .unwrap());
    let legacy = d.path().join("old.db");
    let c = rusqlite::Connection::open(&legacy).unwrap();
    c.execute_batch("CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value INTEGER); INSERT INTO schema_meta VALUES('schema_version',0); CREATE TABLE authored(text TEXT); INSERT INTO authored VALUES('preserve me');").unwrap();
    drop(c);
    assert!(Database::open(&legacy).is_err());
    let c = rusqlite::Connection::open(&legacy).unwrap();
    assert_eq!(
        c.query_row("SELECT text FROM authored", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "preserve me"
    );
}
#[test]
fn abrupt_process_exit_recovers_all_or_none() {
    for phase in [
        "Versions",
        "Changes",
        "Head",
        "Projections",
        "Receipt",
        "BeforeCommit",
        "published",
    ] {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("u.db");
        let k = create(&path);
        let initial = k.head(&cont()).unwrap();
        let a = input(&k, record(1, 1, "Mara"), None, "crash");
        drop(k);
        let result = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "crash_child"])
            .env("UNIVERSE_TEST_CRASH_PATH", &path)
            .env("UNIVERSE_TEST_CRASH_PHASE", phase)
            .output()
            .unwrap();
        assert_eq!(result.status.code(), Some(72));
        let mut k = Kernel::open(&path).unwrap();
        let head = k.head(&cont()).unwrap();
        if phase == "published" {
            assert_ne!(head, initial);
            assert_eq!(k.commit(&a).unwrap(), head);
        } else {
            assert_eq!(head, initial);
            assert!(k.records(&cont(), &head).unwrap().is_empty());
            k.commit(&a).unwrap();
        }
    }
}
#[test]
fn crash_child() {
    let Ok(path) = std::env::var("UNIVERSE_TEST_CRASH_PATH") else {
        return;
    };
    let phase = std::env::var("UNIVERSE_TEST_CRASH_PHASE").unwrap();
    let mut k = Kernel::open(Path::new(&path)).unwrap();
    let a = input(&k, record(1, 1, "Mara"), None, "crash");
    k.commit_with_hook(&a, |p| {
        if format!("{p:?}") == phase {
            std::process::exit(72)
        }
        Ok(())
    })
    .unwrap();
    std::process::exit(72)
}

#[test]
fn sqlite_full_rolls_back_the_entire_transaction() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let k = create(&path);
    let head = k.head(&cont()).unwrap();
    let mut c = Database::open_existing(&path).unwrap().connect().unwrap();
    let pages: i64 = c.query_row("PRAGMA page_count", [], |r| r.get(0)).unwrap();
    c.pragma_update(None, "max_page_count", pages).unwrap();
    let tx = c.transaction().unwrap();
    tx.execute(
        "INSERT INTO record_identities VALUES(?1,?2,'entity')",
        rusqlite::params![uid().as_str(), id("rec", 1)],
    )
    .unwrap();
    let err = tx
        .execute(
            "INSERT INTO record_versions VALUES(?1,?2,?3,'entity','1',zeroblob(1048576),'test')",
            rusqlite::params![uid().as_str(), id("ver", 1), id("rec", 1)],
        )
        .unwrap_err();
    assert_eq!(err.sqlite_error_code(), Some(rusqlite::ErrorCode::DiskFull));
    drop(tx);
    drop(c);
    drop(k);
    let k = Kernel::open(&path).unwrap();
    assert_eq!(k.head(&cont()).unwrap(), head);
    let c = Database::open_existing(&path).unwrap().connect().unwrap();
    assert_eq!(
        c.query_row("SELECT count(*) FROM record_identities", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
}

#[test]
fn empty_legacy_scaffold_upgrades_atomically() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("legacy.db");
    let c = rusqlite::Connection::open(&path).unwrap();
    c.execute_batch(include_str!("../src/schema_v0.sql"))
        .unwrap();
    c.execute("INSERT INTO schema_meta VALUES('schema_version',0)", [])
        .unwrap();
    drop(c);
    let db = Database::open(&path).unwrap();
    assert_eq!(db.schema_version().unwrap(), 2);
    assert_eq!(
        db.connect()
            .unwrap()
            .query_row("SELECT count(*) FROM record_versions", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        0
    );
}

#[test]
fn metadata_field_names_cannot_hide_foreign_or_dangling_references() {
    use universe_domain::value::{RecordRef, Value};
    for key in [
        "text",
        "labels",
        "title",
        "note",
        "aliases",
        "description",
        "symbol",
    ] {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("u.db");
        let mut k = create(&path);
        let before = k.head(&cont()).unwrap();
        for owner in [uid(), UniverseId::parse(&id("unv", 2)).unwrap()] {
            let mut entity = match record(1, 1, "rec_000000000000000000000009").payload {
                Payload::Entity(e) => e,
                _ => unreachable!(),
            };
            entity.metadata.insert(
                key.into(),
                Value::record(RecordRef::new(
                    owner,
                    RecordId::parse(&id("rec", 9)).unwrap(),
                )),
            );
            let candidate = RecordVersion::build(
                RecordVersionId::parse(&id("ver", 1)).unwrap(),
                RecordIdentity::new(
                    uid(),
                    RecordId::parse(&id("rec", 1)).unwrap(),
                    RecordKind::Entity,
                ),
                Payload::Entity(entity),
            )
            .unwrap();
            assert!(
                k.commit(&input(&k, candidate, None, key)).is_err(),
                "typed reference under metadata key {key} was skipped"
            );
            assert_eq!(k.head(&cont()).unwrap(), before);
        }
    }
}

#[test]
fn metadata_references_are_indexed_while_authored_strings_stay_prose() {
    use universe_domain::value::{RecordRef, Value};
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    k.commit(&input(&k, record(9, 9, "Target"), None, "target"))
        .unwrap();
    let mut entity = match record(1, 1, "Holder").payload {
        Payload::Entity(e) => e,
        _ => unreachable!(),
    };
    // Label names and text values may look exactly like reserved DTO/ID fields.
    entity.labels.insert("record".into(), id("rec", 90));
    entity.labels.insert("universe".into(), id("unv", 90));
    entity
        .metadata
        .insert("types".into(), Value::text(id("rec", 90)));
    entity.metadata.insert(
        "text".into(),
        Value::Sequence {
            items: vec![Value::record(RecordRef::new(
                uid(),
                RecordId::parse(&id("rec", 9)).unwrap(),
            ))],
        },
    );
    let candidate = RecordVersion::build(
        RecordVersionId::parse(&id("ver", 1)).unwrap(),
        RecordIdentity::new(
            uid(),
            RecordId::parse(&id("rec", 1)).unwrap(),
            RecordKind::Entity,
        ),
        Payload::Entity(entity),
    )
    .unwrap();
    let revision = k.commit(&input(&k, candidate, None, "holder")).unwrap();
    let count = || {
        let c = Database::open_existing(&path).unwrap().connect().unwrap();
        c.query_row(
            "SELECT count(*) FROM reference_index WHERE target_record=?1",
            [id("rec", 9)],
            |r| r.get::<_, i64>(0),
        )
        .unwrap()
    };
    assert_eq!(count(), 1);
    k.rebuild_projections(|_| Ok(())).unwrap();
    assert_eq!(count(), 1);
    let mut deletion = input(&k, record(9, 10, "unused"), Some(9), "delete");
    deletion.changes[0].next = None;
    assert!(k.commit(&deletion).is_err());
    assert_eq!(k.head(&cont()).unwrap(), revision);
}

#[test]
fn recovery_rejects_previously_stored_dangling_metadata_references() {
    use universe_domain::value::{RecordRef, Value};
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let mut k = create(&path);
    let revision = k
        .commit(&input(&k, record(1, 1, "Holder"), None, "one"))
        .unwrap();
    let mut damaged = record(1, 1, "Holder");
    if let Payload::Entity(e) = &mut damaged.payload {
        e.metadata.insert(
            "text".into(),
            Value::record(RecordRef::new(
                uid(),
                RecordId::parse(&id("rec", 9)).unwrap(),
            )),
        );
    }
    let damaged =
        RecordVersion::build(damaged.record_version_id, damaged.identity, damaged.payload).unwrap();
    // Reproduce an invalid payload admitted by the old walker. Coherent bytes
    // and digests alone must not make a dangling reference a valid snapshot.
    let c = Database::open_existing(&path).unwrap().connect().unwrap();
    c.execute_batch("DROP TRIGGER immutable_record_versions_update")
        .unwrap();
    c.execute(
        "UPDATE record_versions SET payload=?1,digest=?2",
        rusqlite::params![
            universe_domain::canonical::canonical_serde(&damaged).to_bytes(),
            damaged.payload_digest.as_str()
        ],
    )
    .unwrap();
    drop(c);
    assert!(k.records(&cont(), &revision).is_err());
    drop(k);
    assert!(Kernel::open(&path).is_err());
}
#[test]
fn schema_one_upgrade_preserves_history_and_installs_immutable_workflow_storage() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("upgrade.sqlite");
    let mut kernel = create(&path);
    let revision = kernel
        .commit(&input(
            &kernel,
            record(1, 1, "Before upgrade"),
            None,
            "first",
        ))
        .unwrap();
    drop(kernel);
    let connection = rusqlite::Connection::open(&path).unwrap();
    connection.execute_batch("DROP TABLE workflow_entries; UPDATE schema_meta SET value=1 WHERE key='schema_version';").unwrap();
    drop(connection);
    let mut kernel = Kernel::open(&path).unwrap();
    assert_eq!(kernel.status().unwrap().schema_version, 2);
    let copies: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .filter_map(Result::ok)
        .filter(|e| {
            e.file_name()
                .to_string_lossy()
                .starts_with(".upgrade.sqlite.before-schema-1-")
        })
        .collect();
    assert_eq!(copies.len(), 1, "upgrade must first retain a rollback copy");
    let old = rusqlite::Connection::open_with_flags(
        copies[0].path(),
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .unwrap();
    assert_eq!(
        old.query_row(
            "SELECT value FROM schema_meta WHERE key='schema_version'",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        1
    );
    let old_payload: Vec<u8> = old
        .query_row("SELECT payload FROM record_versions", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        serde_json::from_slice::<RecordVersion>(&old_payload).unwrap(),
        record(1, 1, "Before upgrade")
    );
    use std::os::unix::fs::PermissionsExt;
    assert_eq!(
        std::fs::metadata(copies[0].path())
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    assert_eq!(kernel.head(&cont()).unwrap(), revision);
    assert_eq!(
        kernel.records(&cont(), &revision).unwrap()[0],
        record(1, 1, "Before upgrade")
    );
    kernel
        .workflow_put(&[(
            "proposal:test".into(),
            serde_json::json!({"immutable":true}),
        )])
        .unwrap();
    assert!(kernel
        .workflow_put(&[(
            "proposal:test".into(),
            serde_json::json!({"immutable":false})
        )])
        .is_err());
    drop(kernel);
    let kernel = Kernel::open(&path).unwrap();
    assert_eq!(
        kernel.workflow_get("proposal:test").unwrap(),
        Some(serde_json::json!({"immutable":true}))
    );
}

#[test]
fn interrupted_backups_never_publish_partial_files_or_touch_canon() {
    let dir = tempfile::tempdir().unwrap();
    let mut k = create(&dir.path().join("live.sqlite"));
    let revision = k
        .commit(&input(
            &k,
            record(1, 1, "The novel's universe"),
            None,
            "seed",
        ))
        .unwrap();
    k.workflow_put(&[
        (
            "source:manuscript".into(),
            serde_json::json!({"text":"Chapter one — 日本語 👩🏽‍🚀"}),
        ),
        (
            "draft:work".into(),
            serde_json::json!({"unsaved_to_canon":"Keep this draft"}),
        ),
    ])
    .unwrap();
    for point in [FaultPoint::BackupCopied, FaultPoint::BackupVerified] {
        let destination = dir.path().join(format!("interrupted-{point:?}.sqlite"));
        assert!(k
            .backup_with_hook(&destination, |stage| if stage == point {
                Err(StoreError::StorageFailure("injected interruption".into()))
            } else {
                Ok(())
            })
            .is_err());
        assert!(!destination.exists());
        assert_eq!(k.head(&cont()).unwrap(), revision);
        assert_eq!(
            k.records(&cont(), &revision).unwrap(),
            vec![record(1, 1, "The novel's universe")]
        );
    }
    let destination = dir.path().join("verified.sqlite");
    k.backup(&destination).unwrap();
    let original = std::fs::read(&destination).unwrap();
    assert!(k.backup(&destination).is_err());
    assert_eq!(
        std::fs::read(&destination).unwrap(),
        original,
        "never overwrite a good backup"
    );
    let (restored, _staging) = Kernel::stage_restore(&destination, dir.path()).unwrap();
    assert_eq!(restored.head(&cont()).unwrap(), revision);
    assert_eq!(
        restored.records(&cont(), &revision).unwrap(),
        k.records(&cont(), &revision).unwrap()
    );
    assert_eq!(
        restored.workflow_get("source:manuscript").unwrap(),
        k.workflow_get("source:manuscript").unwrap()
    );
    assert_eq!(
        restored.workflow_get("draft:work").unwrap(),
        k.workflow_get("draft:work").unwrap()
    );
}

#[test]
fn backup_rejects_semantically_corrupt_content_despite_valid_sqlite_pages() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("live.sqlite");
    let mut k = create(&path);
    k.commit(&input(&k, record(1, 1, "Original"), None, "seed"))
        .unwrap();
    k.workflow_put(&[(
        "source:text".into(),
        serde_json::json!({"text":"Original manuscript"}),
    )])
    .unwrap();
    let c = rusqlite::Connection::open(&path).unwrap();
    let triggers: Vec<String> = c
        .prepare(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='workflow_entries'",
        )
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    for t in triggers {
        c.execute_batch(&format!("DROP TRIGGER \"{}\"", t.replace('"', "\"\"")))
            .unwrap();
    }
    c.execute(
        "UPDATE workflow_entries SET payload=?1 WHERE key='source:text'",
        [b"{}".as_slice()],
    )
    .unwrap();
    assert_eq!(
        c.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "ok"
    );
    let destination = dir.path().join("must-not-publish.sqlite");
    assert!(k.backup(&destination).is_err());
    assert!(!destination.exists());
    assert!(k.integrity().is_err());
}

#[test]
fn branch_depth_limit_rejects_before_publication_and_preserves_recovery() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("novel.sqlite");
    let mut k = create(&path);
    let original = k
        .commit(&input(&k, record(1, 1, "Keep every branch"), None, "seed"))
        .unwrap();
    let (mut parent, mut revision) = (cont(), original.clone());
    let mut rejected = false;
    for n in 2..=80 {
        let child = ContinuityId::parse(&id("cont", n)).unwrap();
        match k.branch(&child, &parent, &revision, &principal()) {
            Ok(next) => {
                assert_eq!(
                    k.records(&child, &next).unwrap(),
                    vec![record(1, 1, "Keep every branch")]
                );
                parent = child;
                revision = next;
            }
            Err(_) => {
                assert!(k.head(&child).is_err());
                rejected = true;
                break;
            }
        }
    }
    assert!(rejected);
    drop(k);
    let k = Kernel::open(&path).unwrap();
    assert_eq!(
        k.records(&cont(), &original).unwrap(),
        k.records(&parent, &revision).unwrap()
    );
}

#[test]
fn ten_thousand_entities_plus_metadata_survive_import_backup_restore_and_restart() {
    use sha2::{Digest, Sha256};
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let dir = tempfile::tempdir().unwrap();
    let archive_path = dir.path().join("large.jsonl");
    let mut file = std::fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&archive_path)
        .unwrap();
    let mut hasher = Sha256::new();
    let mut rows = 0;
    let revision = RevisionId::parse(&id("rev", 1)).unwrap();
    {
        let mut write_row = |value: serde_json::Value| {
            let mut bytes = serde_json::to_vec(&value).unwrap();
            bytes.push(b'\n');
            hasher.update(&bytes);
            file.write_all(&bytes).unwrap();
            rows += 1;
        };
        write_row(
            serde_json::json!({"entry":"manifest","manifest":{"format":"universe-logical-v1","universe":uid(),"name":"Large novel","complete":true,"omitted_records":0,"includes_history":true,"includes_workflow":false}}),
        );
        write_row(
            serde_json::json!({"entry":"continuity","id":cont(),"head":revision,"baseline":null}),
        );
        write_row(
            serde_json::json!({"entry":"commit","id":revision,"continuity":cont(),"parent":null,"sequence":0,"principal":principal(),"decision":"fixture import","reason":"Scale and recovery regression","digest":"0".repeat(64)}),
        );
        for n in 1..=10_050 {
            write_row(
                serde_json::json!({"entry":"record","record":record(n,n,&format!("Character {n}"))}),
            );
            write_row(
                serde_json::json!({"entry":"change","revision":revision,"record":id("rec",n),"prior":null,"next":id("ver",n)}),
            );
        }
    }
    let checksum =
        serde_json::json!({"entry":"checksum","sha256":hex::encode(hasher.finalize()),"rows":rows});
    writeln!(file, "{checksum}").unwrap();
    file.sync_all().unwrap();
    drop(file);
    let archive = LogicalArchive::read(&archive_path).unwrap();
    let (k, staging) = archive.stage(dir.path(), uid(), "Large novel").unwrap();
    let records = k.records(&cont(), &revision).unwrap();
    assert_eq!(records.len(), 10_050);
    for (offset, r) in records.iter().enumerate() {
        assert_eq!(
            r,
            &record(
                offset as u64 + 1,
                offset as u64 + 1,
                &format!("Character {}", offset + 1)
            )
        );
    }
    let backup = dir.path().join("backup.sqlite");
    k.backup(&backup).unwrap();
    drop(k);
    let k = Kernel::open(&staging.path().join("package.sqlite")).unwrap();
    assert_eq!(k.records(&cont(), &revision).unwrap(), records);
    let (restored, _temporary) = Kernel::stage_restore(&backup, dir.path()).unwrap();
    assert_eq!(restored.records(&cont(), &revision).unwrap(), records);
}
