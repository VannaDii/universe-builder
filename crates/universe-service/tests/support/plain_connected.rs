use super::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_connected_changes_preserve_events_attribution_retcons_and_authority() {
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
    let clock=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap();
    let cal = clock["result"]["records"][0]["payload"]["chronology"]["calendar"].clone();
    let id = |n: u64| format!("rec_{:024x}", 90000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let scope = json!({"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"universe_wide"}});
    let interval = |end: Value| json!({"kind":"calendar_interval","calendar":cal,"start":{"kind":"exact","value":"0"},"end":end});
    let property = |n, key: &str, shape: Value| json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"story","key":key,"labels":{},"subjectTypes":[],"value":shape,"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}});
    let fact = |n, subject, predicate, value: Value, end: Value| json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(subject),"predicate":rr(predicate),"value":value,"context":scope["context"],"quantification":"particular"},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":scope,"validity":interval(end),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Explicit authored setup"}}});
    let action = |n, key: &str, delta: &str| json!({"kind":"define_action","client_ref":id(n),"record":{"namespace":"story","key":key,"labels":{},"requirements":[],"consequenceContract":{"kind":"action_consequences","slots":[{"slot":"stock","order":0,"presence":"required","target":{"role":"pistol","predicate":rr(10)},"condition":{"kind":"always"},"change":{"kind":"delta","delta":delta,"minimum":"0","maximum":"6","unit":null},"lifetime":{"kind":"until_changed"}}]},"scope":scope,"validity":{"kind":"unspecified"}}});
    let policy = |n, key: &str, cap: &str| json!({"kind":"define_rule","client_ref":id(n),"record":{"namespace":"story","key":key,"labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[cap],"executable":true,"validity":{"kind":"unspecified"}}});
    let mut knowledge = policy(50, "Knowledge", "knowledge.acquisition.v1");
    knowledge["record"]["knowledgePolicy"] = json!({"context":scope["context"],"mode":"justified"});
    let mut channel = policy(51, "Radio", "communications.chronology.v1");
    channel["record"]["channelChronology"] =
        json!({"channel":"radio","forwardOnly":true,"minimumDelay":"0","maximumDelay":"10"});
    admit(&mut c,&ctx,vec![entity("Pistol",&id(1)),entity("Sender",&id(2)),entity("Recipient",&id(3)),entity("Office",&id(4)),property(10,"rounds",json!({"kind":"integer"})),property(11,"code",json!({"kind":"text"})),fact(20,1,10,json!({"kind":"integer","digits":"2"}),json!({"kind":"exact","value":"4"})),fact(21,4,11,json!({"kind":"text","text":"green"}),json!({"kind":"unbounded"})),action(30,"fire","-1"),action(31,"replenish","1"),json!({"kind":"define_action","client_ref":id(32),"record":{"namespace":"story","key":"open-office","labels":{},"requirements":[],"consequenceContract":{"kind":"action_consequences","slots":[]},"scope":scope,"validity":{"kind":"unspecified"}}}),knowledge,channel,json!({"kind":"define_rule","client_ref":id(52),"record":{"namespace":"story","key":"accounting","labels":{},"kind":"physical_constraint","commitPolicy":"block_unless_exception","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":["story:rounds"],"expression":{"kind":"lit","value":true},"capabilities":["resources.accounting.v1"],"executable":true,"validity":{"kind":"unspecified"}}})],"plain-seed").await;
    let open = |tick: &str| {
        tool(
            "universe_open_context",
            json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":cal,"value":tick}},"temporal_systems":[],"perspective":"author"}),
        )
    };
    let at = c.call(open("4")).await.unwrap()["result"]["context_id"].clone();
    let contracts = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":at,"action_names":["fire"]}),
        ))
        .await
        .unwrap();
    assert_eq!(
        contracts["result"]["actions"][0]["effects"][0]["property"],
        "rounds"
    );
    assert_eq!(
        contracts["result"]["knowledge_policies"][0]["mode"],
        "justified"
    );
    let timeless = context(&mut c, &u, "Alpha").await;
    let held=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"events":[{"action":"fire","participants":{"pistol":"Pistol"}}]}))).await.unwrap();
    assert_eq!(held["result"]["status"], "needs_clarification");
    assert!(held["result"]["candidate_handle"].is_null());
    let timed=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"events":[{"action":"fire","participants":{"pistol":"Pistol"},"at_tick":"4"}]}))).await.unwrap();
    assert_eq!(timed["result"]["status"], "checked_candidate", "{timed}");
    let unavailable=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"events":[{"action":"unwritten-action","participants":{"pistol":"Pistol"},"at_tick":"4"}]}))).await.unwrap();
    assert!(unavailable["result"]["candidate_handle"].is_null());
    let diagnostic = unavailable["result"]["clarifications"].to_string();
    assert!(
        diagnostic.contains("fire")
            && diagnostic.contains("pistol")
            && diagnostic.contains("Visible authored choices")
    );
    let dated_args = json!({"universe":"Alpha","context_id":timeless,"changes":[{"name":"Recipient","facts":[{"property":"scene_note","value":"waiting","scope":"universe","at_tick":"6","lifetime":{"kind":"until","end_tick":"8"}}]}]});
    let dated = c
        .call(tool("universe_check_changes", dated_args.clone()))
        .await
        .unwrap();
    assert_eq!(dated["result"]["status"], "checked_candidate", "{dated}");
    let p=c.call(tool("universe_get_proposal",json!({"universe":"Alpha","proposal_id":dated["result"]["candidate_handle"],"version":1}))).await.unwrap();
    let assertion = p["result"]["operations"]
        .as_array()
        .unwrap()
        .iter()
        .find(|op| op["kind"] == "assert_proposition")
        .unwrap();
    assert_eq!(assertion["assertion"]["persistence"], "unspecified");
    assert_eq!(assertion["assertion"]["validity"]["start"]["value"], "6");
    assert_eq!(assertion["assertion"]["validity"]["end"]["value"], "8");
    let mut undated_args = dated_args;
    undated_args["changes"][0]["facts"][0]
        .as_object_mut()
        .unwrap()
        .remove("at_tick");
    undated_args["changes"][0]["facts"][0]["when"] = json!("scene");
    let undated = c
        .call(tool("universe_check_changes", undated_args))
        .await
        .unwrap();
    assert_eq!(undated["result"]["status"], "needs_clarification");
    assert!(undated["result"]["candidate_handle"].is_null());
    let args = json!({"universe":"Alpha","context_id":at,"events":[{"action":"fire","participants":{"pistol":"Pistol"}}]});
    let checked = c
        .call(tool("universe_check_changes", args.clone()))
        .await
        .unwrap();
    assert_eq!(
        checked["result"]["status"], "checked_candidate",
        "{checked}"
    );
    let replay = c.call(tool("universe_check_changes", args)).await.unwrap();
    assert_eq!(
        checked["result"]["candidate_handle"],
        replay["result"]["candidate_handle"]
    );
    let handle: universe_domain::ids::ProposalId =
        serde_json::from_value(checked["result"]["candidate_handle"].clone()).unwrap();
    let prepared = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: handle,
                label: "Scene".into(),
                text: "At day 4 the pistol fired once.".into(),
            },
        })
        .await
        .unwrap();
    assert_eq!(prepared["publishable"], true, "{prepared}");
    let receipt = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Publish {
                candidate: serde_json::from_value(prepared["candidate"].clone()).unwrap(),
                validation_run: serde_json::from_value(
                    prepared["validation"]["execution"]["run_id"].clone(),
                )
                .unwrap(),
                idempotency_key: "plain-fire".into(),
            },
        })
        .await
        .unwrap();
    assert!(receipt["result"]["revision"].is_string(), "{receipt}");
    let at = c.call(open("5")).await.unwrap()["result"]["context_id"].clone();
    let read = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":at,"object_names":["Pistol","Office"]}),
        ))
        .await
        .unwrap();
    assert!(
        read["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["value"] == json!(1) && f["state"] == "supported"),
        "{read}"
    );
    let value = read["result"]["objects"][0]["facts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["state"] == "supported")
        .unwrap()["value"]
        .clone();
    let ordinary: universe_protocol::writing::FactValue = serde_json::from_value(value).unwrap();
    assert!(matches!(
        ordinary,
        universe_protocol::writing::FactValue::Number(_)
    ));
    let handle = read["result"]["objects"][1]["facts"][0]["fact_handle"].clone();
    assert!(handle.is_string());
    let replenished=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":at,"events":[{"action":"replenish","participants":{"pistol":"Pistol"}}]}))).await.unwrap();
    assert_eq!(
        replenished["result"]["status"], "checked_candidate",
        "{replenished}"
    );
    let unexplained=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":at,"changes":[{"name":"Pistol","facts":[{"property":"rounds","value":2,"scope":"universe","when":"scene","lifetime":{"kind":"until_changed"}}]}]}))).await.unwrap();
    assert_ne!(
        unexplained["result"]["status"], "checked_candidate",
        "Unexplained replenishment passed: {unexplained}"
    );
    assert!(unexplained["result"]["validation"]["execution"]["findings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["rule_id"] == id(52) && f["outcome"] == "not_established"));
    let false_claim = json!({"subject":"Office","property":"code","value":"red"});
    let true_claim = json!({"subject":"Office","property":"code","value":"green"});
    let connected_args = json!({"universe":"Alpha","context_id":at,"messages":[{"label":"Lie","from":"Sender","to":["Recipient"],"received_by":["Recipient"],"understood_by":["Recipient"],"channel":"radio","claim":false_claim},{"label":"Truth","from":"Sender","to":["Recipient"],"received_by":["Recipient"],"understood_by":["Recipient"],"channel":"radio","claim":true_claim}],"attitudes":[{"holder":"Recipient","claim":true_claim,"attitude":"knows","message":"Truth","lifetime":{"kind":"until_changed"}}],"events":[{"action":"open-office","participants":{"actor":"Recipient"},"at_tick":"6","requires_knowledge":[{"holder":"Recipient","claim":true_claim}]}]});
    let mut instantaneous_args = connected_args.clone();
    instantaneous_args["attitudes"][0]["lifetime"] = json!({"kind":"unspecified"});
    let instantaneous = c
        .call(tool("universe_check_changes", instantaneous_args))
        .await
        .unwrap();
    assert_ne!(
        instantaneous["result"]["status"], "checked_candidate",
        "Instant knowledge satisfied a later action: {instantaneous}"
    );
    let connected = c
        .call(tool("universe_check_changes", connected_args))
        .await
        .unwrap();
    assert_eq!(
        connected["result"]["status"], "checked_candidate",
        "{connected}"
    );
    let prepared=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::Prepare{candidate:serde_json::from_value(connected["result"]["candidate_handle"].clone()).unwrap(),label:"Message".into(),text:"The sender lied about red, then explained green. The recipient understood green and retained this knowledge, using it the next day.".into()}}).await.unwrap();
    assert_eq!(prepared["publishable"], true, "{prepared}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(prepared["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                prepared["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "plain-message".into(),
        },
    })
    .await
    .unwrap();
    let at = c.call(open("7")).await.unwrap()["result"]["context_id"].clone();
    let contracts = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":at}),
        ))
        .await
        .unwrap();
    assert_eq!(
        contracts["result"]["communications"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    let read = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":at,"object_names":["Office"]}),
        ))
        .await
        .unwrap();
    assert!(
        read["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .all(|f| f["value"] != "red"),
        "Lie was promoted: {read}"
    );
    let corrected=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":at,"corrections":[{"fact_handle":handle,"value":"blue","reason":"The original code was blue"}]}))).await.unwrap();
    assert_ne!(
        corrected["result"]["status"], "checked_candidate",
        "Retcon failed to invalidate later knowledge/action: {corrected}"
    );
    assert!(corrected["result"]["impact"].is_object());
    let failed_knowledge=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":at,"attitudes":[{"holder":"Recipient","claim":false_claim,"attitude":"knows"}]}))).await.unwrap();
    assert_eq!(failed_knowledge["result"]["status"], "needs_clarification");
    assert!(failed_knowledge["result"]["candidate_handle"].is_null());
    stop.cancel();
    server.await.unwrap().unwrap();
}
