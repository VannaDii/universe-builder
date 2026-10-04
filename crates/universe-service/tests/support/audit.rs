use super::*;
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn audit_eight_completion_paths() {
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
    let ctx = context(&mut c, &u, "Alpha").await;
    let id = |n| format!("rec_{n:024x}");
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let claim = |n, polarity| json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(1),"predicate":rr(2),"roles":[],"value":{"kind":"boolean","value":true},"quantification":"particular","context":{"universe":u["universe_id"],"record":u["context_id"]}},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":polarity,"scope":{"applicability":{"kind":"universe_wide"},"context":{"universe":u["universe_id"],"record":u["context_id"]}},"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","basis":{"kind":"author_decision","note":"Authored evidence"}}});
    admit(&mut c,&ctx,vec![world("Terra",&id(30)),entity("Mara",&id(1)),json!({"kind":"define_property","client_ref":id(2),"record":{"namespace":"audit","key":"awake","labels":{},"value":{"kind":"boolean"},"multiplicity":"multiple","persistence":"unspecified","exclusive":false,"symmetric":false,"transitive":false}}),claim(3,"support"),claim(4,"refutation")],"audit-seed").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let contexts:Vec<_>=[(5,"character","holder"),(6,"narrator","narrator")].into_iter().map(|(n,kind,holder)| {
        let mut kind_value=json!({"kind":kind}); kind_value[holder]=rr(1);
        json!({"kind":"record_narrative_reference","client_ref":id(n),"record":"represented_context","payload":{"record_kind":"represented_context","universe":u["universe_id"],"kind":kind_value,"labels":{}}})
    }).collect();
    admit(&mut c, &ctx, contexts, "audit-perspectives").await;
    for (n, kind) in [(5, "character"), (6, "narrator")] {
        let mut perspective = json!({});
        perspective[kind] = json!(id(1));
        let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":id(n),"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":perspective}))).await.unwrap();
        let view=c.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"focus_ids":[id(1)],"purpose":"Perspective","byte_budget":65536}))).await.unwrap();
        assert!(
            !view["result"]["records"]
                .as_array()
                .unwrap()
                .iter()
                .any(|r| r["payload"]["record_kind"] == "assertion"),
            "objective evidence must not leak into {kind} view"
        );
    }
    let ctx = context(&mut c, &u, "Alpha").await;
    let work=admit(&mut c,&ctx,vec![json!({"kind":"create_work","client_ref":id(40),"record":{"kind":"novel","title":"Disclosures","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]}})],"reader-work").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    admit(&mut c,&ctx,vec![json!({"kind":"record_narrative_reference","client_ref":id(41),"record":"work_version","payload":{"record_kind":"work_version","work":rr(40),"versionLabel":"First edition","binding":{"kind":"bound","continuity":u["continuity_id"],"revision":work["revision"]}}})],"reader-edition").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let edition=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(41)],"field_groups":["payload"]}))).await.unwrap();
    let version = json!({"universe":u["universe_id"],"record":id(41),"version":edition["result"]["records"][0]["record_version_id"]});
    let scenes=[(42,1,1),(43,2,4)].into_iter().map(|(n,position,disclosed)|json!({"kind":"record_narrative_reference","client_ref":id(n),"record":"scene_ref","payload":{"record_kind":"scene_ref","workVersion":version,"sceneId":format!("scene-{position}"),"viewpoint":null,"narrativePosition":position,"disclosedRecords":[rr(disclosed)],"depictedEvents":[],"narrationFrame":null,"worldAssociations":[]}})).collect();
    admit(&mut c, &ctx, scenes, "reader-scenes").await;
    for (scene, knows_future) in [(42, false), (43, true)] {
        let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"reader","reader_scene":id(scene)}))).await.unwrap();
        let access=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"record_ids":[id(4)],"field_groups":["payload"]}))).await;
        assert_eq!(
            access.is_ok(),
            knows_future,
            "reader disclosure follows explicit edition/scene order"
        );
    }
    let ctx = context(&mut c, &u, "Alpha").await;
    admit(
        &mut c,
        &ctx,
        (200..240).map(|n| claim(n, "support")).collect(),
        "large-context-manifest",
    )
    .await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let brief=c.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":ctx,"focus_ids":[id(1)],"purpose":"Established facts about Mara","byte_budget":65536}))).await.unwrap();
    let records = brief["result"]["records"].as_array().unwrap();
    for polarity in ["support", "refutation"] {
        assert!(records
            .iter()
            .any(|r| r["payload"]["record_kind"] == "assertion"
                && r["payload"]["polarity"] == polarity));
    }
    assert_eq!(brief["result"]["coverage"], "complete");
    let fields=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[id(1)],"field_groups":["summary","evidence","history"]}))).await.unwrap();
    assert!(fields["result"]["records"].as_array().unwrap().is_empty());
    assert_eq!(fields["result"]["summaries"][0]["label"], "Mara");
    assert!(!fields["result"]["evidence"].as_array().unwrap().is_empty());
    assert_eq!(fields["result"]["history_coverage"], "complete");
    assert_eq!(fields["result"]["history"][0]["record_id"], id(1));
    let mut args = json!({"universe":"Alpha","context_id":ctx,"focus_ids":[id(1)],"purpose":"paged","byte_budget":2400});
    let mut collected = std::collections::BTreeSet::new();
    let mut pages = 0;
    loop {
        let page = c
            .call(tool("universe_get_context", args.clone()))
            .await
            .unwrap();
        pages += 1;
        for r in page["result"]["records"].as_array().unwrap() {
            assert!(collected.insert(r["identity"]["record_id"].as_str().unwrap().to_string()));
        }
        if page["delivery"]["complete"] == true {
            break;
        }
        assert!(pages < 100);
        args["cursor"] = page["delivery"]["cursor"].clone();
    }
    assert!(pages > 1);
    assert_eq!(collected.len(), records.len());
    args.as_object_mut().unwrap().remove("cursor");
    args["byte_budget"] = json!(256);
    assert!(c.call(tool("universe_get_context", args)).await.is_err());
    for (name, mut args) in [
        (
            "universe_describe",
            json!({"mode":"definitions","context_id":ctx}),
        ),
        (
            "universe_validate",
            json!({"mode":"inline","context_id":ctx,"operations":[entity("Other",&id(9))],"check_scope":"candidate"}),
        ),
        (
            "universe_get_impact",
            json!({"mode":"inline","context_id":ctx,"changed_records":[id(1)],"scope":"universe","byte_budget":65536}),
        ),
    ] {
        args["universe"] = json!("Alpha");
        args["world"] = json!("Missing");
        assert!(
            c.call(tool(name, args.clone())).await.is_err(),
            "{name} must resolve its world selector"
        );
        args["world"] = json!("Terra");
        args["world_id"] = json!("wld_ffffffffffffffffffffffff");
        assert!(
            c.call(tool(name, args)).await.is_err(),
            "{name} must enforce its world guard"
        );
    }
    let many = proposal(
        &mut c,
        &ctx,
        (100..141)
            .map(|n| entity(&format!("Entry {n}"), &id(n)))
            .collect(),
        "paged-proposal",
    )
    .await;
    let mut args =
        json!({"universe":"Alpha","proposal_id":many["proposal_id"],"version":many["version"]});
    let mut operations = 0;
    let mut changes = 0;
    let mut pages = 0;
    loop {
        let page = c
            .call(tool("universe_get_proposal", args.clone()))
            .await
            .unwrap();
        pages += 1;
        assert_eq!(page["result"]["digest"], many["digest"]);
        operations += page["result"]["operations"].as_array().unwrap().len();
        changes += page["result"]["compiled_changes"].as_array().unwrap().len();
        if page["delivery"]["complete"] == true {
            break;
        }
        args["cursor"] = page["delivery"]["cursor"].clone();
        assert!(pages < 10);
    }
    assert_eq!((operations, changes, pages), (41, 41, 3));
    let researcher: ProfileId =
        serde_json::from_value(c.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone())
            .unwrap();
    let mut grant = GrantSpec {
        profile_id: researcher.clone(),
        universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
        worlds: None,
        propose: false,
        edit: false,
        protected: false,
        limits: Default::default(),
    };
    c.call(EngineRequest::Grant {
        grant: grant.clone(),
    })
    .await
    .unwrap();
    let mut research = connect(&root, &researcher).await;
    let rctx = context(&mut research, &u, "Alpha").await;
    let check=research.call(tool("universe_validate",json!({"mode":"inline","universe":"Alpha","context_id":rctx,"operations":[claim(20,"support")],"check_scope":"universe"}))).await.unwrap();
    assert_eq!(check["result"]["execution"]["coverage"], "complete");
    grant.propose = true;
    grant.edit = true;
    grant.limits = GrantLimits {
        entities: Some(vec![RecordId::parse(&id(1)).unwrap()]),
        predicates: Some(vec![RecordId::parse(&id(2)).unwrap()]),
        continuities: Some(vec![
            serde_json::from_value(u["continuity_id"].clone()).unwrap()
        ]),
        expires_at: Some(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs()
                + 3600,
        ),
        delegated_commit: true,
        allow_shared: true,
    };
    c.call(EngineRequest::Grant { grant }).await.unwrap();
    let rctx = context(&mut research, &u, "Alpha").await;
    let p = proposal(
        &mut research,
        &rctx,
        vec![claim(20, "support")],
        "delegated-claim",
    )
    .await;
    let v = validate(&mut research, &rctx, &p).await;
    research
        .call(commit(&p, &v, "delegated-commit"))
        .await
        .unwrap();
    let rctx = context(&mut research, &u, "Alpha").await;
    assert!(research.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":rctx,"operations":[entity("Outside grant",&id(21))],"submission":"submitted","rationale":"Must reject","idempotency_key":"outside-grant"}))).await.is_err());
    let profiles = c.call(EngineRequest::Profiles).await.unwrap();
    assert!(profiles["profiles"].as_array().unwrap().len() == 2);
    assert!(!profiles.to_string().contains("credential"));
    assert!(research.call(EngineRequest::Profiles).await.is_err());
    c.call(EngineRequest::WithdrawGrant {
        profile_id: researcher,
        universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    assert!(research
        .call(tool(
            "universe_describe",
            json!({"mode":"summary","universe":"Alpha"})
        ))
        .await
        .is_err());
    for pack in universe_domain::starter::CATALOG {
        let ctx = context(&mut c, &u, "Alpha").await;
        let ops = universe_domain::starter::operations(pack.key)
            .unwrap()
            .into_iter()
            .map(|op| serde_json::to_value(op).unwrap())
            .collect();
        admit(&mut c, &ctx, ops, &format!("starter-{}", pack.key)).await;
    }
    let preview = c
        .call(EngineRequest::PreviewPurge {
            universe: Selector("Alpha".into()),
        })
        .await
        .unwrap();
    context(&mut c, &u, "Alpha").await; // A new workflow write makes the destructive preview stale.
    assert!(c
        .call(EngineRequest::Purge {
            universe: Selector("Alpha".into()),
            digest: preview["digest"].as_str().unwrap().into(),
            confirmation: "PURGE Alpha".into()
        })
        .await
        .is_err());
    let preview = c
        .call(EngineRequest::PreviewPurge {
            universe: Selector("Alpha".into()),
        })
        .await
        .unwrap();
    assert!(research
        .call(EngineRequest::Purge {
            universe: Selector("Alpha".into()),
            digest: preview["digest"].as_str().unwrap().into(),
            confirmation: "PURGE Alpha".into()
        })
        .await
        .is_err());
    c.call(EngineRequest::Purge {
        universe: Selector("Alpha".into()),
        digest: preview["digest"].as_str().unwrap().into(),
        confirmation: "PURGE Alpha".into(),
    })
    .await
    .unwrap();
    assert!(c.call(EngineRequest::Status).await.unwrap()["universes"]
        .as_array()
        .unwrap()
        .is_empty());
    drop(research);
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
