use super::*;
pub(crate) fn render(response: Value) -> String {
    let mut dom = VirtualDom::new_with_props(EffectiveState, EffectiveStateProps { response });
    dom.rebuild_to_vec()
        .edits
        .into_iter()
        .filter_map(|m| match m {
            dioxus::core::Mutation::CreateTextNode { value, .. } => Some(value),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join(" ")
}
fn id(n: u64) -> String {
    format!("rec_{n:024x}")
}
fn record(n: u64, payload: Value) -> Value {
    json!({"identity":{"record_id":id(n),"universe_id":"unv_000000000000000000000001","record_kind":payload["record_kind"]},"record_version_id":format!("ver_{n:024x}"),"payload":payload,"payload_digest":format!("digest-{n}")})
}
fn evidence(n: u64, p: u64, mode: &str) -> Value {
    json!({"record":record(n,json!({"record_kind":"assertion","attributeMode":mode,"proposition":{"record":id(p)},"polarity":"support","precision":"exact","validity":{"kind":"calendar_interval","calendar":"cal_000000000000000000000001","start":{"kind":"exact","value":"0"},"end":{"kind":"unbounded"}}})),"applicability":true,"unknowns":[]})
}
fn fixture() -> Value {
    let dependencies = vec![
        record(
            20,
            json!({"record_kind":"property","labels":{"en":"Capacity"}}),
        ),
        record(
            21,
            json!({"record_kind":"property","labels":{"en":"Rounds"}}),
        ),
        record(
            30,
            json!({"record_kind":"proposition","predicate":{"record":id(20)},"value":{"kind":"integer","digits":"50"}}),
        ),
        record(
            31,
            json!({"record_kind":"proposition","predicate":{"record":id(21)},"value":{"kind":"integer","digits":"2"}}),
        ),
        record(
            32,
            json!({"record_kind":"proposition","predicate":{"record":id(21)},"value":{"kind":"integer","digits":"7"}}),
        ),
    ];
    json!({"frame":{"revision":"queried-revision","context":{"record":"queried-context"},"time":{"kind":"at","time":{"kind":"exact","calendar":"queried-calendar","value":"17"}},"perspective":"author"},"world_focus":"queried-world","authorization_scope":"universe grant","delivery":{"complete":true},"result":{"coverage":"partial","objects":[{
        "identity":record(1,json!({"record_kind":"entity","labels":{"en":"Courier"},"classification":id(9),"classificationResolution":"resolved"})),"ancestry":[record(9,json!({"record_kind":"entity_type","labels":{"en":"Courier definition"}}))],"ancestry_complete":true,
        "shared_attributes":[evidence(40,30,"shared")],"instance_facts":[evidence(41,31,"instance")],"initial_value_candidates":[evidence(42,32,"initial_value")],"dependencies":dependencies,
        "initialization_history_coverage":"complete","initialization_receipts":[{"property":id(21),"revision":"init-revision","definition":"exact-definition-version","assertion":"exact-initialized-assertion","source_revision":"source-revision","instance":id(1),"start":id(10)}],
        "behavioral_requirements":[{"record":record(51,json!({"record_kind":"action_definition","labels":{"en":"Spend a round"},"requirements":[{"role":"actor","predicate":{"record":id(21)}}]})),"applicability":true,"unknowns":[]}],
        "rules":[{"record":record(50,json!({"record_kind":"rule","labels":{"en":"Authored stock policy"},"kind":"physical_constraint","commitPolicy":"always_block"})),"applicability":null,"unknowns":["world_applicability"]}],
        "conflicts":[{"predicate":id(21),"applicability":null,"assertions":["exact-conflicting-version"],"initial_values":true}],"unknowns":["resource_arrival_unexplained:exact-fingerprint"],"coverage":"partial"
    }],"unsupported_capabilities":["scope remains partial"],"derived":[],"epistemic":[],"assertions":[],"propositions":[],"completeness":[],"unresolved_assertion_ids":[]}})
}
#[test]
fn state_sections_keep_definitions_stock_candidates_and_provenance_separate() {
    let s = render(fixture());
    for text in [
        "queried-revision",
        "queried-context",
        "queried-world",
        "17 in calendar queried-calendar",
        "Partial",
        "Courier",
        "Resolved",
        "Courier definition",
        "Shared definition attributes",
        "Instance facts",
        "Initial-value candidates",
        "Declared value: 50",
        "Declared value: 2",
        "Declared value: 7",
        "Initialized Rounds in revision init-revision",
        "source-revision",
        "exact-definition-version",
        "Spend a round",
        "Role actor requires Rounds",
        "Authored stock policy",
        "Applicability unresolved",
        "Initial candidates",
        "exact-conflicting-version",
        "Resource arrival unexplained",
        "exact-fingerprint",
    ] {
        assert!(s.contains(text), "Missing {text}: {s}");
    }
    let response = fixture();
    let object = &response["result"]["objects"][0];
    for (lane, expected, others) in [
        (
            "shared_attributes",
            "Declared value: 50",
            ["Declared value: 2", "Declared value: 7"],
        ),
        (
            "instance_facts",
            "Declared value: 2",
            ["Declared value: 50", "Declared value: 7"],
        ),
        (
            "initial_value_candidates",
            "Declared value: 7",
            ["Declared value: 50", "Declared value: 2"],
        ),
    ] {
        let mut dom = VirtualDom::new_with_props(
            EvidenceLane,
            EvidenceLaneProps {
                title: lane.into(),
                note: String::new(),
                rows: object[lane].clone(),
                object: object.clone(),
            },
        );
        let rendered = dom
            .rebuild_to_vec()
            .edits
            .into_iter()
            .filter_map(|m| match m {
                dioxus::core::Mutation::CreateTextNode { value, .. } => Some(value),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join(" ");
        assert!(rendered.contains(expected));
        for other in others {
            assert!(!rendered.contains(other));
        }
    }
}
#[test]
fn restricted_state_objects_and_initialization_history_do_not_render_attached_private_data() {
    let mut response = fixture();
    response["result"]["objects"][0]["initialization_history_coverage"] = json!("restricted");
    response["result"]["objects"][0]["initialization_receipts"][0]["assertion"] =
        json!("concealed-receipt");
    let s = render(response.clone());
    assert!(!s.contains("concealed-receipt"));
    assert!(!s.contains("source-revision"));
    assert!(s.contains("Declared value: 2"));
    response["result"]["objects"][0]["coverage"] = json!("restricted");
    assert!(!render(response.clone()).contains("Courier"));
    response["result"]["coverage"] = json!("restricted");
    response["result"]["propositions"] = json!(["concealed-proposition"]);
    let s = render(response);
    assert!(!s.contains("concealed-proposition"));
    assert!(!s.contains("Authored stock policy"));
}
#[test]
fn missing_and_qualified_evidence_stays_unresolved_without_selecting_values() {
    let mut response = fixture();
    response["result"]["objects"][0]["dependencies"] = json!([]);
    response["result"]["objects"][0]["ancestry_complete"] = json!(false);
    response["result"]["objects"][0]["instance_facts"][0]["applicability"] = Value::Null;
    let s = render(response);
    assert!(s.contains("Record Not reported"));
    assert!(s.contains("Ancestry complete: No"));
    assert!(s.contains("Applicability unresolved"));
    assert!(!s.contains("Declared value: 2"));
    assert_eq!(
        value_text(&json!({"kind":"integer","digits":"0"}), &Value::Null),
        "0"
    );
    assert_eq!(
        value_text(&json!({"kind":"boolean","value":false}), &Value::Null),
        "False"
    );
    assert_eq!(
        value_text(&json!({"kind":"decimal","digits":"3.0010"}), &Value::Null),
        "3.0010"
    );
    assert_eq!(
        value_text(
            &json!({"kind":"range","lower":{"kind":"integer","digits":"0"},"upper":{"kind":"integer","digits":"5"},"lower_inclusive":true,"upper_inclusive":false}),
            &Value::Null
        ),
        "[0 to 5)"
    );
}

#[test]
fn quantity_labels_use_only_returned_units_and_preserve_exact_amounts() {
    let object = json!({"dependencies":[{"identity":{"record_id":"rec_000000000000000000000017"},"payload":{"record_kind":"unit","key":"authored metres","symbol":"m"}}]});
    let value = json!({"kind":"quantity","value":{"kind":"decimal","digits":"1.2300"},"unit":"unit_000000000000000000000017"});
    assert_eq!(value_text(&value, &object), "1.2300 authored metres");
    assert_eq!(
        value_text(&value, &Value::Null),
        "1.2300 unit_000000000000000000000017"
    );
}

#[test]
fn derived_values_are_named_separate_and_restricted() {
    let mut response = fixture();
    response["result"]["derived"] = json!([{"subject":{"record":id(1)},"predicate":{"record":id(21)},"value":{"kind":"integer","digits":"3"},"evidence":["derived-evidence"],"rule":id(50)}]);
    let rendered = render(response.clone());
    assert!(rendered.contains("Derived Rounds: 3"));
    assert!(rendered.contains("Declared value: 2"));
    assert!(rendered.contains("Partial") && rendered.contains("Resource arrival unexplained"));
    assert!(rendered.contains("derived-evidence"));
    response["result"]["coverage"] = json!("restricted");
    let restricted = render(response);
    assert!(!restricted.contains("Derived Rounds: 3"));
    assert!(!restricted.contains("derived-evidence"));
}
