use super::*;
use crate::identity_editor::workflow::{connect, open, publish, read, tool};
use tokio_util::sync::CancellationToken;
use universe_protocol::installation::*;
use universe_service::runtime;
fn frame() -> Frame {
    serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
}
fn clock() -> Chronology {
    universe_domain::chronology::UniverseStart::Fictional {
        calendar_name: "Days".into(),
        initial_tick: "0".into(),
        tick_label: "days".into(),
        ticks_per_month: None,
    }
    .build(universe_domain::ids::CalendarId::parse("cal_000000000000000000000001").unwrap())
    .unwrap()
    .0
}
fn choices() -> Vec<Value> {
    vec![
        json!({"kind":"relation","record_id":"rec_000000000000000000000002","definition":{"roles":[{"name":"office"},{"name":"successor"}]}}),
        json!({"kind":"world","record_id":"rec_000000000000000000000003"}),
        json!({"kind":"realm","record_id":"rec_000000000000000000000004"}),
    ]
}
fn base() -> Form {
    Form {
        namespace: "factual".into(),
        key: "policy".into(),
        context: frame().context.record.to_string(),
        ..Default::default()
    }
}
#[test]
fn factual_forms_match_the_supported_contracts_and_reject_invalid_fields() {
    let mut f = base();
    f.channel = "radio".into();
    f.order = "forward".into();
    f.minimum = "0".into();
    f.maximum_delay = "10".into();
    let op = f.build("chronology", &frame(), None, &choices()).unwrap();
    assert_eq!(
        op["record"]["channelChronology"],
        json!({"channel":"radio","forwardOnly":true,"minimumDelay":"0","maximumDelay":"10"})
    );
    assert_eq!(op["record"]["commitPolicy"], "always_block");
    assert_eq!(
        op["record"]["expression"],
        json!({"kind":"lit","value":true})
    );
    f.maximum_delay = "-1".into();
    assert!(f.build("chronology", &frame(), None, &choices()).is_err());
    f.order = "signed".into();
    f.minimum = "-5".into();
    assert!(f.build("chronology", &frame(), None, &choices()).is_ok());
    f.minimum = "5".into();
    assert!(f.build("chronology", &frame(), None, &choices()).is_err());
    f.minimum = "".into();
    f.maximum_delay = "".into();
    let op = f.build("chronology", &frame(), None, &choices()).unwrap();
    assert!(op["record"]["channelChronology"]
        .get("minimumDelay")
        .is_none());
    f.minimum = "1.5".into();
    assert!(f.build("chronology", &frame(), None, &choices()).is_err());
    f.knowledge = "justified".into();
    let op = f.build("knowledge", &frame(), None, &choices()).unwrap();
    assert_eq!(op["record"]["knowledgePolicy"]["mode"], "justified");
    assert!(op["record"].get("channelChronology").is_none());
    f.knowledge = "author_established".into();
    assert!(f.build("knowledge", &frame(), None, &choices()).is_ok());
    f.knowledge = "observation".into();
    assert!(f.build("knowledge", &frame(), None, &choices()).is_err());
    f.knowledge = "justified".into();
    f.context = "".into();
    assert!(f.build("knowledge", &frame(), None, &choices()).is_err());
    f.context = frame().context.record.to_string();
    f.relation = "rec_000000000000000000000002".into();
    f.grouping = "role".into();
    f.group_role = "office".into();
    f.counted_role = "successor".into();
    f.maximum = "2".into();
    f.applicability = "worlds".into();
    f.worlds = vec!["wld_000000000000000000000003".into()];
    f.realm = "rec_000000000000000000000004".into();
    f.validity = "interval".into();
    f.start = "1".into();
    f.end = "10".into();
    let op = f
        .build("cardinality", &frame(), Some(&clock()), &choices())
        .unwrap();
    let c = &op["record"]["relationCardinality"];
    assert_eq!(c["maximum"], 2);
    assert_eq!(c["grouping"], json!({"kind":"role","role":"office"}));
    assert_eq!(c["scope"]["applicability"]["world_ids"], json!(f.worlds));
    assert_eq!(c["scope"]["realm"]["record"], f.realm);
    assert_eq!(c["validity"]["end"]["value"], "10");
    assert_eq!(op["record"]["validity"]["kind"], "unspecified");
    assert_eq!(op["record"]["applicability"]["kind"], "universe_wide");
    f.grouping = "subject".into();
    f.validity = "instant".into();
    f.maximum = "0".into();
    assert_eq!(
        f.build("cardinality", &frame(), Some(&clock()), &choices())
            .unwrap()["record"]["relationCardinality"]["grouping"]["kind"],
        "subject"
    );
    f.maximum = "4294967296".into();
    assert!(f
        .build("cardinality", &frame(), Some(&clock()), &choices())
        .is_err());
    f.maximum = "-1".into();
    assert!(f
        .build("cardinality", &frame(), Some(&clock()), &choices())
        .is_err());
    f.maximum = "2".into();
    f.counted_role = "invented".into();
    assert!(f
        .build("cardinality", &frame(), Some(&clock()), &choices())
        .is_err());
    f.counted_role = "successor".into();
    f.worlds.clear();
    assert!(f
        .build("cardinality", &frame(), Some(&clock()), &choices())
        .is_err());
    f.applicability = "universe_wide".into();
    f.validity = "interval".into();
    f.end = f.start.clone();
    assert!(f
        .build("cardinality", &frame(), Some(&clock()), &choices())
        .is_err());
    f.validity = "unspecified".into();
    assert!(f.build("cardinality", &frame(), None, &choices()).is_ok());
    assert!(base()
        .build("chronology", &frame(), None, &choices())
        .is_err());
}
#[test]
fn factual_control_branches_mount() {
    fn fixture() -> Element {
        rsx! { for mode in ["chronology","knowledge","cardinality"] { FactualPolicy{mode:mode.to_string(),frame:frame(),clock:Some(clock()),choices:choices(),namespaces:vec![],disabled:false,onadd:move |_|{}} } }
    }
    let mut dom = dioxus::core::VirtualDom::new(fixture);
    let mutations = dom.rebuild_to_vec();
    // Templates carry static labels; rebuilding also proves all three control branches mount.
    assert!(!mutations.edits.is_empty());
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn factual_policy_forms_recover_review_approve_and_publish() {
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
    let relation = "rec_00000000000000000000bc01";
    let world = "rec_00000000000000000000bc02";
    publish(&mut c,&opened,json!([{"kind":"define_relation","client_ref":relation,"record":{"namespace":"factual","key":"successor","labels":{"en":"Successor"},"roles":[{"name":"office","participantTypes":[],"multiplicity":"single","ordered":false},{"name":"successor","participantTypes":[],"multiplicity":"single","ordered":false}]}},{"kind":"create_world","client_ref":world,"record":{"selector":"Setting","labels":{},"metadata":{}}}]),"policy-vocabulary").await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let context_record = read(&mut c, &opened, &u["context_id"]).await;
    let relation_record = read(&mut c, &opened, &json!(relation)).await;
    let world_record = read(&mut c, &opened, &json!(world)).await;
    let choices = crate::author::choices(
        &[json!({"kind":"world","record_id":world,"label":"Setting"})],
        &[context_record.clone(), relation_record, world_record],
        "[]",
    );
    let clock: Chronology =
        serde_json::from_value(context_record["payload"]["chronology"].clone()).unwrap();
    let mut f = Form {
        namespace: "factual".into(),
        key: "radio-policy".into(),
        channel: "radio".into(),
        order: "forward".into(),
        minimum: "0".into(),
        maximum_delay: "10".into(),
        context: frame.context.record.to_string(),
        knowledge: "justified".into(),
        ..Default::default()
    };
    let chronology = f
        .build("chronology", &frame, Some(&clock), &choices)
        .unwrap();
    f.key = "knowledge-policy".into();
    let knowledge = f
        .build("knowledge", &frame, Some(&clock), &choices)
        .unwrap();
    f.key = "count-policy".into();
    f.relation = relation.into();
    f.grouping = "role".into();
    f.group_role = "office".into();
    f.counted_role = "successor".into();
    f.maximum = "2".into();
    f.applicability = "worlds".into();
    f.worlds = vec![world.replacen("rec_", "wld_", 1)];
    f.validity = "interval".into();
    f.start = "0".into();
    f.end = "20".into();
    let cardinality = f
        .build("cardinality", &frame, Some(&clock), &choices)
        .unwrap();
    let operations = json!([chronology, knowledge, cardinality]);
    let load = EngineRequest::LoadDraft {
        universe: universe_protocol::request::Selector("Alpha".into()),
        continuity_id: frame.continuity.clone(),
    };
    let saved = c
        .call(EngineRequest::SaveDraft {
            universe: universe_protocol::request::Selector("Alpha".into()),
            continuity_id: frame.continuity.clone(),
            expected_version: 0,
            content: DraftContent {
                proposal: None,
                base_revision: frame.revision.clone(),
                represented_context: frame.context.record.clone(),
                operations: serde_json::from_value(operations.clone()).unwrap(),
                rationale: "Opt in after exact author review".into(),
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
    let recovered = c.call(load).await.unwrap();
    assert_eq!(recovered, saved);
    assert_eq!(recovered["content"]["operations"], operations);
    let opened = open(&mut c, &u).await;
    // Publication is the ordinary native review/validation/exact approval route.
    publish(
        &mut c,
        &opened,
        recovered["content"]["operations"].clone(),
        "recovered-policies",
    )
    .await;
    let opened = open(&mut c, &u).await;
    for op in operations.as_array().unwrap() {
        let row = read(&mut c, &opened, &op["client_ref"]).await;
        let mut payload = row["payload"].clone();
        payload.as_object_mut().unwrap().remove("record_kind");
        assert_eq!(payload, op["record"]);
    }
    let at = |n: i32| json!({"kind":"exact","calendar":clock.calendar,"value":n.to_string()});
    let rr = |id: &str| json!({"universe":frame.universe,"record":id});
    // The native chronology policy is active after approval, not merely serializable.
    publish(&mut c,&opened,json!([{"kind":"introduce_instance","client_ref":"rec_00000000000000000000bc03","name":{"text":"Sender","validity":{"kind":"unspecified"}},"classification":null,"world_associations":[]},{"kind":"introduce_instance","client_ref":"rec_00000000000000000000bc04","name":{"text":"Recipient","validity":{"kind":"unspecified"}},"classification":null,"world_associations":[]}]),"policy-participants").await;
    let opened = open(&mut c, &u).await;
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[{"kind":"record_communication","client_ref":"rec_00000000000000000000bc05","record":{"sender":rr("rec_00000000000000000000bc03"),"intendedRecipients":[rr("rec_00000000000000000000bc04")],"actualRecipients":[rr("rec_00000000000000000000bc04")],"content":[],"channel":"radio","sentAt":at(5),"receivedAt":at(4),"distorted":false}}],"submission":"submitted","rationale":"Check published native policy","idempotency_key":"native-chronology-rejection"})).await["result"].clone();
    let reference =
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]});
    let validation=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await;
    assert!(validation["result"]["execution"]["findings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["rule_id"] == chronology["client_ref"] && f["outcome"] == "refuted"));
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
