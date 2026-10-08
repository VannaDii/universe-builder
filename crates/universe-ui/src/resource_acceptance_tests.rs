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
fn reference(p: &Value) -> ProposalRef {
    serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap()
}
fn rule() -> Value {
    json!({"namespace":"resource","key":"rounds","labels":{},"kind":"physical_constraint","commitPolicy":"block_unless_exception","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":["resource:rounds"],"expression":{"kind":"lit","value":true},"capabilities":["resources.accounting.v1"],"executable":true,"validity":{"kind":"unspecified"}})
}
fn vocabulary() -> Vec<Value> {
    vec![json!({"kind":"rule","record_id":id(3),"definition":rule()})]
}
#[test]
fn exact_acceptance_requires_author_rationale_and_unrestricted_complete_resource_finding() {
    let mut v = json!({"kind":"evaluated","execution":{"coverage":"complete","findings":[{"fingerprint":"exact","rule_id":id(3),"coverage":"complete","outcome":"not_established","records":[{"record":id(5)},{"record":id(6)}]}]}});
    let profile = "prf_000000000000000000000001";
    let build =
        |v: &Value, author, reason| operation(v, &vocabulary(), "exact", profile, author, reason);
    let op = build(&v, true, "Intentionally unexplained").unwrap();
    assert_eq!(op["record"]["scope"], format!("resource:{}", id(5)));
    assert_eq!(op["record"]["fingerprints"], json!(["exact"]));
    assert!(build(&v, false, "Reason").is_err());
    assert!(build(&v, true, "  ").is_err());
    assert!(operation(&v, &vocabulary(), "old", profile, true, "Reason").is_err());
    assert!(operation(&v, &[], "exact", profile, true, "Reason").is_err());
    v["kind"] = json!("restricted");
    assert!(findings(&v, &vocabulary()).is_empty());
    v["kind"] = json!("evaluated");
    v["execution"]["coverage"] = json!("partial");
    assert!(build(&v, true, "Reason").is_ok());
    v["execution"]["findings"][0]["coverage"] = json!("partial");
    assert!(findings(&v, &vocabulary()).is_empty());
}
fn claim(u: &Value, calendar: &Value, n: u64, count: &str, start: &str, end: Value) -> Value {
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(1),"predicate":rr(2),"value":{"kind":"integer","digits":count},"context":{"universe":u["universe_id"],"record":u["context_id"]},"quantification":"particular"},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":{"applicability":{"kind":"universe_wide"},"context":{"universe":u["universe_id"],"record":u["context_id"]}},"validity":{"kind":"calendar_interval","calendar":calendar,"start":{"kind":"exact","value":start},"end":end},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored count"}}})
}
async fn validate(
    c: &mut universe_client::installation::EngineClient,
    opened: &Value,
    p: &Value,
) -> Value {
    tool(c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference(p),"check_scope":"universe"})).await["result"].clone()
}
async fn revise(
    c: &mut universe_client::installation::EngineClient,
    opened: &Value,
    p: &Value,
    ops: Value,
    key: &str,
) -> Value {
    tool(c,"universe_propose",json!({"action":"revise","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference(p),"operations":ops,"submission":"submitted","rationale":"Explicit creative acceptance","idempotency_key":key})).await["result"].clone()
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn native_resource_acceptance_publishes_count_keeps_arrival_unknown_and_expires_on_changes() {
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
    let clock =
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"]["calendar"].clone();
    let baseline = claim(&u, &clock, 4, "1", "0", json!({"kind":"exact","value":"5"}));
    publish(&mut c,&opened,json!([
        {"kind":"create_entity","client_ref":id(1),"record":{"names":[],"classificationResolution":"unclassified","worldAssociations":[],"labels":{"en":"Bag"},"metadata":{}}},
        {"kind":"define_property","client_ref":id(2),"record":{"namespace":"resource","key":"rounds","labels":{},"subjectTypes":[],"value":{"kind":"integer"},"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}},
        {"kind":"define_rule","client_ref":id(3),"record":rule()},
        {"kind":"create_world","client_ref":id(8),"record":{"selector":"Setting","labels":{},"metadata":{}}},baseline
    ]),"baseline").await;
    let opened = open(&mut c, &u).await;
    let next = claim(&u, &clock, 5, "2", "5", json!({"kind":"unbounded"}));
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[next.clone()],"submission":"submitted","rationale":"Unexplained increase","idempotency_key":"increase"})).await["result"].clone();
    let v = validate(&mut c, &opened, &p).await;
    let f = findings(&v, &vocabulary())
        .pop()
        .unwrap_or_else(|| panic!("Missing resource finding: {v}"));
    assert_eq!(f["records"][0]["record"], id(5));
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["execution"]["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let decision = operation(
        &v,
        &vocabulary(),
        f["fingerprint"].as_str().unwrap(),
        author.as_str(),
        true,
        "The extra round is deliberately unexplained",
    )
    .unwrap();
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
            protected: true,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let mut collaborator = connect(&root, &agent).await;
    let agent_opened = open(&mut collaborator, &u).await;
    let mut forged = decision.clone();
    forged["record"]["principal"] = json!(agent.as_str().replacen("prf_", "prn_", 1));
    forged["client_ref"] = json!(RecordId::generate(&mut rand::rng()));
    let unauthorized=tool(&mut collaborator,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":agent_opened["result"]["context_id"],"operations":[forged],"submission":"submitted","rationale":"Collaborator acceptance attempt","idempotency_key":"unauthorized"})).await["result"].clone();
    assert!(collaborator.call(crate::author::tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":agent_opened["result"]["context_id"],"proposal_reference":reference(&unauthorized),"check_scope":"universe"})).unwrap()).await.is_err());
    c.call(EngineRequest::Grant {
        grant: GrantSpec {
            profile_id: agent.clone(),
            universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
            worlds: Some(vec![
                WorldId::parse(&id(8).replacen("rec_", "wld_", 1)).unwrap()
            ]),
            propose: true,
            edit: true,
            protected: true,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let hidden=collaborator.call(crate::author::tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":agent_opened["result"]["context_id"],"proposal_reference":reference(&p),"check_scope":"universe"})).unwrap()).await.unwrap_err();
    assert!(
        hidden.to_string().contains("not found or not accessible"),
        "{hidden}"
    );
    let accepted = c
        .call(
            revision_request(
                "Alpha",
                &opened["result"]["context_id"],
                &p,
                decision.clone(),
                "accept",
            )
            .unwrap(),
        )
        .await
        .unwrap()["result"]
        .clone();
    let av = validate(&mut c, &opened, &accepted).await;
    assert_eq!(
        findings(&av, &vocabulary())[0]["fingerprint"],
        f["fingerprint"]
    );
    assert!(!av["final_binding_digest"].is_null());
    let mut changed = next.clone();
    changed["proposition"]["value"]["digits"] = json!("3");
    let cp = revise(
        &mut c,
        &opened,
        &accepted,
        json!([changed, decision.clone()]),
        "changed",
    )
    .await;
    let cv = validate(&mut c, &opened, &cp).await;
    assert_ne!(
        findings(&cv, &vocabulary())[0]["fingerprint"],
        f["fingerprint"]
    );
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&cp),
            validation_run: serde_json::from_value(cv["execution"]["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let before=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":"0"}},"temporal_systems":[],"perspective":"author"})).await;
    let base_state=tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":before["result"]["context_id"],"entity_ids":[id(1)],"predicate_filters":[]})).await;
    let a = &base_state["result"]["assertions"][0];
    let mut replacement = a["payload"].clone();
    replacement.as_object_mut().unwrap().remove("record_kind");
    replacement["proposition"]["record"] = json!(id(7));
    let mut prop = baseline["proposition"].clone();
    prop["value"]["digits"] = json!("0");
    let prior_changed=revise(&mut c,&opened,&cp,json!([next.clone(),decision.clone(),
        {"kind":"define_proposition","client_ref":id(7),"record":prop},
        {"kind":"supersede_assertion","record":{"universe":u["universe_id"],"record":a["identity"]["record_id"]},"expected_version":a["record_version_id"],"replacement":replacement,"rationale":"Correct the predecessor count"}]),"changed-prior").await;
    let pv = validate(&mut c, &opened, &prior_changed).await;
    assert_ne!(
        findings(&pv, &vocabulary())[0]["fingerprint"],
        f["fingerprint"]
    );
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&prior_changed),
            validation_run: serde_json::from_value(pv["execution"]["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let restored = revise(
        &mut c,
        &opened,
        &prior_changed,
        json!([next, decision]),
        "restore",
    )
    .await;
    let rv = validate(&mut c, &opened, &restored).await;
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference(&restored),
        validation_run: serde_json::from_value(rv["execution"]["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    tool(&mut c,"universe_commit",json!({"universe":"Alpha","proposal_reference":reference(&restored),"expected_base_revision":restored["base_frame"]["revision"],"validation_run":rv["execution"]["run_id"],"idempotency_key":"accepted-commit"})).await;
    let head = open(&mut c, &u).await;
    assert_eq!(
        read(&mut c, &head, &json!(id(5))).await["payload"]["value"]["digits"],
        "2"
    );
    let at=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":"10"}},"temporal_systems":[],"perspective":"author"})).await;
    let state=tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"entity_ids":[id(1)],"predicate_filters":[]})).await;
    assert!(state.to_string().contains("resource_arrival_unexplained"));
    stop.cancel();
    server.await.unwrap().unwrap();
}
