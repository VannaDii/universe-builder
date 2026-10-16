use serde_json::{json, Value};
use universe_domain::{canonical::PayloadDigest, canonical_json, payload_digest, records::Payload};
use universe_protocol::wire::decode;
fn source_fixtures() -> Vec<Value> {
    serde_json::from_str(include_str!(
        "../../../fixtures/action-consequences/payload-digests.json"
    ))
    .unwrap()
}
fn fixtures() -> Vec<Value> {
    serde_json::from_str(include_str!(
        "../../../fixtures/normalized-foundation/historical-digests.json"
    ))
    .unwrap()
}
fn fire() -> Value {
    fixtures()[3]["payload"].clone()
}
fn rejects(payload: Value) {
    assert!(
        decode::<Payload>(&serde_json::to_vec(&payload).unwrap()).is_err(),
        "accepted {payload}"
    );
}
#[test]
fn independently_authored_payloads_round_trip_with_frozen_bytes_and_digests() {
    let normative: Vec<Value> = serde_json::from_str(include_str!(
        "../../../fixtures/normalized-foundation/historical-digests.json"
    ))
    .unwrap();
    for fixture in fixtures() {
        let expected = normative
            .iter()
            .find(|r| r["name"] == fixture["name"])
            .unwrap();
        let payload: Payload = decode(&serde_json::to_vec(&fixture["payload"]).unwrap()).unwrap();
        assert_eq!(
            String::from_utf8(canonical_json(&payload)).unwrap(),
            expected["canonical_utf8"]
        );
        assert_eq!(
            payload_digest(&payload.kind(), &payload).as_str(),
            expected["normative_digest"]
        );
        // Original published vectors remain unchanged and independently checked.
        let source = source_fixtures()
            .into_iter()
            .find(|r| r["name"] == fixture["name"])
            .unwrap();
        assert_eq!(
            PayloadDigest::compute(
                &format!("{}:v1:v1", payload.kind().as_str()),
                &universe_domain::canonical::canonical_json_value(&source["payload"])
            )
            .as_str(),
            source["digest"]
        );
        assert_eq!(
            String::from_utf8(
                universe_domain::canonical::canonical_json_value(&source["payload"]).to_bytes()
            )
            .unwrap(),
            source["canonical_utf8"]
        );
        assert_eq!(expected["source_digest"], source["digest"]);
        let decoded: Payload = decode(&canonical_json(&payload)).unwrap();
        assert_eq!(payload, decoded);
        assert_eq!(
            payload_digest(&decoded.kind(), &decoded).as_str(),
            expected["normative_digest"]
        );
    }
}
#[test]
fn absence_empty_and_null_keep_distinct_meanings() {
    let without_contract: Payload = decode(&serde_json::to_vec(&fixtures()[0]["payload"]).unwrap()).unwrap();
    let Payload::ActionDefinition(action) = without_contract else {
        panic!()
    };
    assert!(action.consequence_contract.is_none());
    let Payload::ActionDefinition(action) =
        decode(&serde_json::to_vec(&fixtures()[2]["payload"]).unwrap()).unwrap()
    else {
        panic!()
    };
    assert!(action.consequence_contract.unwrap().slots.is_empty());
    let mut null = fire();
    null["consequenceContract"] = Value::Null;
    rejects(null);
}
#[test]
fn unsupported_missing_and_unknown_shapes_fail_closed() {
    for (path, value) in [
        ("/consequenceContract/kind", json!("action_consequences_v1")),
        ("/consequenceContract/kind", json!("action_consequences_v2")),
        ("/consequenceContract/slots/0/presence", json!("permitted")),
        (
            "/consequenceContract/slots/0/change/kind",
            json!("expression"),
        ),
        (
            "/consequenceContract/slots/0/condition/kind",
            json!("guess"),
        ),
        (
            "/consequenceContract/slots/0/lifetime/kind",
            json!("forever"),
        ),
        (
            "/consequenceContract/slots/0/target/predicate/record",
            json!("bad"),
        ),
    ] {
        let mut bad = fire();
        *bad.pointer_mut(path).unwrap() = value;
        rejects(bad);
    }
    for index in [3, 5] {
        for path in [
            "/consequenceContract",
            "/consequenceContract/slots/0",
            "/consequenceContract/slots/0/target",
            "/consequenceContract/slots/0/condition",
            "/consequenceContract/slots/0/change",
            "/consequenceContract/slots/0/lifetime",
        ] {
            let original = fixtures()[index]["payload"].clone();
            for key in original.pointer(path).unwrap().as_object().unwrap().keys() {
                let mut bad = original.clone();
                bad.pointer_mut(path)
                    .unwrap()
                    .as_object_mut()
                    .unwrap()
                    .remove(key);
                rejects(bad);
            }
            let mut bad = original;
            bad.pointer_mut(path).unwrap()["unsupported"] = json!(true);
            rejects(bad);
        }
    }
}
#[test]
fn invalid_numbers_bounds_names_and_duplicates_fail() {
    for number in [
        "-0",
        "+1",
        "01",
        " 1",
        "1e2",
        "",
        "170141183460469231731687303715884105728",
        "-170141183460469231731687303715884105729",
        "0",
    ] {
        let mut bad = fire();
        bad["consequenceContract"]["slots"][0]["change"]["delta"] = json!(number);
        rejects(bad);
    }
    for (path, value) in [
        ("/consequenceContract/slots/0/change/delta", json!(1)),
        ("/consequenceContract/slots/0/change/minimum", json!(13)),
        ("/consequenceContract/slots/0/change/minimum", json!("13")),
        ("/consequenceContract/slots/0/order", json!(64)),
        ("/consequenceContract/slots/0/order", json!(-1)),
        ("/consequenceContract/slots/0/order", json!(1.5)),
        ("/consequenceContract/slots/0/slot", json!(" ")),
        (
            "/consequenceContract/slots/0/target/role",
            json!("x".repeat(121)),
        ),
        ("/consequenceContract/slots/0/slot", json!("é".repeat(61))),
        (
            "/consequenceContract/slots/0/lifetime",
            json!({"kind":"ticks","count":"5"}),
        ),
    ] {
        let mut bad = fire();
        *bad.pointer_mut(path).unwrap() = value;
        rejects(bad);
    }
    let slot = fire()["consequenceContract"]["slots"][0].clone();
    for count in [2, 65] {
        let mut bad = fire();
        bad["consequenceContract"]["slots"] = json!(vec![slot.clone(); count]);
        rejects(bad);
    }
    for field in ["slot", "order", "target"] {
        let mut other = slot.clone();
        other["slot"] = json!("other");
        other["order"] = json!(1);
        other["target"]["role"] = json!("other");
        other[field] = slot[field].clone();
        let mut bad = fire();
        bad["consequenceContract"]["slots"] = json!([slot, other]);
        rejects(bad);
    }
    for count in ["0", "-1"] {
        let mut bad = fixtures()[5]["payload"].clone();
        bad["consequenceContract"]["slots"][0]["lifetime"]["count"] = json!(count);
        rejects(bad);
    }
}
#[test]
fn duplicate_wire_keys_and_escaped_aliases_are_rejected() {
    let bytes = serde_json::to_string(&fire()).unwrap();
    for replacement in [
        r#""kind":"delta","kind":"delta""#,
        r#""kind":"delta","\u006bind":"delta""#,
    ] {
        let bad = bytes.replace(r#""kind":"delta""#, replacement);
        assert_ne!(bad, bytes);
        assert!(decode::<Payload>(bad.as_bytes()).is_err());
    }
}
#[test]
fn supported_extreme_numbers_and_maximum_slots_round_trip() {
    let mut payload = fire();
    let mut slot = payload["consequenceContract"]["slots"][0].clone();
    slot["change"]["minimum"] = json!(i128::MIN.to_string());
    slot["change"]["maximum"] = json!(i128::MAX.to_string());
    slot["change"]["delta"] = json!(i128::MIN.to_string());
    let slots: Vec<_> = (0..64)
        .map(|n| {
            let mut s = slot.clone();
            s["slot"] = json!(format!("s{n}"));
            s["order"] = json!(n);
            s["target"]["role"] = json!(format!("r{n}"));
            s
        })
        .collect();
    payload["consequenceContract"]["slots"] = json!(slots);
    let decoded: Payload = decode(&serde_json::to_vec(&payload).unwrap()).unwrap();
    assert_eq!(serde_json::to_value(decoded).unwrap(), payload);
}

#[test]
fn fractional_contract_digits_are_exact_and_tick_counts_remain_integer() {
    let mut payload = fire();
    payload["consequenceContract"]["slots"][0]["change"]["delta"] = json!("-0.125000000000000001");
    payload["consequenceContract"]["slots"][0]["change"]["minimum"] = json!("0.000000000000000001");
    let parsed: universe_domain::Payload = serde_json::from_value(payload.clone()).unwrap();
    assert_eq!(serde_json::to_value(parsed).unwrap(), payload);
    payload["consequenceContract"]["slots"][0]["lifetime"] = json!({"kind":"ticks","count":"0.1"});
    rejects(payload);
}
