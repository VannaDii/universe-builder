//! Explicit opt-in workload: ordinary CI keeps the smaller fault/recovery suite.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    io::{BufWriter, Write},
    os::unix::fs::OpenOptionsExt,
    time::Instant,
};
use universe_domain::{ids::*, records::*};
use universe_store::kernel::{Kernel, LogicalArchive};

#[test]
#[ignore = "standard workload; run explicitly in release mode"]
fn standard_workload_preserves_full_history_and_evaluates_indexed_rules() {
    let start = Instant::now();
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("standard.jsonl");
    let mut output = BufWriter::new(
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
            .unwrap(),
    );
    let u = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let c = ContinuityId::parse("cont_000000000000000000000001").unwrap();
    let rev = RevisionId::parse("rev_000000000000000000000001").unwrap();
    let principal = PrincipalId::parse("prn_000000000000000000000001").unwrap();
    let id = |n| format!("rec_{n:024x}");
    let rr = |n| json!({"universe":u,"record":id(n)});
    let mut hash = Sha256::new();
    let mut rows = 0usize;
    {
        let mut row = |value: Value| {
            let mut bytes = serde_json::to_vec(&value).unwrap();
            bytes.push(b'\n');
            hash.update(&bytes);
            output.write_all(&bytes).unwrap();
            rows += 1;
        };
        row(
            json!({"entry":"manifest","manifest":{"format":"universe-logical-v1","universe":u,"name":"Standard workload","complete":true,"omitted_records":0,"includes_history":true,"includes_workflow":false}}),
        );
        row(json!({"entry":"continuity","id":c,"head":rev,"baseline":null}));
        row(
            json!({"entry":"commit","id":rev,"continuity":c,"parent":null,"sequence":0,"principal":principal,"decision":"fixture import","reason":"Standard scale and recovery","digest":"0".repeat(64)}),
        );
        let mut add = |n, payload: Value| {
            let payload: Payload = serde_json::from_value(payload).unwrap();
            let record = RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                RecordIdentity::new(u.clone(), RecordId::parse(&id(n)).unwrap(), payload.kind()),
                payload,
            )
            .unwrap();
            row(json!({"entry":"record","record":record}));
            row(
                json!({"entry":"change","revision":rev,"record":record.identity.record_id,"prior":null,"next":record.record_version_id}),
            );
        };
        add(
            1,
            json!({"record_kind":"represented_context","universe":u,"kind":{"kind":"objective"},"labels":{"en":"Objective"}}),
        );
        add(
            2,
            json!({"record_kind":"property","namespace":"scale","key":"member","labels":{},"value":{"kind":"integer"},"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}),
        );
        for entity in 0..10_000 {
            add(
                100 + entity,
                json!({"record_kind":"entity","names":[],"types":[],"worldAssociations":[],"labels":{"en":format!("Character {entity}")},"metadata":{}}),
            );
            for value in 0..20 {
                let n = 20_000 + entity * 40 + value * 2;
                add(
                    n,
                    json!({"record_kind":"proposition","subject":rr(100+entity),"predicate":rr(2),"roles":[],"value":{"kind":"integer","digits":value.to_string()},"context":rr(1),"quantification":"particular"}),
                );
                add(
                    n + 1,
                    json!({"record_kind":"assertion","proposition":rr(n),"polarity":"support","scope":{"applicability":{"kind":"universe_wide"},"context":rr(1)},"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","alternatives":[],"basis":{"kind":"author_decision","note":"Authored workload member"}}),
                );
            }
        }
        for n in 0..2_000 {
            add(
                500_000 + n,
                json!({"record_kind":"rule","namespace":"scale","key":format!("member-{n}"),"labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":["scale:member"],"expression":{"kind":"claim","subject":{"kind":"record","ref":rr(100+n)},"predicate":"scale:member","roles":[],"value":{"kind":"value","value":{"kind":"integer","digits":(n%20).to_string()}},"polarity":"support"},"capabilities":["basic.v1"],"executable":true,"validity":{"kind":"unspecified"}}),
            );
        }
    }
    writeln!(
        output,
        "{}",
        json!({"entry":"checksum","sha256":hex::encode(hash.finalize()),"rows":rows})
    )
    .unwrap();
    let file = output.into_inner().unwrap();
    file.sync_all().unwrap();
    drop(file);
    let generated_ms = start.elapsed().as_millis();
    eprintln!(
        "standard: generated 10000 entities, 200000 assertions, 2000 rules; archive_bytes={}",
        std::fs::metadata(&path).unwrap().len()
    );
    let t = Instant::now();
    let archive = LogicalArchive::read(&path).unwrap();
    let (mut kernel, staging) = archive
        .stage(directory.path(), u.clone(), "Standard workload")
        .unwrap();
    let import_ms = t.elapsed().as_millis();
    drop(archive);
    eprintln!("standard: import_ms={import_ms}");
    let t = Instant::now();
    for n in 2..=10 {
        kernel
            .branch(
                &ContinuityId::parse(&format!("cont_{n:024x}")).unwrap(),
                &c,
                &rev,
                &principal,
            )
            .unwrap();
    }
    let branches_ms = t.elapsed().as_millis();
    eprintln!("standard: branches_ms={branches_ms}");
    let t = Instant::now();
    let records = kernel.records(&c, &rev).unwrap();
    let read_ms = t.elapsed().as_millis();
    assert_eq!(records.len(), 412_002);
    let frame: universe_domain::Frame = serde_json::from_value(json!({"universe":u,"continuity":c,"revision":rev,"context":rr(1),"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
    let t = Instant::now();
    let index = universe_rules::EvaluationIndex::new(&records);
    let index_ms = t.elapsed().as_millis();
    let t = Instant::now();
    let mut evaluated = 0;
    for r in records
        .iter()
        .filter(|r| matches!(r.payload, Payload::Rule(_)))
    {
        let compiled = universe_rules::compile_rule(r).unwrap();
        let mut context = universe_rules::EvaluationContext {
            frame: Some(&frame),
            base_snapshot: &records,
            candidate_changes: vec![],
            index: Some(&index),
            world_scope: Some(vec![]),
        };
        let indexed = universe_rules::evaluate_rule(&compiled, &context);
        assert_eq!(
            indexed.coverage,
            universe_rules::EvaluationCoverage::Complete
        );
        assert_eq!(indexed.outcome, universe_rules::EvidenceOutcome::Supported);
        // The same bounded reference evaluator must report its work limit,
        // never turn a large unindexed scan into a complete result.
        if evaluated % 199 == 0 || evaluated == 1999 {
            context.index = None;
            let reference = universe_rules::evaluate_rule(&compiled, &context);
            assert_ne!(
                reference.coverage,
                universe_rules::EvaluationCoverage::Complete
            );
        }
        evaluated += 1;
    }
    assert_eq!(evaluated, 2000);
    let evaluation_ms = t.elapsed().as_millis();
    drop(index);
    let t = Instant::now();
    let backup = directory.path().join("backup.sqlite");
    kernel.backup(&backup).unwrap();
    let backup_ms = t.elapsed().as_millis();
    eprintln!("standard: backup_ms={backup_ms}");
    let expected_heads = kernel.status().unwrap().heads;
    drop(kernel);
    let t = Instant::now();
    let reopened = Kernel::open(&staging.path().join("package.sqlite")).unwrap();
    assert_eq!(reopened.records(&c, &rev).unwrap(), records);
    assert_eq!(reopened.status().unwrap().heads, expected_heads);
    let restart_ms = t.elapsed().as_millis();
    let t = Instant::now();
    let (restored, _temporary) = Kernel::stage_restore(&backup, directory.path()).unwrap();
    assert_eq!(restored.records(&c, &rev).unwrap(), records);
    assert_eq!(restored.status().unwrap().heads, expected_heads);
    let restore_ms = t.elapsed().as_millis();
    eprintln!(
        "{}",
        json!({"standard_workload":"pass","entities":10000,"assertions":200000,"rules":2000,"continuities":10,"archive_generation_ms":generated_ms,"import_ms":import_ms,"branches_ms":branches_ms,"snapshot_read_ms":read_ms,"index_ms":index_ms,"evaluation_ms":evaluation_ms,"backup_ms":backup_ms,"restart_ms":restart_ms,"restore_ms":restore_ms,"total_ms":start.elapsed().as_millis()})
    );
}
