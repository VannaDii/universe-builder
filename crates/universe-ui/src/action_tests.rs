use super::*;
use crate::identity_editor::workflow::{connect, open, publish, read, tool};
use tokio_util::sync::CancellationToken;
use universe_protocol::{
    installation::*,
    request::{ProposalRef, Selector},
};
use universe_service::runtime;
fn id(n: u64) -> String {
    format!("rec_{n:024x}")
}
fn frame() -> Frame {
    serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":id(9)},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
}
fn choices() -> Vec<Value> {
    vec![
        json!({"kind":"property","record_id":id(1),"label":"Rounds","definition":{"value":{"kind":"integer"},"multiplicity":"single"}}),
        json!({"kind":"property","record_id":id(2),"label":"Charge","definition":{"value":{"kind":"quantity","unit":"unit_000000000000000000000004"},"multiplicity":"single"}}),
        json!({"kind":"property","record_id":id(3),"label":"Enabled","definition":{"value":{"kind":"boolean"},"multiplicity":"single"}}),
        json!({"kind":"unit","record_id":id(4),"label":"Charge units"}),
    ]
}
fn delta(role: &str, prop: u64, amount: &str, order: &str) -> SlotForm {
    SlotForm {
        slot: format!("stock-{role}"),
        order: order.into(),
        presence: "required".into(),
        role: role.into(),
        predicate: id(prop),
        condition: "always".into(),
        change: "delta".into(),
        delta: amount.into(),
        minimum: "0".into(),
        maximum: "10".into(),
        unit: if prop == 2 {
            "unit_000000000000000000000004".into()
        } else {
            "none".into()
        },
        lifetime: "until_changed".into(),
        ..Default::default()
    }
}
fn action(key: &str, slots: Vec<SlotForm>) -> ActionForm {
    ActionForm {
        namespace: "actions".into(),
        key: key.into(),
        mode: "ordinary".into(),
        consequences: if slots.is_empty() {
            "none".into()
        } else {
            "declared".into()
        },
        slots,
        ..Default::default()
    }
}
#[test]
fn contracts_preserve_presence_conditions_values_lifetimes_and_exact_units() {
    let f = frame();
    let c = choices();
    let mut a = action("consume", vec![delta("actor", 1, "-1", "0")]);
    let op = a.build(&f, &c).unwrap();
    assert_eq!(
        op["record"]["consequenceContract"]["slots"][0]["change"]["unit"],
        Value::Null
    );
    a.slots[0] = delta("source", 2, "-2", "0");
    a.slots.push(delta("recipient", 2, "2", "1"));
    let op = a.build(&f, &c).unwrap();
    assert_eq!(
        op["record"]["consequenceContract"]["slots"][1]["change"]["unit"],
        "unit_000000000000000000000004"
    );
    let s = &mut a.slots[1];
    s.presence = "optional".into();
    s.condition = "attribute_equals".into();
    s.condition_role = "recipient".into();
    s.condition_property = id(3);
    s.condition_value = FixedValue {
        source: "literal".into(),
        value: "false".into(),
        ..Default::default()
    };
    s.change = "set".into();
    s.predicate = id(3);
    s.polarity = "refutation".into();
    s.value = FixedValue {
        source: "literal".into(),
        value: "true".into(),
        ..Default::default()
    };
    s.lifetime = "ticks".into();
    s.ticks = "5".into();
    let slot = &a.build(&f, &c).unwrap()["record"]["consequenceContract"]["slots"][1];
    assert_eq!(slot["presence"], "optional");
    assert_eq!(slot["condition"]["value"]["value"], false);
    assert_eq!(slot["change"]["polarity"], "refutation");
    assert_eq!(slot["lifetime"]["count"], "5");
    let ordinary = action("walk", vec![]).build(&f, &c).unwrap();
    assert_eq!(
        ordinary["record"]["consequenceContract"]["slots"],
        json!([])
    );
    assert_eq!(ordinary["record"]["requirements"], json!([]));
}
#[test]
fn fixed_values_preserve_precision_units_and_explicit_proposition_selection() {
    let f = frame();
    let mut c = choices();
    let v = FixedValue {
        source: "literal".into(),
        value: "3.0010".into(),
        ..Default::default()
    };
    let value = v.build(&f, &c, &id(2)).unwrap();
    assert_eq!(value["value"]["digits"], "3.0010");
    assert_eq!(value["unit"], "unit_000000000000000000000004");
    c.push(json!({"kind":"property","record_id":id(20),"label":"Sequence","definition":{"value":{"kind":"sequence","item":{"kind":"integer"}},"multiplicity":"single"}}));
    let exact = json!({"kind":"sequence","items":[{"kind":"integer","digits":"9007199254740993"},{"kind":"integer","digits":"0"}]});
    c.push(json!({"kind":"proposition","record_id":id(21),"label":"Exact sequence","definition":{"predicate":{"universe":f.universe,"record":id(20)},"value":exact}}));
    let mut v = FixedValue {
        source: "proposition".into(),
        value: id(21),
        ..Default::default()
    };
    assert_eq!(v.build(&f, &c, &id(20)).unwrap(), exact);
    assert!(v.build(&f, &c, &id(1)).is_err());
    v.source.clear();
    assert!(v.build(&f, &c, &id(20)).is_err());
}
#[test]
fn malformed_contracts_and_blank_choices_are_rejected() {
    let f = frame();
    let c = choices();
    for amount in [
        "",
        "0",
        "01",
        "-0",
        "1.5",
        "170141183460469231731687303715884105728",
    ] {
        assert!(action("bad", vec![delta("actor", 1, amount, "0")])
            .build(&f, &c)
            .is_err());
    }
    let good = delta("actor", 1, "-1", "0");
    for field in [
        "presence",
        "condition",
        "change",
        "lifetime",
        "unit",
        "role",
        "slot",
        "order",
    ] {
        let mut s = good.clone();
        match field {
            "presence" => s.presence.clear(),
            "condition" => s.condition.clear(),
            "change" => s.change.clear(),
            "lifetime" => s.lifetime.clear(),
            "unit" => s.unit.clear(),
            "role" => s.role.clear(),
            "slot" => s.slot.clear(),
            _ => s.order = "64".into(),
        };
        assert!(action("bad", vec![s]).build(&f, &c).is_err(), "{field}");
    }
    let mut a = action("bad", vec![good.clone(), good.clone()]);
    assert!(a.build(&f, &c).is_err());
    a.slots.pop();
    a.slots[0].minimum = "11".into();
    assert!(a.build(&f, &c).is_err());
    a.slots[0] = good.clone();
    a.slots[0].lifetime = "ticks".into();
    a.slots[0].ticks = "1".into();
    assert!(a.build(&f, &c).is_err());
    a.slots[0] = delta("actor", 2, "1", "0");
    a.slots[0].unit = "unit_000000000000000000000005".into();
    assert!(a.build(&f, &c).is_err());
    let mut a = action("walk", vec![]);
    a.consequences.clear();
    assert!(a.build(&f, &c).is_err());
}
#[test]
fn consequence_controls_mount_for_delta_and_fixed_conditions() {
    fn fixture() -> Element {
        let mut s = delta("actor", 1, "-1", "0");
        s.condition = "attribute_equals".into();
        s.condition_property = id(3);
        s.condition_value.source = "literal".into();
        rsx! {ActionEditor{frame:frame(),choices:choices(),disabled:false,onadd:move |_|{}}SlotControls{id:"test-slot",slot:s,choices:choices(),disabled:false,onchange:move |_|{}}}
    }
    let mut dom = VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn definitions_recover_require_approval_publish_and_drive_a_consuming_event() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Days".into(),
                initial_tick: "0".into(),
                tick_label: "days".into(),
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let opened = open(&mut c, &u).await;
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let prop = |n, key, shape| json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"actions","key":key,"labels":{},"subjectTypes":[],"value":shape,"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}});
    publish(&mut c,&opened,json!([prop(1,"rounds",json!({"kind":"integer"})),{"kind":"define_unit","client_ref":id(4),"record":{"namespace":"actions","key":"charge-unit","labels":{},"dimension":"charge","symbol":"q","base":null,"validity":{"kind":"unspecified"}}},prop(2,"charge",json!({"kind":"quantity","unit":"unit_000000000000000000000004"})),prop(3,"enabled",json!({"kind":"boolean"})),{"kind":"create_entity","client_ref":id(5),"record":{"names":[],"classificationResolution":"unclassified","worldAssociations":[],"labels":{},"metadata":{}}}]),"seed-actions").await;
    let opened = open(&mut c, &u).await;
    let f: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    let consume = action("consume", vec![delta("actor", 1, "-1", "0")])
        .build(&f, &choices())
        .unwrap();
    let refill = action("refill", vec![delta("actor", 1, "3", "0")])
        .build(&f, &choices())
        .unwrap();
    let transfer = action(
        "transfer",
        vec![
            delta("source", 2, "-2", "0"),
            delta("recipient", 2, "2", "1"),
        ],
    )
    .build(&f, &choices())
    .unwrap();
    let ordinary = action("walk", vec![]).build(&f, &choices()).unwrap();
    let conditional_slot = SlotForm {
        slot: "enable".into(),
        order: "0".into(),
        presence: "optional".into(),
        role: "actor".into(),
        predicate: id(3),
        condition: "attribute_equals".into(),
        condition_role: "actor".into(),
        condition_property: id(3),
        condition_value: FixedValue {
            source: "literal".into(),
            value: "false".into(),
            ..Default::default()
        },
        change: "set".into(),
        polarity: "support".into(),
        value: FixedValue {
            source: "literal".into(),
            value: "true".into(),
            ..Default::default()
        },
        lifetime: "ticks".into(),
        ticks: "5".into(),
        ..Default::default()
    };
    let conditional = action("enable", vec![conditional_slot])
        .build(&f, &choices())
        .unwrap();
    let ops = json!([consume, refill, transfer, ordinary, conditional]);
    c.call(EngineRequest::SaveDraft {
        universe: Selector("Alpha".into()),
        continuity_id: f.continuity.clone(),
        expected_version: 0,
        content: DraftContent {
            proposal: None,
            base_revision: f.revision.clone(),
            represented_context: f.context.record.clone(),
            operations: serde_json::from_value(ops.clone()).unwrap(),
            rationale: "Authored action consequences".into(),
        },
    })
    .await
    .unwrap();
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let recovered = c
        .call(EngineRequest::LoadDraft {
            universe: Selector("Alpha".into()),
            continuity_id: f.continuity.clone(),
        })
        .await
        .unwrap();
    assert_eq!(recovered["content"]["operations"], ops);
    let opened = open(&mut c, &u).await;
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":ops,"submission":"submitted","rationale":"Authored action consequences","idempotency_key":"native-actions"})).await["result"].clone();
    let reference: ProposalRef = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let review = c
        .call(EngineRequest::Review {
            universe: Selector("Alpha".into()),
            proposal_reference: reference.clone(),
        })
        .await
        .unwrap();
    assert!(review.to_string().contains("consequenceContract"));
    let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"]["execution"].clone();
    assert_eq!(v["coverage"], "complete");
    let commit=crate::author::tool("universe_commit",json!({"universe":"Alpha","proposal_reference":reference,"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["run_id"],"idempotency_key":"native-actions-commit"})).unwrap();
    assert!(c.call(commit.clone()).await.is_err());
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference,
        validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    c.call(commit).await.unwrap();
    let opened = open(&mut c, &u).await;
    for op in ops.as_array().unwrap() {
        assert_eq!(
            read(&mut c, &opened, &op["client_ref"]).await["payload"]["consequenceContract"],
            op["record"]["consequenceContract"]
        );
    }
    let f: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    // Candidate validation must still reject malformed definitions supplied outside the controls.
    let mut bad = consume.clone();
    bad["client_ref"] = json!(id(99));
    bad["record"]["key"] = json!("wrong-shape");
    bad["record"]["consequenceContract"]["slots"][0]["change"] =
        json!({"kind":"set","polarity":"support","value":{"kind":"boolean","value":true}});
    let request = crate::author::tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[bad],"submission":"submitted","rationale":"Invalid assignment type","idempotency_key":"bad-action-shape"})).unwrap();
    let bad_proposal = c.call(request).await.unwrap()["result"].clone();
    let bad_ref = json!({"proposal_id":bad_proposal["proposal_id"],"version":bad_proposal["version"],"digest":bad_proposal["digest"]});
    let request=crate::author::tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":bad_ref,"check_scope":"universe"})).unwrap();
    let error = c.call(request).await.unwrap_err().to_string();
    assert!(
        error.contains("consequence set value does not conform"),
        "{error}"
    );
    let mut bad = consume.clone();
    bad["record"]["consequenceContract"]["slots"][0]["change"]
        .as_object_mut()
        .unwrap()
        .remove("unit");
    assert!(crate::author::tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[bad],"submission":"submitted","rationale":"Missing explicit delta unit","idempotency_key":"bad-action-unit"})).is_err());
    let clock =
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"]["calendar"].clone();
    let scope = json!({"context":f.context,"applicability":{"kind":"universe_wide"}});
    let proposition = |n, digits| json!({"kind":"define_proposition","client_ref":id(n),"record":{"subject":rr(5),"predicate":rr(1),"value":{"kind":"integer","digits":digits},"context":f.context,"quantification":"particular"}});
    let validity = |start, end| json!({"kind":"calendar_interval","calendar":clock,"start":{"kind":"exact","value":start},"end":end});
    publish(&mut c,&opened,json!([{"kind":"assert_proposition","client_ref":id(7),"proposition":proposition(6,"3")["record"],"assertion":{"attributeMode":"instance","proposition":rr(7),"polarity":"support","scope":scope,"validity":validity("0",json!({"kind":"exact","value":"1"})),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Initial stock"}}}]),"initial-stock").await;
    let opened = open(&mut c, &u).await;
    publish(&mut c,&opened,json!([proposition(8,"2"),{"kind":"record_event","client_ref":id(9),"record":{"occurrence":"occurred","action":{"universe":f.universe,"record":consume["client_ref"]},"time":{"kind":"exact","calendar":clock,"value":"1"},"worlds":[],"participants":[{"record":rr(5),"role":"actor"}],"effects":[{"slot":"stock-actor","order":0,"proposition":rr(8),"polarity":"support","scope":scope,"validity":validity("1",json!({"kind":"unbounded"}))}],"labels":{}}}]),"consume-event").await;
    let opened = open(&mut c, &u).await;
    assert_eq!(
        read(&mut c, &opened, &json!(id(9))).await["payload"]["effects"][0]["slot"],
        "stock-actor"
    );
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
