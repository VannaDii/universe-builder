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
        rsx! { for mode in ["chronology","knowledge","cardinality","resources"] { FactualPolicy{mode:mode.to_string(),frame:frame(),clock:Some(clock()),choices:choices(),namespaces:vec![],disabled:false,onadd:move |_|{}} } }
    }
    let mut dom = dioxus::core::VirtualDom::new(fixture);
    let mutations = dom.rebuild_to_vec();
    // Templates carry static labels; rebuilding also proves the factual control branches mount.
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
    // The inspected contract controls preserve untouched metadata and publish exact revisions.
    let opened = open(&mut c, &u).await;
    let relation_row = read(&mut c, &opened, &json!(relation)).await;
    let role_edit = crate::inspector_editor::contract_operation(
        &frame,
        &relation_row,
        "role_ordered",
        "successor",
        "true",
    )
    .unwrap();
    assert_eq!(
        role_edit["replacement"]["roles"][0],
        relation_row["payload"]["roles"][0]
    );
    publish(&mut c, &opened, json!([role_edit]), "native-role-edit").await;
    let opened = open(&mut c, &u).await;
    let limit_row = read(&mut c, &opened, &cardinality["client_ref"]).await;
    let max_edit = crate::inspector_editor::contract_operation(
        &frame,
        &limit_row,
        "relation_maximum",
        "",
        "1",
    )
    .unwrap();
    assert_eq!(
        max_edit["replacement"]["relationCardinality"]["scope"],
        limit_row["payload"]["relationCardinality"]["scope"]
    );
    assert_eq!(
        max_edit["replacement"]["relationCardinality"]["validity"],
        limit_row["payload"]["relationCardinality"]["validity"]
    );
    publish(&mut c, &opened, json!([max_edit]), "native-maximum-edit").await;
    let opened = open(&mut c, &u).await;
    let claim = crate::claim_editor::Form {
        attribute_mode: "instance".into(),
        subject: "rec_00000000000000000000bc03".into(),
        predicate: relation.into(),
        kind: "relationship".into(),
        roles: vec![
            ("office".into(), "rec_00000000000000000000bc03".into()),
            ("successor".into(), "rec_00000000000000000000bc04".into()),
        ],
        precision: "exact".into(),
        polarity: "support".into(),
        applicability: "worlds".into(),
        worlds: world.replacen("rec_", "wld_", 1),
        validity: "interval".into(),
        start_kind: "exact".into(),
        end_kind: "exact".into(),
        calendar: clock.calendar.to_string(),
        when: "0".into(),
        until: "20".into(),
        note: "Explicit authored successor".into(),
        ..Default::default()
    }
    .build(&frame, Some(&clock))
    .unwrap();
    let claim = serde_json::to_value(claim).unwrap();
    publish(&mut c, &opened, json!([claim]), "native-relationship").await;
    let opened = open(&mut c, &u).await;
    let hits=tool(&mut c,"universe_search",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"query":"","typed_filters":{"record_kinds":["assertion"]},"limit":100})).await;
    let mut original = Value::Null;
    for hit in hits["result"]["hits"].as_array().unwrap() {
        let row = read(&mut c, &opened, &hit["record_id"]).await;
        if row["payload"]["proposition"]["record"] == claim["client_ref"] {
            original = row;
        }
    }
    assert!(!original.is_null());
    let prop = read(&mut c, &opened, &claim["client_ref"]).await;
    let relation_row = read(&mut c, &opened, &json!(relation)).await;
    let sender = read(&mut c, &opened, &json!("rec_00000000000000000000bc03")).await;
    let recipient = read(&mut c, &opened, &json!("rec_00000000000000000000bc04")).await;
    let selected =
        crate::author::choices(&[], &[prop, relation_row.clone(), sender, recipient], "[]");
    let correction = crate::claim_editor::relationship_operations(
        &frame,
        &original,
        &selected,
        "successor",
        &["rec_00000000000000000000bc03".into()],
        "Explicit historical correction",
        None,
    )
    .unwrap();
    assert_eq!(
        correction[1]["replacement"]["validity"],
        original["payload"]["validity"]
    );
    assert_eq!(correction[0]["record"]["roles"][0]["role"], "office");
    publish(
        &mut c,
        &opened,
        json!(correction),
        "native-participant-correction",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let original = read(&mut c, &opened, &original["identity"]["record_id"]).await;
    let prop = read(
        &mut c,
        &opened,
        &original["payload"]["proposition"]["record"],
    )
    .await;
    let mut selected = selected;
    selected.push(json!({"kind":"proposition","record_id":prop["identity"]["record_id"],"definition":prop["payload"]}));
    let transfer = crate::claim_editor::relationship_operations(
        &frame,
        &original,
        &selected,
        "successor",
        &["rec_00000000000000000000bc04".into()],
        "Explicit transfer at day ten",
        Some(("10", Some(&clock))),
    )
    .unwrap();
    assert_eq!(transfer.len(), 2);
    assert_eq!(transfer[0]["kind"], "end_assertion_at");
    assert_eq!(transfer[1]["kind"], "record_relation");
    let replacement = transfer[1].clone();
    publish(
        &mut c,
        &opened,
        json!(transfer),
        "native-relationship-transfer",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let state=tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"entity_ids":["rec_00000000000000000000bc03"],"predicate_filters":[]})).await;
    assert!(state["result"]["objects"][0]["dependencies"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["identity"]["record_id"] == "rec_00000000000000000000bc04"));
    let rendered = crate::effective_object_view::tests::render(state);
    assert!(
        rendered.contains("Declared participants: office: Sender; successor: Recipient"),
        "{rendered}"
    );
    let ended = read(&mut c, &opened, &original["identity"]["record_id"]).await;
    assert_eq!(ended["payload"]["validity"]["end"]["value"], "10");
    let tightened = crate::inspector_editor::contract_operation(
        &frame,
        &relation_row,
        "role_multiple",
        "successor",
        "single",
    )
    .unwrap();
    assert_eq!(tightened["replacement"]["roles"][1]["ordered"], true);
    let limit_row = read(&mut c, &opened, &cardinality["client_ref"]).await;
    let invalid = crate::inspector_editor::contract_operation(
        &frame,
        &limit_row,
        "relation_maximum",
        "",
        "0",
    )
    .unwrap();
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[invalid],"submission":"submitted","rationale":"Explicit proposed tightening","idempotency_key":"native-limit-denial"})).await["result"].clone();
    let reference =
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]});
    let checked=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await;
    assert!(checked["result"]["execution"]["findings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["outcome"] == "refuted"));
    let denied = c
        .call(EngineRequest::Approve {
            universe: universe_protocol::request::Selector("Alpha".into()),
            proposal_reference: serde_json::from_value(reference).unwrap(),
            validation_run: serde_json::from_value(
                checked["result"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
        })
        .await
        .unwrap_err();
    assert!(
        denied.to_string().contains("validation blocks approval"),
        "{denied}"
    );
    assert!(read(&mut c, &opened, &replacement["client_ref"]).await["payload"].is_object());
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[test]
fn resource_policy_requires_a_single_supported_stock_property() {
    let mut f = base();
    let mut c = choices();
    let id = "rec_000000000000000000000005";
    c.push(json!({"kind":"property","record_id":id,"definition":{"namespace":"stock","key":"rounds","multiplicity":"single","value":{"kind":"integer"}}}));
    assert!(f.build("resources", &frame(), None, &c).is_err());
    f.predicate = id.into();
    let op = f.build("resources", &frame(), None, &c).unwrap();
    assert_eq!(
        op["record"]["capabilities"],
        json!(["resources.accounting.v1"])
    );
    assert_eq!(op["record"]["commitPolicy"], "block_unless_exception");
    assert_eq!(op["record"]["targetPredicates"], json!(["stock:rounds"]));
    c.last_mut().unwrap()["definition"]["multiplicity"] = json!("multiple");
    assert!(f.build("resources", &frame(), None, &c).is_err());
    c.last_mut().unwrap()["definition"]["multiplicity"] = json!("single");
    c.last_mut().unwrap()["definition"]["value"]["kind"] = json!("text");
    assert!(f.build("resources", &frame(), None, &c).is_err());
}

#[test]
fn inspected_relationship_fields_preserve_other_role_and_policy_metadata() {
    let relation = json!({"identity":{"record_id":"rec_000000000000000000000002"},"record_version_id":"ver_000000000000000000000002","payload":{"record_kind":"relation","namespace":"authored","key":"ownership","labels":{},"roles":[{"name":"item","participantTypes":[],"multiplicity":"single","ordered":false},{"name":"owner","participantTypes":["rec_000000000000000000000003"],"multiplicity":"multiple","ordered":true}]}});
    let op = crate::inspector_editor::contract_operation(
        &frame(),
        &relation,
        "role_multiple",
        "owner",
        "single",
    )
    .unwrap();
    assert_eq!(op["expected_version"], relation["record_version_id"]);
    assert_eq!(
        op["replacement"]["roles"][0],
        relation["payload"]["roles"][0]
    );
    assert_eq!(
        op["replacement"]["roles"][1]["participantTypes"],
        relation["payload"]["roles"][1]["participantTypes"]
    );
    assert_eq!(op["replacement"]["roles"][1]["ordered"], true);
    assert!(crate::inspector_editor::contract_operation(
        &frame(),
        &relation,
        "role_ordered",
        "missing",
        "true"
    )
    .is_err());
    assert!(crate::inspector_editor::contract_operation(
        &frame(),
        &relation,
        "role_multiple",
        "owner",
        ""
    )
    .is_err());
    let cleared = crate::inspector_editor::contract_operation(
        &frame(),
        &relation,
        "role_type_clear",
        "owner",
        "",
    )
    .unwrap();
    assert_eq!(
        cleared["replacement"]["roles"][1]["participantTypes"],
        json!([])
    );
    assert_eq!(cleared["replacement"]["roles"][1]["ordered"], true);
}

#[test]
fn relationship_inspector_controls_mount_without_shared_editor_ids() {
    fn fixture() -> Element {
        let generation = use_signal(|| 0);
        let original = json!({"identity":{"record_id":"rec_000000000000000000000002"},"record_version_id":"ver_000000000000000000000002","payload":{"record_kind":"assertion","attributeMode":"instance"}});
        rsx! {crate::claim_editor::RelationshipCorrection{root:"unused".to_string(),profile:"unused".to_string(),universe:"Alpha".to_string(),context:Value::Null,frame:frame(),original,clock:Some(clock()),available:vec![],generation,disabled:false,onadd:move |_|{}} crate::inspector_editor::InspectorEditor{frame:frame(),selected:json!({"payload":{"record_kind":"relation","roles":[{"name":"owner"}]}}),choices:choices(),clock:Some(clock()),disabled:false,onadd:move |_|{}}}
    }
    let mut dom = dioxus::core::VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
