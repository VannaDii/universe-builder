//! Capability characterization only. Known gaps are asserted, never patched here.
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
