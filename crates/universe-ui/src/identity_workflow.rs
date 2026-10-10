//! Exercise the native form builders through the authenticated service and draft store.
use super::*;
use tokio_util::sync::CancellationToken;
use universe_client::installation::EngineClient;
use universe_protocol::{installation::*, request::ProposalRef};
use universe_service::runtime;

pub(crate) async fn connect(root: &std::path::Path, author: &ProfileId) -> EngineClient {
    for _ in 0..100 {
        if let Ok(c) = EngineClient::connect(root, author, "native-identity-test").await {
            return c;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    panic!("engine unavailable");
}
pub(crate) async fn tool(c: &mut EngineClient, name: &str, args: Value) -> Value {
    c.call(crate::author::tool(name, args).unwrap())
        .await
        .unwrap()
}
pub(crate) async fn open(c: &mut EngineClient, u: &Value) -> Value {
    tool(c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).await
}
pub(crate) async fn read(c: &mut EngineClient, opened: &Value, id: &Value) -> Value {
    tool(c,"universe_get",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"record_ids":[id],"field_groups":[]})).await["result"]["records"][0].clone()
}
pub(crate) async fn publish(c: &mut EngineClient, opened: &Value, ops: Value, key: &str) {
    let p = tool(c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":ops,"submission":"submitted","rationale":"Native identity changes","idempotency_key":key})).await["result"].clone();
    let reference: ProposalRef = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let review = c
        .call(EngineRequest::Review {
            universe: universe_protocol::request::Selector("Alpha".into()),
            proposal_reference: reference.clone(),
        })
        .await
        .unwrap();
    assert!(!review["diff"].is_null());
    let v = tool(c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"]["execution"].clone();
    assert_eq!(v["coverage"], "complete");
    c.call(EngineRequest::Approve {
        universe: universe_protocol::request::Selector("Alpha".into()),
        proposal_reference: reference.clone(),
        validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    tool(c,"universe_commit",json!({"universe":"Alpha","proposal_reference":reference,"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["run_id"],"idempotency_key":format!("commit-{key}")})).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn native_forms_create_refine_reject_and_recover_stable_identity() {
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
    let world = Form {
        kind: "world".into(),
        name: "Garden world".into(),
        ..Default::default()
    }
    .create(&serde_json::from_value(opened["frame"].clone()).unwrap())
    .unwrap();
    publish(&mut c, &opened, json!([world]), "native-world-introduction").await;
    let opened = open(&mut c, &u).await;
    let authored = read(&mut c, &opened, &world["client_ref"]).await;
    assert_eq!(authored["payload"]["selector"], "Garden world");
    let context_record = read(&mut c, &opened, &u["context_id"]).await;
    let chronology = &context_record["payload"]["chronology"];
    let context_form = Form {
        kind: "story_context".into(),
        name: "Garden dream".into(),
        context_kind: "dream".into(),
        parent_context: u["context_id"].as_str().unwrap().into(),
        calendar: chronology["calendar"].as_str().unwrap().into(),
        story_time: "5".into(),
        ..Default::default()
    };
    let choices = vec![
        json!({"kind":"represented_context","record_id":u["context_id"],"definition":context_record["payload"]}),
    ];
    let story = context_form
        .create_context(
            &serde_json::from_value(opened["frame"].clone()).unwrap(),
            &choices,
        )
        .unwrap();
    publish(&mut c, &opened, json!([story]), "native-story-context").await;
    let library = c
        .call(EngineRequest::Library {
            universe: universe_protocol::request::Selector("Alpha".into()),
        })
        .await
        .unwrap();
    let empty_draft = json!({"content":{"represented_context":u["context_id"],"operations":[],"proposal":null,"rationale":""}});
    let target = story["client_ref"].as_str().unwrap();
    assert_eq!(
        crate::author::workspace_context(&library, &empty_draft, target).unwrap(),
        story["client_ref"]
    );
    let mut unfinished = empty_draft.clone();
    unfinished["content"]["operations"] = json!([story]);
    assert!(crate::author::workspace_context(&library, &unfinished, target).is_err());
    let named=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":{"name":"Garden dream"},"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).await;
    let authored = read(&mut c, &named, &story["client_ref"]).await;
    assert_eq!(authored["payload"]["parent"]["record"], u["context_id"]);
    assert_eq!(authored["payload"]["chronology"]["current"], "5");
    let opened = open(&mut c, &u).await;
    let parent = "rec_00000000000000000000ab01";
    let child = "rec_00000000000000000000ab02";
    let unrelated = "rec_00000000000000000000ab03";
    let definition = |id, key, parent: Option<&str>| json!({"kind":"introduce_definition","client_ref":id,"namespace":"identity","key":key,"name":key,"parent":parent,"applicability":{"kind":"universe_wide"},"classification_executable":true});
    publish(
        &mut c,
        &opened,
        json!([
            definition(parent, "Person", None),
            definition(child, "Scholar", Some(parent)),
            definition(unrelated, "Book", None)
        ]),
        "definitions",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let minimal = Form {
        kind: "entity".into(),
        name: "Mara".into(),
        ..Default::default()
    }
    .create(&frame)
    .unwrap();
    let classified = Form {
        kind: "entity".into(),
        name: "Iven".into(),
        classification: parent.into(),
        ..Default::default()
    }
    .create(&frame)
    .unwrap();
    publish(&mut c, &opened, json!([minimal, classified]), "creation").await;
    let opened = open(&mut c, &u).await;
    let mara = read(&mut c, &opened, &minimal["client_ref"]).await;
    let iven = read(&mut c, &opened, &classified["client_ref"]).await;
    assert!(mara["payload"]["classification"].is_null());
    assert_eq!(mara["payload"]["names"][0]["text"], "Mara");
    assert_eq!(iven["payload"]["classification"], parent);
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let first = crate::inspector_editor::operation(
        &frame,
        &mara,
        "refine_classification",
        parent,
        "",
        None,
    )
    .unwrap();
    publish(&mut c, &opened, json!([first]), "first-classification").await;
    let opened = open(&mut c, &u).await;
    let mara_parent = read(&mut c, &opened, &minimal["client_ref"]).await;
    assert_eq!(mara_parent["identity"], mara["identity"]);
    assert_eq!(mara_parent["payload"]["classification"], parent);
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let refine = crate::inspector_editor::operation(
        &frame,
        &mara_parent,
        "refine_classification",
        child,
        "",
        None,
    )
    .unwrap();
    let another = Form {
        kind: "entity".into(),
        name: "Nera".into(),
        classification: child.into(),
        ..Default::default()
    }
    .create(&frame)
    .unwrap();
    let operations = json!([refine, another]);
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
                rationale: "Recover the intended identity changes".into(),
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
    let choices = crate::author::choices(&[], &[], &recovered["content"]["operations"].to_string());
    assert_eq!(choices[0]["record_id"], another["client_ref"]);
    assert_eq!(choices[0]["label"], "Nera (draft)");
    let opened = open(&mut c, &u).await;
    publish(
        &mut c,
        &opened,
        recovered["content"]["operations"].clone(),
        "recovered-refinement",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let mara_child = read(&mut c, &opened, &minimal["client_ref"]).await;
    assert_eq!(mara_child["identity"], mara["identity"]);
    assert_eq!(mara_child["payload"]["names"], mara["payload"]["names"]);
    assert_eq!(mara_child["payload"]["classification"], child);
    assert_ne!(
        mara_child["record_version_id"],
        mara_parent["record_version_id"]
    );
    assert_eq!(
        read(&mut c, &opened, &another["client_ref"]).await["payload"]["classification"],
        child
    );
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let invalid = crate::inspector_editor::operation(
        &frame,
        &mara_child,
        "refine_classification",
        unrelated,
        "",
        None,
    )
    .unwrap();
    let error = c.call(crate::author::tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[invalid],"submission":"submitted","rationale":"Reject unrelated refinement","idempotency_key":"unrelated"})).unwrap()).await.unwrap_err();
    assert!(
        error.to_string().contains("not a descendant refinement"),
        "{error}"
    );
    assert_eq!(
        read(&mut c, &opened, &minimal["client_ref"]).await,
        mara_child
    );
    // The actual inspector name form preserves identity and classification across publication.
    let clock: universe_domain::chronology::Chronology = serde_json::from_value(
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"].clone(),
    )
    .unwrap();
    let form = crate::inspector_editor::NameForm {
        text: "Garden Fox".into(),
        language: "en".into(),
        community: "Garden".into(),
        role: "nickname".into(),
        validity: "interval".into(),
        start: "5".into(),
        end: "10".into(),
        end_kind: "exact".into(),
    };
    assert!(crate::inspector_editor::name_operation(
        &frame,
        &mara_child,
        &crate::inspector_editor::NameForm {
            text: "Fox".into(),
            ..Default::default()
        },
        Some(&clock)
    )
    .is_err());
    assert!(crate::inspector_editor::name_operation(&frame, &mara_child, &form, None).is_err());
    let alias =
        crate::inspector_editor::name_operation(&frame, &mara_child, &form, Some(&clock)).unwrap();
    let before_alias = opened["frame"]["revision"].clone();
    publish(&mut c, &opened, json!([alias]), "contextual-name").await;
    let fresh = open(&mut c, &u).await;
    let named = read(&mut c, &fresh, &minimal["client_ref"]).await;
    assert_eq!(named["identity"], mara_child["identity"]);
    assert_eq!(
        named["payload"]["classification"],
        mara_child["payload"]["classification"]
    );
    assert_eq!(
        named["payload"]["names"][0],
        mara_child["payload"]["names"][0]
    );
    assert_eq!(named["payload"]["names"][1]["community"], "Garden");
    for (revision, tick, expected) in [
        (json!({"kind":"head"}), "5", Some(true)),
        (json!({"kind":"head"}), "10", Some(false)),
        (json!({"kind":"head"}), "4", Some(false)),
        (
            json!({"kind":"exact","revision_id":before_alias}),
            "5",
            None,
        ),
    ] {
        let at = tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":revision,"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock.calendar,"value":tick}},"temporal_systems":[],"perspective":"author"})).await;
        let state = tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"entity_ids":[minimal["client_ref"]],"predicate_filters":[]})).await;
        let names = state["result"]["objects"][0]["contextual_names"]
            .as_array()
            .unwrap();
        let found = names.iter().find(|n| n["name"]["text"] == "Garden Fox");
        match expected {
            Some(applies) => assert_eq!(found.unwrap()["applicability"], applies),
            None => assert!(found.is_none()),
        }
        let html = crate::effective_object_view::tests::render(state);
        assert!(html.contains("Names with unresolved applicability"));
    }
    let current = open(&mut c, &u).await;
    let nera = read(&mut c, &current, &another["client_ref"]).await;
    let current_frame: Frame = serde_json::from_value(current["frame"].clone()).unwrap();
    let same_alias =
        crate::inspector_editor::name_operation(&current_frame, &nera, &form, Some(&clock))
            .unwrap();
    publish(
        &mut c,
        &current,
        json!([same_alias]),
        "second-contextual-name",
    )
    .await;
    let at = tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock.calendar,"value":"5"}},"temporal_systems":[],"perspective":"author"})).await;
    let lookup = tool(&mut c,"universe_read_facts",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"object_names":["Garden Fox"]})).await;
    assert_eq!(
        lookup["result"]["objects"][0]["identity"], "ambiguous",
        "{lookup}"
    );
    assert_eq!(
        read(&mut c, &at, &minimal["client_ref"]).await["identity"],
        mara_child["identity"]
    );
    assert_eq!(
        read(&mut c, &at, &another["client_ref"]).await["identity"],
        nera["identity"]
    );
    let load_draft = EngineRequest::LoadDraft {
        universe: universe_protocol::request::Selector("Alpha".into()),
        continuity_id: frame.continuity.clone(),
    };
    let unfinished = c.call(load_draft.clone()).await.unwrap();
    assert!(crate::author::workspace_context(&library, &unfinished, target).is_err());
    let empty_content = DraftContent {
        proposal: None,
        base_revision: serde_json::from_value(at["frame"]["revision"].clone()).unwrap(),
        represented_context: frame.context.record.clone(),
        operations: vec![],
        rationale: String::new(),
    };
    let cleared = c
        .call(EngineRequest::SaveDraft {
            universe: universe_protocol::request::Selector("Alpha".into()),
            continuity_id: frame.continuity.clone(),
            expected_version: unfinished["version"].as_u64().unwrap(),
            content: empty_content,
        })
        .await
        .unwrap();
    let selected_context = crate::author::workspace_context(&library, &cleared, target).unwrap();
    let switched=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":selected_context,"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"})).await;
    let switched_content = DraftContent {
        proposal: None,
        base_revision: serde_json::from_value(switched["frame"]["revision"].clone()).unwrap(),
        represented_context: serde_json::from_value(switched["frame"]["context"]["record"].clone())
            .unwrap(),
        operations: vec![],
        rationale: String::new(),
    };
    c.call(EngineRequest::SaveDraft {
        universe: universe_protocol::request::Selector("Alpha".into()),
        continuity_id: frame.continuity.clone(),
        expected_version: cleared["version"].as_u64().unwrap(),
        content: switched_content,
    })
    .await
    .unwrap();
    assert_eq!(
        c.call(load_draft).await.unwrap()["content"]["represented_context"],
        story["client_ref"]
    );
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
