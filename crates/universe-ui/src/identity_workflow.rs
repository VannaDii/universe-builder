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
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
