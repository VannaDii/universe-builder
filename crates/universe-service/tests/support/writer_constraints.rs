use super::*;
async fn brief(c: &mut EngineClient, ctx: &Value, focus: Value) -> Vec<Value> {
    let mut args = json!({"universe":"Alpha","context_id":ctx,"focus_ids":focus,"purpose":"Prepare a factual action with policy and receipt evidence","byte_budget":4096});
    let mut rows = vec![];
    loop {
        let page = c
            .call(tool("universe_get_context", args.clone()))
            .await
            .unwrap();
        rows.extend(page["result"]["records"].as_array().unwrap().clone());
        if page["delivery"]["complete"] == true {
            break;
        }
        args["cursor"] = page["delivery"]["cursor"].clone();
    }
    rows
}
async fn rows(c: &mut EngineClient, ctx: &Value, ids: Value) -> Vec<Value> {
    c.call(tool(
        "universe_get",
        json!({"universe":"Alpha","context_id":ctx,"record_ids":ids,"field_groups":[]}),
    ))
    .await
    .unwrap()["result"]["records"]
        .as_array()
        .unwrap()
        .clone()
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn writer_repairs_and_recovers_receipt_knowledge_action_and_cardinality_dependencies() {
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
    let id = |n: u64| format!("rec_{:024x}", 64000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let cal = rows(&mut c, &ctx, json!([u["context_id"]])).await[0]["payload"]["chronology"]
        ["calendar"]
        .clone();
    let time = |n: i32| json!({"kind":"exact","calendar":cal,"value":n.to_string()});
    let interval = |n: i32| json!({"kind":"calendar_interval","calendar":cal,"start":{"kind":"exact","value":n.to_string()},"end":{"kind":"exact","value":"20"}});
    let scope = json!({"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"universe_wide"}});
    let instance = |n, name: &str, world: u64| json!({"kind":"introduce_instance","client_ref":id(n),"name":{"text":name,"validity":interval(0)},"classification":null,"world_associations":[{"world":format!("wld_{:024x}",64000+world),"role":"setting","validity":interval(0),"qualifiers":{}}]});
    let policy = |n, name: &str, cap: &str| json!({"kind":"define_rule","client_ref":id(n),"record":{"namespace":"writer","key":name,"labels":{"en":name},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[cap],"executable":true,"validity":{"kind":"unspecified"}}});
    let mut chronology = policy(50, "Radio timing", "communications.chronology.v1");
    chronology["record"]["channelChronology"] =
        json!({"channel":"radio","forwardOnly":true,"minimumDelay":"0","maximumDelay":"10"});
    let mut knowledge_policy = policy(51, "Interpreted knowledge", "knowledge.acquisition.v1");
    knowledge_policy["record"]["knowledgePolicy"] =
        json!({"context":scope["context"],"mode":"justified"});
    let mut count = policy(52, "Single successor", "relations.cardinality.v1");
    count["record"]["relationCardinality"] = json!({"relation":rr(60),"grouping":{"kind":"role","role":"office"},"countedRole":"successor","maximum":1,"scope":scope,"validity":{"kind":"unspecified"}});
    let assertion = json!({"attributeMode":"instance","proposition":rr(20),"polarity":"support","scope":scope,"validity":interval(0),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored access code"}});
    let relation = |n, person| json!({"kind":"record_relation","client_ref":id(n),"proposition":{"subject":rr(10),"predicate":rr(60),"roles":[{"role":"office","participant":rr(10)},{"role":"successor","participant":rr(person)}],"quantification":"particular","context":scope["context"]},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":scope,"validity":interval(0),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored succession"}}});
    let message = |n| json!({"kind":"record_communication","client_ref":id(n),"record":{"sender":rr(11),"intendedRecipients":[rr(12)],"actualRecipients":[rr(12)],"content":[rr(20)],"channel":"radio","sentAt":time(1),"receivedAt":time(3),"distorted":false}});
    admit(&mut c,&ctx,vec![world("Visible",&id(1)),world("Private",&id(2)),instance(10,"Office",1),instance(11,"Sender",1),instance(12,"Successor",1),instance(14,"Unrelated focus",1),instance(15,"Hidden person",2),chronology,knowledge_policy,count,json!({"kind":"define_relation","client_ref":id(60),"record":{"namespace":"writer","key":"successor","labels":{},"roles":[{"name":"office","participantTypes":[],"multiplicity":"single","ordered":false},{"name":"successor","participantTypes":[],"multiplicity":"single","ordered":false}]}}),json!({"kind":"define_property","client_ref":id(21),"record":{"namespace":"writer","key":"code","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}}),json!({"kind":"assert_proposition","client_ref":id(20),"proposition":{"subject":rr(10),"predicate":rr(21),"value":{"kind":"boolean","value":true},"quantification":"particular","context":scope["context"]},"assertion":assertion}),message(30),relation(70,12),json!({"kind":"define_action","client_ref":id(80),"record":{"namespace":"writer","key":"open-office","labels":{},"requirements":[],"consequenceContract":{"kind":"action_consequences","slots":[]},"scope":scope,"validity":{"kind":"unspecified"}}})],"writer-seed").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let at = c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":time(4)},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone();
    let state = c.call(tool("universe_get_state",json!({"universe":"Alpha","context_id":at,"entity_ids":[id(12)],"predicate_filters":[]}))).await.unwrap();
    for n in [50, 51, 52] {
        assert!(
            state["result"]["objects"][0]["rules"]
                .as_array()
                .unwrap()
                .iter()
                .any(
                    |r| r["record"]["identity"]["record_id"] == id(n) && r["applicability"] == true
                ),
            "policy applicability: {state}"
        );
    }
    let search = c.call(tool("universe_search", json!({"universe":"Alpha","context_id":ctx,"query":"Single successor","typed_filters":{"record_kinds":["rule"]},"limit":10}))).await.unwrap();
    assert!(
        search["result"]["hits"]
            .as_array()
            .unwrap()
            .iter()
            .any(|hit| hit["record_id"] == id(52) && hit["label"] == "Single successor"),
        "authored policy search: {search}"
    );
    let evidence = brief(&mut c, &ctx, json!([id(14)])).await;
    for n in [50, 51, 52, 70] {
        assert!(
            evidence.iter().any(|r| r["identity"]["record_id"] == id(n)),
            "missing policy/cross-instance evidence {n}"
        );
    }
    let evidence = brief(&mut c, &ctx, json!([id(12)])).await;
    assert!(
        evidence
            .iter()
            .any(|r| r["identity"]["record_id"] == id(30)),
        "receipt discovery before knowledge is authored"
    );
    let knowledge = |n, t: i32| json!({"kind":"add_belief","client_ref":id(n),"record":{"holder":rr(12),"proposition":rr(20),"attitude":"knows","validity":interval(t),"basis":{"kind":"author_decision","note":"Explicit interpreted receipt"},"acquisition":{"truthContext":scope["context"],"time":time(t),"basis":{"kind":"communication_receipt","communication":rr(30),"interpretation":rr(20)}}}});
    let event = |n, t: i32| json!({"kind":"record_event","client_ref":id(n),"record":{"action":rr(80),"occurrence":"occurred","time":time(t),"worlds":[],"participants":[{"role":"actor","record":rr(12)}],"effects":[],"preconditions":[{"kind":"attitude","holder":rr(12),"proposition":rr(20),"attitude":"knows"}],"labels":{}}});
    let p = proposal(
        &mut c,
        &ctx,
        vec![knowledge(90, 4), event(91, 5)],
        "connected-original",
    )
    .await;
    let historical_revision = p["base_frame"]["revision"].clone();
    let v = validate(&mut c, &ctx, &p).await;
    assert_eq!(v["coverage"], "complete");
    assert!(v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference(&p),
        validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    // An earlier truth correction is published before this proposed action.
    let truth = evidence
        .iter()
        .find(|r| {
            r["payload"]["record_kind"] == "assertion"
                && r["payload"]["proposition"]["record"] == id(20)
        })
        .unwrap();
    let mut corrected = truth["payload"].clone();
    corrected.as_object_mut().unwrap().remove("record_kind");
    corrected["validity"] = interval(6);
    admit(&mut c,&ctx,vec![json!({"kind":"supersede_assertion","record":{"universe":u["universe_id"],"record":truth["identity"]["record_id"]},"expected_version":truth["record_version_id"],"replacement":corrected,"rationale":"The access code is established later"})],"earlier-correction").await;
    assert!(c
        .call(commit(&p, &v, "stale-connected-commit"))
        .await
        .is_err());
    let ctx = context(&mut c, &u, "Alpha").await;
    let p = proposal(
        &mut c,
        &ctx,
        vec![knowledge(92, 4), event(93, 5)],
        "connected-rebased",
    )
    .await;
    let v = validate(&mut c, &ctx, &p).await;
    let failure = v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["rule_id"] == id(51) && f["outcome"] != "supported")
        .unwrap();
    assert!(failure["message"]
        .as_str()
        .unwrap()
        .contains("supporting truth"));
    assert!(failure["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["record"] == id(20)));
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference(&p),
            validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    // Repair acquisition first; the event must also move after knowledge onset.
    let p = proposal(
        &mut c,
        &ctx,
        vec![knowledge(94, 7), event(95, 5)],
        "knowledge-only-repair",
    )
    .await;
    let v = validate(&mut c, &ctx, &p).await;
    let failure = v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["rule_id"] == id(95))
        .unwrap();
    assert!(failure["message"]
        .as_str()
        .unwrap()
        .contains("prerequisite"));
    assert!(failure["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["record"] == id(95)));
    admit(
        &mut c,
        &ctx,
        vec![knowledge(96, 7), event(97, 8)],
        "connected-repaired",
    )
    .await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let p = proposal(&mut c, &ctx, vec![relation(72, 11)], "count-conflict").await;
    let v = validate(&mut c, &ctx, &p).await;
    let f = v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["rule_id"] == id(52))
        .unwrap();
    assert_eq!(f["outcome"], "refuted");
    assert!(f["message"].as_str().unwrap().contains("maximum 1"));
    assert!(f["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["record"] == id(70)));
    let repaired_count = c.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"operations":[relation(72,12)],"submission":"submitted","rationale":"Repeated evidence names the existing successor","idempotency_key":"repair-count-proposal"}))).await.unwrap()["result"].clone();
    let repaired_v = validate(&mut c, &ctx, &repaired_count).await;
    assert!(repaired_v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    publish_proposal(&mut c, &ctx, &repaired_count, "count-repair-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let mut reversed = message(32);
    reversed["record"]["receivedAt"] = time(0);
    let p = proposal(&mut c, &ctx, vec![reversed], "chronology-conflict").await;
    let v = validate(&mut c, &ctx, &p).await;
    assert!(v["findings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["rule_id"] == id(50)
            && f["outcome"] == "refuted"
            && f["message"].as_str().unwrap().contains("Transmission")));
    let repaired_message = c.call(tool("universe_propose",json!({"action":"revise","universe":"Alpha","context_id":ctx,"proposal_reference":reference(&p),"operations":[message(32)],"submission":"submitted","rationale":"Correct actual receipt time","idempotency_key":"repair-message-proposal"}))).await.unwrap()["result"].clone();
    publish_proposal(&mut c, &ctx, &repaired_message, "message-repair-commit").await;
    let ctx = context(&mut c, &u, "Alpha").await;
    // Restricted validation stays invariant while visible retrieval still helps.
    let enrolled: ProfileId =
        serde_json::from_value(c.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone())
            .unwrap();
    c.call(EngineRequest::Grant {
        grant: GrantSpec {
            profile_id: enrolled.clone(),
            universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
            worlds: Some(vec![WorldId::parse(&format!("wld_{:024x}", 64001)).unwrap()]),
            propose: true,
            edit: true,
            protected: false,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let mut restricted = connect(&root, &enrolled).await;
    let rctx = context(&mut restricted, &u, "Alpha").await;
    let visible = brief(&mut restricted, &rctx, json!([id(12)])).await;
    assert!(!json!(visible).to_string().contains(&id(15)));
    assert!(visible.iter().any(|r| r["identity"]["record_id"] == id(30)));
    let restricted_check = |ctx: Value| {
        tool(
            "universe_validate",
            json!({"mode":"inline","universe":"Alpha","context_id":ctx,"operations":[event(99,8)],"check_scope":"universe"}),
        )
    };
    let first = restricted
        .call(restricted_check(rctx.clone()))
        .await
        .unwrap()["result"]
        .clone();
    assert_eq!(first["kind"], "restricted");
    assert!(first.get("execution").is_none());
    admit(
        &mut c,
        &ctx,
        vec![instance(16, "Another hidden fact", 2)],
        "hidden-change",
    )
    .await;
    let rctx = context(&mut restricted, &u, "Alpha").await;
    assert_eq!(
        restricted.call(restricted_check(rctx)).await.unwrap()["result"],
        first
    );
    let description = restricted
        .call(tool(
            "universe_describe",
            json!({"mode":"capabilities","universe":"Alpha"}),
        ))
        .await
        .unwrap();
    assert!(description.to_string().contains("author validation"));
    drop(restricted);
    let ctx = context(&mut c, &u, "Alpha").await;
    // Persist every new typed field in both authored operations and compiled proposal records.
    let mut pending_ops = vec![
        message(130),
        knowledge(196, 7),
        event(197, 9),
        relation(170, 12),
    ];
    for n in [50, 51, 52] {
        let record = rows(&mut c, &ctx, json!([id(n)])).await.remove(0);
        let mut payload = record["payload"].clone();
        payload.as_object_mut().unwrap().remove("record_kind");
        payload["key"] = json!(format!("pending-{n}"));
        pending_ops.push(json!({"kind":"define_rule","client_ref":id(n+100),"record":payload}));
    }
    let pending = proposal(&mut c, &ctx, pending_ops.clone(), "recovery-pending").await;
    let pending_validation = validate(&mut c, &ctx, &pending).await;
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference(&pending),
        validation_run: serde_json::from_value(pending_validation["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    let load = EngineRequest::LoadDraft {
        universe: Selector("Alpha".into()),
        continuity_id: serde_json::from_value(u["continuity_id"].clone()).unwrap(),
    };
    let saved = c
        .call(EngineRequest::SaveDraft {
            universe: Selector("Alpha".into()),
            continuity_id: serde_json::from_value(u["continuity_id"].clone()).unwrap(),
            expected_version: 0,
            content: DraftContent {
                proposal: Some(reference(&pending)),
                base_revision: serde_json::from_value(pending["base_frame"]["revision"].clone())
                    .unwrap(),
                represented_context: serde_json::from_value(u["context_id"].clone()).unwrap(),
                operations: serde_json::from_value(json!(pending_ops)).unwrap(),
                rationale: "Pending connected constraints".into(),
            },
        })
        .await
        .unwrap();
    let snapshot_ids = json!([
        id(50),
        id(51),
        id(52),
        id(20),
        id(30),
        id(70),
        id(96),
        id(97),
        truth["identity"]["record_id"]
    ]);
    let expected = rows(&mut c, &ctx, snapshot_ids.clone()).await;
    let historical = c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":historical_revision},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone();
    let expected_old = rows(
        &mut c,
        &historical,
        json!([
            id(20),
            id(50),
            id(51),
            id(52),
            id(30),
            truth["identity"]["record_id"]
        ]),
    )
    .await;
    assert_ne!(
        expected_old
            .iter()
            .find(|r| r["identity"]["record_id"] == truth["identity"]["record_id"])
            .unwrap(),
        expected
            .iter()
            .find(|r| r["identity"]["record_id"] == truth["identity"]["record_id"])
            .unwrap()
    );
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    // Restart the source before exporting, so recovery does not rely on live caches.
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    assert_eq!(c.call(load.clone()).await.unwrap(), saved);
    let ctx = context(&mut c, &u, "Alpha").await;
    assert_eq!(rows(&mut c, &ctx, snapshot_ids.clone()).await, expected);
    let after_restart = validate(&mut c, &ctx, &pending).await;
    assert!(after_restart["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    let backup = dir.path().join("constraint-backup.sqlite");
    let archive = dir.path().join("constraint-history.sqlite");
    c.call(EngineRequest::Backup {
        universe: Selector("Alpha".into()),
        destination: backup.clone(),
    })
    .await
    .unwrap();
    let manifest = c
        .call(EngineRequest::ExportLogical {
            universe: Selector("Alpha".into()),
            destination: archive.clone(),
            record_ids: vec![],
            complete_history: true,
        })
        .await
        .unwrap();
    assert_eq!(manifest["includes_workflow"], true);
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    let source = universe_store::kernel::Kernel::open(&backup).unwrap();
    let workflow: Vec<_> = source
        .workflow_keys("")
        .unwrap()
        .into_iter()
        .filter(|k| {
            k.starts_with("draft:")
                || k.starts_with("proposal:")
                || k.starts_with("validation:")
                || k.starts_with("approval:")
        })
        .map(|k| {
            let v = source.workflow_evidence_get(&k).unwrap().unwrap();
            (k, v)
        })
        .collect();
    assert!(workflow
        .iter()
        .any(|(k, v)| k.starts_with("draft:") && v == &saved));
    let stored = &workflow
        .iter()
        .find(|(k, v)| {
            k.starts_with("proposal:") && v["proposal"]["proposal_id"] == pending["proposal_id"]
        })
        .unwrap()
        .1;
    for (canonical, proposed, field) in [
        (50, 150, "channelChronology"),
        (51, 151, "knowledgePolicy"),
        (52, 152, "relationCardinality"),
        (96, 196, "acquisition"),
    ] {
        let original = expected
            .iter()
            .find(|r| r["identity"]["record_id"] == id(canonical))
            .unwrap();
        let compiled = stored["changes"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["record_id"] == id(proposed))
            .unwrap();
        assert_eq!(
            compiled["next"]["payload"][field], original["payload"][field],
            "compiled field {field}"
        );
        assert!(!compiled["next"]["payload"][field].is_null());
    }
    drop(source);
    for logical in [false, true] {
        let restored = dir.path().join(if logical {
            "archive-install"
        } else {
            "backup-install"
        });
        let current_author = runtime::initialize(&restored).unwrap();
        assert_ne!(current_author, author);
        let stop = CancellationToken::new();
        let (r, s) = (restored.clone(), stop.clone());
        let server = tokio::spawn(async move { runtime::serve(&r, s).await });
        let mut c = connect(&restored, &current_author).await;
        let mut restored_u = u.clone();
        if logical {
            let preview = c
                .call(EngineRequest::PreviewImport {
                    source: archive.clone(),
                    name: "Alpha".into(),
                    mode: ImportMode::Clone,
                })
                .await
                .unwrap();
            assert!(preview["conflicts"].as_array().unwrap().is_empty());
            c.call(EngineRequest::AcceptImport {
                preview_id: serde_json::from_value(preview["preview_id"].clone()).unwrap(),
                digest: preview["digest"].as_str().unwrap().into(),
            })
            .await
            .unwrap();
            restored_u["universe_id"] = preview["target_universe"].clone();
        } else {
            c.call(EngineRequest::Restore {
                source: backup.clone(),
                name: "Alpha".into(),
            })
            .await
            .unwrap();
        }
        // Original approvals and private drafts never become this installation's authority.
        assert!(c
            .call(commit(
                &pending,
                &pending_validation,
                "foreign-approved-commit"
            ))
            .await
            .is_err());
        assert_eq!(c.call(load.clone()).await.unwrap(), Value::Null);
        drop(c);
        stop.cancel();
        server.await.unwrap().unwrap();
        let path = restored.join("packages").join(format!(
            "{}.sqlite",
            restored_u["universe_id"].as_str().unwrap()
        ));
        let kernel = universe_store::kernel::Kernel::open(&path).unwrap();
        for (key, value) in &workflow {
            assert_eq!(
                kernel.workflow_evidence_get(key).unwrap().as_ref(),
                Some(value),
                "workflow recovery: {key}"
            );
        }
        if logical {
            assert!(kernel.workflow_keys("approval:").unwrap().is_empty());
        }
        drop(kernel);
        // Restart the recovered installation, then continue with newly issued permissions.
        let stop = CancellationToken::new();
        let (r, s) = (restored.clone(), stop.clone());
        let server = tokio::spawn(async move { runtime::serve(&r, s).await });
        let mut c = connect(&restored, &current_author).await;
        let ctx = context(&mut c, &restored_u, "Alpha").await;
        let mapped = |mut value: Value| {
            remap_test_references(&mut value, &u["universe_id"], &restored_u["universe_id"]);
            value
        };
        let actual = rows(&mut c, &ctx, snapshot_ids.clone()).await;
        for old in &expected {
            let row = actual
                .iter()
                .find(|r| r["identity"]["record_id"] == old["identity"]["record_id"])
                .unwrap();
            assert_eq!(row["payload"], mapped(old["payload"].clone()));
            assert_eq!(row["record_version_id"], old["record_version_id"]);
        }
        let historical = c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":historical_revision},"represented_context":u["context_id"],"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone();
        let actual_old = rows(
            &mut c,
            &historical,
            json!([
                id(20),
                id(50),
                id(51),
                id(52),
                id(30),
                truth["identity"]["record_id"]
            ]),
        )
        .await;
        for old in &expected_old {
            let row = actual_old
                .iter()
                .find(|r| r["identity"]["record_id"] == old["identity"]["record_id"])
                .unwrap();
            assert_eq!(row["payload"], mapped(old["payload"].clone()));
            assert_eq!(row["record_version_id"], old["record_version_id"]);
        }
        let mut reversed = message(230);
        reversed["record"]["receivedAt"] = time(0);
        let mut unsupported = knowledge(296, 7);
        unsupported["record"]["acquisition"]["basis"]
            .as_object_mut()
            .unwrap()
            .remove("interpretation");
        for (op, rule, outcome, key) in [
            (reversed, 50, "refuted", "bad-chronology"),
            (unsupported, 51, "not_established", "unsupported-knowledge"),
            (relation(270, 11), 52, "refuted", "excess-successor"),
        ] {
            let p = proposal(&mut c, &ctx, vec![mapped(op)], key).await;
            let v = validate(&mut c, &ctx, &p).await;
            assert!(
                v["findings"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|f| f["rule_id"] == id(rule) && f["outcome"] == outcome),
                "restored constraint {key}: {v}"
            );
            assert!(c
                .call(EngineRequest::Approve {
                    universe: Selector("Alpha".into()),
                    proposal_reference: reference(&p),
                    validation_run: serde_json::from_value(v["run_id"].clone()).unwrap()
                })
                .await
                .is_err());
        }
        let agent: ProfileId = serde_json::from_value(
            c.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone(),
        )
        .unwrap();
        let mut writer = connect(&restored, &agent).await;
        assert!(writer.call(load.clone()).await.is_err());
        c.call(EngineRequest::Grant {
            grant: GrantSpec {
                profile_id: agent.clone(),
                universe_id: serde_json::from_value(restored_u["universe_id"].clone()).unwrap(),
                worlds: None,
                propose: true,
                edit: true,
                protected: false,
                limits: Default::default(),
            },
        })
        .await
        .unwrap();
        let writer_ctx = context(&mut writer, &restored_u, "Alpha").await;
        assert!(writer.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":writer_ctx,"operations":[mapped(event(297,9))],"submission":"submitted","rationale":"Current protected-action grant required","idempotency_key":"denied-continuation"}))).await.unwrap_err().to_string().contains("full write footprint"));
        c.call(EngineRequest::Grant {
            grant: GrantSpec {
                profile_id: agent,
                universe_id: serde_json::from_value(restored_u["universe_id"].clone()).unwrap(),
                worlds: None,
                propose: true,
                edit: true,
                protected: true,
                limits: Default::default(),
            },
        })
        .await
        .unwrap();
        let writer_ctx = context(&mut writer, &restored_u, "Alpha").await;
        let p = proposal(
            &mut writer,
            &writer_ctx,
            vec![mapped(event(297, 9))],
            "continued-action",
        )
        .await;
        assert!(writer
            .call(commit(&p, &pending_validation, "unapproved-agent-commit"))
            .await
            .is_err());
        publish_proposal(&mut c, &ctx, &p, "continued-author-approved").await;
        let ctx = context(&mut c, &restored_u, "Alpha").await;
        assert_eq!(
            rows(&mut c, &ctx, json!([id(297)])).await[0]["payload"]["time"],
            time(9)
        );
        drop(writer);
        drop(c);
        stop.cancel();
        server.await.unwrap().unwrap();
    }
}

// Expected namespace remapping for clone assertions; workflow evidence keeps original bindings.
fn remap_test_references(value: &mut Value, source: &Value, target: &Value) {
    match value {
        Value::Object(fields) => {
            if fields.get("universe") == Some(source) {
                fields.insert("universe".into(), target.clone());
            }
            for child in fields.values_mut() {
                remap_test_references(child, source, target);
            }
        }
        Value::Array(items) => {
            for child in items {
                remap_test_references(child, source, target);
            }
        }
        _ => {}
    }
}
