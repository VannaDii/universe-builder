use serde_json::{json, Value};
use tokio_util::sync::CancellationToken;
use universe_client::{Client, ClientConfig, ConnectedClient};
use universe_protocol::{
    examples::{id, valid},
    Request, Response,
};
struct Harness {
    client: ConnectedClient,
    shutdown: CancellationToken,
    task: tokio::task::JoinHandle<anyhow::Result<()>>,
    _dir: tempfile::TempDir,
}
impl Drop for Harness {
    fn drop(&mut self) {
        self.shutdown.cancel();
        self.task.abort();
    }
}
async fn start() -> Harness {
    let dir = tempfile::tempdir().unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(dir.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let socket = dir.path().join("fixture.sock");
    let shutdown = CancellationToken::new();
    let signal = shutdown.clone();
    let path = socket.clone();
    let task = tokio::spawn(async move { universe_service::ipc::serve(&path, signal).await });
    let client = Client::with_config(ClientConfig::default().with_socket_path(socket))
        .connect_with_retry()
        .await
        .unwrap();
    Harness {
        client,
        shutdown,
        task,
        _dir: dir,
    }
}
async fn send(c: &ConnectedClient, tool: &str, args: Value) -> Response {
    c.send(Request::from_tool(tool, args).unwrap())
        .await
        .unwrap()
}
async fn context(c: &ConnectedClient, universe: &str) -> String {
    let mut a = valid()[1].1.clone();
    a["universe"] = json!(universe);
    match send(c, "universe_open_context", a).await {
        Response::OpenContext(r) => r.result.context_id.0,
        _ => panic!("wrong response"),
    }
}
#[tokio::test]
async fn named_universes_no_remembered_world_and_cross_scope_rejection() {
    let h = start().await;
    let c = context(&h.client, "The Ashen Cycle").await;
    let mut a = valid()[2].1.clone();
    a["context_id"] = json!(c);
    a["query"] = json!("");
    a["world"] = json!("Aster");
    let first = send(&h.client, "universe_search", a.clone())
        .await
        .body_json();
    assert!(first["world_focus"].is_string());
    a.as_object_mut().unwrap().remove("world");
    let second = send(&h.client, "universe_search", a.clone())
        .await
        .body_json();
    assert!(second["world_focus"].is_null());
    assert!(
        second["result"]["hits"].as_array().unwrap().len()
            > first["result"]["hits"].as_array().unwrap().len()
    );
    a["universe"] = json!("The Glass Archive");
    assert!(h
        .client
        .send(Request::from_tool("universe_search", a.clone()).unwrap())
        .await
        .is_err());
    a["context_id"] = json!(context(&h.client, "The Glass Archive").await);
    a["world"] = json!("Aster");
    let result = send(&h.client, "universe_search", a).await.body_json();
    assert_eq!(result["universe_id"], id("unv", 2));
}
#[tokio::test]
async fn lost_response_recovery_retry_conflict_and_no_canon_change() {
    let h = start().await;
    let c = context(&h.client, "The Ashen Cycle").await;
    let mut a = valid()[7].1.clone();
    a["context_id"] = json!(c);
    let first = send(&h.client, "universe_propose", a.clone())
        .await
        .body_json();
    assert_eq!(first["result"]["canonical"], false);
    let second = send(&h.client, "universe_propose", a.clone())
        .await
        .body_json();
    assert_eq!(first["result"], second["result"]);
    let recovered = send(&h.client, "universe_get_operation", valid()[11].1.clone())
        .await
        .body_json();
    assert_eq!(recovered["result"]["proposal"], first["result"]);
    a["rationale"] = json!("different request");
    assert!(h
        .client
        .send(Request::from_tool("universe_propose", a).unwrap())
        .await
        .is_err());
    let mut search = valid()[2].1.clone();
    search["context_id"] = json!(c);
    search["query"] = json!("Lantern");
    let result = send(&h.client, "universe_search", search).await.body_json();
    assert!(result["result"]["hits"].as_array().unwrap().is_empty());
    assert!(h
        .client
        .send(Request::from_tool("universe_commit", valid()[10].1.clone()).unwrap())
        .await
        .is_err());
}
#[tokio::test]
async fn concurrent_requests_are_correlated() {
    let h = start().await;
    let work = (0..32).map(|i| {
        let c = h.client.clone();
        async move {
            let u = if i % 2 == 0 {
                "The Ashen Cycle"
            } else {
                "The Glass Archive"
            };
            let r = send(
                &c,
                "universe_describe",
                json!({"universe":u,"mode":"summary"}),
            )
            .await;
            assert_eq!(r.body_json()["universe"], u);
        }
    });
    futures::future::join_all(work).await;
}
#[tokio::test]
async fn typed_unsupported_error_does_not_poison_connection() {
    let h = start().await;
    let c = context(&h.client, "The Ashen Cycle").await;
    let mut a = valid()[6].1.clone();
    a["context_id"] = json!(c);
    let e = h
        .client
        .send(Request::from_tool("universe_validate", a).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(
        e,
        universe_client::ClientError::Protocol(
            universe_protocol::ProtocolError::UnsupportedSemantics { .. }
        )
    ));
    send(&h.client, "universe_describe", valid()[0].1.clone()).await;
}

fn reference(p: &Value) -> Value {
    json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]})
}
async fn get_proposal(c: &ConnectedClient, p: &Value) -> Value {
    send(
        c,
        "universe_get_proposal",
        json!({"universe":"The Ashen Cycle","proposal_id":p["proposal_id"],"version":p["version"]}),
    )
    .await
    .body_json()["result"]
        .clone()
}
#[tokio::test]
async fn stale_mutations_cannot_overwrite_or_resurrect_proposal_versions() {
    let h = start().await;
    let ctx = context(&h.client, "The Ashen Cycle").await;
    let mut create = valid()[7].1.clone();
    create["context_id"] = json!(ctx);
    let first = send(&h.client, "universe_propose", create.clone())
        .await
        .body_json()["result"]
        .clone();
    let mut revise = create.clone();
    revise["action"] = json!("revise");
    revise["proposal_reference"] = reference(&first);
    revise["idempotency_key"] = json!("revision-2");
    revise["rationale"] = json!("Second version");
    let second = send(&h.client, "universe_propose", revise.clone())
        .await
        .body_json()["result"]
        .clone();
    revise["rationale"] = json!("Must not overwrite version two");
    revise["idempotency_key"] = json!("stale-revision");
    assert!(h
        .client
        .send(Request::from_tool("universe_propose", revise).unwrap())
        .await
        .is_err());
    assert_eq!(get_proposal(&h.client, &first).await, first);
    assert_eq!(get_proposal(&h.client, &second).await, second);
    let withdraw = json!({"universe":"The Ashen Cycle","context_id":ctx,"action":"withdraw","proposal_reference":reference(&second),"idempotency_key":"withdraw"});
    let third = send(&h.client, "universe_propose", withdraw)
        .await
        .body_json()["result"]
        .clone();
    for prior in [&first, &second, &third] {
        let submit = json!({"universe":"The Ashen Cycle","context_id":ctx,"action":"submit","proposal_reference":reference(prior),"idempotency_key":format!("stale-submit-{}",prior["version"])});
        assert!(h
            .client
            .send(Request::from_tool("universe_propose", submit).unwrap())
            .await
            .is_err());
    }
    // An exact retry remains valid even after later versions exist.
    assert_eq!(
        send(&h.client, "universe_propose", create)
            .await
            .body_json()["result"],
        first
    );
}
#[tokio::test]
async fn capacity_does_not_prevent_receipt_recovery_or_exact_retry() {
    let h = start().await;
    let ctx = context(&h.client, "The Ashen Cycle").await;
    let mut args = valid()[7].1.clone();
    args["context_id"] = json!(ctx);
    let first = send(&h.client, "universe_propose", args.clone())
        .await
        .body_json()["result"]
        .clone();
    for i in 1..256 {
        let mut next = args.clone();
        next["idempotency_key"] = json!(format!("fill-{i}"));
        send(&h.client, "universe_propose", next).await;
    }
    assert_eq!(
        send(&h.client, "universe_propose", args.clone())
            .await
            .body_json()["result"],
        first
    );
    args["idempotency_key"] = json!("over-capacity");
    assert!(h
        .client
        .send(Request::from_tool("universe_propose", args).unwrap())
        .await
        .is_err());
    assert_eq!(
        send(&h.client, "universe_get_operation", valid()[11].1.clone())
            .await
            .body_json()["result"]["proposal"],
        first
    );
}
fn association(n: u64) -> Value {
    serde_json::to_value(universe_domain::records::WorldAssociation {
        world: universe_domain::ids::WorldId::parse(&id("wld", n)).unwrap(),
        role: "setting".into(),
        validity: Default::default(),
        qualifiers: Default::default(),
    })
    .unwrap()
}
#[tokio::test]
async fn selected_world_is_a_write_envelope_not_an_inferred_fact() {
    let h = start().await;
    let ctx = context(&h.client, "The Ashen Cycle").await;
    let mut args = valid()[7].1.clone();
    args["context_id"] = json!(ctx);
    args["world"] = json!("Aster");
    for worlds in [
        vec![],
        vec![association(2)],
        vec![association(1), association(2)],
        vec![association(3)],
    ] {
        args["operations"][0]["record"]["worldAssociations"] = json!(worlds);
        assert!(h
            .client
            .send(Request::from_tool("universe_propose", args.clone()).unwrap())
            .await
            .is_err());
    }
    args["operations"][0]["record"]["worldAssociations"] = json!([association(1)]);
    let proposal = send(&h.client, "universe_propose", args.clone())
        .await
        .body_json()["result"]
        .clone();
    assert_eq!(proposal["world_scope"], id("wld", 1));
    // Adding a matching guard changes no resolved semantic input.
    args["world_id"] = json!(id("wld", 1));
    assert_eq!(
        send(&h.client, "universe_propose", args).await.body_json()["result"],
        proposal
    );
}
#[tokio::test]
async fn unknown_or_foreign_world_associations_are_rejected_even_without_focus() {
    let h = start().await;
    let ctx = context(&h.client, "The Ashen Cycle").await;
    let mut args = valid()[7].1.clone();
    args["context_id"] = json!(ctx);
    for n in [3, 999] {
        args["operations"][0]["record"]["worldAssociations"] = json!([association(n)]);
        assert!(h
            .client
            .send(Request::from_tool("universe_propose", args.clone()).unwrap())
            .await
            .is_err());
    }
    args["operations"][0]["record"]["worldAssociations"] = json!([association(1), association(2)]);
    let p = send(&h.client, "universe_propose", args).await.body_json();
    assert!(p["result"]["world_scope"].is_null());
    assert_eq!(
        p["result"]["operations"][0]["record"]["worldAssociations"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
}

#[tokio::test]
async fn unsupported_views_are_not_returned_as_complete_payloads() {
    let h = start().await;
    let ctx = context(&h.client, "The Ashen Cycle").await;
    let mut get = valid()[3].1.clone();
    get["context_id"] = json!(ctx);
    get["field_groups"] = json!(["history"]);
    let err = h
        .client
        .send(Request::from_tool("universe_get", get).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        universe_client::ClientError::Protocol(
            universe_protocol::ProtocolError::UnsupportedSemantics { .. }
        )
    ));
    let mut create = valid()[7].1.clone();
    create["context_id"] = json!(ctx);
    let proposal = send(&h.client, "universe_propose", create)
        .await
        .body_json()["result"]
        .clone();
    let get = json!({"universe":"The Ashen Cycle","proposal_id":proposal["proposal_id"],"version":proposal["version"],"view_group":"history"});
    let err = h
        .client
        .send(Request::from_tool("universe_get_proposal", get).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        universe_client::ClientError::Protocol(
            universe_protocol::ProtocolError::UnsupportedSemantics { .. }
        )
    ));
}

#[tokio::test]
async fn scoped_edits_cannot_modify_shared_records_or_unproven_effects() {
    let h = start().await;
    let ctx = context(&h.client, "The Ashen Cycle").await;
    let mut args = valid()[7].1.clone();
    args["context_id"] = json!(ctx);
    args["world"] = json!("Aster");
    args["operations"] = json!([{"kind":"tombstone_record","record":{"record":id("rec",10)},"expected_version":id("ver",10),"rationale":"Fixture scope test"}]);
    let err = h
        .client
        .send(Request::from_tool("universe_propose", args.clone()).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        universe_client::ClientError::Protocol(
            universe_protocol::ProtocolError::WorldScopeConflict { .. }
        )
    ));
    args["operations"] = json!([{"kind":"create_world","client_ref":"new_world","record":{"selector":"Another world","aliases":[],"labels":{},"metadata":{}}}]);
    let err = h
        .client
        .send(Request::from_tool("universe_propose", args).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        universe_client::ClientError::Protocol(
            universe_protocol::ProtocolError::UnsupportedSemantics { .. }
        )
    ));
}
