use serde::Deserialize;
use std::{collections::BTreeMap, path::Path};
use universe_domain::{ids::*, records::*};
use universe_store::{
    kernel::{Assignment, CommitInput, FaultPoint, Kernel},
    Database, StoreError,
};

#[derive(Deserialize)]
struct Fixture {
    universe: UniverseId,
    continuity: ContinuityId,
    principal: PrincipalId,
    initial: Vec<RecordVersion>,
    later: Vec<RecordVersion>,
}
fn fixture() -> Fixture {
    let f: Fixture = serde_json::from_str(include_str!(
        "../../../fixtures/normalized-foundation/facts.json"
    ))
    .unwrap();
    for r in f.initial.iter().chain(&f.later) {
        assert!(
            r.verify_digest(),
            "fixture serialization mismatch {}: {}",
            r.record_version_id,
            serde_json::to_string(&r.payload).unwrap()
        );
    }
    f
}
fn create(path: &Path) -> Kernel {
    let f = fixture();
    Kernel::create(path, f.universe, "Foundation", f.continuity, &f.principal).unwrap()
}
fn input(k: &Kernel, records: &[RecordVersion], key: &str) -> CommitInput {
    let f = fixture();
    let head = k.head(&f.continuity).unwrap();
    let map = k.snapshot(&f.continuity, &head).unwrap();
    CommitInput {
        universe: f.universe,
        continuity: f.continuity,
        expected_head: head,
        principal: f.principal,
        decision: "authored facts".into(),
        reason: "Independent foundation fixture".into(),
        idempotency_key: key.into(),
        changes: records
            .iter()
            .map(|r| Assignment {
                record_id: r.identity.record_id.clone(),
                expected: map
                    .get(r.identity.record_id.as_str())
                    .map(|v| RecordVersionId::parse(v).unwrap()),
                next: Some(r.clone()),
            })
            .collect(),
    }
}
fn check(k: &Kernel, revision: &RevisionId, expected: &[RecordVersion]) {
    let f = fixture();
    let actual = k.records(&f.continuity, revision).unwrap();
    let map: BTreeMap<_, _> = actual.iter().map(|r| (&r.identity.record_id, r)).collect();
    assert_eq!(map.len(), expected.len());
    for r in expected {
        assert_eq!(map[&r.identity.record_id], r);
        assert!(
            r.verify_digest(),
            "independently frozen digest {}",
            r.record_version_id
        );
    }
}
fn counts(path: &Path) -> BTreeMap<String, i64> {
    let c = Database::open_existing(path).unwrap().connect().unwrap();
    let tables:Vec<String>=c.prepare("SELECT name FROM sqlite_master WHERE type='table' AND (name GLOB 'r_*' OR name IN ('record_identities','record_versions','commits','commit_changes','operation_receipts','type_definition','instance_classification','definition_attribute')) ORDER BY name").unwrap().query_map([],|r|r.get(0)).unwrap().collect::<Result<_,_>>().unwrap();
    tables
        .into_iter()
        .map(|t| {
            let n = c
                .query_row(
                    &format!("SELECT count(*) FROM \"{}\"", t.replace('"', "\"\"")),
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            (t, n)
        })
        .collect()
}

#[test]
fn independent_facts_history_and_sql_reconstruction_survive_restart() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("foundation.sqlite");
    let f = fixture();
    let mut k = create(&path);
    // Order does not determine dependency resolution: parents, clocks and
    // source versions may be assigned after the referring record in a batch.
    let mut initial = f.initial.clone();
    initial.reverse();
    let first_input = input(&k, &initial, "initial");
    let first = k.commit(&first_input).unwrap();
    check(&k, &first, &f.initial);
    let branch = ContinuityId::parse("cont_000000000000000000000002").unwrap();
    let fork = k
        .branch(&branch, &f.continuity, &first, &f.principal)
        .unwrap();
    let second_input = input(&k, &f.later, "later");
    let second = k.commit(&second_input).unwrap();
    let mut expected: BTreeMap<_, _> = f
        .initial
        .iter()
        .cloned()
        .map(|r| (r.identity.record_id.clone(), r))
        .collect();
    for r in &f.later {
        expected.insert(r.identity.record_id.clone(), r.clone());
    }
    let expected: Vec<_> = expected.into_values().collect();
    check(&k, &second, &expected);
    k.cache_snapshot(&f.continuity, &first, |_| Ok(())).unwrap();
    k.cache_snapshot(&f.continuity, &second, |_| Ok(()))
        .unwrap();
    let history = k
        .record_history(&f.continuity, &second, &f.later[0].identity.record_id)
        .unwrap();
    assert_eq!(history.len(), 2);
    drop(k);
    let k = Kernel::open(&path).unwrap();
    check(&k, &first, &f.initial);
    check(&k, &second, &expected);
    assert_eq!(k.records(&branch, &fork).unwrap().len(), f.initial.len());
    assert_eq!(k.receipt(&first_input).unwrap(), Some(first.clone()));
    assert_eq!(k.receipt(&second_input).unwrap(), Some(second.clone()));
    assert_eq!(
        k.record_history(&f.continuity, &second, &f.later[0].identity.record_id)
            .unwrap(),
        history
    );
    let c = Database::open_existing(&path).unwrap().connect().unwrap();
    assert_eq!(
        c.query_row("SELECT count(*) FROM snapshot_member", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        (f.initial.len() * 2) as i64
    );
    assert_eq!(
        c.query_row("SELECT count(*) FROM definition_attribute", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        2
    );
    assert_eq!(
        c.query_row("SELECT count(*) FROM type_definition", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        5
    );
    assert_eq!(
        c.query_row("SELECT count(*) FROM instance_classification", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        4
    );
    // This read-only program imports neither the Rust codec nor a writer.
    let output = std::process::Command::new("python3")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../scripts/verify_normalized_foundation.py"
        ))
        .arg(&path)
        .arg(first.as_str())
        .arg(second.as_str())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn rebuild(record: &RecordVersion, payload: Payload) -> RecordVersion {
    RecordVersion::build(
        RecordVersionId::parse("ver_0000000000000000000003e8").unwrap(),
        record.identity.clone(),
        payload,
    )
    .unwrap()
}
#[test]
fn invalid_namespaces_kinds_versions_ancestry_and_values_leave_every_row_intact() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("invalid.sqlite");
    let mut k = create(&path);
    let f = fixture();
    let first = k.commit(&input(&k, &f.initial, "initial")).unwrap();
    let before = counts(&path);
    let select = |n: u32| {
        f.initial
            .iter()
            .find(|r| r.identity.record_id.as_str() == format!("rec_{n:024x}"))
            .unwrap()
    };
    let mut cases = Vec::new();
    for n in [999, 9] {
        let r = select(6);
        let Payload::Entity(mut e) = r.payload.clone() else {
            unreachable!()
        };
        e.classification = Some(RecordId::parse(&format!("rec_{n:024x}")).unwrap());
        cases.push(rebuild(r, Payload::Entity(e)));
    }
    let r = select(1);
    let Payload::EntityType(mut t) = r.payload.clone() else {
        unreachable!()
    };
    t.parent = Some(select(2).identity.record_id.clone());
    t.parent_resolution = ParentResolution::Resolved;
    cases.push(rebuild(r, Payload::EntityType(t)));
    let r = select(23);
    let Payload::Anchor(a) = r.payload.clone() else {
        unreachable!()
    };
    let mut b = a.clone();
    b.source_version.record = select(21).identity.record_id.clone();
    cases.push(rebuild(r, Payload::Anchor(b)));
    let mut b = a.clone();
    b.source_version.version = RecordVersionId::parse("ver_0000000000000000000003e7").unwrap();
    cases.push(rebuild(r, Payload::Anchor(b)));
    let r = select(17);
    let Payload::Assertion(a) = r.payload.clone() else {
        unreachable!()
    };
    let mut b = a.clone();
    b.scope.context.universe = Some(UniverseId::parse("unv_000000000000000000000002").unwrap());
    cases.push(rebuild(r, Payload::Assertion(b)));
    let mut b = a.clone();
    b.scope.context.record = select(14).identity.record_id.clone();
    cases.push(rebuild(r, Payload::Assertion(b)));
    let mut b = a.clone();
    b.proposition.record = select(6).identity.record_id.clone();
    cases.push(rebuild(r, Payload::Assertion(b)));
    let mut b = a.clone();
    b.attribute_mode = AttributeMode::Shared;
    cases.push(rebuild(r, Payload::Assertion(b)));
    let r = select(16);
    let Payload::Proposition(p) = r.payload.clone() else {
        unreachable!()
    };
    let mut b = p.clone();
    b.value = Some(universe_domain::value::Value::Quantity {
        value: Box::new(universe_domain::value::Value::Decimal {
            digits: "NaN".into(),
        }),
        unit: UnitId::parse("unit_00000000000000000000000c").unwrap(),
    });
    cases.push(rebuild(r, Payload::Proposition(b)));
    let mut b = p.clone();
    b.value = Some(universe_domain::value::Value::Quantity {
        value: Box::new(universe_domain::value::Value::Decimal {
            digits: "30.00".into(),
        }),
        unit: UnitId::parse("unit_00000000000000000000000d").unwrap(),
    });
    cases.push(rebuild(r, Payload::Proposition(b)));
    for (i, case) in cases.iter().enumerate() {
        let change = input(&k, std::slice::from_ref(case), &format!("invalid-{i}"));
        assert!(k.commit(&change).is_err(), "case {i}");
        assert_eq!(k.head(&f.continuity).unwrap(), first);
        assert_eq!(
            counts(&path),
            before,
            "body children or authority leaked in case {i}"
        );
        assert!(k.receipt(&change).unwrap().is_none());
    }
    drop(k);
    let k = Kernel::open(&path).unwrap();
    check(&k, &first, &f.initial);
}

#[test]
fn every_kernel_publication_fault_rolls_back_typed_children_and_history() {
    for fault in [
        FaultPoint::Versions,
        FaultPoint::Changes,
        FaultPoint::Head,
        FaultPoint::Projections,
        FaultPoint::Receipt,
        FaultPoint::BeforeCommit,
    ] {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("rollback.sqlite");
        let mut k = create(&path);
        let f = fixture();
        let first = k.commit(&input(&k, &f.initial, "initial")).unwrap();
        let before = counts(&path);
        let change = input(&k, &f.later, "later");
        assert!(k
            .commit_with_hook(&change, |point| if point == fault {
                Err(StoreError::StorageFailure("injected interruption".into()))
            } else {
                Ok(())
            })
            .is_err());
        assert_eq!(k.head(&f.continuity).unwrap(), first);
        assert_eq!(counts(&path), before);
        assert!(k.receipt(&change).unwrap().is_none());
        drop(k);
        let mut k = Kernel::open(&path).unwrap();
        check(&k, &first, &f.initial);
        assert_eq!(counts(&path), before);
        let revision = k.commit(&change).unwrap();
        assert_eq!(k.commit(&change).unwrap(), revision);
    }
}

#[test]
fn normalized_crash_child() {
    let Ok(path) = std::env::var("FOUNDATION_CRASH_PACKAGE") else {
        return;
    };
    let phase = std::env::var("FOUNDATION_CRASH_PHASE").unwrap();
    let mut k = Kernel::open(Path::new(&path)).unwrap();
    let f = fixture();
    let change = input(&k, &f.later, "later");
    k.commit_with_hook(&change, |point| {
        if format!("{point:?}") == phase {
            std::process::exit(72)
        }
        Ok(())
    })
    .unwrap();
    std::process::exit(72);
}

#[test]
fn abrupt_process_exit_recovers_the_complete_fixture_or_its_exact_prior_state() {
    for phase in [
        "Versions",
        "Changes",
        "Head",
        "Projections",
        "Receipt",
        "BeforeCommit",
        "Committed",
    ] {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("crash.sqlite");
        let f = fixture();
        let mut k = create(&path);
        let first = k.commit(&input(&k, &f.initial, "initial")).unwrap();
        let change = input(&k, &f.later, "later");
        let before = counts(&path);
        drop(k);
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "normalized_crash_child", "--nocapture"])
            .env("FOUNDATION_CRASH_PACKAGE", &path)
            .env("FOUNDATION_CRASH_PHASE", phase)
            .output()
            .unwrap();
        assert_eq!(
            output.status.code(),
            Some(72),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let mut k = Kernel::open(&path).unwrap();
        check(&k, &first, &f.initial);
        if phase == "Committed" {
            let revision = k.receipt(&change).unwrap().unwrap();
            assert_eq!(k.head(&f.continuity).unwrap(), revision);
            let actual: BTreeMap<_, _> = k
                .records(&f.continuity, &revision)
                .unwrap()
                .into_iter()
                .map(|r| (r.identity.record_id.clone(), r))
                .collect();
            for r in &f.later {
                assert_eq!(&actual[&r.identity.record_id], r);
            }
            assert_eq!(k.commit(&change).unwrap(), revision);
        } else {
            assert_eq!(k.head(&f.continuity).unwrap(), first);
            assert_eq!(counts(&path), before);
            assert!(k.receipt(&change).unwrap().is_none());
        }
    }
}
