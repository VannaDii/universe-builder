use sha2::Digest;
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
            classification: None,
            classification_resolution:
                universe_domain::records::ClassificationResolution::Unclassified,
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
fn selection(generation: u64, selected: Option<u64>) -> serde_json::Value {
    serde_json::json!({"proposal":{"proposal_id":id("prp",1),"version":1,"digest":"a".repeat(64)},
        "generation":generation,"selected":selected.map(|n|serde_json::json!({"assessment_id":id("asm",n),"digest":"b".repeat(64)}))})
}
fn stored_proposal(k: &Kernel) -> serde_json::Value {
    serde_json::json!({"owner":id("prf",1),"author_origin":true,"changes":[],
        "footprint":{"worlds":[],"shared":false,"protected":false},
        "proposal":{"base_frame":{"universe":uid(),"continuity":cont(),"revision":k.head(&cont()).unwrap(),"context":{"universe":uid(),"record":id("rec",1)},"time":{"kind":"timeless"},"perspective":"author"},
        "proposal_id":id("prp",1),"version":1,"digest":"a".repeat(64),"submission":"submitted","operations":[],
        "rationale":"fixture","canonical":false,"operation_id":id("op",1),"withdrawn":false}})
}
fn insert_selection(c: &rusqlite::Connection, key: &str, generation: u64, selected: Option<u64>) {
    let body = selection(generation, selected);
    c.execute("INSERT INTO r_assessment_selection_proposal(proposal_id__state,proposal_id,version__state,version,digest__state,digest) VALUES(2,?1,2,'1',2,?2)",rusqlite::params![id("prp",1),"a".repeat(64)]).unwrap();
    let proposal_row = c.last_insert_rowid();
    let selected_row=selected.map(|n| {
        c.execute("INSERT INTO r_assessment_ref(assessment_id__state,assessment_id,digest__state,digest) VALUES(2,?1,2,?2)",rusqlite::params![id("asm",n),"b".repeat(64)]).unwrap();
        let reference=c.last_insert_rowid();
        c.execute("INSERT INTO r_assessment_selection_selected(variant,v0) VALUES(0,?1)",[reference]).unwrap();
        c.last_insert_rowid()
    });
    c.execute("INSERT INTO r_assessment_selection(proposal__state,proposal,generation__state,generation,selected__state,selected) VALUES(2,?1,2,?2,?3,?4)",rusqlite::params![proposal_row,generation.to_string(),if selected.is_some(){2}else{1},selected_row]).unwrap();
    let row = c.last_insert_rowid();
    let hash = hex::encode(sha2::Sha256::digest(
        universe_domain::canonical::canonical_serde(&body).to_bytes(),
    ));
    c.execute("INSERT INTO workflow_entries(key,family,digest,digest_recipe,AssessmentSelection) VALUES(?1,'AssessmentSelection',?2,'workflow-canonical',?3)",rusqlite::params![key,hash,row]).unwrap();
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
fn assessment_publication_compares_selection_and_rolls_back_every_fault() {
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
        let head = k.head(&cont()).unwrap();
        let prefix = "assessment-selection:proposal:00000000000000000001:";
        let first = format!("{prefix}00000000000000000001");
        k.workflow_put(&[(first.clone(), selection(1, Some(1)))])
            .unwrap();
        let expected = [(prefix.into(), Some(first))];
        let change = input(&k, record(1, 1, "Mara"), None, "assessed");
        assert!(k
            .commit_compared_with_hook(&change, &expected, |p| {
                if p == point {
                    Err(StoreError::StorageFailure(
                        "injected publication failure".into(),
                    ))
                } else {
                    Ok(())
                }
            })
            .is_err());
        assert_eq!(k.head(&cont()).unwrap(), head);
        assert!(k.receipt(&change).unwrap().is_none());
        let conn = Database::open_existing(&path).unwrap().connect().unwrap();
        for table in [
            "record_versions",
            "record_identities",
            "commit_changes",
            "operation_receipts",
        ] {
            assert_eq!(
                conn.query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r
                    .get::<_, i64>(0))
                    .unwrap(),
                0
            );
        }
        let revision = k.commit_compared(&change, &expected).unwrap();
        assert_eq!(k.receipt(&change).unwrap(), Some(revision));
    }
}
#[test]
fn assessment_publication_concurrent_replacement_withdrawal_and_aba_reject() {
    for mutation in [
        "replacement",
        "withdrawal",
        "aba",
        "first-selection",
        "proposal",
    ] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("u.db");
        let mut k = create(&path);
        let head = k.head(&cont()).unwrap();
        let prefix = "assessment-selection:proposal:00000000000000000001:";
        let first = format!("{prefix}00000000000000000001");
        if mutation != "first-selection" {
            k.workflow_put(&[(first.clone(), selection(1, Some(1)))])
                .unwrap();
        }
        k.workflow_put(&[("proposal:00000000000000000001".into(), stored_proposal(&k))])
            .unwrap();
        let expected = [
            (
                prefix.into(),
                (mutation != "first-selection").then_some(first),
            ),
            (
                "proposal:".into(),
                Some("proposal:00000000000000000001".into()),
            ),
        ];
        let change = input(&k, record(1, 1, "Mara"), None, "assessed");
        // A separate writer wins after service preparation, before BEGIN IMMEDIATE.
        // Join is the deterministic ordering barrier; no timing assumption is used.
        let writer_path = path.clone();
        std::thread::spawn(move || {
            let conn = Database::open_existing(&writer_path).unwrap().connect().unwrap();
            let key = if mutation == "proposal" { "proposal:00000000000000000002".into() }
                else { format!("{prefix}00000000000000000002") };
            conn.execute_batch("BEGIN IMMEDIATE").unwrap();
            if mutation == "proposal" {
                conn.execute("INSERT INTO workflow_entries(key,family,digest,digest_recipe,StoredProposal) SELECT ?1,family,digest,digest_recipe,StoredProposal FROM workflow_entries WHERE key='proposal:00000000000000000001'",[key]).unwrap();
            } else {
                insert_selection(&conn,&key,2,if mutation == "withdrawal" {None}else{Some(2)});
            }
            if mutation == "aba" { insert_selection(&conn,&format!("{prefix}00000000000000000003"),3,Some(1)); }
            conn.execute_batch("COMMIT").unwrap();
        }).join().unwrap();
        assert!(k.commit_compared(&change, &expected).is_err(), "{mutation}");
        assert_eq!(k.head(&cont()).unwrap(), head);
        assert!(k.receipt(&change).unwrap().is_none());
        assert!(k.records(&cont(), &head).unwrap().is_empty());
    }
}
#[test]
fn assessment_publication_write_transaction_excludes_selection_between_check_and_head() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("u.db");
    let mut k = create(&path);
    let selection_key = "assessment-selection:proposal:00000000000000000001:00000000000000000001";
    k.workflow_put(&[(selection_key.into(), selection(1, Some(1)))])
        .unwrap();
    let expected = [(
        "assessment-selection:proposal:00000000000000000001:".into(),
        Some(selection_key.into()),
    )];
    let change = input(&k, record(1, 1, "Mara"), None, "assessed");
    let revision = k.commit_compared_with_hook(&change, &expected, |point| {
        if point == FaultPoint::Versions {
            let writer_path = path.clone();
            std::thread::spawn(move || {
                let db = rusqlite::Connection::open(writer_path).unwrap();
                db.busy_timeout(std::time::Duration::ZERO).unwrap();
                // This runs after selection comparison and before head movement.
                let err = db.execute_batch("BEGIN IMMEDIATE").unwrap_err();
                assert!(matches!(err, rusqlite::Error::SqliteFailure(e, _) if e.code == rusqlite::ErrorCode::DatabaseBusy));
            }).join().unwrap();
        }
        Ok(())
    }).unwrap();
    assert_eq!(k.head(&cont()).unwrap(), revision);
    assert_eq!(
        k.workflow_latest_key(&expected[0].0).unwrap(),
        expected[0].1
    );
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
    assert!(c.execute("INSERT INTO record_versions SELECT universe_id,'ver_bad',record_id,'world',payload_row,digest FROM record_versions",[]).is_err());
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
fn serialized_package_is_rejected_without_modification() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.db");
    let c = rusqlite::Connection::open(&path).unwrap();
    c.execute_batch("CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value INTEGER); INSERT INTO schema_meta VALUES('schema_version',999);") .unwrap();
    drop(c);
    let original = std::fs::read(&path).unwrap();
    assert!(Database::open(&path).is_err());
    assert!(Database::open_existing(&path).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), original);
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
    tx.execute("INSERT INTO r_payload_v0_labels DEFAULT VALUES", [])
        .unwrap();
    let owner = tx.last_insert_rowid();
    let err = tx
        .execute(
            "INSERT INTO r_payload_v0_labels_items VALUES(?1,'capacity-test',?2)",
            rusqlite::params![owner, "x".repeat(1048576)],
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
fn empty_legacy_scaffold_requires_explicit_conversion() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("legacy.db");
    let c = rusqlite::Connection::open(&path).unwrap();
    c.execute_batch(include_str!("../src/schema_v0.sql"))
        .unwrap();
    c.execute("INSERT INTO schema_meta VALUES('schema_version',0)", [])
        .unwrap();
    drop(c);
    let original = std::fs::read(&path).unwrap();
    assert!(Database::open(&path).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), original);
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
    let mut original = record(1, 1, "Holder");
    if let Payload::Entity(e) = &mut original.payload {
        e.metadata.insert(
            "text".into(),
            Value::record(RecordRef::new(
                uid(),
                RecordId::parse(&id("rec", 1)).unwrap(),
            )),
        );
    }
    let original = RecordVersion::build(
        original.record_version_id,
        original.identity,
        original.payload,
    )
    .unwrap();
    let revision = k.commit(&input(&k, original, None, "one")).unwrap();
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
    c.execute_batch(
        "DROP TRIGGER immutable_record_versions_update; DROP TRIGGER r_record_ref_no_update;",
    )
    .unwrap();
    c.execute("UPDATE r_record_ref SET record=?1", [id("rec", 9)])
        .unwrap();
    c.execute(
        "UPDATE record_versions SET digest=?1",
        [damaged.payload_digest.as_str()],
    )
    .unwrap();
    drop(c);
    assert!(k.records(&cont(), &revision).is_err());
    drop(k);
    assert!(Kernel::open(&path).is_err());
}
#[test]
fn missing_workflow_storage_is_rejected_without_repair() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("damaged.sqlite");
    let mut kernel = create(&path);
    kernel
        .commit(&input(&kernel, record(1, 1, "Preserved"), None, "first"))
        .unwrap();
    drop(kernel);
    let connection = rusqlite::Connection::open(&path).unwrap();
    connection
        .execute_batch("DROP TABLE workflow_entries;")
        .unwrap();
    drop(connection);
    assert!(Kernel::open(&path).is_err());
    let connection = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(
        connection
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE name='workflow_entries'",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
        0
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM record_versions", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        1
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
            format!(
                "source:{}",
                hex::encode(sha2::Sha256::digest("Chapter one — 日本語 👩🏽‍🚀".as_bytes()))
            ),
            serde_json::json!("Chapter one — 日本語 👩🏽‍🚀"),
        ),
        (
            "cursor:work".into(),
            serde_json::json!({"binding":"a".repeat(64),"offset":1}),
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
        restored
            .workflow_get(&format!(
                "source:{}",
                hex::encode(sha2::Sha256::digest("Chapter one — 日本語 👩🏽‍🚀".as_bytes()))
            ))
            .unwrap(),
        k.workflow_get(&format!(
            "source:{}",
            hex::encode(sha2::Sha256::digest("Chapter one — 日本語 👩🏽‍🚀".as_bytes()))
        ))
        .unwrap()
    );
    assert_eq!(
        restored.workflow_get("cursor:work").unwrap(),
        k.workflow_get("cursor:work").unwrap()
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
        format!(
            "source:{}",
            hex::encode(sha2::Sha256::digest("Original manuscript".as_bytes()))
        ),
        serde_json::json!("Original manuscript"),
    )])
    .unwrap();
    let c = rusqlite::Connection::open(&path).unwrap();
    let triggers: Vec<String> = c
        .prepare(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='source_content'",
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
        "UPDATE source_content SET utf8_content=?1",
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

#[test]
fn relational_workflow_retries_immutability_failure_atomicity_and_recovery() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("workflow.sqlite");
    let mut k = create(&path);
    let key = "assessment-selection:prp_000000000000000000000001:00000000000000000001:00000000000000000001";
    let body = selection(1, None);
    k.workflow_put(&[(key.into(), body.clone())]).unwrap();
    let db = Database::open_existing(&path).unwrap().connect().unwrap();
    let count = || {
        db.query_row("SELECT count(*) FROM r_assessment_selection", [], |r| {
            r.get::<_, i64>(0)
        })
        .unwrap()
    };
    assert_eq!(count(), 1);
    k.workflow_put(&[(key.into(), body.clone())]).unwrap();
    assert_eq!(count(), 1, "retry must not create another body tree");
    assert!(k
        .workflow_put(&[(key.into(), selection(1, Some(1)))])
        .is_err());
    for table in [
        "workflow_entries",
        "r_assessment_selection",
        "r_assessment_selection_proposal",
    ] {
        assert!(db
            .execute(
                &format!(
                    "UPDATE {table} SET {}",
                    if table == "workflow_entries" {
                        "digest=digest"
                    } else {
                        "__row_id=__row_id"
                    }
                ),
                []
            )
            .is_err());
        assert!(db.execute(&format!("DELETE FROM {table}"), []).is_err());
    }
    db.execute_batch("CREATE TRIGGER interrupted_workflow BEFORE INSERT ON workflow_entries WHEN NEW.key='cursor:interrupted' BEGIN SELECT RAISE(ABORT,'injected interruption'); END").unwrap();
    let next_key = format!("{}{:020}", &key[..key.len() - 20], 2);
    assert!(k
        .workflow_put(&[
            (next_key.clone(), selection(2, Some(1))),
            (
                "cursor:interrupted".into(),
                serde_json::json!({"binding":"test","offset":7})
            )
        ])
        .is_err());
    assert_eq!(
        count(),
        1,
        "no orphan typed tree after interrupted publication"
    );
    assert!(k.workflow_get(&next_key).unwrap().is_none());
    assert!(k
        .workflow_put(&[("unknown:opaque".into(), serde_json::json!({"x":1}))])
        .is_err());
    assert_eq!(k.workflow_get(key).unwrap(), Some(body.clone()));
    assert_eq!(
        db.query_row("SELECT count(*) FROM record_versions", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
    db.execute_batch("DROP TRIGGER interrupted_workflow")
        .unwrap();
    drop(k);
    let mut k = Kernel::open(&path).unwrap();
    assert_eq!(k.workflow_get(key).unwrap(), Some(body.clone()));
    k.workflow_put(&[(key.into(), body)]).unwrap();
    // Remove the actual trigger by its table inventory, then corrupt a typed
    // scalar without changing the retained hash. Recovery must reject it.
    let triggers:Vec<String>=db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='r_assessment_selection' AND sql LIKE '%UPDATE%'").unwrap().query_map([],|r|r.get(0)).unwrap().collect::<Result<_,_>>().unwrap();
    for trigger in triggers {
        db.execute_batch(&format!("DROP TRIGGER \"{trigger}\""))
            .unwrap();
    }
    db.execute("UPDATE r_assessment_selection SET generation='99'", [])
        .unwrap();
    assert!(k.workflow_get(key).is_err());
    assert!(k.workflow_put(&[(key.into(), selection(1, None))]).is_err());
    drop(k);
    assert!(Kernel::open(&path).is_err());
}

#[test]
fn editorial_bindings_reject_missing_or_wrong_continuity_and_preserve_history() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("editorial.sqlite");
    let mut k = create(&path);
    let make = |r, v, payload: Payload| {
        RecordVersion::build(
            RecordVersionId::parse(&id("ver", v)).unwrap(),
            RecordIdentity::new(
                uid(),
                RecordId::parse(&id("rec", r)).unwrap(),
                payload.kind(),
            ),
            payload,
        )
        .unwrap()
    };
    let work = make(
        1,
        1,
        Payload::Work(Work {
            kind: WorkKind::Novel,
            title: "Exact editions".into(),
            labels: BTreeMap::new(),
            source_refs: vec![],
            versions: vec![],
            world_associations: vec![],
        }),
    );
    k.commit(&input(&k, work, None, "work")).unwrap();
    let revision = k.head(&cont()).unwrap();
    let bound = WorkBinding::Bound {
        continuity: cont(),
        revision: revision.clone(),
    };
    let edition = |binding| {
        make(
            2,
            2,
            Payload::WorkVersion(WorkVersion {
                work: universe_domain::RecordRef::new(
                    uid(),
                    RecordId::parse(&id("rec", 1)).unwrap(),
                ),
                version_label: "α".into(),
                binding,
            }),
        )
    };
    let counts = || {
        let c = Database::open_existing(&path).unwrap().connect().unwrap();
        let mut tables = vec![
            "record_versions".to_owned(),
            "commits".into(),
            "operation_receipts".into(),
        ];
        tables.extend(
            c.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'r_*'")
                .unwrap()
                .query_map([], |row| row.get::<_, String>(0))
                .unwrap()
                .map(Result::unwrap),
        );
        tables
            .into_iter()
            .map(|t| {
                c.query_row(&format!("SELECT count(*) FROM {t}"), [], |r| {
                    r.get::<_, i64>(0)
                })
                .unwrap()
            })
            .collect::<Vec<_>>()
    };
    let before = counts();
    let bad = [
        WorkBinding::Bound {
            continuity: cont(),
            revision: RevisionId::parse(&id("rev", 999)).unwrap(),
        },
        WorkBinding::Bound {
            continuity: ContinuityId::parse(&id("cont", 999)).unwrap(),
            revision: revision.clone(),
        },
        WorkBinding::Segments {
            segments: vec![
                WorkSegment {
                    segment: "good".into(),
                    continuity: cont(),
                    revision: revision.clone(),
                },
                WorkSegment {
                    segment: "bad".into(),
                    continuity: cont(),
                    revision: RevisionId::parse(&id("rev", 999)).unwrap(),
                },
            ],
        },
    ];
    for (n, binding) in bad.into_iter().enumerate() {
        let candidate = input(&k, edition(binding), None, &format!("invalid-{n}"));
        assert!(k.preview(&candidate).is_err());
        assert!(k.commit(&candidate).is_err());
        assert_eq!(k.head(&cont()).unwrap(), revision);
        assert_eq!(counts(), before);
    }
    let first = k
        .commit(&input(&k, edition(bound), None, "edition"))
        .unwrap();
    let unbound = make(
        2,
        3,
        Payload::WorkVersion(WorkVersion {
            work: universe_domain::RecordRef::new(uid(), RecordId::parse(&id("rec", 1)).unwrap()),
            version_label: "β".into(),
            binding: WorkBinding::Unbound,
        }),
    );
    k.commit(&input(&k, unbound, Some(2), "unbound")).unwrap();
    // A pin to the earlier edition remains legal after its current replacement.
    let pin = universe_domain::VersionRef {
        universe: Some(uid()),
        record: RecordId::parse(&id("rec", 2)).unwrap(),
        version: RecordVersionId::parse(&id("ver", 2)).unwrap(),
    };
    let passage = make(
        3,
        4,
        Payload::PassageRef(PassageRef {
            work_version: pin,
            passage_id: "opening".into(),
            anchor: None,
        }),
    );
    let head = k.commit(&input(&k, passage, None, "passage")).unwrap();
    // Matching identity/version alone cannot turn a Work into a WorkVersion.
    let wrong = make(
        4,
        5,
        Payload::SceneRef(SceneRef {
            work_version: universe_domain::VersionRef {
                universe: Some(uid()),
                record: RecordId::parse(&id("rec", 1)).unwrap(),
                version: RecordVersionId::parse(&id("ver", 1)).unwrap(),
            },
            scene_id: "wrong kind".into(),
            disclosed_records: vec![],
            viewpoint: None,
            narrative_position: None,
            depicted_events: vec![],
            narration_frame: None,
            world_associations: vec![],
        }),
    );
    let before = counts();
    assert!(k.commit(&input(&k, wrong, None, "wrong-kind")).is_err());
    assert_eq!(counts(), before);
    drop(k);
    let reopened = Kernel::open(&path).unwrap();
    assert_eq!(reopened.head(&cont()).unwrap(), head);
    assert!(reopened.records(&cont(),&first).unwrap().iter().any(|r|matches!(&r.payload,Payload::WorkVersion(w) if matches!(w.binding,WorkBinding::Bound{..}))));
    assert!(reopened.records(&cont(),&head).unwrap().iter().any(|r|matches!(&r.payload,Payload::PassageRef(p) if p.work_version.version.as_str()==id("ver",2))));
}
