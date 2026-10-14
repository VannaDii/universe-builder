use serde_json::json;
use universe_domain::records::{EvidenceReviewMethod, RequiredEvidence, Rule};

fn ordinary() -> serde_json::Value {
    json!({"namespace":"real_world","key":"history","labels":{},"kind":"authorial_restriction","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[],"executable":true,"validity":{"kind":"unspecified"}})
}
#[test]
fn optional_review_and_exact_source_category_round_trip() {
    let source = json!({"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000002","version":"ver_000000000000000000000003"});
    for methods in [
        vec![],
        vec![
            EvidenceReviewMethod::HumanReview,
            EvidenceReviewMethod::ExternalModelReview,
        ],
    ] {
        let policy = RequiredEvidence {
            source_categories: vec![serde_json::from_value(source.clone()).unwrap()],
            review_methods: methods.clone(),
        };
        let mut value = ordinary();
        value["requiredEvidence"] = serde_json::to_value(&policy).unwrap();
        let rule: Rule = serde_json::from_value(value.clone()).unwrap();
        assert_eq!(serde_json::to_value(rule).unwrap(), value);
        assert_eq!(
            serde_json::to_value(&policy.source_categories[0]).unwrap(),
            source
        );
        assert_eq!(policy.review_methods, methods);
    }
}
#[test]
fn ordinary_rules_do_not_receive_a_default_policy() {
    let value = ordinary();
    let rule: Rule = serde_json::from_value(value.clone()).unwrap();
    assert_eq!(serde_json::to_value(rule).unwrap(), value);
    assert!(serde_json::from_value::<RequiredEvidence>(
        json!({"sourceCategories":[],"reviewMethods":["automatically_true"]})
    )
    .is_err());
    assert!(serde_json::from_value::<RequiredEvidence>(
        json!({"sourceCategories":[],"realityVerified":true})
    )
    .is_err());
}
