//! Form operations use the existing authenticated proposal and receipt path.
use super::*;
use crate::identity_editor::workflow::{connect, open, publish, read, tool};
use tokio_util::sync::CancellationToken;
use universe_protocol::{
    installation::*,
    request::{ProposalRef, Selector},
};
use universe_service::runtime;
fn id(n: u64) -> String {
    format!("rec_{:024x}", 88000 + n)
}
fn form(instance: u64) -> Form {
    Form {
        instance: id(instance),
        start: id(instance + 10),
        source: id(5),
        applicability: "universe_wide".into(),
        duration: "unbounded".into(),
        ..Default::default()
    }
}
#[test]
fn typed_initialization_requires_explicit_source_start_scope_and_end() {
    let frame:Frame=serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":id(99)},"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
    let rr = |n| json!({"universe":frame.universe,"record":id(n)});
    let event = json!({"identity":{"record_id":id(11)},"payload":{"record_kind":"event","occurrence":"occurred","time":{"kind":"exact","calendar":"cal_000000000000000000000001","value":"10"},"participants":[{"record":rr(1)}]}});
    let source = json!({"identity":{"record_id":id(5)},"record_version_id":"ver_000000000000000000000001","payload":{"record_kind":"assertion","attributeMode":"initial_value"}});
    let f = form(1);
    let op = f.operation(&frame, None, &event, &source).unwrap();
    assert_eq!(op["definition"]["version"], source["record_version_id"]);
    assert_eq!(
        op["scope"]["context"],
        serde_json::to_value(&frame.context).unwrap()
    );
    assert_eq!(op["validity"]["start"]["value"], "10");
    assert_eq!(op["validity"]["end"]["kind"], "unbounded");
    for field in ["instance", "start", "source", "applicability", "duration"] {
        let mut f = form(1);
        match field {
            "instance" => f.instance.clear(),
            "start" => f.start.clear(),
            "source" => f.source.clear(),
            "applicability" => f.applicability.clear(),
            _ => f.duration.clear(),
        };
        assert!(f.operation(&frame, None, &event, &source).is_err());
    }
    let mut scoped = form(1);
    scoped.applicability = "worlds".into();
    assert!(scoped.operation(&frame, None, &event, &source).is_err());
    scoped.worlds = vec!["wld_000000000000000000000001".into()];
    scoped.duration = "exact".into();
    scoped.end = "10".into();
    assert!(scoped.operation(&frame, None, &event, &source).is_err());
    scoped.end = "20".into();
    assert_eq!(
        scoped.operation(&frame, None, &event, &source).unwrap()["validity"]["end"]["value"],
        "20"
    );
    for (key, value) in [
        ("occurrence", json!("planned")),
        ("time", json!({"kind":"unknown"})),
        ("participants", json!([])),
    ] {
        let mut e = event.clone();
        e["payload"][key] = value;
        assert!(f.operation(&frame, None, &e, &source).is_err());
    }
    let mut s = source.clone();
    s["payload"]["attributeMode"] = json!("shared");
    assert!(f.operation(&frame, None, &event, &s).is_err());
    let fact = starting_fact(
        &op,
        &json!({"payload":{"predicate":rr(4),"value":{"kind":"integer","digits":"7"}}}),
    );
    assert_eq!(fact["subject"], rr(1));
    assert_eq!(fact["value"]["digits"], "7");
    assert_eq!(fact["source_assertion_version"], op["definition"]);
    assert!(crate::readable::operation_summary(&op).contains("assertion version"));
}
#[test]
fn initialization_control_mounts() {
    fn fixture() -> Element {
        let frame:Frame=serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":id(99)},"time":{"kind":"timeless"},"perspective":"author"})).unwrap();
        rsx! {InitializationEditor{root:"",profile:"",universe:"",context:ContextId::parse("ctx_000000000000000000000001").unwrap(),frame,clock:None,choices:vec![],disabled:false,onadd:move|_|{}}}
    }
    let mut dom = dioxus::core::VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
async fn rejected(
    c: &mut universe_client::installation::EngineClient,
    opened: &Value,
    ops: Value,
    key: &str,
    expected: &str,
) {
    let proposed=c.call(crate::author::tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":ops,"submission":"submitted","rationale":"Explicit instance initialization","idempotency_key":key})).unwrap()).await;
    let error = match proposed {
        Err(e) => e,
        Ok(p) => {
            let p = &p["result"];
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
            assert!(!review["diff"].is_null());
            let v=tool(c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"]["execution"].clone();
            c.call(EngineRequest::Approve {
                universe: Selector("Alpha".into()),
                proposal_reference: reference.clone(),
                validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
            })
            .await
            .unwrap();
            c.call(crate::author::tool("universe_commit",json!({"universe":"Alpha","proposal_reference":reference,"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["run_id"],"idempotency_key":format!("commit-{key}")})).unwrap()).await.unwrap_err()
        }
    };
    assert!(error.to_string().contains(expected), "{error}");
    let library = c
        .call(EngineRequest::Library {
            universe: Selector("Alpha".into()),
        })
        .await
        .unwrap();
    assert_eq!(
        library["storage"]["heads"][0][1],
        opened["frame"]["revision"]
    );
}
async fn state(
    c: &mut universe_client::installation::EngineClient,
    u: &Value,
    clock: &Chronology,
) -> Value {
    let at=tool(c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock.calendar,"value":"10"}},"temporal_systems":[],"perspective":"author"})).await;
    tool(c,"universe_get_state",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"entity_ids":[id(1),id(2)],"predicate_filters":[]})).await["result"].clone()
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn native_initialization_reviews_publishes_recovers_and_cannot_repeat() {
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
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let clock: Chronology = serde_json::from_value(
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"].clone(),
    )
    .unwrap();
    let rr = |n| json!({"universe":frame.universe,"record":id(n)});
    let definition = |n, key, parent: Option<String>| json!({"kind":"introduce_definition","client_ref":id(n),"namespace":"init","key":key,"name":key,"parent":parent,"applicability":{"kind":"universe_wide"},"classification_executable":true});
    let assertion = |n, value, precision: &str| json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"predicate":rr(4),"subject":rr(3),"value":{"kind":"integer","digits":value},"quantification":"particular","context":frame.context},"assertion":{"attributeMode":"initial_value","proposition":rr(n),"polarity":"support","scope":{"context":frame.context,"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":"0"},"end":{"kind":"unbounded"}},"persistence":"explicit_interval","precision":precision,"basis":{"kind":"author_decision","note":"Initial count"}}});
    let entity = |n| json!({"kind":"introduce_instance","client_ref":id(n),"name":{"text":format!("Instance {n}"),"validity":{"kind":"unspecified"}},"classification":id(3),"world_associations":[]});
    let event = |n| json!({"kind":"record_event","client_ref":id(n+10),"record":{"occurrence":"occurred","action":rr(7),"time":{"kind":"exact","calendar":clock.calendar,"value":"10"},"participants":[{"record":rr(n),"role":"starting_instance"}],"labels":{}}});
    publish(&mut c,&opened,json!([definition(3,"Device",None),definition(6,"Lamp",Some(id(3))),{"kind":"define_property","client_ref":id(4),"record":{"namespace":"init","key":"charge","labels":{},"subjectTypes":[],"value":{"kind":"integer"},"multiplicity":"multiple","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}},{"kind":"define_action","client_ref":id(7),"record":{"namespace":"init","key":"start","labels":{},"requirements":[],"consequenceContract":{"kind":"action_consequences","slots":[]},"scope":{"context":frame.context,"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unspecified"}}},entity(1),entity(2),entity(8),event(8),event(1),event(2),assertion(5,"7","exact")]),"initialization-fixture").await;
    let opened = open(&mut c, &u).await;
    let mut shared = assertion(50, "10", "exact");
    shared["proposition"]["predicate"] = rr(9);
    shared["assertion"]["attributeMode"] = json!("shared");
    let stock = |n, subject| {
        let mut op = assertion(n, "4", "exact");
        op["proposition"]["predicate"] = rr(9);
        op["proposition"]["subject"] = rr(subject);
        op["assertion"]["attributeMode"] = json!("instance");
        op
    };
    publish(&mut c,&opened,json!([{"kind":"define_property","client_ref":id(9),"record":{"namespace":"init","key":"capacity","labels":{},"subjectTypes":[],"value":{"kind":"integer"},"multiplicity":"multiple","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}},shared,stock(51,1),stock(52,2)]),"separate-shared-stock").await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    // Assertion IDs are generated separately from the form's proposition client ref.
    let before = state(&mut c, &u, &clock).await;
    let source = before["objects"][0]["initial_value_candidates"][0]["record"].clone();
    for object in before["objects"].as_array().unwrap() {
        assert_eq!(object["shared_attributes"].as_array().unwrap().len(), 1);
        assert_eq!(
            object["initial_value_candidates"].as_array().unwrap().len(),
            1
        );
        assert_eq!(object["instance_facts"].as_array().unwrap().len(), 1);
        assert_eq!(object["initialization_receipts"], json!([]));
    }
    let mut forms = [form(1), form(2)];
    for f in &mut forms {
        f.source = source["identity"]["record_id"].as_str().unwrap().into();
    }
    let mut ops = Vec::new();
    for f in &forms {
        let event = read(&mut c, &opened, &json!(f.start)).await;
        ops.push(f.operation(&frame, Some(&clock), &event, &source).unwrap());
    }
    let operations = json!(ops);
    let saved = c
        .call(EngineRequest::SaveDraft {
            universe: Selector("Alpha".into()),
            continuity_id: frame.continuity.clone(),
            expected_version: 0,
            content: DraftContent {
                proposal: None,
                base_revision: frame.revision.clone(),
                represented_context: frame.context.record.clone(),
                operations: serde_json::from_value(operations.clone()).unwrap(),
                rationale: "Separate reviewed starting facts".into(),
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
            continuity_id: frame.continuity.clone(),
        })
        .await
        .unwrap();
    assert_eq!(recovered, saved);
    assert_eq!(recovered["content"]["operations"], operations);
    let opened = open(&mut c, &u).await;
    publish(
        &mut c,
        &opened,
        operations.clone(),
        "reviewed-initialization",
    )
    .await;
    let after = state(&mut c, &u, &clock).await;
    for object in after["objects"].as_array().unwrap() {
        assert_eq!(object["instance_facts"].as_array().unwrap().len(), 2);
        assert_eq!(
            object["initialization_receipts"].as_array().unwrap().len(),
            1
        );
        let fact = &object["instance_facts"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["record"]["payload"]["basis"]["kind"] == "instance_initialization")
            .unwrap()["record"]["payload"];
        let proposition = object["dependencies"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["identity"]["record_id"] == fact["proposition"]["record"])
            .unwrap();
        assert_eq!(proposition["payload"]["value"]["digits"], "7");
        assert_eq!(
            proposition["payload"]["subject"]["record"],
            object["identity"]["identity"]["record_id"]
        );
        assert_eq!(
            object["shared_attributes"],
            before["objects"][0]["shared_attributes"]
        );
        assert_eq!(fact["attributeMode"], "instance");
        assert_eq!(
            fact["basis"]["definition"]["version"],
            source["record_version_id"]
        );
    }
    assert_ne!(
        after["objects"][0]["instance_facts"][0]["record"]["identity"],
        after["objects"][1]["instance_facts"][0]["record"]["identity"]
    );
    assert_ne!(
        after["objects"][0]["initialization_receipts"][0]["assertion"],
        after["objects"][1]["initialization_receipts"][0]["assertion"]
    );
    let opened = open(&mut c, &u).await;
    let mut retry = operations[0].clone();
    retry["client_ref"] = json!(id(40));
    rejected(
        &mut c,
        &opened,
        json!([retry.clone()]),
        "repeat",
        "storage failure",
    )
    .await;
    let selected = read(&mut c, &opened, &json!(id(1))).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let rename = crate::inspector_editor::operation(
        &frame,
        &selected,
        "add_name",
        "Renamed device",
        "",
        None,
    )
    .unwrap();
    publish(&mut c, &opened, json!([rename]), "rename").await;
    let opened = open(&mut c, &u).await;
    rejected(
        &mut c,
        &opened,
        json!([retry.clone()]),
        "repeat-renamed",
        "storage failure",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let selected = read(&mut c, &opened, &json!(id(1))).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let refinement = crate::inspector_editor::operation(
        &frame,
        &selected,
        "refine_classification",
        &id(6),
        "",
        None,
    )
    .unwrap();
    publish(&mut c, &opened, json!([refinement]), "refine").await;
    let opened = open(&mut c, &u).await;
    rejected(
        &mut c,
        &opened,
        json!([retry.clone()]),
        "repeat-refined",
        "storage failure",
    )
    .await;
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let opened = open(&mut c, &u).await;
    rejected(
        &mut c,
        &opened,
        json!([retry]),
        "repeat-restarted",
        "storage failure",
    )
    .await;
    let restarted = state(&mut c, &u, &clock).await;
    for object in restarted["objects"].as_array().unwrap() {
        assert_eq!(object["instance_facts"].as_array().unwrap().len(), 2);
        assert_eq!(
            object["initialization_receipts"].as_array().unwrap().len(),
            1
        );
    }
    assert_eq!(
        restarted["objects"][0]["initialization_receipts"],
        after["objects"][0]["initialization_receipts"]
    );
    // Conflicting/unresolved candidates pass through ordinary proposal construction.
    for (n, value, precision, expected) in [
        (30, "8", "exact", "conflict"),
        (31, "7", "unresolved", "unresolved"),
    ] {
        let opened = open(&mut c, &u).await;
        let mut f = form(8);
        f.source = source["identity"]["record_id"].as_str().unwrap().into();
        let event = read(&mut c, &opened, &json!(f.start)).await;
        let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
        let operation = f.operation(&frame, Some(&clock), &event, &source).unwrap();
        rejected(
            &mut c,
            &opened,
            json!([assertion(n, value, precision), operation]),
            &format!("candidate-{n}"),
            expected,
        )
        .await;
    }
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
