//! Publication/persistence tests. Service applicability qualification is separate.
use serde_json::{json, Value};
use universe_domain::{ids::*, records::*};
use universe_store::{kernel::*, Database, StoreError};
fn id(prefix: &str, n: u64) -> String {
    format!("{prefix}_{n:024x}")
}
fn uid() -> UniverseId {
    UniverseId::parse(&id("unv", 1)).unwrap()
}
fn cont() -> ContinuityId {
    ContinuityId::parse(&id("cont", 1)).unwrap()
}
fn rr(n: u64) -> Value {
    json!({"universe":uid(),"record":id("rec",n)})
}
fn record(n: u64, v: u64, payload: Value) -> RecordVersion {
    let payload: Payload = serde_json::from_value(payload).unwrap();
    RecordVersion::build(
        RecordVersionId::parse(&id("ver", v)).unwrap(),
        RecordIdentity::new(
            uid(),
            RecordId::parse(&id("rec", n)).unwrap(),
            payload.kind(),
        ),
        payload,
    )
    .unwrap()
}
fn interval(start: i32, end: i32) -> Value {
    json!({"kind":"calendar_interval","calendar":id("cal",4),"start":{"kind":"exact","value":start.to_string()},"end":{"kind":"exact","value":end.to_string()}})
}
fn assertion(n: u64, v: u64, proposition: u64, mode: &str, basis: Value) -> RecordVersion {
    record(
        n,
        v,
        json!({"record_kind":"assertion","attributeMode":mode,"proposition":rr(proposition),"polarity":"support","scope":{"context":rr(3),"applicability":{"kind":"universe_wide"}},"validity":interval(10,11),"persistence":"explicit_interval","precision":"exact","basis":basis}),
    )
}
fn proposition(n: u64, v: u64, subject: u64, digits: &str) -> RecordVersion {
    record(
        n,
        v,
        json!({"record_kind":"proposition","subject":rr(subject),"predicate":rr(2),"value":{"kind":"integer","digits":digits},"quantification":"particular","context":rr(3)}),
    )
}
fn base() -> Vec<RecordVersion> {
    vec![
        record(
            1,
            1,
            json!({"record_kind":"entity_type","namespace":"pistol","key":"gun","name":"Gun","labels":{},"parent":null,"parentResolution":"root","applicability":{"kind":"universe_wide"},"classificationExecutable":true}),
        ),
        record(
            2,
            2,
            json!({"record_kind":"property","namespace":"pistol","key":"rounds","labels":{},"subjectTypes":[id("rec",1)],"value":{"kind":"integer"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}),
        ),
        record(
            3,
            3,
            json!({"record_kind":"represented_context","universe":uid(),"kind":{"kind":"objective"},"labels":{}}),
        ),
        record(
            4,
            4,
            json!({"record_kind":"calendar","namespace":"pistol","key":"clock","labels":{},"unitStructure":{}}),
        ),
        proposition(5, 5, 1, "12"),
        assertion(
            6,
            6,
            5,
            "initial_value",
            json!({"kind":"author_decision","note":"Starts with twelve"}),
        ),
        record(
            7,
            7,
            json!({"record_kind":"entity","names":[],"classification":id("rec",1),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}}),
        ),
        record(
            8,
            8,
            json!({"record_kind":"entity","names":[],"classification":id("rec",1),"classificationResolution":"resolved","worldAssociations":[],"labels":{},"metadata":{}}),
        ),
    ]
}
fn input(k: &Kernel, rows: Vec<RecordVersion>, key: &str) -> CommitInput {
    let head = k.head(&cont()).unwrap();
    let map = k.snapshot(&cont(), &head).unwrap();
    CommitInput {
        universe: uid(),
        continuity: cont(),
        expected_head: head,
        principal: PrincipalId::parse(&id("prn", 1)).unwrap(),
        decision: "reviewed fixture".into(),
        reason: key.into(),
        idempotency_key: key.into(),
        changes: rows
            .into_iter()
            .map(|r| Assignment {
                record_id: r.identity.record_id.clone(),
                expected: map
                    .get(r.identity.record_id.as_str())
                    .map(|v| RecordVersionId::parse(v).unwrap()),
                next: Some(r),
            })
            .collect(),
    }
}
fn initial(k: &Kernel, instance: u64, offset: u64, key: &str) -> CommitInput {
    let start = offset;
    let prop = offset + 1;
    let a = offset + 2;
    let event = record(
        start,
        start,
        json!({"record_kind":"event","occurrence":"occurred","time":{"kind":"exact","calendar":id("cal",4),"value":"10"},"participants":[{"record":rr(instance),"role":"starting_instance"}],"labels":{}}),
    );
    let basis = json!({"kind":"instance_initialization","start":{"universe":uid(),"record":id("rec",start),"version":id("ver",start)},"definition":{"universe":uid(),"record":id("rec",6),"version":id("ver",6)},"source_revision":k.head(&cont()).unwrap()});
    input(
        k,
        vec![
            event,
            proposition(prop, prop, instance, "12"),
            assertion(a, a, prop, "instance", basis),
        ],
        key,
    )
}
fn create(path: &std::path::Path) -> Kernel {
    let mut k = Kernel::create(
        path,
        uid(),
        "Initialization",
        cont(),
        &PrincipalId::parse(&id("prn", 1)).unwrap(),
    )
    .unwrap();
    k.commit(&input(&k, base(), "base")).unwrap();
    k
}
fn counts(path: &std::path::Path) -> Vec<(String, i64)> {
    let c = Database::open_existing(path).unwrap().connect().unwrap();
    let tables:Vec<String>=c.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").unwrap().query_map([],|r|r.get(0)).unwrap().collect::<Result<_,_>>().unwrap();
    tables
        .into_iter()
        .map(|t| {
            let n = c
                .query_row(&format!("SELECT count(*) FROM \"{t}\""), [], |r| r.get(0))
                .unwrap();
            (t, n)
        })
        .collect()
}
#[test]
fn separate_instances_retry_restart_correction_and_retraction_keep_receipts() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.sqlite");
    let mut k = create(&path);
    let first = initial(&k, 7, 10, "a");
    let a = k.commit(&first).unwrap();
    let second = initial(&k, 8, 20, "b");
    let b = k.commit(&second).unwrap();
    assert_eq!(k.commit(&first).unwrap(), a);
    let receipts = k.initialization_receipts().unwrap();
    assert_eq!(receipts.len(), 2);
    assert_eq!(receipts[0].instance.as_str(), id("rec", 7));
    assert_eq!(receipts[0].assertion.as_str(), id("ver", 12));
    assert_eq!(receipts[0].revision, a);
    assert_eq!(receipts[1].revision, b);
    drop(k);
    let mut k = Kernel::open(&path).unwrap();
    assert_eq!(k.initialization_receipts().unwrap(), receipts);
    assert_eq!(k.commit(&second).unwrap(), b);
    // Renaming the same identity cannot turn initialization into a refill.
    let entity = k
        .records(&cont(), &k.head(&cont()).unwrap())
        .unwrap()
        .into_iter()
        .find(|r| r.identity.record_id.as_str() == id("rec", 7))
        .unwrap();
    let mut renamed = entity.payload.clone();
    if let Payload::Entity(e) = &mut renamed {
        e.labels.insert("en".into(), "Renamed pistol".into());
    }
    let renamed = RecordVersion::build(
        RecordVersionId::parse(&id("ver", 30)).unwrap(),
        entity.identity,
        renamed,
    )
    .unwrap();
    k.commit(&input(&k, vec![renamed], "rename")).unwrap();
    assert!(k
        .commit(&initial(&k, 7, 35, "refill-after-rename"))
        .is_err());
    assert_eq!(k.initialization_receipts().unwrap(), receipts);
    // Correct the initial proposition through an authored historical change.
    k.commit(&input(&k, vec![proposition(11, 31, 7, "7")], "correction"))
        .unwrap();
    assert_eq!(k.initialization_receipts().unwrap(), receipts);
    let old = k.records(&cont(), &a).unwrap();
    assert!(old.iter().any(|r| r == &proposition(11, 11, 7, "12")));
    let mut retract = input(
        &k,
        vec![old
            .iter()
            .find(|r| r.identity.record_id.as_str() == id("rec", 12))
            .unwrap()
            .clone()],
        "retract",
    );
    retract.changes[0].next = None;
    k.commit(&retract).unwrap();
    let before = counts(&path);
    assert!(k.commit(&initial(&k, 7, 40, "refill")).is_err());
    assert_eq!(counts(&path), before);
    assert_eq!(k.initialization_receipts().unwrap(), receipts);
    k.integrity().unwrap();
}
#[test]
fn every_publication_fault_rolls_back_assertions_and_receipts() {
    for fault in [
        FaultPoint::Versions,
        FaultPoint::Changes,
        FaultPoint::Head,
        FaultPoint::Projections,
        FaultPoint::Receipt,
        FaultPoint::BeforeCommit,
    ] {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("u.sqlite");
        let mut k = create(&path);
        let request = initial(&k, 7, 10, "a");
        let before = counts(&path);
        assert!(k
            .commit_with_hook(&request, |point| if point == fault {
                Err(StoreError::StorageFailure("injected".into()))
            } else {
                Ok(())
            })
            .is_err());
        assert_eq!(counts(&path), before);
        assert!(k.initialization_receipts().unwrap().is_empty());
        drop(k);
        let mut k = Kernel::open(&path).unwrap();
        k.commit(&request).unwrap();
        assert_eq!(k.initialization_receipts().unwrap().len(), 1);
    }
}
#[test]
fn duplicate_initializations_and_forged_values_publish_nothing() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.sqlite");
    let mut k = create(&path);
    let mut request = initial(&k, 7, 10, "a");
    let second = initial(&k, 7, 20, "b");
    request.changes.extend(second.changes);
    let before = counts(&path);
    assert!(k.commit(&request).is_err());
    assert_eq!(counts(&path), before);
    let mut wrong = initial(&k, 7, 30, "wrong");
    wrong.changes[1].next = Some(proposition(31, 31, 7, "13"));
    assert!(k.commit(&wrong).is_err());
    assert_eq!(counts(&path), before);
    k.preview(&initial(&k, 7, 40, "preview")).unwrap();
    assert_eq!(counts(&path), before);
}
#[test]
fn missing_or_forged_receipt_is_detected_on_open() {
    for missing in [true, false] {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("u.sqlite");
        let mut k = create(&path);
        k.commit(&initial(&k, 7, 10, "a")).unwrap();
        drop(k);
        let db = Database::open_existing(&path).unwrap();
        let c = db.connect().unwrap();
        if missing {
            c.execute("DELETE FROM initialization_receipt", []).unwrap();
        } else {
            c.execute(
                "UPDATE initialization_receipt SET instance_id=?1",
                [id("rec", 8)],
            )
            .unwrap();
        }
        drop(c);
        assert!(Kernel::open(&path).is_err());
    }
}

#[test]
fn complete_and_filtered_archives_preserve_once_only_evidence() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.sqlite");
    let mut k = create(&path);
    k.commit(&initial(&k, 7, 10, "a")).unwrap();
    k.commit(&initial(&k, 8, 20, "b")).unwrap();
    let receipts = k.initialization_receipts().unwrap();
    for filtered in [false, true] {
        let destination = d.path().join(if filtered {
            "filtered.sqlite"
        } else {
            "complete.sqlite"
        });
        k.export_logical(
            &destination,
            &if filtered {
                vec![RecordId::parse(&id("rec", 7)).unwrap()]
            } else {
                vec![]
            },
        )
        .unwrap();
        let archive = LogicalArchive::read(&destination).unwrap();
        let target = UniverseId::parse(&id("unv", if filtered { 2 } else { 1 })).unwrap();
        let (restored, _staging) = archive.stage(d.path(), target, "Restored").unwrap();
        assert_eq!(
            restored.initialization_receipts().unwrap(),
            if filtered {
                vec![receipts[0].clone()]
            } else {
                receipts.clone()
            }
        );
        restored.integrity().unwrap();
    }
}

#[test]
fn explicit_historical_restoration_retains_original_receipt_and_pinned_history() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("u.sqlite");
    let mut k = create(&path);
    let before = k.head(&cont()).unwrap();
    let first = initial(&k, 7, 10, "a");
    let revision = k.commit(&first).unwrap();
    let receipts = k.initialization_receipts().unwrap();
    assert!(k
        .initialization_receipts_at(&cont(), &before)
        .unwrap()
        .is_empty());
    assert_eq!(
        k.initialization_receipts_at(&cont(), &revision).unwrap(),
        receipts
    );
    let original = first.changes[2].next.as_ref().unwrap().clone();
    let mut retract = input(&k, vec![original.clone()], "retract");
    retract.changes[0].next = None;
    k.commit(&retract).unwrap();
    let restored = RecordVersion::build(
        RecordVersionId::parse(&id("ver", 99)).unwrap(),
        original.identity.clone(),
        original.payload.clone(),
    )
    .unwrap();
    k.commit(&input(&k, vec![restored], "reviewed-restore"))
        .unwrap();
    assert_eq!(k.initialization_receipts().unwrap(), receipts);
    k.integrity().unwrap();
    drop(k);
    let mut k = Kernel::open(&path).unwrap();
    assert_eq!(k.initialization_receipts().unwrap(), receipts);
    assert!(k.commit(&initial(&k, 7, 40, "refill")).is_err());
}
