//! Frozen characterization specimens retain original bytes and digests.
//! Separately authored expectations qualify Goal 28 inherited uncertainty.
use super::rule_checks::evaluate_indexed;
use serde_json::Value;
use universe_domain::{ids::*, records::*, Frame};

#[test]
fn object_rule_capabilities_match_frozen_expectations() {
    let gold: Value = serde_json::from_str(include_str!(
        "../../../fixtures/object-rules/capabilities.json"
    ))
    .unwrap();
    for case in gold["cases"].as_array().unwrap() {
        let records: Vec<RecordVersion> = case["records"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                let n = row["id"].as_u64().unwrap();
                let payload: Payload = serde_json::from_value(row["payload"].clone())
                    .unwrap_or_else(|e| panic!("{} record {n}: {e}", case["name"]));
                if let Payload::Rule(rule) = &payload {
                    assert_eq!(
                        rule.labels["author_wording"],
                        row["payload"]["labels"]["author_wording"].as_str().unwrap()
                    );
                }
                RecordVersion::build(
                    RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                    RecordIdentity::new(
                        UniverseId::parse("unv_000000000000000000000001").unwrap(),
                        RecordId::parse(&format!("rec_{n:024x}")).unwrap(),
                        payload.kind(),
                    ),
                    payload,
                )
                .unwrap()
            })
            .collect();
        let records = storage_readback(records, case["name"].as_str().unwrap());
        let target = records
            .iter()
            .find(|r| {
                r.identity.record_id.as_str()
                    == format!("rec_{:024x}", case["rule"].as_u64().unwrap())
            })
            .unwrap();
        assert!(crate::operations::protected(&target.payload));
        let frame: Frame = serde_json::from_value(case["frame"].clone()).unwrap();
        let worlds: Vec<RecordId> = serde_json::from_value(case["worlds"].clone()).unwrap();
        let index = universe_rules::EvaluationIndex::new(&records);
        for indexed in [None, Some(&index)] {
            let got = evaluate_indexed(indexed, target, &records, &frame, &worlds);
            let actual = serde_json::json!({
                "accepted": got.accepted,
                "complete": got.complete,
                "outcome": match got.evidence.outcome() {
                    universe_rules::EvidenceOutcome::Supported => "supported",
                    universe_rules::EvidenceOutcome::Refuted => "refuted",
                    universe_rules::EvidenceOutcome::Conflicting => "conflicting",
                    universe_rules::EvidenceOutcome::NotEstablished => "not_established",
                }
            });
            assert_eq!(actual, case["expected"], "{}", case["name"]);
            println!(
                "{}",
                serde_json::json!({
                    "case": case["name"], "indexed": indexed.is_some(), "actual": actual
                })
            );
        }
    }
    for operand in gold["undecided_operands"].as_array().unwrap() {
        assert!(serde_json::from_value::<universe_domain::expr::Operand>(operand.clone()).is_err());
    }
}

/// Characterize the same evaluator against records reconstructed by the actual
/// kernel after a process-independent SQL reader has checked original digests.
fn storage_readback(mut records: Vec<RecordVersion>, name: &str) -> Vec<RecordVersion> {
    use universe_store::kernel::{Assignment, CommitInput, Kernel};
    let universe = UniverseId::parse("unv_000000000000000000000001").unwrap();
    let continuity = ContinuityId::parse("cont_000000000000000000000001").unwrap();
    let principal = PrincipalId::parse("prn_000000000000000000000001").unwrap();
    // The original evaluator-only specimens intentionally omit definitions.
    // Supply those dependencies without changing any original record or digest.
    let support = [
        (
            70,
            serde_json::json!({"record_kind":"entity_type","namespace":"support","key":"pistol","name":"Pistol","labels":{},"parent":null,"parentResolution":"root","applicability":{"kind":"universe_wide"},"classificationExecutable":true}),
        ),
        (
            71,
            serde_json::json!({"record_kind":"entity_type","namespace":"support","key":"other","name":"Other","labels":{},"parent":null,"parentResolution":"root","applicability":{"kind":"universe_wide"},"classificationExecutable":true}),
        ),
        (
            99,
            serde_json::json!({"record_kind":"represented_context","universe":universe,"kind":{"kind":"objective"},"labels":{}}),
        ),
        (
            10,
            serde_json::json!({"record_kind":"calendar","namespace":"support","key":"tick","labels":{},"unitStructure":{}}),
        ),
        (
            20,
            serde_json::json!({"record_kind":"world","selector":"World A","labels":{},"metadata":{}}),
        ),
        (
            21,
            serde_json::json!({"record_kind":"world","selector":"World B","labels":{},"metadata":{}}),
        ),
    ];
    for (n, value) in support {
        let id = RecordId::parse(&format!("rec_{n:024x}")).unwrap();
        if records.iter().any(|r| r.identity.record_id == id) {
            continue;
        }
        let payload: Payload = serde_json::from_value(value).unwrap();
        records.push(
            RecordVersion::build(
                RecordVersionId::parse(&format!("ver_{n:024x}")).unwrap(),
                RecordIdentity::new(universe.clone(), id, payload.kind()),
                payload,
            )
            .unwrap(),
        );
    }
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("rules.sqlite");
    let oracle = directory.path().join("original.json");
    std::fs::write(&oracle, serde_json::to_vec(&records).unwrap()).unwrap();
    let mut kernel = Kernel::create(
        &path,
        universe.clone(),
        name,
        continuity.clone(),
        &principal,
    )
    .unwrap();
    let input = CommitInput {
        universe,
        continuity: continuity.clone(),
        expected_head: kernel.head(&continuity).unwrap(),
        principal,
        decision: "capability characterization".into(),
        reason: name.into(),
        idempotency_key: "original".into(),
        changes: records
            .iter()
            .map(|r| Assignment {
                record_id: r.identity.record_id.clone(),
                expected: None,
                next: Some(r.clone()),
            })
            .collect(),
    };
    let revision = kernel
        .commit(&input)
        .unwrap_or_else(|e| panic!("{name}: {e}"));
    drop(kernel);
    let output = std::process::Command::new("python3")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../scripts/relational_history.py"
        ))
        .arg(&path)
        .arg(&oracle)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{name}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let kernel = Kernel::open(&path).unwrap();
    assert_eq!(kernel.receipt(&input).unwrap(), Some(revision.clone()));
    let restored = kernel.records(&continuity, &revision).unwrap();
    for original in &records {
        assert_eq!(
            restored
                .iter()
                .find(|r| r.record_version_id == original.record_version_id),
            Some(original),
            "{name}"
        );
    }
    restored
}

#[test]
fn cedar_capabilities_keep_original_digests_and_verdicts_after_storage() {
    let foundation: Value = serde_json::from_str(include_str!(
        "../../../fixtures/normalized-foundation/facts.json"
    ))
    .unwrap();
    let cedar: Value = serde_json::from_str(include_str!(
        "../../../fixtures/normalized-foundation/cedar-capabilities.json"
    ))
    .unwrap();
    let current: Value = serde_json::from_str(include_str!(
        "../../../fixtures/ancestor-applicability/historical-expectations.json"
    ))
    .unwrap();
    let mut original: Vec<RecordVersion> =
        serde_json::from_value(foundation["initial"].clone()).unwrap();
    original
        .extend(serde_json::from_value::<Vec<RecordVersion>>(cedar["records"].clone()).unwrap());
    assert!(original.iter().all(RecordVersion::verify_digest));
    let restored = storage_readback(original.clone(), "Cedar capabilities");
    for records in [&original, &restored] {
        let index = universe_rules::EvaluationIndex::new(records);
        for query in cedar["queries"].as_array().unwrap() {
            let target = records
                .iter()
                .find(|r| r.identity.record_id.as_str() == query["rule"].as_str().unwrap())
                .unwrap();
            assert!(crate::operations::protected(&target.payload));
            let frame: Frame = serde_json::from_value(query["frame"].clone()).unwrap();
            let worlds: Vec<RecordId> = serde_json::from_value(query["worlds"].clone()).unwrap();
            for indexed in [None, Some(&index)] {
                let got = evaluate_indexed(indexed, target, records, &frame, &worlds);
                let outcome = match got.evidence.outcome() {
                    universe_rules::EvidenceOutcome::Supported => "supported",
                    universe_rules::EvidenceOutcome::Refuted => "refuted",
                    universe_rules::EvidenceOutcome::Conflicting => "conflicting",
                    universe_rules::EvidenceOutcome::NotEstablished => "not_established",
                };
                assert_eq!(
                    serde_json::json!({"accepted":got.accepted,"complete":got.complete,"outcome":outcome}),
                    current
                        .get(query["name"].as_str().unwrap())
                        .unwrap_or(&query["expected"])
                        .clone(),
                    "{}",
                    query["name"]
                );
            }
        }
    }
    let action = restored
        .iter()
        .find(|r| r.identity.record_id.as_str() == "rec_00000000000000000000006e")
        .unwrap();
    assert!(crate::operations::protected(&action.payload));
}
