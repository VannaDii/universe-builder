use super::*;
async fn get(c: &mut EngineClient, ctx: &Value, ids: Value) -> Value {
    c.call(tool(
        "universe_get",
        json!({"universe":"Alpha","context_id":ctx,"record_ids":ids,"field_groups":[]}),
    ))
    .await
    .unwrap()["result"]["records"]
        .clone()
}
async fn assertion(c: &mut EngineClient, ctx: &Value, proposition: &str) -> Value {
    let hits=c.call(tool("universe_search",json!({"universe":"Alpha","context_id":ctx,"query":"","typed_filters":{"record_kinds":["assertion"]},"limit":100}))).await.unwrap();
    let ids: Vec<_> = hits["result"]["hits"]
        .as_array()
        .unwrap()
        .iter()
        .map(|h| h["record_id"].clone())
        .collect();
    get(c, ctx, json!(ids))
        .await
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["payload"]["proposition"]["record"] == proposition)
        .unwrap()
        .clone()
}
async fn blocked(
    c: &mut EngineClient,
    ctx: &Value,
    operations: Vec<Value>,
    key: &str,
    outcome: &str,
) {
    let p = proposal(c, ctx, operations, key).await;
    let v = validate(c, ctx, &p).await;
    assert!(
        v["findings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["outcome"] == outcome),
        "{key}: {v}"
    );
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    assert!(c.call(commit(&p, &v, key)).await.is_err());
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn scoped_cardinality_admission_corrections_history_and_restart() {
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
                ticks_per_month: None,
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n: u64| format!("rec_{:024x}", 61000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let calendar = get(&mut c, &ctx, json!([u["context_id"]])).await[0]["payload"]["chronology"]
        ["calendar"]
        .clone();
    let scope = json!({"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"universe_wide"}});
    let interval = |lo: i32, hi: i32| json!({"kind":"calendar_interval","calendar":calendar,"start":{"kind":"exact","value":lo.to_string()},"end":{"kind":"exact","value":hi.to_string()}});
    let rule = |max| json!({"namespace":"succession","key":"maximum","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":["relations.cardinality.v1"],"executable":true,"validity":{"kind":"unspecified"},"relationCardinality":{"relation":rr(2),"grouping":{"kind":"role","role":"office"},"countedRole":"successor","maximum":max,"scope":scope,"validity":{"kind":"unspecified"}}});
    let fact = |n, person, validity: Value| json!({"kind":"record_relation","client_ref":id(n),"proposition":{"subject":rr(10),"predicate":rr(2),"roles":[{"role":"office","participant":rr(10)},{"role":"successor","participant":rr(person)}],"quantification":"particular","context":scope["context"]},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":scope,"validity":validity,"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"succession"}}});
    let instance = |n, name: &str| json!({"kind":"introduce_instance","client_ref":id(n),"name":{"text":name,"validity":interval(0,100)},"classification":null,"world_associations":[]});
    admit(&mut c,&ctx,vec![instance(10,"Office"),instance(11,"First"),instance(12,"Second"),instance(13,"Third"),json!({"kind":"define_relation","client_ref":id(2),"record":{"namespace":"succession","key":"successor","labels":{},"roles":[{"name":"office","participantTypes":[],"multiplicity":"single","ordered":false},{"name":"successor","participantTypes":[],"multiplicity":"single","ordered":false}]}}),json!({"kind":"define_rule","client_ref":id(1),"record":rule(1)}),fact(20,11,interval(0,10))],"cardinality-seed").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    blocked(
        &mut c,
        &ctx,
        vec![fact(30, 12, interval(5, 15))],
        "simultaneous",
        "refuted",
    )
    .await;
    blocked(
        &mut c,
        &ctx,
        vec![fact(31, 12, json!({"kind":"unknown"}))],
        "unknown",
        "not_established",
    )
    .await;
    // Sequential and repeated evidence are legal through actual review/commit.
    admit(
        &mut c,
        &ctx,
        vec![
            fact(32, 12, interval(10, 20)),
            fact(34, 11, interval(0, 10)),
        ],
        "sequential-duplicate",
    )
    .await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let old_rule = get(&mut c, &ctx, json!([id(1)])).await[0].clone();
    let mut replacement = rule(2);
    replacement["record_kind"] = json!("rule");
    let receipt=admit(&mut c,&ctx,vec![json!({"kind":"revise_definition","record":rr(1),"expected_version":old_rule["record_version_id"],"replacement":replacement}),fact(40,13,interval(0,10))],"max-two").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    // max-two across instances does not relax a single role inside one instance.
    let mut invalid_local = fact(44, 13, interval(0, 10));
    invalid_local["proposition"]["roles"]
        .as_array_mut()
        .unwrap()
        .push(json!({"role":"successor","participant":rr(12)}));
    let p = proposal(&mut c, &ctx, vec![invalid_local], "local-single-role").await;
    assert!(c.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"check_scope":"universe"}))).await.is_err());

    blocked(
        &mut c,
        &ctx,
        vec![fact(42, 12, interval(5, 8))],
        "third-participant",
        "refuted",
    )
    .await;
    let old_assertion = assertion(&mut c, &ctx, &id(40)).await;
    let current_rule = get(&mut c, &ctx, json!([id(1)])).await[0].clone();
    let mut tightened = rule(1);
    tightened["record_kind"] = json!("rule");
    let revise = json!({"kind":"revise_definition","record":rr(1),"expected_version":current_rule["record_version_id"],"replacement":tightened});
    blocked(
        &mut c,
        &ctx,
        vec![revise.clone()],
        "tighten-without-correction",
        "refuted",
    )
    .await;
    // Correct the retained assertion and rule atomically; previous versions survive.
    let mut corrected = old_assertion["payload"].clone();
    corrected.as_object_mut().unwrap().remove("record_kind");
    corrected["validity"] = interval(20, 30);
    admit(&mut c,&ctx,vec![revise,json!({"kind":"supersede_assertion","record":{"universe":u["universe_id"],"record":old_assertion["identity"]["record_id"]},"expected_version":old_assertion["record_version_id"],"replacement":corrected,"rationale":"Successor starts after the prior terms"})],"cardinality-correction").await;
    let history = |revision: Value| {
        tool(
            "universe_open_context",
            json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":revision},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}),
        )
    };
    let historical_ctx =
        c.call(history(receipt["revision"].clone())).await.unwrap()["result"]["context_id"].clone();
    let ids = json!([id(1), old_assertion["identity"]["record_id"]]);
    let before = get(&mut c, &historical_ctx, ids.clone()).await;
    // Proposal preview requires a current head. Fork the pinned historical
    // snapshot with the existing operation to recompute its original rule.
    let branch = ContinuityId::generate(&mut rand::rng());
    c.call(EngineRequest::ForkContinuity {
        universe: Selector("Alpha".into()),
        name: "Historical cardinality".into(),
        continuity_id: branch.clone(),
        source: serde_json::from_value(u["continuity_id"].clone()).unwrap(),
        revision: serde_json::from_value(receipt["revision"].clone()).unwrap(),
    })
    .await
    .unwrap();
    let mut historical_universe = u.clone();
    historical_universe["continuity_id"] = json!(branch);
    let branch_ctx = context(&mut c, &historical_universe, "Alpha").await;
    let p = proposal(
        &mut c,
        &branch_ctx,
        vec![fact(60, 13, interval(0, 10))],
        "historical-max-two-before",
    )
    .await;
    let v = validate(&mut c, &branch_ctx, &p).await;
    assert_eq!(v["coverage"], "complete");
    assert!(v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    assert!(before.as_array().unwrap().contains(&old_assertion));
    assert!(before.as_array().unwrap().contains(&current_rule));
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let historical_ctx =
        c.call(history(receipt["revision"].clone())).await.unwrap()["result"]["context_id"].clone();
    assert_eq!(get(&mut c, &historical_ctx, ids.clone()).await, before);
    let branch_ctx = context(&mut c, &historical_universe, "Alpha").await;
    let p = proposal(
        &mut c,
        &branch_ctx,
        vec![fact(62, 13, interval(0, 10))],
        "historical-max-two-after",
    )
    .await;
    let v = validate(&mut c, &branch_ctx, &p).await;
    assert_eq!(v["coverage"], "complete");
    assert!(v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    let ctx = context(&mut c, &u, "Alpha").await;
    blocked(
        &mut c,
        &ctx,
        vec![fact(64, 13, interval(0, 10))],
        "head-max-one-at-old-time",
        "refuted",
    )
    .await;
    let head = get(&mut c, &ctx, ids).await;
    assert!(head
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["payload"]["relationCardinality"]["maximum"] == 1));
    assert!(head
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["payload"]["validity"] == interval(20, 30)));
    blocked(
        &mut c,
        &ctx,
        vec![fact(50, 12, interval(22, 25))],
        "restart-enforcement",
        "refuted",
    )
    .await;
    admit(
        &mut c,
        &ctx,
        vec![fact(52, 13, interval(20, 30))],
        "restart-duplicate",
    )
    .await;
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
