use super::*;
async fn universe(c: &mut EngineClient, name: &str) -> Value {
    c.call(EngineRequest::CreateUniverse {
        name: name.into(),
        start: universe_domain::chronology::UniverseStart::Fictional {
            calendar_name: "Days".into(),
            initial_tick: "0".into(),
            tick_label: "days".into(),
            ticks_per_month: Some(30),
        },
    })
    .await
    .unwrap()
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn named_world_scope_narratives_cursors_and_cross_universe_references() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let a = universe(&mut c, "Alpha").await;
    let b = universe(&mut c, "Beta").await;
    assert_ne!(a["universe_id"], b["universe_id"]);
    let a0 = context(&mut c, &a, "Alpha").await;
    let b0 = context(&mut c, &b, "Beta").await;
    let id = |n| format!("rec_{:024x}", 10000 + n);
    let wid = |n| format!("wld_{:024x}", 10000 + n);
    let rr = |n| json!({"universe":a["universe_id"],"record":id(n)});
    let association = |n| json!({"world":wid(n),"role":"setting","validity":{"kind":"unspecified"},"qualifiers":{}});
    // V05: shared material requires no placeholder world.
    admit(&mut c, &a0, vec![entity("Shared", &id(10))], "scope-shared").await;
    let ctx = context(&mut c, &a, "Alpha").await;
    let d = c
        .call(tool(
            "universe_describe",
            json!({"mode":"definitions","universe":"Alpha","context_id":ctx}),
        ))
        .await
        .unwrap();
    assert!(d["result"]["worlds"].as_array().unwrap().is_empty());
    let work = |n, title: &str| json!({"kind":"create_work","client_ref":id(n),"record":{"kind":"novel","title":title,"labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[association(1),association(2)]}});
    let saga = |n, title: &str| json!({"kind":"create_saga","client_ref":id(n),"record":{"title":title,"labels":{},"memberships":[{"work":rr(11),"role":"volume","order":1},{"work":rr(12),"role":"volume","order":2}]}});
    let mut local = entity("Local", &id(13));
    local["record"]["worldAssociations"] = json!([association(1)]);
    admit(
        &mut c,
        &ctx,
        vec![
            world("Aster", &id(1)),
            world("Nacre", &id(2)),
            work(11, "Two shores"),
            work(12, "Return"),
            saga(21, "Voyages"),
            saga(22, "Anthology"),
            local,
        ],
        "scope-worlds",
    )
    .await;
    let current = context(&mut c, &a, "Alpha").await;
    // V03: an identical world selector in another universe has an independent identity.
    let p=c.call(tool("universe_propose",json!({"action":"create","universe":"Beta","context_id":b0,"operations":[world("Aster",&id(30))],"submission":"submitted","rationale":"Independent world","idempotency_key":"beta-world"}))).await.unwrap()["result"].clone();
    let v=c.call(tool("universe_validate",json!({"mode":"proposal","universe":"Beta","context_id":b0,"proposal_reference":reference(&p),"check_scope":"universe"}))).await.unwrap()["result"]["execution"].clone();
    c.call(EngineRequest::Approve {
        universe: Selector("Beta".into()),
        proposal_reference: reference(&p),
        validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    c.call(tool("universe_commit",json!({"universe":"Beta","proposal_reference":reference(&p),"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["run_id"],"idempotency_key":"beta-world-commit"}))).await.unwrap();
    let bc = context(&mut c, &b, "Beta").await;
    let search = |u: &str, ctx: &Value, w: Option<&str>, limit| {
        let mut q = json!({"universe":u,"context_id":ctx,"query":"","typed_filters":{"record_kinds":[]},"limit":limit});
        if let Some(w) = w {
            q["world"] = json!(w);
        }
        q
    };
    // V10/V11/V12: focus is per request, and omission retains shared/unassigned records.
    let focused = c
        .call(tool(
            "universe_search",
            search("Alpha", &current, Some("Aster"), 100),
        ))
        .await
        .unwrap();
    let all = c
        .call(tool(
            "universe_search",
            search("Alpha", &current, None, 100),
        ))
        .await
        .unwrap();
    assert!(all["result"].to_string().contains(&id(10)));
    assert!(focused["result"].to_string().contains(&id(13)));
    assert!(c
        .call(tool(
            "universe_search",
            search("Beta", &bc, Some("Nacre"), 100)
        ))
        .await
        .is_err());
    assert!(c
        .call(tool(
            "universe_search",
            search("Alpha", &a0, Some("Aster"), 100)
        ))
        .await
        .is_err());
    assert!(c
        .call(tool("universe_search", search("Beta", &current, None, 100)))
        .await
        .is_err());
    // V15: cursors cannot be moved between world/universe views.
    let page = c
        .call(tool(
            "universe_search",
            search("Alpha", &current, Some("Aster"), 1),
        ))
        .await
        .unwrap();
    let cursor = page["delivery"]["cursor"].clone();
    assert!(cursor.is_string(), "{page}");
    for (u, ctx, w) in [
        ("Alpha", &current, Some("Nacre")),
        ("Beta", &bc, Some("Aster")),
    ] {
        let mut q = search(u, ctx, w, 1);
        q["cursor"] = cursor.clone();
        assert!(c.call(tool("universe_search", q)).await.is_err());
    }
    // V14/V21-V23: exact dependency expansion reaches both worlds and both works;
    // each work participates independently in more than one saga.
    let brief=c.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":current,"world":"Aster","focus_ids":[id(21),id(22)],"purpose":"Cross-world narrative bindings","byte_budget":65536}))).await.unwrap();
    for n in [1, 2, 11, 12, 21, 22] {
        assert!(brief["result"].to_string().contains(&id(n)), "missing {n}");
    }
    // V40: references do not turn an accessible second universe into shared canon.
    let mut foreign = work(40, "Invalid crossover");
    foreign["record"]["sourceRefs"] = json!([{"universe":b["universe_id"],"record":id(30)}]);
    let rejected=c.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":current,"operations":[foreign],"submission":"submitted","rationale":"Must reject foreign reference","idempotency_key":"foreign"}))).await;
    assert!(rejected.is_err());
    // V04: canonical selector collisions cannot be admitted.
    assert!(c.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":current,"operations":[world("aStEr",&id(50))],"submission":"submitted","rationale":"Must reject normalized duplicate","idempotency_key":"duplicate-world"}))).await.is_err());
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn s17_s19_s20_advisories_norms_and_s45_unresolved_boundary_with_exact_exception() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = universe(&mut c, "Alpha").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n| format!("rec_{:024x}", 11000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let rule = |n, key: &str, kind: &str, policy: &str| json!({"kind":"define_rule","client_ref":id(n),"record":{"namespace":"acceptance","key":key,"labels":{},"kind":kind,"commitPolicy":policy,"applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":false},"capabilities":["basic.v1"],"executable":true,"validity":{"kind":"unspecified"}}});
    let scope = json!({"applicability":{"kind":"universe_wide"},"context":{"universe":u["universe_id"],"record":u["context_id"]}});
    let boundary = json!({"kind":"set_creative_boundary","client_ref":id(5),"record":{"key":"divine-question","area":{"kind":"record","universe":u["universe_id"],"record":id(1)},"mode":"intentionally_unresolved","constraints":[],"validity":{"kind":"unspecified"},"scope":scope}});
    let p = proposal(
        &mut c,
        &ctx,
        vec![
            entity("Unanswered divine question", &id(1)),
            rule(2, "usually-winged", "behavioral_tendency", "advisory"),
            rule(
                3,
                "custom-after-experience",
                "behavioral_tendency",
                "advisory",
            ),
            rule(4, "jurisdiction-law", "law", "record_finding"),
        ],
        "norms",
    )
    .await;
    let v = validate(&mut c, &ctx, &p).await;
    assert_eq!(v["coverage"], "complete");
    assert_eq!(v["findings"].as_array().unwrap().len(), 3);
    assert!(v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "refuted"));
    publish_proposal(&mut c, &ctx, &p, "norms-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    admit(&mut c, &ctx, vec![boundary], "unanswered").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let read=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(1),id(5)],"field_groups":[]}))).await.unwrap();
    let records = read["result"]["records"].as_array().unwrap();
    let question = records
        .iter()
        .find(|r| r["identity"]["record_id"] == id(1))
        .unwrap();
    let b = records
        .iter()
        .find(|r| r["identity"]["record_id"] == id(5))
        .unwrap();
    let change = json!({"kind":"add_name","record":rr(1),"expected_version":question["record_version_id"],"name":{"text":"Author chooses an answer","language":null,"community":null,"role":null,"validity":{"kind":"unspecified"}}});
    let p = proposal(&mut c, &ctx, vec![change.clone()], "answer").await;
    let v = validate(&mut c, &ctx, &p).await;
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let decision = json!({"kind":"record_issue_decision","client_ref":id(6),"record":{"fingerprints":[],"mode":"accept","scope":id(5),"rationale":"Author explicitly resolves this question","principal":author.as_str().replacen("prf_","prn_",1)}});
    let exception = json!({"kind":"add_exception","client_ref":id(7),"record":{"rule":rr(5),"ruleVersion":b["record_version_id"],"scope":scope,"validity":{"kind":"unspecified"},"authorizingDecision":rr(6),"rationale":"Exact boundary only"}});
    let p = proposal(
        &mut c,
        &ctx,
        vec![change, decision, exception],
        "answer-with-exception",
    )
    .await;
    publish_proposal(&mut c, &ctx, &p, "answer-commit").await;
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn v16_v17_cross_world_journey_preserves_identity_and_failed_destination_is_atomic() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("installation");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = universe(&mut c, "Alpha").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n| format!("rec_{:024x}", 12000 + n);
    let wid = |n| format!("wld_{:024x}", 12000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let clock=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap()["result"]["records"][0]["payload"]["chronology"]["calendar"].clone();
    let scope = json!({"applicability":{"kind":"universe_wide"},"context":{"universe":u["universe_id"],"record":u["context_id"]}});
    let prop = |n, subject, place| json!({"kind":"define_proposition","client_ref":id(n),"record":{"subject":rr(subject),"predicate":rr(7),"roles":[],"value":{"kind":"entity_ref","ref":rr(place)},"quantification":"particular","context":scope["context"]}});
    let effect = |slot: &str, proposition, t, order| json!({"slot":slot,"proposition":rr(proposition),"polarity":"support","scope":scope,"validity":{"kind":"calendar_interval","calendar":clock,"start":{"kind":"exact","value":format!("{t}")},"end":{"kind":"unbounded"}},"order":order});
    let event = |n, t, person, item| json!({"kind":"record_event","client_ref":id(n),"record":{"occurrence":"occurred","worlds":[wid(1),wid(2)],"time":{"kind":"exact","calendar":clock,"value":format!("{t}")},"participants":[{"record":rr(3),"role":"traveler"},{"record":rr(4),"role":"carried item"},{"record":rr(5),"role":"departure"},{"record":rr(6),"role":"destination"}],"labels":{"en":"Crossing"},"effects":[effect("traveler",person,t,0),effect("item",item,t,1)]}});
    let p=proposal(&mut c,&ctx,vec![world("Aster",&id(1)),world("Nacre",&id(2)),entity("Traveler",&id(3)),entity("Unique seal",&id(4)),entity("Aster portal",&id(5)),entity("Nacre portal",&id(6)),json!({"kind":"define_property","client_ref":id(7),"record":{"namespace":"travel","key":"location","labels":{},"value":{"kind":"entity_ref","subject_types":[]},"multiplicity":"single","persistence":"persistent_until_changed","exclusive":true,"symmetric":false,"transitive":false}}),prop(11,3,5),prop(12,4,5),prop(13,3,6),prop(14,4,6),event(21,10,11,12),event(22,20,13,14)],"cross-world").await;
    publish_proposal(&mut c, &ctx, &p, "cross-world-commit").await;
    let current = context(&mut c, &u, "Alpha").await;
    for (tick, place) in [(19, 5), (20, 6)] {
        let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":tick.to_string()}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
        let state=c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"entity_ids":[id(3),id(4)],"predicate_filters":[]}))).await.unwrap();
        let assertions = state["result"]["assertions"].as_array().unwrap();
        assert_eq!(assertions.len(), 2);
        let facts = state["result"]["propositions"].as_array().unwrap();
        assert!(assertions
            .iter()
            .all(|a| facts.iter().any(|p| p["identity"]["record_id"]
                == a["payload"]["proposition"]["record"]
                && p["payload"]["value"]["ref"] == rr(place))));
    }
    let before=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":current,"record_ids":[id(3),id(4),id(22)],"field_groups":[]}))).await.unwrap();
    // First effect names a valid source update; the destination's missing reference
    // fails admission. Neither effect nor a new event may enter canon.
    assert!(c.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":current,"operations":[event(23,25,11,999)],"submission":"submitted","rationale":"Incomplete destination must reject the entire event","idempotency_key":"broken-crossing"}))).await.is_err());
    let after_ctx = context(&mut c, &u, "Alpha").await;
    let after=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":after_ctx,"record_ids":[id(3),id(4),id(22)],"field_groups":[]}))).await.unwrap();
    assert_eq!(before["frame"]["revision"], after["frame"]["revision"]);
    assert_eq!(before["result"], after["result"]);
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
