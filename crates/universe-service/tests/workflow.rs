//! Real authenticated transport: exact review/approval, atomic retry and restart.
use serde_json::{json, Value};
use std::{path::Path, time::Duration};
use tokio_util::sync::CancellationToken;
use universe_client::installation::EngineClient;
use universe_domain::ids::*;
use universe_protocol::{
    installation::*,
    request::{ProposalRef, Selector},
    Request,
};
use universe_service::runtime;

/// Mandatory action requirements cannot be omitted or satisfied by another
/// owner. Direct and item-granted attributes share exact pre-event semantics.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn wall_traversal_requires_owning_entity_attributes() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Phase days".into(),
                initial_tick: "0".into(),
                tick_label: "days".into(),
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n| format!("rec_{:024x}", 50000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let clock = c.call(tool("universe_get", json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap();
    let cal = clock["result"]["records"][0]["payload"]["chronology"]["calendar"].clone();
    let scope = json!({"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"universe_wide"}});
    let interval = json!({"kind":"calendar_interval","calendar":cal,"start":{"kind":"exact","value":"10"},"end":{"kind":"exact","value":"20"}});
    let def = |n, key: &str, shape: Value| json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"phase","key":key,"labels":{},"subjectTypes":[],"value":shape,"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}});
    let grant = |n, subject, predicate, value: Value| json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(subject),"predicate":rr(predicate),"value":value,"context":scope["context"],"quantification":"particular"},"assertion":{"proposition":rr(n),"polarity":"support","scope":scope,"validity":interval,"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Declared power/custody for bounded sci-fi test"}}});
    let setup = proposal(&mut c, &ctx, vec![
        entity("Mara", &id(1)), entity("Iven", &id(2)),
        entity("Phase probe", &id(3)), entity("Phase ring", &id(4)),
        entity("Solid wall", &id(5)),
        def(10, "wall_phase", json!({"kind":"boolean"})),
        def(11, "holder", json!({"kind":"entity_ref","subject_types":[]})),
        def(12, "colour", json!({"kind":"text"})),
        grant(26, 1, 12, json!({"kind":"text","text":"blue"})),
        grant(27, 3, 12, json!({"kind":"text","text":"red"})),
        { let mut mute = grant(28, 2, 10, json!({"kind":"boolean","value":true})); mute["assertion"]["polarity"] = json!("refutation"); mute["assertion"]["validity"]["start"]["value"] = json!("13"); mute["assertion"]["validity"]["end"]["value"] = json!("15"); mute },
        json!({"kind":"define_action","client_ref":id(24),"record":{"namespace":"phase","key":"walk_through_wall","labels":{},"requirements":[{"role":"actor","predicate":rr(10),"value":{"kind":"boolean","value":true}}],"scope":scope,"validity":{"kind":"unspecified"}}}),
        json!({"kind":"define_action","client_ref":id(25),"record":{"namespace":"phase","key":"blue_actor_action","labels":{},"requirements":[{"role":"actor","predicate":rr(12),"value":{"kind":"text","text":"blue"}}],"scope":scope,"validity":{"kind":"unspecified"}}}),
        grant(20, 1, 10, json!({"kind":"boolean","value":true})),
        grant(21, 3, 10, json!({"kind":"boolean","value":true})),
        grant(22, 4, 11, json!({"kind":"entity_ref","ref":rr(2)})),
        json!({"kind":"define_item_power","client_ref":id(23),"record":{"item":rr(4),"holderPredicate":rr(11),"powerPredicate":rr(10),"value":{"kind":"boolean","value":true},"scope":scope,"validity":interval}}),
    ], "phase-seed").await;
    publish_proposal(&mut c, &ctx, &setup, "phase-seed-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let requirement = |subject, predicate: &str| json!({"kind":"claim","subject":{"kind":"record","ref":rr(subject)},"predicate":predicate,"value":{"kind":"value","value":{"kind":"boolean","value":true}},"polarity":"support"});
    let crossing = |n, actor, tick, preconditions: Vec<Value>| json!({"kind":"record_event","client_ref":id(n),"record":{"occurrence":"occurred","action":rr(24),"time":{"kind":"exact","calendar":cal,"value":format!("{tick}")},"participants":[{"record":rr(actor),"role":"actor"},{"record":rr(5),"role":"wall"}],"effects":[],"preconditions":preconditions,"labels":{"en":"Walk through solid wall"}}});
    for (n, actor, tick, predicate, allowed) in [
        (30, 1, 11, "phase:wall_phase", true),
        (31, 3, 11, "phase:wall_phase", true),
        (32, 5, 11, "phase:wall_phase", false),
        (33, 1, 21, "phase:wall_phase", false),
        (34, 1, 11, "phase:teleport", false),
        (35, 2, 11, "phase:wall_phase", true),
        (36, 2, 14, "phase:wall_phase", false),
        (37, 2, 16, "phase:wall_phase", true),
        (38, 1, 10, "phase:wall_phase", false),
    ] {
        let p = proposal(
            &mut c,
            &ctx,
            vec![crossing(
                n,
                actor,
                tick,
                vec![requirement(actor, predicate)],
            )],
            &format!("phase-{n}"),
        )
        .await;
        let result = c.call(tool("universe_validate", json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe"}))).await;
        if allowed {
            let v = result.unwrap()["result"]["execution"].clone();
            assert_eq!(v["coverage"], "complete");
            assert!(v["findings"].as_array().unwrap().is_empty());
        } else {
            let error = result.unwrap_err();
            assert!(
                error.to_string().contains("event.preconditions")
                    || error.to_string().contains("event.action.requirements"),
                "{n}: {error}"
            );
        }
    }
    // Both state output and prerequisite validation retain the exact grant
    // chain; only the named ring holder receives its power.
    let at = c.call(tool("universe_open_context", json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":cal,"value":"11"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let state = c.call(tool("universe_get_state", json!({"universe":"Alpha","context_id":at["result"]["context_id"],"entity_ids":[id(2)],"predicate_filters":[id(10)]}))).await.unwrap();
    assert!(state["result"]["derived"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["subject"]["record"] == id(2) && f["rule"] == id(23)));
    // Optional prerequisites cannot substitute another owner's attributes.
    // Nor can deleting the action binding opt out of mandatory admission.
    for (n, conditions) in [(40, vec![]), (41, vec![requirement(1, "phase:wall_phase")])] {
        let p = proposal(
            &mut c,
            &ctx,
            vec![crossing(n, 5, 11, conditions)],
            &format!("phase-gap-{n}"),
        )
        .await;
        let error = c.call(tool("universe_validate", json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe"}))).await.unwrap_err();
        assert!(error.to_string().contains("event.action.requirements"));
    }
    let mut omitted = crossing(42, 5, 11, vec![]);
    omitted["record"].as_object_mut().unwrap().remove("action");
    let p = c.call(tool("universe_propose", json!({"action":"create","universe":"Alpha","context_id":ctx,"operations":[omitted],"submission":"submitted","rationale":"Test omitted action","idempotency_key":"phase-omitted"}))).await.unwrap()["result"].clone();
    let error = c.call(tool("universe_validate", json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe"}))).await.unwrap_err();
    assert!(error.to_string().contains("event.action"));
    assert!(c
        .call(commit(
            &p,
            &json!({"run_id":"val_000000000000000000000001"}),
            "cannot-commit-omitted"
        ))
        .await
        .is_err());
    // Attribute ownership is generic: another entity's blue colour does not
    // authorize a red object, even if an optional condition checks Mara.
    for (n, actor, allowed) in [(43, 1, true), (44, 3, false)] {
        let mut op = crossing(n, actor, 11, vec![]);
        op["record"]["action"] = rr(25);
        let p = proposal(&mut c, &ctx, vec![op], &format!("colour-{n}")).await;
        let result = c.call(tool("universe_validate", json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe"}))).await;
        if allowed {
            assert_eq!(
                result.unwrap()["result"]["execution"]["coverage"],
                "complete"
            );
        } else {
            assert!(result
                .unwrap_err()
                .to_string()
                .contains("event.action.requirements"));
        }
    }
    // A successful owned use becomes canon only after validation/approval/commit.
    let p = proposal(
        &mut c,
        &ctx,
        vec![crossing(45, 2, 16, vec![])],
        "phase-owned-use",
    )
    .await;
    publish_proposal(&mut c, &ctx, &p, "phase-owned-use-commit").await;
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
async fn connect(root: &Path, p: &ProfileId) -> EngineClient {
    for _ in 0..100 {
        if let Ok(c) = EngineClient::connect(root, p, "workflow-test").await {
            return c;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("engine unavailable")
}
fn tool(name: &str, args: Value) -> EngineRequest {
    EngineRequest::Tool {
        request: Box::new(
            serde_json::from_value::<Request>(json!({"tool":name,"args":args})).unwrap(),
        ),
    }
}
fn reference(p: &Value) -> ProposalRef {
    serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap()
}
async fn context(c: &mut EngineClient, u: &Value, name: &str) -> Value {
    c.call(tool("universe_open_context",json!({"universe":name,"continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone()
}
fn world(name: &str, id: &str) -> Value {
    json!({"kind":"create_world","client_ref":id,"record":{"selector":name,"labels":{},"metadata":{}}})
}
fn entity(name: &str, id: &str) -> Value {
    json!({"kind":"create_entity","client_ref":id,"record":{"names":[],"types":[],"worldAssociations":[],"labels":{"en":name},"metadata":{}}})
}
async fn proposal(c: &mut EngineClient, ctx: &Value, ops: Vec<Value>, key: &str) -> Value {
    // Existing fixtures declare ordinary action vocabulary explicitly. The
    // production compiler never fills an omitted action; admission tests below
    // dispatch raw proposals when testing omissions.
    let mut ops = ops;
    if ops
        .iter()
        .any(|o| o["kind"] == "record_event" && o["record"].get("action").is_none())
    {
        let frame = c.call(tool("universe_search", json!({"universe":"Alpha","context_id":ctx,"query":"","typed_filters":{"record_kinds":[]},"limit":1}))).await.unwrap()["frame"].clone();
        let action = RecordId::generate(&mut rand::rng());
        let reference = json!({"universe":frame["universe"],"record":action});
        for op in &mut ops {
            if op["kind"] == "record_event" && op["record"].get("action").is_none() {
                op["record"]["action"] = reference.clone();
            }
        }
        ops.push(json!({"kind":"define_action","client_ref":action,"record":{"namespace":"fixture","key":action,"labels":{},"requirements":[],"scope":{"context":frame["context"],"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unspecified"}}}));
    }
    c.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":ctx,"operations":ops,"submission":"submitted","rationale":"test review","idempotency_key":key}))).await.unwrap()["result"].clone()
}
async fn validate(c: &mut EngineClient, ctx: &Value, p: &Value) -> Value {
    let report = c.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(p),"check_scope":"universe"}))).await.unwrap()["result"].clone();
    if report["kind"] == "restricted" {
        report
    } else {
        report["execution"].clone()
    }
}
fn commit(p: &Value, v: &Value, key: &str) -> EngineRequest {
    tool(
        "universe_commit",
        json!({"universe":"Alpha","proposal_reference":reference(p),"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["run_id"],"idempotency_key":key}),
    )
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn author_agent_review_commit_retry_restart_and_isolation() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut desktop = connect(&root, &author).await;
    let u = desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let beta = desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Beta".into(),
        })
        .await
        .unwrap();
    let agent: ProfileId = serde_json::from_value(
        desktop.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone(),
    )
    .unwrap();
    let grant = GrantSpec {
        profile_id: agent.clone(),
        universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
        worlds: None,
        propose: true,
        edit: true,
        protected: false,
        limits: Default::default(),
    };
    desktop
        .call(EngineRequest::Grant {
            grant: grant.clone(),
        })
        .await
        .unwrap();
    let mut mcp = connect(&root, &agent).await;
    let ctx = context(&mut mcp, &u, "Alpha").await;
    let p = proposal(
        &mut mcp,
        &ctx,
        vec![
            world("Terra", "rec_000000000000000000000011"),
            world("Luna", "rec_000000000000000000000012"),
            entity("Mara", "rec_000000000000000000000013"),
            {let mut traveler=entity("Shared traveler","rec_000000000000000000000014");traveler["record"]["worldAssociations"]=json!([
                {"world":"wld_000000000000000000000011","role":"shared setting","validity":{"kind":"unspecified"},"qualifiers":{}},
                {"world":"wld_000000000000000000000012","role":"shared setting","validity":{"kind":"unspecified"},"qualifiers":{}}
            ]);traveler},
        ],
        "batch",
    )
    .await;
    assert_eq!(p["canonical"], false);
    let v = validate(&mut mcp, &ctx, &p).await;
    assert_eq!(v["coverage"], "complete");
    assert!(mcp.call(commit(&p, &v, "commit")).await.is_err());
    assert!(mcp
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let review = desktop
        .call(EngineRequest::Review {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
        })
        .await
        .unwrap();
    assert_eq!(review["footprint"]["worlds"].as_array().unwrap().len(), 2);
    assert_eq!(review["footprint"]["shared"], true);
    desktop
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    // Revising content invalidates the old exact approval and validation binding.
    let changed=mcp.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"operations":p["operations"],"submission":"submitted","rationale":"Revised review rationale","idempotency_key":"revise"}))).await.unwrap()["result"].clone();
    assert!(mcp.call(commit(&p, &v, "old-approval")).await.is_err());
    assert!(mcp
        .call(commit(&changed, &v, "stale-validation"))
        .await
        .is_err());
    let p = changed;
    let v = validate(&mut mcp, &ctx, &p).await;
    assert!(mcp
        .call(commit(&p, &v, "new-approval-needed"))
        .await
        .is_err());
    desktop
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    // A grant revoked after approval still denies publication.
    let mut no_edit = grant.clone();
    no_edit.edit = false;
    desktop
        .call(EngineRequest::Grant { grant: no_edit })
        .await
        .unwrap();
    assert!(mcp.call(commit(&p, &v, "commit")).await.is_err());
    desktop.call(EngineRequest::Grant { grant }).await.unwrap();
    let receipt = mcp.call(commit(&p, &v, "commit")).await.unwrap()["result"].clone();
    assert_eq!(
        receipt,
        mcp.call(commit(&p, &v, "commit")).await.unwrap()["result"]
    );
    // Withdrawal changes proposal lifecycle, never history, even after the base advanced.
    let withdrawn=mcp.call(tool("universe_propose",json!({"action":"withdraw","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"idempotency_key":"withdraw-after-head-change"}))).await.unwrap()["result"].clone();
    assert_eq!(withdrawn["withdrawn"], true);
    assert_eq!(
        receipt,
        mcp.call(commit(&p, &v, "commit")).await.unwrap()["result"]
    );
    let old=mcp.call(tool("universe_search",json!({"universe":"Alpha","context_id":ctx,"query":"","typed_filters":{"record_kinds":["world"]},"limit":100}))).await.unwrap();
    assert_eq!(old["result"]["hits"], json!([]));
    let current = context(&mut mcp, &u, "Alpha").await;
    let hits=mcp.call(tool("universe_search",json!({"universe":"Alpha","context_id":current,"query":"","typed_filters":{"record_kinds":["world"]},"limit":1}))).await.unwrap();
    let cursor = hits["delivery"]["cursor"].clone();
    assert!(cursor.is_string());
    let next=mcp.call(tool("universe_search",json!({"universe":"Alpha","context_id":current,"query":"","typed_filters":{"record_kinds":["world"]},"limit":1,"cursor":cursor}))).await.unwrap();
    assert_ne!(hits["result"]["hits"], next["result"]["hits"]);
    assert!(mcp.call(tool("universe_search",json!({"universe":"Beta","context_id":current,"query":"","typed_filters":{"record_kinds":[]},"limit":100}))).await.is_err());
    let beta_ctx = context(&mut desktop, &beta, "Beta").await;
    assert_ne!(current, beta_ctx);
    // Identical world names and opaque record IDs remain isolated by universe.
    let beta_proposal=desktop.call(tool("universe_propose",json!({"action":"create","universe":"Beta","context_id":beta_ctx,"operations":[world("Terra","rec_000000000000000000000011")],"submission":"submitted","rationale":"independent world","idempotency_key":"beta-world"}))).await.unwrap()["result"].clone();
    let beta_validation=desktop.call(tool("universe_validate",json!({"mode":"proposal","universe":"Beta","context_id":beta_ctx,"proposal_reference":reference(&beta_proposal),"check_scope":"universe"}))).await.unwrap()["result"]["execution"].clone();
    desktop
        .call(EngineRequest::Approve {
            universe: Selector("Beta".into()),
            proposal_reference: reference(&beta_proposal),
            validation_run: serde_json::from_value(beta_validation["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    desktop.call(tool("universe_commit",json!({"universe":"Beta","proposal_reference":reference(&beta_proposal),"expected_base_revision":beta_proposal["base_frame"]["revision"],"validation_run":beta_validation["run_id"],"idempotency_key":"beta-commit"}))).await.unwrap();
    let beta_current = context(&mut desktop, &beta, "Beta").await;
    let beta_worlds=desktop.call(tool("universe_search",json!({"universe":"Beta","context_id":beta_current,"query":"Terra","typed_filters":{"record_kinds":["world"]},"limit":100}))).await.unwrap();
    assert_eq!(beta_worlds["result"]["hits"].as_array().unwrap().len(), 1);
    assert_eq!(beta_worlds["universe_id"], beta["universe_id"]);

    // Invalid dependency in a cross-world batch cannot publish either world.
    let mut bad = entity("bad", "rec_000000000000000000000031");
    bad["record"]["types"] = json!(["rec_000000000000000000000099"]);
    assert!(mcp.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":current,"operations":[world("Third","rec_000000000000000000000030"),bad],"submission":"submitted","rationale":"invalid dependency","idempotency_key":"bad"}))).await.is_err());
    drop(mcp);
    drop(desktop);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut mcp = connect(&root, &agent).await;
    assert_eq!(
        receipt,
        mcp.call(commit(&p, &v, "commit")).await.unwrap()["result"]
    );
    let op=mcp.call(tool("universe_get_operation",json!({"lookup":"key","universe":"Alpha","operation_kind":"commit","idempotency_key":"commit"}))).await.unwrap();
    assert_eq!(op["result"]["state"], "succeeded");
    assert_eq!(op["result"]["receipt"], receipt);
    let new_ctx = context(&mut mcp, &u, "Alpha").await;
    let hits=mcp.call(tool("universe_search",json!({"universe":"Alpha","context_id":new_ctx,"query":"","typed_filters":{"record_kinds":["world"]},"limit":100}))).await.unwrap();
    assert_eq!(hits["result"]["hits"].as_array().unwrap().len(), 2);
    drop(mcp);
    stop.cancel();
    server.await.unwrap().unwrap();
}
async fn admit(author: &mut EngineClient, ctx: &Value, ops: Vec<Value>, key: &str) -> Value {
    let p = proposal(author, ctx, ops, key).await;
    let v = validate(author, ctx, &p).await;
    author
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    author.call(commit(&p, &v, key)).await.unwrap()["result"].clone()
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn utf8_sources_and_verified_backup_restore_keep_history() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("first");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut desktop = connect(&root, &author).await;
    let u = desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut desktop, &u, "Alpha").await;
    let text = "Mara — café 👩🏽‍🚀\n";
    let staged = desktop
        .call(EngineRequest::StageSource {
            universe: Selector("Alpha".into()),
            label: "Notebook".into(),
            text: text.into(),
        })
        .await
        .unwrap();
    assert_eq!(staged["canonical"], false);
    let ops: Vec<Value> = serde_json::from_value(staged["operations"].clone()).unwrap();
    let source_version_id = ops[1]["client_ref"].clone();
    let source_receipt = admit(&mut desktop, &ctx, ops, "source").await;
    let current = context(&mut desktop, &u, "Alpha").await;
    let source=desktop.call(tool("universe_get",json!({"universe":"Alpha","context_id":current,"record_ids":[source_version_id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0].clone();
    use sha2::{Digest, Sha256};
    let excerpt = "café";
    let start = text.find(excerpt).unwrap();
    let anchor = json!({"kind":"add_source_anchor","client_ref":"anchor","record":{"sourceVersion":{"universe":u["universe_id"],"record":source["identity"]["record_id"],"version":source["record_version_id"]},"locator":{"kind":"byte_range","start":start,"end":start+excerpt.len()},"excerptDigest":hex::encode(Sha256::digest(excerpt.as_bytes())),"excerpt":excerpt,"context":null}});
    let anchor_receipt = admit(&mut desktop, &current, vec![anchor.clone()], "anchor").await;
    let latest = context(&mut desktop, &u, "Alpha").await;
    let mut bad = anchor;
    bad["client_ref"] = json!("broken-anchor");
    bad["record"]["locator"]["end"] = json!(start + excerpt.len() - 1);
    let p = proposal(&mut desktop, &latest, vec![bad], "bad-anchor").await;
    assert!(desktop.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":latest,"proposal_reference":reference(&p),"check_scope":"universe"}))).await.is_err());
    let backup = dir.path().join("whole.sqlite");
    desktop
        .call(EngineRequest::Backup {
            universe: Selector("Alpha".into()),
            destination: backup.clone(),
        })
        .await
        .unwrap();
    assert!(desktop
        .call(EngineRequest::Backup {
            universe: Selector("Alpha".into()),
            destination: backup.clone()
        })
        .await
        .is_err());
    let second = dir.path().join("second");
    let author2 = runtime::initialize(&second).unwrap();
    let stop2 = CancellationToken::new();
    let (r, s) = (second.clone(), stop2.clone());
    let server2 = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut restored = connect(&second, &author2).await;
    restored
        .call(EngineRequest::Restore {
            source: backup,
            name: "Restored".into(),
        })
        .await
        .unwrap();
    let library = restored
        .call(EngineRequest::Library {
            universe: Selector("Restored".into()),
        })
        .await
        .unwrap();
    assert_eq!(
        library["storage"]["heads"][0][1],
        anchor_receipt["revision"]
    );
    let old=restored.call(tool("universe_open_context",json!({"universe":"Restored","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":source_receipt["revision"]},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let fetched=restored.call(tool("universe_get",json!({"universe":"Restored","context_id":old["result"]["context_id"],"record_ids":[source_version_id],"field_groups":["payload"]}))).await.unwrap();
    assert_eq!(fetched["result"]["records"][0], source);
    drop(restored);
    stop2.cancel();
    server2.await.unwrap().unwrap();
    drop(desktop);
    stop.cancel();
    server.await.unwrap().unwrap();
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn basic_prerequisite_and_conflicting_evidence_block_admission() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("rules");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut desktop = connect(&root, &author).await;
    let u = desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut desktop, &u, "Alpha").await;
    let gate = "rec_000000000000000000000041";
    let property = "rec_000000000000000000000042";
    let rule = "rec_000000000000000000000043";
    let proposition = "rec_000000000000000000000044";
    let record_ref = |id: Value| json!({"universe":u["universe_id"],"record":id});
    let property_op = json!({"kind":"define_property","client_ref":property,"record":{"namespace":"gate","key":"open","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","unitDimension":null,"persistence":"unspecified","exclusive":true,"inverse":null,"symmetric":false,"transitive":false}});
    let rule_op = json!({"kind":"define_rule","client_ref":rule,"record":{"namespace":"gate","key":"must-open","labels":{},"kind":"structural_invariant","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":["gate:open"],"expression":{"kind":"claim","subject":{"kind":"record","ref":record_ref(json!(gate))},"predicate":"gate:open","roles":[],"value":{"kind":"value","value":{"kind":"boolean","value":true}},"polarity":"support"},"capabilities":[],"executable":true,"validity":{"kind":"unspecified"}}});
    let base = vec![entity("Silver gate", gate), property_op, rule_op];
    let p = proposal(&mut desktop, &ctx, base.clone(), "missing-prerequisite").await;
    let v = validate(&mut desktop, &ctx, &p).await;
    assert_eq!(v["findings"][0]["outcome"], "not_established");
    assert!(desktop
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let claim = json!({"kind":"assert_proposition","client_ref":proposition,"proposition":{"predicate":record_ref(json!(property)),"subject":record_ref(json!(gate)),"roles":[],"value":{"kind":"boolean","value":true},"quantification":"particular","context":record_ref(u["context_id"].clone())},"assertion":{"proposition":record_ref(json!(proposition)),"polarity":"support","scope":{"applicability":{"kind":"universe_wide"},"context":record_ref(u["context_id"].clone())},"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","alternatives":[],"basis":{"kind":"author_decision","note":"open gate"}}});
    let mut supported = base.clone();
    supported.push(claim.clone());
    assert!(desktop.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":ctx,"operations":supported,"submission":"submitted","rationale":"Must not reassign reserved identities","idempotency_key":"collision"}))).await.is_err());
    let p = desktop.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"operations":supported,"submission":"submitted","rationale":"Add the missing prerequisite","idempotency_key":"supported-prerequisite"}))).await.unwrap()["result"].clone();
    let v = validate(&mut desktop, &ctx, &p).await;
    assert_eq!(v["findings"][0]["outcome"], "supported");
    assert_eq!(v["coverage"], "complete");
    let mut refutation = claim;
    refutation["client_ref"] = json!("rec_000000000000000000000045");
    refutation["assertion"]["proposition"] = record_ref(json!("rec_000000000000000000000045"));
    refutation["assertion"]["polarity"] = json!("refutation");
    supported.push(refutation);
    let p = desktop.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"operations":supported,"submission":"submitted","rationale":"Preserve opposing evidence","idempotency_key":"conflicting-prerequisite"}))).await.unwrap()["result"].clone();
    let v = validate(&mut desktop, &ctx, &p).await;
    assert_eq!(v["findings"][0]["outcome"], "conflicting");
    assert_eq!(v["findings"][0]["evidence"].as_array().unwrap().len(), 2);
    assert!(desktop
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    drop(desktop);
    stop.cancel();
    server.await.unwrap().unwrap();
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn fixed_author_boundary_blocks_edits_without_blocking_its_own_creation() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("boundaries");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut desktop = connect(&root, &author).await;
    let u = desktop
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut desktop, &u, "Alpha").await;
    let id = "rec_000000000000000000000061";
    admit(
        &mut desktop,
        &ctx,
        vec![entity("Fixed character", id)],
        "character",
    )
    .await;
    let ctx = context(&mut desktop, &u, "Alpha").await;
    let boundary = json!({"kind":"set_creative_boundary","client_ref":"boundary","record":{"key":"fixed-character","area":{"kind":"record","universe":u["universe_id"],"record":id},"mode":"fixed","constraints":[],"validity":{"kind":"unspecified"},"scope":{"applicability":{"kind":"universe_wide"},"context":{"universe":u["universe_id"],"record":u["context_id"]}}}});
    admit(&mut desktop, &ctx, vec![boundary], "fixed").await;
    let ctx = context(&mut desktop, &u, "Alpha").await;
    let entity=desktop.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0].clone();
    let edit = json!({"kind":"add_name","record":{"universe":u["universe_id"],"record":id},"expected_version":entity["record_version_id"],"name":{"text":"Changed","language":null,"community":null,"role":null,"validity":{"kind":"unspecified"}}});
    let p = proposal(&mut desktop, &ctx, vec![edit], "blocked-edit").await;
    let v = validate(&mut desktop, &ctx, &p).await;
    assert_eq!(v["findings"][0]["outcome"], "refuted");
    assert!(desktop
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    drop(desktop);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn drafts_survive_restart_without_canon_and_reject_cross_window_overwrites() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let alpha = client
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let beta = client
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Beta".into(),
        })
        .await
        .unwrap();
    let continuity: ContinuityId = serde_json::from_value(alpha["continuity_id"].clone()).unwrap();
    let load = EngineRequest::LoadDraft {
        universe: Selector("Alpha".into()),
        continuity_id: continuity.clone(),
    };
    assert_eq!(client.call(load.clone()).await.unwrap(), Value::Null);
    let content = DraftContent {
        proposal: None,
        base_revision: serde_json::from_value(alpha["revision"].clone()).unwrap(),
        represented_context: serde_json::from_value(alpha["context_id"].clone()).unwrap(),
        operations: "[{ unfinished café".into(),
        rationale: "still editing".into(),
    };
    let save = EngineRequest::SaveDraft {
        universe: Selector("Alpha".into()),
        continuity_id: continuity.clone(),
        expected_version: 0,
        content: content.clone(),
    };
    let first = client.call(save.clone()).await.unwrap();
    assert_eq!(first["version"], 1);
    assert_eq!(client.call(save.clone()).await.unwrap(), first); // lost-response retry
    let mut other = content.clone();
    other.operations = "[]".into();
    assert!(client
        .call(EngineRequest::SaveDraft {
            universe: Selector("Alpha".into()),
            continuity_id: continuity.clone(),
            expected_version: 0,
            content: other.clone()
        })
        .await
        .is_err());
    assert_eq!(client.call(load.clone()).await.unwrap(), first);
    let agent: ProfileId = serde_json::from_value(
        client.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone(),
    )
    .unwrap();
    client
        .call(EngineRequest::Grant {
            grant: GrantSpec {
                profile_id: agent.clone(),
                universe_id: serde_json::from_value(alpha["universe_id"].clone()).unwrap(),
                worlds: None,
                propose: true,
                edit: true,
                protected: false,
                limits: Default::default(),
            },
        })
        .await
        .unwrap();
    let mut agent_client = connect(&root, &agent).await;
    assert!(agent_client.call(load.clone()).await.is_err());
    assert!(agent_client.call(save).await.is_err());
    assert!(client
        .call(EngineRequest::LoadDraft {
            universe: Selector("Beta".into()),
            continuity_id: continuity.clone()
        })
        .await
        .is_err());
    assert_eq!(
        client
            .call(EngineRequest::LoadDraft {
                universe: Selector("Beta".into()),
                continuity_id: serde_json::from_value(beta["continuity_id"].clone()).unwrap()
            })
            .await
            .unwrap(),
        Value::Null
    );
    let library = client
        .call(EngineRequest::Library {
            universe: Selector("Alpha".into()),
        })
        .await
        .unwrap();
    assert_eq!(library["storage"]["heads"][0][1], alpha["revision"]);
    drop(client);
    drop(agent_client);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    assert_eq!(client.call(load).await.unwrap(), first);
    let second = client
        .call(EngineRequest::SaveDraft {
            universe: Selector("Alpha".into()),
            continuity_id: continuity,
            expected_version: 1,
            content: other,
        })
        .await
        .unwrap();
    assert_eq!(second["version"], 2);
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
}

async fn publish_proposal(client: &mut EngineClient, ctx: &Value, p: &Value, key: &str) -> Value {
    let v = validate(client, ctx, p).await;
    client
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    client.call(commit(p, &v, key)).await.unwrap()["result"].clone()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn recovered_submitted_draft_revises_its_reserved_ids_and_invalidates_approval() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let u = client
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Gregorian {
                timestamp: "2040-01-02T03:04:05Z".into(),
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut client, &u, "Alpha").await;
    let operations = vec![entity("Lantern", "rec_000000000000000000000991")];
    let p = proposal(&mut client, &ctx, operations.clone(), "first-draft").await;
    let v = validate(&mut client, &ctx, &p).await;
    client
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    let continuity = serde_json::from_value(u["continuity_id"].clone()).unwrap();
    client
        .call(EngineRequest::SaveDraft {
            universe: Selector("Alpha".into()),
            continuity_id: continuity,
            expected_version: 0,
            content: DraftContent {
                proposal: Some(reference(&p)),
                base_revision: serde_json::from_value(u["revision"].clone()).unwrap(),
                represented_context: serde_json::from_value(u["context_id"].clone()).unwrap(),
                operations: serde_json::to_string(&operations).unwrap(),
                rationale: "Lantern".into(),
            },
        })
        .await
        .unwrap();
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let saved = client
        .call(EngineRequest::LoadDraft {
            universe: Selector("Alpha".into()),
            continuity_id: serde_json::from_value(u["continuity_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    let content: DraftContent = serde_json::from_value(saved["content"].clone()).unwrap();
    assert_eq!(content.proposal, Some(reference(&p)));
    let ctx = context(&mut client, &u, "Alpha").await;
    let mut revised: Vec<Value> = serde_json::from_str(&content.operations).unwrap();
    revised[0]["record"]["labels"]["en"] = json!("Blue Lantern");
    let next=client.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":content.proposal,"operations":revised,"submission":"submitted","rationale":"Edited after restart","idempotency_key":"second-draft"}))).await.unwrap()["result"].clone();
    assert_eq!(next["proposal_id"], p["proposal_id"]);
    assert_eq!(next["version"], 2);
    assert!(client
        .call(commit(&p, &v, "old-approval-denied"))
        .await
        .is_err());
    publish_proposal(&mut client, &ctx, &next, "new-draft-publish").await;
    let ctx = context(&mut client, &u, "Alpha").await;
    let read=client.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":["rec_000000000000000000000991"],"field_groups":[]}))).await.unwrap();
    let entity = &read["result"]["records"][0];
    assert_eq!(entity["payload"]["labels"]["en"], "Blue Lantern");
    // An assertion-specific edit must never delete an entity.
    assert!(client.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":ctx,"operations":[{"kind":"retract_assertion","record":{"universe":u["universe_id"],"record":entity["identity"]["record_id"]},"expected_version":entity["record_version_id"],"rationale":"wrong kind"}],"submission":"submitted","rationale":"wrong kind","idempotency_key":"wrong-kind-retraction"}))).await.is_err());
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn contextual_search_saga_updates_dependency_briefs_and_cancel_keys() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let u = client
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut client, &u, "Alpha").await;
    let rr = |id: &str| json!({"universe":u["universe_id"],"record":id});
    let mut named = entity("Traveler", "rec_000000000000000000000081");
    named["record"]["names"] = json!([{"text":"Étoile du matin","language":"fr","community":null,"role":null,"validity":{"kind":"unspecified"}}]);
    let work = json!({"kind":"create_work","client_ref":"rec_000000000000000000000082","record":{"kind":"novel","title":"Across the Sea","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[{"world":"wld_000000000000000000000084","role":"setting","validity":{"kind":"unspecified"},"qualifiers":{}}]}});
    let saga = json!({"kind":"create_saga","client_ref":"rec_000000000000000000000083","record":{"title":"Voyages","labels":{},"memberships":[{"work":rr("rec_000000000000000000000082"),"role":"volume","order":null}]}});
    let p = proposal(
        &mut client,
        &ctx,
        vec![
            named,
            work,
            saga,
            world("Sea", "rec_000000000000000000000084"),
        ],
        "seed-research",
    )
    .await;
    let receipt = publish_proposal(&mut client, &ctx, &p, "publish-research").await;
    let pinned = context(&mut client, &u, "Alpha").await;
    let query = |context: &Value, term: &str| {
        tool(
            "universe_search",
            json!({"universe":"Alpha","context_id":context,"query":term,"typed_filters":{"record_kinds":["entity"]},"limit":10}),
        )
    };
    assert!(
        client.call(query(&ctx, "etoile")).await.unwrap()["result"]["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    let hits = client.call(query(&pinned, "etoile")).await.unwrap(); // FTS Unicode diacritic matching
    assert_eq!(
        hits["result"]["hits"][0]["record_id"],
        "rec_000000000000000000000081"
    );
    assert_eq!(
        client.call(query(&pinned, "DU MATIN")).await.unwrap()["result"]["hits"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let brief=client.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":pinned,"focus_ids":["rec_000000000000000000000083"],"purpose":"Inspect saga membership","byte_budget":65536}))).await.unwrap();
    assert_eq!(brief["result"]["coverage"], "complete");
    assert!(brief["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["identity"]["record_id"] == "rec_000000000000000000000082"));
    assert!(brief["result"]["required_dependencies"]
        .as_array()
        .unwrap()
        .contains(&json!("rec_000000000000000000000084")));
    let small=client.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":pinned,"focus_ids":["rec_000000000000000000000083"],"purpose":"Small brief","byte_budget":256}))).await.unwrap_err();
    assert!(small.to_string().contains("budget"));
    let records=client.call(tool("universe_get",json!({"universe":"Alpha","context_id":pinned,"record_ids":["rec_000000000000000000000083"],"field_groups":["payload"]}))).await.unwrap();
    let saga = &records["result"]["records"][0];
    let edit = json!({"kind":"set_saga_membership","record":rr("rec_000000000000000000000083"),"expected_version":saga["record_version_id"],"membership":{"work":rr("rec_000000000000000000000082"),"role":"volume","order":2}});
    let p2 = proposal(&mut client, &pinned, vec![edit], "order-saga").await;
    let review = client
        .call(EngineRequest::Review {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p2),
        })
        .await
        .unwrap();
    assert_eq!(
        review["footprint"]["worlds"],
        json!(["wld_000000000000000000000084"])
    );
    assert_eq!(
        review["changes"][0]["next"]["payload"]["memberships"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    publish_proposal(&mut client, &pinned, &p2, "publish-order").await;
    let cancel = tool(
        "universe_cancel_operation",
        json!({"universe":"Alpha","operation_id":receipt["operation_id"],"idempotency_key":"cancel-one"}),
    );
    let cancelled = client.call(cancel.clone()).await.unwrap()["result"].clone();
    assert_eq!(cancelled["state"], "succeeded");
    assert_eq!(client.call(cancel).await.unwrap()["result"], cancelled);
    let other=client.call(tool("universe_get_operation",json!({"lookup":"key","universe":"Alpha","operation_kind":"propose","idempotency_key":"order-saga"}))).await.unwrap();
    assert!(client.call(tool("universe_cancel_operation",json!({"universe":"Alpha","operation_id":other["result"]["operation_id"],"idempotency_key":"cancel-one"}))).await.is_err());
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn restored_proposals_require_approval_from_the_current_installation_author() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("source-install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let u = client
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut client, &u, "Alpha").await;
    let p = proposal(
        &mut client,
        &ctx,
        vec![entity("Pending traveler", "rec_000000000000000000000099")],
        "pending",
    )
    .await;
    let v = validate(&mut client, &ctx, &p).await;
    let approve = EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference(&p),
        validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
    };
    client.call(approve.clone()).await.unwrap();
    let backup = dir.path().join("universe.sqlite");
    client
        .call(EngineRequest::Backup {
            universe: Selector("Alpha".into()),
            destination: backup.clone(),
        })
        .await
        .unwrap();
    let restored = dir.path().join("restored-install");
    let new_author = runtime::initialize(&restored).unwrap();
    assert_ne!(author, new_author);
    let stop2 = CancellationToken::new();
    let (r, s) = (restored.clone(), stop2.clone());
    let server2 = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut current = connect(&restored, &new_author).await;
    current
        .call(EngineRequest::Restore {
            source: backup,
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let denied = current
        .call(commit(&p, &v, "restored-commit"))
        .await
        .unwrap_err();
    assert!(denied.to_string().contains("approval required"));
    let library = current
        .call(EngineRequest::Library {
            universe: Selector("Alpha".into()),
        })
        .await
        .unwrap();
    assert_eq!(library["storage"]["heads"][0][1], u["revision"]);
    current.call(approve).await.unwrap();
    let result = current
        .call(commit(&p, &v, "restored-commit"))
        .await
        .unwrap();
    assert_ne!(result["result"]["revision"], u["revision"]);
    drop(current);
    stop2.cancel();
    server2.await.unwrap().unwrap();
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn logical_archives_preview_clone_history_sources_and_filtered_dependencies() {
    use sha2::{Digest, Sha256};
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let u = client
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut client, &u, "Alpha").await;
    let source = client
        .call(EngineRequest::StageSource {
            universe: Selector("Alpha".into()),
            label: "Archive source".into(),
            text: "café 🌕".into(),
        })
        .await
        .unwrap();
    let ops = source["operations"].as_array().unwrap().clone();
    let source_receipt = admit(&mut client, &ctx, ops, "archive-source").await;
    let ctx = context(&mut client, &u, "Alpha").await;
    let source_id = source["operations"][1]["client_ref"].clone();
    let record=client.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[source_id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0].clone();
    let anchor_id = "rec_0000000000000000000000aa";
    let anchor = json!({"kind":"add_source_anchor","client_ref":anchor_id,"record":{"sourceVersion":{"universe":u["universe_id"],"record":source_id,"version":record["record_version_id"]},"locator":{"kind":"byte_range","start":0,"end":5},"excerpt":"café","excerptDigest":hex::encode(Sha256::digest("café".as_bytes()))}});
    admit(
        &mut client,
        &ctx,
        vec![
            anchor,
            entity("Omitted character", "rec_0000000000000000000000ab"),
        ],
        "archive-anchor",
    )
    .await;
    let whole = dir.path().join("whole.jsonl");
    let exported = client
        .call(EngineRequest::ExportLogical {
            universe: Selector("Alpha".into()),
            destination: whole.clone(),
            record_ids: vec![],
        })
        .await
        .unwrap();
    assert_eq!(exported["complete"], true);
    assert_eq!(exported["includes_workflow"], false);
    // Backup and collection share the sole writer queue; all retention roots survive.
    let mut backup_client = connect(&root, &author).await;
    let mut maintenance_client = connect(&root, &author).await;
    let backup_path = dir.path().join("retained.sqlite");
    let (backup, maintenance) = tokio::join!(
        backup_client.call(EngineRequest::Backup {
            universe: Selector("Alpha".into()),
            destination: backup_path.clone()
        }),
        maintenance_client.call(EngineRequest::Maintain {
            universe: Selector("Alpha".into()),
            collect: true
        })
    );
    backup.unwrap();
    let maintenance = maintenance.unwrap();
    assert_eq!(maintenance["retained_source_assets"], 1);
    assert_eq!(maintenance["source_assets_collected"], 0);
    let second = dir.path().join("after-maintenance.jsonl");
    client
        .call(EngineRequest::ExportLogical {
            universe: Selector("Alpha".into()),
            destination: second.clone(),
            record_ids: vec![],
        })
        .await
        .unwrap();
    assert_eq!(
        std::fs::read(&whole).unwrap(),
        std::fs::read(second).unwrap()
    );
    let backed = universe_store::kernel::Kernel::open(&backup_path).unwrap();
    assert_eq!(
        backed.universe().as_str(),
        u["universe_id"].as_str().unwrap()
    );
    drop(backed);
    drop(backup_client);
    drop(maintenance_client);

    assert!(client
        .call(EngineRequest::ExportLogical {
            universe: Selector("Alpha".into()),
            destination: whole.clone(),
            record_ids: vec![]
        })
        .await
        .is_err());
    let conflict = client
        .call(EngineRequest::PreviewImport {
            source: whole.clone(),
            name: "Conflicted".into(),
            mode: ImportMode::Restore,
        })
        .await
        .unwrap();
    assert!(!conflict["conflicts"].as_array().unwrap().is_empty());
    {
        let archive = universe_store::kernel::LogicalArchive::read(&whole).unwrap();
        let _stage = archive
            .stage(
                dir.path(),
                UniverseId::generate(&mut rand::rng()),
                "Direct clone",
            )
            .unwrap();
    }
    let preview = client
        .call(EngineRequest::PreviewImport {
            source: whole.clone(),
            name: "Clone".into(),
            mode: ImportMode::Clone,
        })
        .await
        .unwrap();
    assert!(preview["conflicts"].as_array().unwrap().is_empty());
    assert_eq!(
        client.call(EngineRequest::Status).await.unwrap()["universes"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let accept = EngineRequest::AcceptImport {
        preview_id: serde_json::from_value(preview["preview_id"].clone()).unwrap(),
        digest: preview["digest"].as_str().unwrap().into(),
    };
    assert!(client
        .call(EngineRequest::AcceptImport {
            preview_id: serde_json::from_value(preview["preview_id"].clone()).unwrap(),
            digest: "different".into()
        })
        .await
        .is_err());
    let imported = client.call(accept.clone()).await.unwrap();
    assert_eq!(client.call(accept).await.unwrap(), imported);
    let cloned_ctx = context(&mut client, &u, "Clone").await;
    let cloned=client.call(tool("universe_get",json!({"universe":"Clone","context_id":cloned_ctx,"record_ids":[anchor_id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0].clone();
    assert_eq!(cloned["payload"]["excerpt"], "café");
    assert_eq!(
        cloned["payload"]["sourceVersion"]["universe"],
        preview["target_universe"]
    );
    let historical=client.call(tool("universe_open_context",json!({"universe":"Clone","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":source_receipt["revision"]},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    assert!(client.call(tool("universe_get",json!({"universe":"Clone","context_id":historical["result"]["context_id"],"record_ids":[anchor_id],"field_groups":["payload"]}))).await.is_err());
    let partial = dir.path().join("partial.jsonl");
    let manifest = client
        .call(EngineRequest::ExportLogical {
            universe: Selector("Alpha".into()),
            destination: partial.clone(),
            record_ids: vec![RecordId::parse(anchor_id).unwrap()],
        })
        .await
        .unwrap();
    assert_eq!(manifest["complete"], false);
    assert_eq!(manifest["omitted_records"], 1);
    assert!(client
        .call(EngineRequest::PreviewImport {
            source: partial.clone(),
            name: "Partial restore".into(),
            mode: ImportMode::Restore
        })
        .await
        .is_err());
    let partial_preview = client
        .call(EngineRequest::PreviewImport {
            source: partial.clone(),
            name: "Partial".into(),
            mode: ImportMode::Clone,
        })
        .await
        .unwrap();
    client
        .call(EngineRequest::AcceptImport {
            preview_id: serde_json::from_value(partial_preview["preview_id"].clone()).unwrap(),
            digest: partial_preview["digest"].as_str().unwrap().into(),
        })
        .await
        .unwrap();
    let partial_ctx = context(&mut client, &u, "Partial").await;
    assert!(client.call(tool("universe_get",json!({"universe":"Partial","context_id":partial_ctx,"record_ids":[source_id,anchor_id],"field_groups":["payload"]}))).await.is_ok());
    assert!(client.call(tool("universe_get",json!({"universe":"Partial","context_id":partial_ctx,"record_ids":["rec_0000000000000000000000ab"],"field_groups":["payload"]}))).await.is_err());
    // Even an internally consistent checksum cannot hide a missing source asset.
    let original = std::fs::read_to_string(&whole).unwrap();
    let rows: Vec<Value> = original
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .filter(|r: &Value| r["entry"] != "text" && r["entry"] != "checksum")
        .collect();
    let mut malformed = rows
        .iter()
        .map(|r| serde_json::to_string(r).unwrap() + "\n")
        .collect::<String>();
    let digest = hex::encode(Sha256::digest(malformed.as_bytes()));
    malformed.push_str(
        &(serde_json::to_string(&json!({"entry":"checksum","sha256":digest,"rows":rows.len()}))
            .unwrap()
            + "\n"),
    );
    std::fs::write(&whole, malformed).unwrap();
    assert!(client
        .call(EngineRequest::PreviewImport {
            source: whole,
            name: "Missing asset".into(),
            mode: ImportMode::Clone
        })
        .await
        .is_err());
    drop(client);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn authored_clock_state_boundaries_end_assertion_and_pinned_history() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut client = connect(&root, &author).await;
    let u = client
        .call(EngineRequest::CreateUniverse {
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Test clock".into(),
                initial_tick: "0".into(),
                tick_label: "ticks".into(),
                ticks_per_month: None,
            },
            name: "Alpha".into(),
        })
        .await
        .unwrap();
    let ctx = context(&mut client, &u, "Alpha").await;
    let rr = |id: &str| json!({"universe":u["universe_id"],"record":id});
    let entity_id = "rec_000000000000000000000101";
    let prop = "rec_000000000000000000000102";
    let clock = "cal_000000000000000000000103";
    let claim = |id: &str, text: &str, start: &str, end: &str, polarity: &str| json!({"kind":"assert_proposition","client_ref":id,"proposition":{"subject":rr(entity_id),"predicate":rr(prop),"value":{"kind":"text","text":text},"quantification":"particular","context":rr(u["context_id"].as_str().unwrap())},"assertion":{"proposition":rr(id),"polarity":polarity,"scope":{"applicability":{"kind":"universe_wide"},"context":rr(u["context_id"].as_str().unwrap())},"validity":{"kind":"calendar_interval","calendar":clock,"start":{"kind":"exact","value":start},"end":{"kind":"exact","value":end}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored intervals"}}});
    let p=proposal(&mut client,&ctx,vec![entity("Traveler",entity_id),json!({"kind":"define_property","client_ref":prop,"record":{"namespace":"story","key":"light","labels":{},"value":{"kind":"text"},"multiplicity":"single","subjectTypes":[],"persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}}),json!({"kind":"define_calendar","client_ref":"rec_000000000000000000000103","record":{"namespace":"story","key":"days","labels":{},"unitStructure":{},"conversions":[]}}),claim("rec_000000000000000000000104","lamp","0","10","support"),claim("rec_000000000000000000000105","torch","10","20","support"),claim("rec_000000000000000000000106","torch","10","20","refutation")],"time-seed").await;
    let validation = validate(&mut client, &ctx, &p).await;
    assert_eq!(validation["coverage"], "complete");
    client
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(validation["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    client
        .call(commit(&p, &validation, "time-commit"))
        .await
        .unwrap();
    let mut pinned = Value::Null;
    let mut target = Value::Null;
    for (tick, count) in [(0, 1), (9, 1), (10, 2), (19, 2), (20, 0)] {
        let opened=client.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":tick.to_string()}},"temporal_systems":[clock],"perspective":"author"}))).await.unwrap();
        let state=client.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"entity_ids":[entity_id],"predicate_filters":[]}))).await.unwrap();
        assert_eq!(
            state["result"]["assertions"].as_array().unwrap().len(),
            count,
            "tick {tick}"
        );
        if tick == 19 {
            pinned = opened["result"]["context_id"].clone();
            target = state["result"]["assertions"]
                .as_array()
                .unwrap()
                .iter()
                .find(|a| a["payload"]["polarity"] == "support")
                .unwrap()
                .clone();
        }
    }
    // A time-sliced research context cannot narrow commit validation.
    assert!(client.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":pinned,"operations":[entity("No slice write","rec_000000000000000000000107")],"submission":"submitted","rationale":"test","idempotency_key":"time-slice-denied"}))).await.is_err());
    let ctx = context(&mut client, &u, "Alpha").await;
    let end = json!({"kind":"end_assertion_at","record":rr(target["identity"]["record_id"].as_str().unwrap()),"expected_version":target["record_version_id"],"at":{"kind":"exact","calendar":clock,"value":"15"},"basis":{"kind":"author_decision","note":"Light ended"}});
    let p = proposal(&mut client, &ctx, vec![end], "time-end").await;
    let v = validate(&mut client, &ctx, &p).await;
    client
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    client
        .call(commit(&p, &v, "time-end-commit"))
        .await
        .unwrap();
    let old=client.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":pinned,"entity_ids":[entity_id],"predicate_filters":[]}))).await.unwrap();
    assert_eq!(old["result"]["assertions"].as_array().unwrap().len(), 2);
    let latest=client.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":"15"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let now=client.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":latest["result"]["context_id"],"entity_ids":[entity_id],"predicate_filters":[]}))).await.unwrap();
    assert_eq!(now["result"]["assertions"].as_array().unwrap().len(), 1);
    assert_eq!(
        now["result"]["assertions"][0]["payload"]["polarity"],
        "refutation"
    );

    // Ordinary record edits never advance story time; changes are explicit and versioned.
    assert_eq!(now["result"]["chronology"]["current"], "0");
    for (step, next, mode) in [("elapsed", "4", "elapsed"), ("travel", "2", "time_travel")] {
        let ctx = context(&mut client, &u, "Alpha").await;
        let read=client.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap();
        let record = &read["result"]["records"][0];
        let op = json!({"kind":"set_story_time","record":rr(u["context_id"].as_str().unwrap()),"expected_version":record["record_version_id"],"value":next,"mode":mode,"reason":"Author deliberately moves story time"});
        let p = proposal(&mut client, &ctx, vec![op], step).await;
        let v = validate(&mut client, &ctx, &p).await;
        client
            .call(EngineRequest::Approve {
                universe: Selector("Alpha".into()),
                proposal_reference: reference(&p),
                validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
            })
            .await
            .unwrap();
        client
            .call(commit(&p, &v, &format!("commit-{step}")))
            .await
            .unwrap();
        let current = context(&mut client, &u, "Alpha").await;
        let state=client.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":current,"entity_ids":[entity_id],"predicate_filters":[]}))).await.unwrap();
        assert_eq!(state["result"]["chronology"]["current"], next);
        assert_eq!(state["result"]["chronology"]["first_interaction"], "0");
    }
    let old=client.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":pinned,"entity_ids":[entity_id],"predicate_filters":[]}))).await.unwrap();
    assert_eq!(old["result"]["chronology"]["current"], "0");
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn event_timeline_possession_powers_timers_and_historical_revision() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
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
                ticks_per_month: Some(30),
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let clock_read=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap();
    let calendar = clock_read["result"]["records"][0]["payload"]["chronology"]["calendar"].clone();
    let id = |n| format!("rec_{n:024x}");
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let scope = json!({"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"universe_wide"}});
    let validity = |start: Value, end: Value| json!({"kind":"calendar_interval","calendar":calendar,"start":start,"end":end});
    let exact = |n: i32| json!({"kind":"exact","value":n.to_string()});
    let prop = |n, holder| json!({"kind":"define_proposition","client_ref":id(n),"record":{"subject":rr(3),"predicate":rr(4),"value":{"kind":"entity_ref","ref":rr(holder)},"context":scope["context"],"quantification":"particular"}});
    let event = |n, proposition, t, polarity: &str, occurrence: &str, end: Value| json!({"kind":"record_event","client_ref":id(n),"record":{"occurrence":occurrence,"time":{"kind":"exact","calendar":calendar,"value":format!("{t}")},"participants":[{"record":rr(3),"role":"item"}],"labels":{"en":format!("Event {n}")},"effects":[{"slot":"holder","proposition":rr(proposition),"polarity":polarity,"validity":validity(exact(t),end),"scope":scope,"order":0}]}});
    let mut ops = vec![
        entity("Mara", &id(1)),
        entity("Iven", &id(2)),
        entity("Seal", &id(3)),
        json!({"kind":"define_property","client_ref":id(4),"record":{"namespace":"story","key":"holder","labels":{},"value":{"kind":"entity_ref","subject_types":[]},"multiplicity":"single","subjectTypes":[],"persistence":"persistent_until_changed","exclusive":true,"symmetric":false,"transitive":false}}),
        json!({"kind":"define_property","client_ref":id(5),"record":{"namespace":"story","key":"flight","labels":{},"value":{"kind":"boolean"},"multiplicity":"single","subjectTypes":[],"persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}}),
        json!({"kind":"define_item_power","client_ref":id(6),"record":{"item":rr(3),"holderPredicate":rr(4),"powerPredicate":rr(5),"value":{"kind":"boolean","value":true},"scope":scope,"validity":validity(json!({"kind":"unbounded"}),json!({"kind":"unbounded"}))}}),
        prop(11, 1),
        prop(12, 1),
        prop(13, 2),
    ];
    ops.extend([
        event(
            21,
            11,
            10,
            "support",
            "occurred",
            json!({"kind":"unbounded"}),
        ),
        event(
            22,
            12,
            20,
            "refutation",
            "occurred",
            json!({"kind":"unbounded"}),
        ),
        event(23, 13, 30, "support", "occurred", exact(40)),
        event(
            24,
            13,
            15,
            "support",
            "reported",
            json!({"kind":"unbounded"}),
        ),
    ]);
    let p = proposal(&mut c, &ctx, ops, "event-seed").await;
    let published = publish_proposal(&mut c, &ctx, &p, "event-publish").await;
    for (t, mara, iven) in [
        (9, 0, 0),
        (10, 1, 0),
        (19, 1, 0),
        (20, 0, 0),
        (29, 0, 0),
        (30, 0, 1),
        (39, 0, 1),
        (40, 0, 0),
    ] {
        let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":published["revision"]},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":calendar,"value":t.to_string()}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
        let state=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"entity_ids":[id(1),id(2)],"predicate_filters":[]}))).await.unwrap();
        let facts = state["result"]["derived"].as_array().unwrap();
        assert_eq!(
            facts
                .iter()
                .filter(|f| f["subject"]["record"] == id(1))
                .count(),
            mara,
            "Mara at {t}"
        );
        assert_eq!(
            facts
                .iter()
                .filter(|f| f["subject"]["record"] == id(2))
                .count(),
            iven,
            "Iven at {t}"
        );
        assert!(facts
            .iter()
            .all(|f| f["evidence"].as_array().unwrap().len() >= 3));
    }
    let ctx = context(&mut c, &u, "Alpha").await;
    for (event, side, expected) in [
        (22, "before", 1),
        (22, "after", 0),
        (23, "before", 0),
        (23, "after", 1),
    ] {
        let state=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":ctx,"entity_ids":[id(1),id(2)],"predicate_filters":[],"event":id(event),"event_side":side}))).await.unwrap();
        assert_eq!(state["frame"]["time"]["kind"], "at_event");
        assert_eq!(state["frame"]["time"]["side"], side);
        assert_eq!(
            state["result"]["derived"].as_array().unwrap().len(),
            expected,
            "{event} {side}"
        );
    }
    // Editing event time updates its generated effect, not prior pinned revisions.
    let read = c
        .call(tool(
            "universe_get",
            json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(23)],"field_groups":[]}),
        ))
        .await
        .unwrap();
    let old = &read["result"]["records"][0];
    let mut replacement = old["payload"].clone();
    replacement.as_object_mut().unwrap().remove("record_kind");
    replacement["time"]["value"] = json!("35");
    replacement["effects"][0]["validity"]["start"]["value"] = json!("35");
    let p=proposal(&mut c,&ctx,vec![json!({"kind":"revise_event","record":rr(23),"expected_version":old["record_version_id"],"replacement":replacement})],"event-revise").await;
    publish_proposal(&mut c, &ctx, &p, "event-revise-publish").await;
    let before = c
        .call(tool(
            "universe_get",
            json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(23)],"field_groups":[]}),
        ))
        .await
        .unwrap();
    assert_eq!(before["result"]["records"][0], *old);
    let current = context(&mut c, &u, "Alpha").await;
    let after=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":current,"record_ids":[id(23)],"field_groups":[]}))).await.unwrap();
    assert_eq!(
        after["result"]["records"][0]["payload"]["time"]["value"],
        "35"
    );
    let timer=proposal(&mut c,&current,vec![json!({"kind":"define_property","client_ref":id(46),"record":{"namespace":"story","key":"night_sight","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}}),json!({"kind":"define_item_power","client_ref":id(47),"record":{"item":rr(3),"holderPredicate":rr(4),"powerPredicate":rr(46),"value":{"kind":"boolean","value":true},"scope":scope,"validity":validity(exact(36),exact(38))}})],"independent-power-timer").await;
    publish_proposal(&mut c, &current, &timer, "independent-power-timer-commit").await;
    for (tick, active) in [
        (35, false),
        (36, true),
        (37, true),
        (38, false),
        (39, false),
    ] {
        let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":calendar,"value":tick.to_string()}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
        let power=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"entity_ids":[id(2)],"predicate_filters":[]}))).await.unwrap();
        let facts = power["result"]["derived"].as_array().unwrap();
        assert_eq!(
            facts.iter().any(|f| f["rule"] == id(47)),
            active,
            "independent power at {tick}"
        );
        assert!(
            facts.iter().any(|f| f["rule"] == id(6)),
            "ordinary possession power remains at {tick}"
        );
    }
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

fn advisory_rule(index: usize) -> Value {
    json!({"kind":"define_rule","client_ref":format!("rec_{:024x}",5000+index),"record":{
        "namespace":"tests","key":format!("advice_{index}"),"labels":{},"kind":"behavioral_tendency",
        "commitPolicy":"advisory","applicability":{"kind":"universe_wide"},"targetPredicates":[],
        "expression":{"kind":"lit","value":false},"capabilities":["basic.v1"],"executable":true,"validity":{"kind":"unspecified"}
    }})
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn durable_validation_jobs_page_evidence_retry_restart_and_isolate_owners() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Story".into(),
                initial_tick: "0".into(),
                tick_label: "day".into(),
                ticks_per_month: Some(30),
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let seed = proposal(
        &mut c,
        &ctx,
        (0..100).map(advisory_rule).collect(),
        "seed-rules",
    )
    .await;
    publish_proposal(&mut c, &ctx, &seed, "seed-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let p = proposal(
        &mut c,
        &ctx,
        (100..105).map(advisory_rule).collect(),
        "rules",
    )
    .await;
    let immediate = validate(&mut c, &ctx, &p).await;
    let args = json!({"mode":"queued_proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe","idempotency_key":"queued"});
    let queued = c
        .call(tool("universe_validate", args.clone()))
        .await
        .unwrap()["result"]
        .clone();
    let id = queued["execution"]["operation_id"].clone();
    assert!(id.is_string());
    let lookup = json!({"lookup":"id","universe":"Alpha","operation_id":id});
    let mut page = c
        .call(tool("universe_get_operation", lookup.clone()))
        .await
        .unwrap();
    for _ in 0..100 {
        if page["result"]["state"] == "succeeded" {
            break;
        }
        tokio::task::yield_now().await;
        page = c
            .call(tool("universe_get_operation", lookup.clone()))
            .await
            .unwrap();
    }
    assert_eq!(page["result"]["state"], "succeeded", "{page}");
    assert_eq!(
        page["result"]["validation"]["execution"]["coverage"],
        "complete"
    );
    assert_eq!(page["delivery"]["complete"], false);
    assert_eq!(
        page["result"]["validation"]["execution"]["findings"]
            .as_array()
            .unwrap()
            .len(),
        100
    );
    let mut next = lookup.clone();
    next["cursor"] = page["delivery"]["cursor"].clone();
    let last = c
        .call(tool("universe_get_operation", next.clone()))
        .await
        .unwrap();
    assert_eq!(last["delivery"]["complete"], true);
    let mut findings = page["result"]["validation"]["execution"]["findings"]
        .as_array()
        .unwrap()
        .clone();
    findings.extend(
        last["result"]["validation"]["execution"]["findings"]
            .as_array()
            .unwrap()
            .clone(),
    );
    assert_eq!(findings, immediate["findings"].as_array().unwrap().clone());
    assert_eq!(
        c.call(tool("universe_validate", args.clone()))
            .await
            .unwrap()["result"]["execution"]["operation_id"],
        id
    );
    let keyed=c.call(tool("universe_get_operation",json!({"lookup":"key","universe":"Alpha","operation_kind":"validate","idempotency_key":"queued"}))).await.unwrap();
    assert_eq!(keyed["result"]["state"], "succeeded");
    let mut changed = args.clone();
    changed["proposal_reference"]["digest"] = json!("different");
    assert!(c.call(tool("universe_validate", changed)).await.is_err());
    let agent: ProfileId =
        serde_json::from_value(c.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone())
            .unwrap();
    c.call(EngineRequest::Grant {
        grant: GrantSpec {
            profile_id: agent.clone(),
            universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
            worlds: None,
            propose: true,
            edit: true,
            protected: false,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let mut other = connect(&root, &agent).await;
    assert!(other
        .call(tool("universe_get_operation", lookup.clone()))
        .await
        .is_err());
    drop(other);
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    assert_eq!(
        c.call(tool("universe_get_operation", next)).await.unwrap()["result"],
        last["result"]
    );
    let cancelled = c
        .call(tool(
            "universe_cancel_operation",
            json!({"universe":"Alpha","operation_id":id,"idempotency_key":"late-cancel"}),
        ))
        .await
        .unwrap();
    assert_eq!(cancelled["result"]["state"], "succeeded");
    let ctx = context(&mut c, &u, "Alpha").await;
    let mut invalid = advisory_rule(1000);
    invalid["record"]["kind"] = json!("structural_invariant");
    let invalid = proposal(&mut c, &ctx, vec![invalid], "invalid-rule").await;
    let failed=c.call(tool("universe_validate",json!({"mode":"queued_proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&invalid),"check_scope":"universe","idempotency_key":"failed-job"}))).await.unwrap();
    let mut status = Value::Null;
    for _ in 0..100 {
        status=c.call(tool("universe_get_operation",json!({"lookup":"id","universe":"Alpha","operation_id":failed["result"]["execution"]["operation_id"]}))).await.unwrap();
        if status["result"]["state"] == "failed" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(status["result"]["state"], "failed");
    assert!(status["result"]["failure"].is_string());
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn pinned_fork_reviewed_adoption_and_pack_upgrade_preserve_parent_history() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Gregorian {
                timestamp: "2040-01-01T00:00:00Z".into(),
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let pack = json!({"kind":"install_pack","client_ref":"rec_000000000000000000001999","record":{"key":"story","version":"1","dependencies":{},"capabilities":[],"records":[]}});
    let p = proposal(&mut c, &ctx, vec![pack], "pack").await;
    let base = publish_proposal(&mut c, &ctx, &p, "pack-commit").await;
    let child = ContinuityId::generate(&mut rand::rng());
    let parent: ContinuityId = serde_json::from_value(u["continuity_id"].clone()).unwrap();
    let base_revision: RevisionId = serde_json::from_value(base["revision"].clone()).unwrap();
    let fork = EngineRequest::ForkContinuity {
        universe: Selector("Alpha".into()),
        name: "Alternate ending".into(),
        continuity_id: child.clone(),
        source: parent.clone(),
        revision: base_revision.clone(),
    };
    let forked = c.call(fork.clone()).await.unwrap();
    assert_eq!(c.call(fork).await.unwrap(), forked);
    let parent_ctx = context(&mut c, &u, "Alpha").await;
    let p = proposal(
        &mut c,
        &parent_ctx,
        vec![entity(
            "Parent-only arrival",
            "rec_000000000000000000001998",
        )],
        "parent",
    )
    .await;
    let parent_head = publish_proposal(&mut c, &parent_ctx, &p, "parent-commit").await;
    let source_revision: RevisionId =
        serde_json::from_value(parent_head["revision"].clone()).unwrap();
    let target_revision: RevisionId = serde_json::from_value(forked["revision"].clone()).unwrap();
    let compare = EngineRequest::CompareContinuities {
        universe: Selector("Alpha".into()),
        target: child.clone(),
        target_revision: target_revision.clone(),
        source: parent.clone(),
        source_revision: source_revision.clone(),
    };
    let diff = c.call(compare.clone()).await.unwrap();
    assert_eq!(diff["differences"].as_array().unwrap().len(), 1);
    assert!(diff["differences"][0]["target_version"].is_null());
    let adoption = c
        .call(EngineRequest::PrepareAdoption {
            universe: Selector("Alpha".into()),
            target: child.clone(),
            target_revision: target_revision.clone(),
            source: parent.clone(),
            source_revision: source_revision.clone(),
            record_ids: vec![RecordId::parse("rec_000000000000000000001998").unwrap()],
        })
        .await
        .unwrap();
    let mut child_u = u.clone();
    child_u["continuity_id"] = json!(child);
    let child_ctx = context(&mut c, &child_u, "Alpha").await;
    let adopt = proposal(
        &mut c,
        &child_ctx,
        adoption["operations"].as_array().unwrap().clone(),
        "adopt",
    )
    .await;
    let adopted = publish_proposal(&mut c, &child_ctx, &adopt, "adopt-commit").await;
    assert_ne!(adopted["revision"], parent_head["revision"]);
    assert_eq!(c.call(compare).await.unwrap(), diff); // historical child remains pinned
    let now = c
        .call(EngineRequest::CompareContinuities {
            universe: Selector("Alpha".into()),
            target: child,
            target_revision: serde_json::from_value(adopted["revision"].clone()).unwrap(),
            source: parent,
            source_revision,
        })
        .await
        .unwrap();
    assert!(now["differences"].as_array().unwrap().is_empty());
    let latest = context(&mut c, &child_u, "Alpha").await;
    let pack_id = "rec_000000000000000000001999";
    let read=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":latest,"record_ids":[pack_id],"field_groups":[]}))).await.unwrap();
    let pack = &read["result"]["records"][0];
    let upgrade = json!({"kind":"upgrade_pack","record":{"universe":u["universe_id"],"record":pack_id},"expected_version":pack["record_version_id"],"replacement":{"key":"story","version":"2","dependencies":{},"capabilities":[],"records":[]}});
    let upgrade = proposal(&mut c, &latest, vec![upgrade], "upgrade-pack").await;
    publish_proposal(&mut c, &latest, &upgrade, "upgrade-commit").await;
    let current = context(&mut c, &child_u, "Alpha").await;
    let read=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":current,"record_ids":[pack_id],"field_groups":[]}))).await.unwrap();
    assert_eq!(read["result"]["records"][0]["payload"]["version"], "2");
    let read=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":parent_ctx,"record_ids":[pack_id],"field_groups":[]}))).await.unwrap();
    assert_eq!(read["result"]["records"][0]["payload"]["version"], "1");
    let dependency = json!({"kind":"install_pack","client_ref":"dependent","record":{"key":"dependent","version":"1","dependencies":{"story":"1"},"capabilities":[],"records":[]}});
    let invalid=c.call(tool("universe_validate",json!({"mode":"inline","universe":"Alpha","context_id":current,"operations":[dependency],"check_scope":"universe"}))).await;
    assert!(invalid.is_err());
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn scoped_validation_has_no_hidden_finding_oracle_but_exact_author_approval_can_commit() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Day".into(),
                initial_tick: "0".into(),
                tick_label: "days".into(),
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let rr = |id: &str| json!({"universe":u["universe_id"],"record":id});
    let mut hidden_person = entity("Lunar observer", "rec_000000000000000000002010");
    hidden_person["record"]["worldAssociations"] = json!([{"world":"wld_000000000000000000002002","role":"resident","validity":{"kind":"unspecified"},"qualifiers":{}}]);
    let mut hidden = advisory_rule(499);
    hidden["record"]["applicability"] =
        json!({"kind":"worlds","world_ids":["wld_000000000000000000002002"]});
    let p = proposal(
        &mut c,
        &ctx,
        vec![
            world("Terra", "rec_000000000000000000002001"),
            world("Luna", "rec_000000000000000000002002"),
            hidden,hidden_person,
            json!({"kind":"define_property","client_ref":"rec_000000000000000000002011","record":{"namespace":"scope","key":"awake","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}}),
            json!({"kind":"define_proposition","client_ref":"rec_000000000000000000002012","record":{"subject":rr("rec_000000000000000000002010"),"predicate":rr("rec_000000000000000000002011"),"value":{"kind":"boolean","value":true},"quantification":"particular","context":rr(u["context_id"].as_str().unwrap())}}),
            json!({"kind":"add_belief","client_ref":"rec_000000000000000000002013","record":{"holder":rr("rec_000000000000000000002010"),"proposition":rr("rec_000000000000000000002012"),"attitude":"knows","certainty":null,"validity":{"kind":"unspecified"},"basis":{"kind":"author_decision","note":"Lunar knowledge"}}}),
        ],
        "scope-setup",
    )
    .await;
    publish_proposal(&mut c, &ctx, &p, "scope-commit").await;
    let agent: ProfileId =
        serde_json::from_value(c.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone())
            .unwrap();
    c.call(EngineRequest::Grant {
        grant: GrantSpec {
            profile_id: agent.clone(),
            universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
            worlds: Some(vec![WorldId::parse("wld_000000000000000000002001").unwrap()]),
            propose: true,
            edit: true,
            protected: false,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let mut a = connect(&root, &agent).await;
    let ac = context(&mut a, &u, "Alpha").await;
    let search=a.call(tool("universe_search",json!({"universe":"Alpha","context_id":ac,"query":"","typed_filters":{"record_kinds":[]},"limit":100}))).await.unwrap();
    let definitions = a
        .call(tool(
            "universe_describe",
            json!({"mode":"definitions","universe":"Alpha","context_id":ac}),
        ))
        .await
        .unwrap();
    for hidden in [
        "rec_000000000000000000002010",
        "rec_000000000000000000002012",
        "rec_000000000000000000002013",
    ] {
        assert!(!search["result"].to_string().contains(hidden));
        assert!(!definitions["result"].to_string().contains(hidden));
        assert!(a
            .call(tool(
                "universe_get",
                json!({"universe":"Alpha","context_id":ac,"record_ids":[hidden],"field_groups":[]})
            ))
            .await
            .is_err());
    }
    let mut local = entity("Local traveller", "rec_000000000000000000002003");
    local["record"]["worldAssociations"] = json!([{"world":"wld_000000000000000000002001","role":"resident","validity":{"kind":"unspecified"},"qualifiers":{}}]);
    let p = proposal(&mut a, &ac, vec![local], "scoped").await;
    let impact=a.call(tool("universe_get_impact",json!({"mode":"proposal","universe":"Alpha","context_id":ac,"proposal_reference":reference(&p),"scope":"universe","byte_budget":65536}))).await.unwrap();
    assert_eq!(impact["result"]["coverage"], "restricted");
    assert!(!impact["result"]
        .to_string()
        .contains("rec_000000000000000000002013"));
    let limited = validate(&mut a, &ac, &p).await;
    assert_eq!(
        limited,
        json!({"kind":"restricted","execution_coverage":"restricted","submitted_input":{"kind":"restricted"},"assessment":{"kind":"restricted"}})
    );
    assert!(!limited.to_string().contains("advice_499"));
    let author_ctx = context(&mut c, &u, "Alpha").await;
    let checked = validate(&mut c, &author_ctx, &p).await;
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference(&p),
        validation_run: serde_json::from_value(checked["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    assert!(a.call(commit(&p, &checked, "scoped-commit")).await.is_ok());
    drop(a);
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn exact_rule_exception_allows_reviewed_departure_and_definition_revision_stales_it() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Day".into(),
                initial_tick: "0".into(),
                tick_label: "days".into(),
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n| format!("rec_{:024x}", 8000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let scope = json!({"applicability":{"kind":"universe_wide"},"context":{"universe":u["universe_id"],"record":u["context_id"]}});
    let claim = json!({"kind":"assert_proposition","client_ref":id(3),"proposition":{"subject":rr(1),"predicate":rr(2),"value":{"kind":"boolean","value":true},"quantification":"particular","context":scope["context"]},"assertion":{"proposition":rr(3),"polarity":"support","scope":scope,"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","basis":{"kind":"author_decision","note":"Initial prerequisite"}}});
    let rule = json!({"kind":"define_rule","client_ref":id(4),"record":{"namespace":"gate","key":"requires-charge","labels":{},"kind":"physical_constraint","commitPolicy":"block_unless_exception","applicability":{"kind":"universe_wide"},"targetPredicates":["gate:charged"],"expression":{"kind":"claim","subject":{"kind":"record","ref":rr(1)},"predicate":"gate:charged","value":{"kind":"value","value":{"kind":"boolean","value":true}},"polarity":"support"},"capabilities":["basic.v1"],"executable":true,"validity":{"kind":"unspecified"}}});
    let p=proposal(&mut c,&ctx,vec![entity("Seal",&id(1)),json!({"kind":"define_property","client_ref":id(2),"record":{"namespace":"gate","key":"charged","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}}),claim,rule],"exception-base").await;
    publish_proposal(&mut c, &ctx, &p, "exception-base-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let state=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":ctx,"entity_ids":[id(1)],"predicate_filters":[]}))).await.unwrap();
    let assertion = &state["result"]["assertions"][0];
    let retract = json!({"kind":"retract_assertion","record":{"universe":u["universe_id"],"record":assertion["identity"]["record_id"]},"expected_version":assertion["record_version_id"],"rationale":"Author declares a reviewed exception"});
    let p = proposal(&mut c, &ctx, vec![retract.clone()], "exception-departure").await;
    let v = validate(&mut c, &ctx, &p).await;
    assert_eq!(v["findings"][0]["outcome"], "not_established");
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let read = c
        .call(tool(
            "universe_get",
            json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(4)],"field_groups":[]}),
        ))
        .await
        .unwrap();
    let rule = &read["result"]["records"][0];
    let decision = json!({"kind":"record_issue_decision","client_ref":id(5),"record":{"fingerprints":[v["findings"][0]["fingerprint"]],"mode":"accept","scope":id(4),"rationale":"An explicit author exception to this prerequisite","principal":author.as_str().replacen("prf_","prn_",1)}});
    let exception = json!({"kind":"add_exception","client_ref":id(6),"record":{"rule":rr(4),"ruleVersion":rule["record_version_id"],"scope":scope,"validity":{"kind":"unspecified"},"authorizingDecision":rr(5),"rationale":"Reviewed departure"}});
    let revised=c.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"operations":[retract,decision,exception],"submission":"submitted","rationale":"Exact rule exception","idempotency_key":"exception-revise"}))).await.unwrap()["result"].clone();
    let accepted = validate(&mut c, &ctx, &revised).await;
    assert_eq!(accepted["coverage"], "complete");
    assert_eq!(accepted["findings"][0]["outcome"], "not_established"); // finding remains visible
    publish_proposal(&mut c, &ctx, &revised, "exception-commit").await;
    let current = context(&mut c, &u, "Alpha").await;
    let mut replacement = rule["payload"].clone();
    replacement["labels"]["en"] = json!("Revised prerequisite");
    let revision=proposal(&mut c,&current,vec![json!({"kind":"revise_definition","record":rr(4),"expected_version":rule["record_version_id"],"replacement":replacement})],"revise-definition").await;
    let stale = validate(&mut c, &current, &revision).await;
    assert_eq!(stale["coverage"], "partial");
    assert!(stale["unsupported_capabilities"]
        .to_string()
        .contains("stale rule version"));
    assert_ne!(
        accepted["findings"][0]["fingerprint"],
        stale["findings"][0]["fingerprint"]
    );
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn silver_gate_s01_to_s10_use_pinned_candidates_and_explicit_story_time() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Gate days".into(),
                initial_tick: "16".into(),
                tick_label: "days".into(),
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n| format!("rec_{:024x}", 10000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let clock=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap();
    let cal = clock["result"]["records"][0]["payload"]["chronology"]["calendar"].clone();
    let scope = json!({"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"universe_wide"}});
    let interval = |start, end: Option<i32>| json!({"kind":"calendar_interval","calendar":cal,"start":{"kind":"exact","value":format!("{start}")},"end":end.map_or(json!({"kind":"unbounded"}),|n|json!({"kind":"exact","value":n.to_string()}))});
    let def = |n, key: &str, shape: Value, multiple: bool| json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"silver","key":key,"labels":{},"subjectTypes":[],"value":shape,"multiplicity":if multiple{"multiple"}else{"single"},"persistence":"explicit_interval","exclusive":!multiple,"symmetric":false,"transitive":false}});
    let claim = |n, subject, predicate, value: Value, start, end| json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(subject),"predicate":rr(predicate),"value":value,"context":scope["context"],"quantification":"particular"},"assertion":{"proposition":rr(n),"polarity":"support","scope":scope,"validity":interval(start,end),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Silver Gate authored premise"}}});
    let reference_value = |n| json!({"kind":"entity_ref","ref":rr(n)});
    let boolean = |v| json!({"kind":"boolean","value":v});
    let query = |subject, key: &str, value: Value| json!({"kind":"claim","subject":{"kind":"record","ref":rr(subject)},"predicate":format!("silver:{key}"),"value":{"kind":"value","value":value},"polarity":"support"});
    let event = |n, t, occurrence: &str, effects: Vec<Value>, preconditions: Vec<Value>| json!({"kind":"record_event","client_ref":id(n),"record":{"occurrence":occurrence,"time":{"kind":"exact","calendar":cal,"value":format!("{t}")},"participants":[{"record":rr(2),"role":"actor"}],"effects":effects,"preconditions":preconditions,"labels":{"en":format!("Gate event {n}")}}});
    let transfer = |n, t, occurrence: &str| {
        event(
            n,
            t,
            occurrence,
            vec![
                json!({"slot":"custody","proposition":rr(20),"polarity":"support","scope":scope,"validity":interval(t,None),"order":0}),
            ],
            vec![],
        )
    };
    let opening = |n, t| {
        event(
            n,
            t,
            "occurred",
            vec![],
            vec![
                query(3, "holder", reference_value(2)),
                query(3, "charged", boolean(true)),
            ],
        )
    };
    let setup = vec![
        entity("Mara", &id(1)),
        entity("Iven", &id(2)),
        entity("One seal", &id(3)),
        entity("Silver gate", &id(4)),
        entity("Side entrance", &id(5)),
        entity("Courtyard", &id(6)),
        entity("Retrospective narrator", &id(7)),
        def(
            10,
            "holder",
            json!({"kind":"entity_ref","subject_types":[]}),
            false,
        ),
        def(11, "charged", json!({"kind":"boolean"}), false),
        def(12, "knows_location", json!({"kind":"boolean"}), false),
        def(
            13,
            "entrance",
            json!({"kind":"entity_ref","subject_types":[]}),
            true,
        ),
        def(14, "new_method", json!({"kind":"boolean"}), false),
        claim(15, 3, 10, reference_value(1), 0, Some(17)),
        claim(16, 3, 11, boolean(true), 0, Some(17)),
        claim(17, 2, 12, boolean(false), 0, Some(18)),
        claim(18, 6, 13, reference_value(4), 0, None),
        claim(19, 4, 14, boolean(true), 21, None),
        json!({"kind":"define_proposition","client_ref":id(20),"record":{"subject":rr(3),"predicate":rr(10),"value":reference_value(2),"context":scope["context"],"quantification":"particular"}}),
        json!({"kind":"record_narrative_reference","client_ref":id(25),"record":"represented_context","payload":{"record_kind":"represented_context","universe":u["universe_id"],"kind":{"kind":"narrator","narrator":rr(7)},"labels":{"en":"Retrospective narration"}}}),
        json!({"kind":"create_work","client_ref":id(26),"record":{"kind":"novel","title":"The gate passage","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]}}),
        json!({"kind":"record_narrative_reference","client_ref":id(27),"record":"work_version","payload":{"record_kind":"work_version","work":rr(26),"versionLabel":"Draft 1","binding":{"kind":"bound","continuity":u["continuity_id"],"revision":u["revision"]}}}),
        event(28, 16, "occurred", vec![], vec![]),
    ];
    let setup = proposal(&mut c, &ctx, setup, "silver-base").await;
    let base = publish_proposal(&mut c, &ctx, &setup, "silver-base-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let state=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":ctx,"entity_ids":[id(3)],"predicate_filters":[id(10)]}))).await.unwrap();
    let custody = &state["result"]["assertions"][0];
    let end_custody = json!({"kind":"end_assertion_at","record":{"universe":u["universe_id"],"record":custody["identity"]["record_id"]},"expected_version":custody["record_version_id"],"at":{"kind":"exact","calendar":cal,"value":"15"},"basis":{"kind":"author_decision","note":"Explicit earlier transfer ends the previous continuous custody"}});
    for number in 1..=10 {
        let branch = ContinuityId::generate(&mut rand::rng());
        c.call(EngineRequest::ForkContinuity {
            universe: Selector("Alpha".into()),
            name: format!("S{number:02}"),
            continuity_id: branch.clone(),
            source: serde_json::from_value(u["continuity_id"].clone()).unwrap(),
            revision: serde_json::from_value(base["revision"].clone()).unwrap(),
        })
        .await
        .unwrap();
        let mut scenario = u.clone();
        scenario["continuity_id"] = json!(branch);
        let mut ctx = context(&mut c, &scenario, "Alpha").await;
        let n = 100 + number * 10;
        let operations = match number {
            1 => vec![opening(n, 16)],
            2 => vec![transfer(n, 16, "reported")],
            3 => vec![claim(n, 2, 12, boolean(true), 16, Some(17))],
            4 => vec![event(n, 16, "occurred", vec![], vec![])],
            5 => vec![claim(n, 6, 13, reference_value(5), 16, None)],
            6 => vec![
                claim(n, 6, 13, reference_value(5), 16, None),
                json!({"kind":"set_completeness","client_ref":id(n+1),"record":{"subject":rr(6),"predicate":"silver:entrance","members":[rr(4)],"completeness":"objective_reality","validity":interval(0,None),"scope":scope}}),
            ],
            7 => vec![
                end_custody.clone(),
                transfer(n, 15, "occurred"),
                opening(n + 1, 16),
            ],
            8 => vec![transfer(n, 15, "occurred"), opening(n + 1, 16)],
            9 => vec![event(
                n,
                16,
                "occurred",
                vec![],
                vec![query(4, "new_method", boolean(true))],
            )],
            10 => {
                scenario["context_id"] = json!(id(25));
                ctx = context(&mut c, &scenario, "Alpha").await;
                let mut retrospective = claim(n, 2, 12, boolean(true), 80, None);
                retrospective["proposition"]["context"] = rr(25);
                retrospective["assertion"]["scope"]["context"] = rr(25);
                let read=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(27)],"field_groups":[]}))).await.unwrap();
                let version = json!({"universe":u["universe_id"],"record":id(27),"version":read["result"]["records"][0]["record_version_id"]});
                vec![
                    retrospective,
                    json!({"kind":"record_narrative_reference","client_ref":id(n+1),"record":"scene_ref","payload":{"record_kind":"scene_ref","workVersion":version,"sceneId":"Event 16 passage","viewpoint":rr(7),"narrativePosition":16,"depictedEvents":[rr(28)],"narrationFrame":rr(25),"worldAssociations":[]}}),
                ]
            }
            _ => unreachable!(),
        };
        let p = proposal(&mut c, &ctx, operations, &format!("S{number:02}")).await;
        let result=c.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe"}))).await;
        let should_pass = [2, 4, 5, 7, 10].contains(&number);
        if should_pass {
            let validated = result.unwrap_or_else(|e| panic!("S{number:02}: {e}"));
            assert_eq!(
                validated["result"]["execution"]["coverage"], "complete",
                "S{number:02}"
            );
            publish_proposal(&mut c, &ctx, &p, &format!("S{number:02}-commit")).await;
            if [2, 4, 7, 10].contains(&number) {
                let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":branch,"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":cal,"value":"16"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
                let state=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"entity_ids":[id(2)],"predicate_filters":[id(12)]}))).await.unwrap();
                assert_eq!(
                    state["result"]["assertions"].as_array().unwrap().len(),
                    1,
                    "S{number:02}: no invented knowledge"
                );
                assert_eq!(state["result"]["chronology"]["current"], "16");
            }
        } else if let Ok(v) = result {
            assert!(
                c.call(EngineRequest::Approve {
                    universe: Selector("Alpha".into()),
                    proposal_reference: reference(&p),
                    validation_run: serde_json::from_value(
                        v["result"]["execution"]["run_id"].clone()
                    )
                    .unwrap()
                })
                .await
                .is_err(),
                "S{number:02}: conflicting candidate approved"
            );
        }
        if number == 9 {
            let later = proposal(
                &mut c,
                &ctx,
                vec![event(
                    n + 1,
                    22,
                    "occurred",
                    vec![],
                    vec![query(4, "new_method", boolean(true))],
                )],
                "S09-later",
            )
            .await;
            publish_proposal(&mut c, &ctx, &later, "S09-later-commit").await;
        }
    }
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[path = "support/completion.rs"]
mod completion;

#[path = "support/appearance.rs"]
mod appearance;

#[path = "support/audit.rs"]
mod audit;
