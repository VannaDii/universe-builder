use super::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_contracts_setup_requires_explicit_author_declaration_and_checks_stock() {
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
    let setup=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":ctx,
        "properties":[{"name":"rounds","introduce":true,"value_type":"integer","single_value":true,"persistence":"explicit_interval"},{"name":"ready","introduce":true,"value_type":"boolean","single_value":true,"persistence":"until_changed"}],
        "changes":[{"name":"Pistol","introduce":true,"facts":[{"property":"rounds","value":2,"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"4"}},{"property":"ready","value":true,"scope":"universe","at_tick":"0","lifetime":{"kind":"until_changed"}}]}],
        "actions":[{"name":"begin","introduce":true,"scope":"universe"},{"name":"fire","introduce":true,"scope":"universe","requirements":[{"role":"pistol","property":"ready","value":true}],"effects":[{"role":"pistol","property":"rounds","change":{"kind":"delta","amount":-1,"minimum":0,"maximum":6},"lifetime":{"kind":"until_changed"}}]},{"name":"replenish","introduce":true,"scope":"universe","effects":[{"role":"pistol","property":"rounds","change":{"kind":"delta","amount":1,"minimum":0,"maximum":6},"lifetime":{"kind":"until_changed"}}]}],
        "constraints":[{"kind":"resource_accounting","name":"stock continuity","property":"rounds","scope":"universe"},{"kind":"no_opposing_evidence","name":"ready consistency","object":"Pistol","property":"ready","scope":"universe"}]
    }))).await.unwrap();
    assert_eq!(setup["result"]["status"], "checked_candidate", "{setup}");
    let candidate: ProposalId =
        serde_json::from_value(setup["result"]["candidate_handle"].clone()).unwrap();
    assert!(c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: candidate.clone(),
                label: "Contracts".into(),
                text: "Author selected contracts".into()
            }
        })
        .await
        .is_err());
    let declared=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::PrepareContracts{candidate,label:"Declared mechanics".into(),text:"The author declares single integer rounds and ready status, two rounds before day 4, a ready pistol firing consumes one round and replenishment adds one within zero to six; resource arrival must be accounted and ready evidence cannot oppose itself.".into()}}).await.unwrap();
    assert_eq!(declared["publishable"], true, "{declared}");
    let description = declared["summary"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(Value::as_str)
        .find(|s| s.contains("Author action declaration") && s.contains("fire"))
        .unwrap();
    assert!(
        description.contains("rounds") && description.contains("pistol"),
        "{description}"
    );
    assert!(
        !description.contains("rec_") && !description.contains("consequenceContract"),
        "{description}"
    );
    let publication = EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(declared["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                declared["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "declared-contracts".into(),
        },
    };
    let receipt = c.call(publication.clone()).await.unwrap();
    assert_eq!(
        c.call(publication).await.unwrap()["result"],
        receipt["result"]
    );
    let timeless = context(&mut c, &u, "Alpha").await;
    let read = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":timeless}),
        ))
        .await
        .unwrap();
    assert_eq!(read["result"]["actions"].as_array().unwrap().len(), 3);
    assert_eq!(read["result"]["constraints"].as_array().unwrap().len(), 2);
    let action = read["result"]["actions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["name"] == "fire")
        .unwrap();
    assert_eq!(action["requirements"][0]["role"], "pistol");
    assert_eq!(action["effects"][0]["change"]["amount"], -1);
    let fire=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"events":[{"action":"fire","participants":{"pistol":"Pistol"},"at_tick":"4"}]}))).await.unwrap();
    assert_eq!(fire["result"]["status"], "checked_candidate", "{fire}");
    let reviewed = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: serde_json::from_value(fire["result"]["candidate_handle"].clone())
                    .unwrap(),
                label: "Firing".into(),
                text: "At day 4 the ready Pistol fired once.".into(),
            },
        })
        .await
        .unwrap();
    assert_eq!(reviewed["publishable"], true, "{reviewed}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(reviewed["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                reviewed["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "fire-with-declared-contracts".into(),
        },
    })
    .await
    .unwrap();
    let timeless = context(&mut c, &u, "Alpha").await;
    let clocks = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":timeless,"object_names":["Pistol"]}),
        ))
        .await
        .unwrap();
    let at = c.call(tool("universe_open_context", json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"5"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let current = c.call(tool("universe_read_facts", json!({"universe":"Alpha","context_id":at["result"]["context_id"],"object_names":["Pistol"]}))).await.unwrap();
    assert!(
        current["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "rounds" && f["value"] == 1 && f["state"] == "supported"),
        "{current}"
    );
    let increased=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"changes":[{"name":"Pistol","facts":[{"property":"rounds","value":2,"scope":"universe","at_tick":"5","lifetime":{"kind":"until_changed"}}]}]}))).await.unwrap();
    assert_ne!(
        increased["result"]["status"], "checked_candidate",
        "{increased}"
    );
    let weakened=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"properties":[{"name":"rounds","value_type":"integer","single_value":false,"persistence":"unspecified"}]}))).await.unwrap();
    assert_eq!(weakened["result"]["status"], "needs_clarification");
    assert!(weakened["result"]["candidate_handle"].is_null());
    let opposed=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"changes":[{"name":"Pistol","facts":[{"property":"ready","value":true,"negated":true,"scope":"universe","at_tick":"5","lifetime":{"kind":"until_changed"}}]}]}))).await.unwrap();
    assert_ne!(
        opposed["result"]["status"], "checked_candidate",
        "{opposed}"
    );

    // Publish reusable starting values before selecting them for two independent starts.
    let defaults=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":timeless,"definitions":[{"name":"Pistol kind","introduce":true,"scope":"universe","shared_attributes":[{"property":"finish","value":"plain","scope":"universe","at_tick":"0","lifetime":{"kind":"until_changed"}}],"initial_values":[{"property":"rounds","value":2,"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"100"}}]},{"name":"Ornate pistol","introduce":true,"parent":"Pistol kind","scope":"universe"}]}))).await.unwrap();
    assert_eq!(
        defaults["result"]["status"], "checked_candidate",
        "{defaults}"
    );
    publish_plain(
        &mut c,
        &defaults,
        "A pistol starts with two rounds; ornate pistols are pistols.",
        "initial-definitions",
    )
    .await;
    let fresh = context(&mut c, &u, "Alpha").await;
    let initial = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":fresh,"object_names":["Pistol kind"]}),
        ))
        .await
        .unwrap();
    let selected =
        initial["result"]["objects"][0]["initial_value_candidates"][0]["fact_handle"].clone();
    assert!(selected.is_string(), "{initial}");
    assert!(initial["result"]["objects"][0]["facts"]
        .as_array()
        .unwrap()
        .is_empty());
    assert!(initial["result"]["objects"][0]["inherited_attributes"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["property"] != "rounds"));
    let start = |name: &str, end: &str| json!({"instance":name,"initial_value_handles":[selected],"start":{"kind":"occurred","event":{"action":"begin","participants":{"instance":name},"at_tick":"10"}},"scope":"universe","lifetime":{"kind":"until","end_tick":end}});
    let starts_args = json!({"universe":"Alpha","context_id":fresh,"changes":[{"name":"First pistol","introduce":true,"classification":"Pistol kind","facts":[{"property":"ready","value":true,"scope":"universe","at_tick":"10","lifetime":{"kind":"until_changed"}}]},{"name":"Second pistol","introduce":true,"classification":"Pistol kind"}],"initializations":[start("First pistol","11"),start("Second pistol","100")]});
    let starts = c
        .call(tool("universe_check_changes", starts_args.clone()))
        .await
        .unwrap();
    assert_eq!(starts["result"]["status"], "checked_candidate", "{starts}");
    assert_eq!(
        c.call(tool("universe_check_changes", starts_args))
            .await
            .unwrap()["result"]["candidate_handle"],
        starts["result"]["candidate_handle"]
    );
    publish_plain(
        &mut c,
        &starts,
        "At day 10 two separate pistols began with two rounds each. The first was ready.",
        "two-starts",
    )
    .await;
    let fresh = context(&mut c, &u, "Alpha").await;
    let fired=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"events":[{"action":"fire","participants":{"pistol":"First pistol"},"at_tick":"11"}]}))).await.unwrap();
    assert_eq!(fired["result"]["status"], "checked_candidate", "{fired}");
    publish_plain(
        &mut c,
        &fired,
        "At day 11 the first pistol fired.",
        "initialized-fire",
    )
    .await;
    let fresh = context(&mut c, &u, "Alpha").await;
    let at=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"12"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let stock=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"object_names":["First pistol","Second pistol"]}))).await.unwrap();
    for (i, expected) in [(0, 1), (1, 2)] {
        assert!(
            stock["result"]["objects"][i]["facts"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f["property"] == "rounds"
                    && f["value"] == expected
                    && f["state"] == "supported"),
            "{stock}"
        );
    }
    let existing = stock["result"]["objects"][0]["occurred_events"][0]["handle"].clone();
    assert!(existing.is_string(), "{stock}");
    let again=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"initializations":[start("First pistol","100")]}))).await;
    assert!(
        again.is_err() || again.as_ref().unwrap()["result"]["status"] != "checked_candidate",
        "{again:?}"
    );
    let missing=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"initializations":[{"instance":"Second pistol","initial_value_handles":["not-approved"],"start":{"kind":"existing","handle":existing},"scope":"universe","lifetime":{"kind":"until_changed"}}]}))).await.unwrap();
    assert_eq!(missing["result"]["status"], "needs_clarification");
    assert!(missing["result"]["candidate_handle"].is_null());
    let refined=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"changes":[{"name":"First pistol","classification":"Ornate pistol"}]}))).await.unwrap();
    assert_eq!(
        refined["result"]["status"], "checked_candidate",
        "{refined}"
    );
    publish_plain(
        &mut c,
        &refined,
        "The first pistol is an ornate pistol; its identity and remaining ammunition persist.",
        "refine-initialized",
    )
    .await;
    let fresh = context(&mut c, &u, "Alpha").await;
    let attempted=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"initializations":[{"instance":"First pistol","initial_value_handles":[selected],"start":{"kind":"existing","handle":existing},"scope":"universe","lifetime":{"kind":"until_changed"}}]}))).await;
    assert!(
        attempted.is_err()
            || attempted.as_ref().unwrap()["result"]["status"] != "checked_candidate",
        "{attempted:?}"
    );

    let third=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"changes":[{"name":"Third pistol","introduce":true,"classification":"Pistol kind"}],"events":[{"action":"begin","participants":{"instance":"Third pistol"},"at_tick":"13"}]}))).await.unwrap();
    assert_eq!(third["result"]["status"], "checked_candidate", "{third}");
    publish_plain(
        &mut c,
        &third,
        "At day 13 a third independent pistol began; it has not been initialized yet.",
        "third-start",
    )
    .await;
    let fresh = context(&mut c, &u, "Alpha").await;
    let research = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":fresh,"object_names":["Third pistol"]}),
        ))
        .await
        .unwrap();
    assert!(
        research["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .is_empty(),
        "{research}"
    );
    assert_eq!(
        research["result"]["objects"][0]["occurred_events"][0]["action"],
        "begin"
    );
    let third_start = research["result"]["objects"][0]["occurred_events"][0]["handle"].clone();
    let initialize = json!({"universe":"Alpha","context_id":fresh,"initializations":[{"instance":"Third pistol","initial_value_handles":[selected],"start":{"kind":"existing","handle":third_start},"scope":"universe","lifetime":{"kind":"until","end_tick":"100"}}]});
    let mut unspecified = initialize.clone();
    unspecified["initializations"][0]["lifetime"] = json!({"kind":"unspecified"});
    let held = c
        .call(tool("universe_check_changes", unspecified))
        .await
        .unwrap();
    assert_eq!(held["result"]["status"], "needs_clarification");
    assert!(held["result"]["candidate_handle"].is_null());
    let initialized = c
        .call(tool("universe_check_changes", initialize))
        .await
        .unwrap();
    assert_eq!(
        initialized["result"]["status"], "checked_candidate",
        "{initialized}"
    );
    publish_plain(
        &mut c,
        &initialized,
        "The third pistol uses the approved two-round initial value at its actual day 13 start.",
        "existing-start-initialize",
    )
    .await;

    // A later committed shot makes the earlier consequence correction consequential.
    let fresh = context(&mut c, &u, "Alpha").await;
    let history = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":fresh,"object_names":["First pistol"]}),
        ))
        .await
        .unwrap();
    let first_shot = history["result"]["objects"][0]["occurred_events"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["action"] == "fire")
        .unwrap()["handle"]
        .clone();
    let later=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"events":[{"action":"fire","participants":{"pistol":"First pistol"},"at_tick":"12"}]}))).await.unwrap();
    assert_eq!(later["result"]["status"], "checked_candidate", "{later}");
    publish_plain(
        &mut c,
        &later,
        "At day 12 the first pistol fired its remaining round.",
        "later-shot",
    )
    .await;
    let old_context = context(&mut c, &u, "Alpha").await;
    let history = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":old_context,"object_names":["First pistol"]}),
        ))
        .await
        .unwrap();
    let later_shot = history["result"]["objects"][0]["occurred_events"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["action"] == "fire" && e["handle"] != first_shot)
        .unwrap()["handle"]
        .clone();
    let denied=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":old_context,"event_corrections":[{"event_handle":first_shot,"reason":"The day 11 action was replenishment, not firing.","action":"replenish"}]}))).await;
    let denial = denied.unwrap_err().to_string();
    assert!(
        denial.contains("resource post-value does not equal pre-value plus declared change"),
        "{denial}"
    );
    let unchanged = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":old_context,"object_names":["First pistol"]}),
        ))
        .await
        .unwrap();
    assert_eq!(
        unchanged["result"]["objects"][0]["occurred_events"],
        history["result"]["objects"][0]["occurred_events"]
    );
    let repaired=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":old_context,"event_corrections":[{"event_handle":first_shot,"reason":"The day 11 action was replenishment.","action":"replenish"},{"event_handle":later_shot,"reason":"Recheck the author's retained day 12 shot against the corrected earlier action."}]}))).await.unwrap();
    assert_eq!(
        repaired["result"]["status"], "checked_candidate",
        "{repaired}"
    );
    assert_eq!(repaired["result"]["impact"]["coverage"], "complete");
    publish_plain(&mut c,&repaired,"Correction: day 11 replenished one round; the day 12 shot still occurred and leaves two rounds.","atomic-event-correction").await;
    let old = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":old_context,"object_names":["First pistol"]}),
        ))
        .await
        .unwrap();
    assert_eq!(
        old["result"]["objects"][0]["occurred_events"],
        history["result"]["objects"][0]["occurred_events"]
    );
    let fresh = context(&mut c, &u, "Alpha").await;
    let new = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":fresh,"object_names":["First pistol"]}),
        ))
        .await
        .unwrap();
    assert_eq!(
        new["result"]["objects"][0]["occurred_events"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["handle"] == first_shot)
            .unwrap()["action"],
        "replenish"
    );
    let after=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"14"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let balance=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":after["result"]["context_id"],"object_names":["First pistol"]}))).await.unwrap();
    assert!(
        balance["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "rounds" && f["value"] == 2 && f["state"] == "supported"),
        "{balance}"
    );

    assert!(
        balance["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|f| f["property"] == "rounds")
            .all(|f| f["fact_handle"].is_null()),
        "Generated balance must not be an editable factual correction handle: {balance}"
    );
    let before=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"exact","revision_id":history["frame"]["revision"]},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"14"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let former=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":before["result"]["context_id"],"object_names":["First pistol"]}))).await.unwrap();
    assert!(
        former["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "rounds" && f["value"] == 0 && f["state"] == "supported"),
        "{former}"
    );
    // Revision edits retain identity/history and recheck genuinely committed events/instances.
    let pinned = context(&mut c, &u, "Alpha").await;
    let blocked=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":pinned,"action_corrections":[{"name":"fire","reason":"Firing requires not ready instead.","requirements":[{"role":"pistol","property":"ready","value":false}]}]}))).await.unwrap_err();
    assert!(
        blocked.to_string().contains("event.action.requirements"),
        "{blocked}"
    );
    let cycle=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":pinned,"definition_corrections":[{"name":"Pistol kind","reason":"Change the ancestry.","parent":{"kind":"definition","name":"Ornate pistol"}}]}))).await.unwrap_err();
    assert!(cycle.to_string().contains("structural"), "{cycle}");
    let old_defs=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":pinned,"object_names":["Ornate pistol","First pistol"]}))).await.unwrap();
    let legal=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":pinned,"action_corrections":[{"name":"fire","reason":"Expand the explicitly authored round limit.","effects":[{"role":"pistol","property":"rounds","change":{"kind":"delta","amount":-1,"minimum":0,"maximum":7},"lifetime":{"kind":"until_changed"}}]}],"definition_corrections":[{"name":"Ornate pistol","reason":"This is an independent root type.","parent":{"kind":"root"}}]}))).await.unwrap();
    assert_eq!(legal["result"]["status"], "checked_candidate", "{legal}");
    let candidate: ProposalId =
        serde_json::from_value(legal["result"]["candidate_handle"].clone()).unwrap();
    assert!(c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: candidate.clone(),
                label: "revision".into(),
                text: "Explicit contract correction".into()
            }
        })
        .await
        .is_err());
    let review=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::PrepareContracts{candidate,label:"revision".into(),text:"Ornate pistol is a root type. Firing retains its requirements, validity and universe applicability, consumes one round, with the declared maximum changed to seven.".into()}}).await.unwrap();
    assert_eq!(review["publishable"], true, "{review}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(review["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                review["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "contract-revision".into(),
        },
    })
    .await
    .unwrap();
    let latest = context(&mut c, &u, "Alpha").await;
    let now_defs=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":latest,"object_names":["Ornate pistol","First pistol"]}))).await.unwrap();
    assert!(
        old_defs["result"]["objects"][0]["ancestry"]
            .as_array()
            .unwrap()
            .contains(&json!("Pistol kind")),
        "{old_defs}"
    );
    assert!(
        !now_defs["result"]["objects"][0]["ancestry"]
            .as_array()
            .unwrap()
            .contains(&json!("Pistol kind")),
        "{now_defs}"
    );
    assert_eq!(
        old_defs["result"]["objects"][1]["classification"],
        now_defs["result"]["objects"][1]["classification"]
    );
    let old_contracts = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":pinned}),
        ))
        .await
        .unwrap();
    let new_contracts = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":latest}),
        ))
        .await
        .unwrap();
    let old_fire = old_contracts["result"]["actions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["name"] == "fire")
        .unwrap();
    let new_fire = new_contracts["result"]["actions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["name"] == "fire")
        .unwrap();
    assert_eq!(old_fire["requirements"], new_fire["requirements"]);
    assert_eq!(old_fire["scope"], new_fire["scope"]);
    assert_eq!(old_fire["time"], new_fire["time"]);
    assert_eq!(old_fire["effects"][0]["change"]["maximum"], 6);
    assert_eq!(new_fire["effects"][0]["change"]["maximum"], 7);
    let shared=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":latest,"object_names":["Pistol kind","Second pistol"]}))).await.unwrap();
    let shared_fact = shared["result"]["objects"][0]["inherited_attributes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["property"] == "finish")
        .unwrap();
    let corrected=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":latest,"corrections":[{"fact_handle":shared_fact["fact_handle"],"value":"polished","reason":"The shared finish was polished."}]}))).await.unwrap();
    assert_eq!(
        corrected["result"]["status"], "checked_candidate",
        "{corrected}"
    );
    publish_plain(
        &mut c,
        &corrected,
        "Pistols have a polished shared finish, without changing stock or classification.",
        "shared-finish-correction",
    )
    .await;
    let newest = context(&mut c, &u, "Alpha").await;
    let revised=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":newest,"object_names":["Pistol kind","Second pistol"]}))).await.unwrap();
    assert!(
        revised["result"]["objects"][1]["inherited_attributes"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "finish" && f["value"] == "polished"),
        "{revised}"
    );
    let retained = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":latest,"object_names":["Pistol kind"]}),
        ))
        .await
        .unwrap();
    assert!(
        retained["result"]["objects"][0]["inherited_attributes"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "finish" && f["value"] == "plain"),
        "{retained}"
    );
    stop.cancel();
    server.await.unwrap().unwrap();
}

async fn publish_plain(c: &mut EngineClient, checked: &Value, text: &str, key: &str) {
    let review = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: serde_json::from_value(checked["result"]["candidate_handle"].clone())
                    .unwrap(),
                label: "Author selected writing".into(),
                text: text.into(),
            },
        })
        .await
        .unwrap();
    assert_eq!(review["publishable"], true, "{review}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(review["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                review["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: key.into(),
        },
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_quantities_keep_exact_authored_units_and_history() {
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
    let exact: serde_json::Number = serde_json::from_str("1.2300").unwrap();
    let args = json!({"universe":"Alpha","context_id":ctx,
        "units":[{"name":"metre","introduce":true,"dimension":"length","symbol":"m"},{"name":"litre","introduce":true,"dimension":"volume","symbol":"L"},{"name":"other length","introduce":true,"dimension":"length","symbol":"m"}],
        "properties":[{"name":"height","introduce":true,"value_type":"quantity","unit":"metre","single_value":true,"persistence":"until_changed"},{"name":"fuel","introduce":true,"value_type":"quantity","unit":"litre","single_value":true,"persistence":"explicit_interval"}],
        "changes":[{"name":"Craft","introduce":true,"facts":[{"property":"height","value":{"amount":exact,"unit":"metre"},"scope":"universe","at_tick":"0","lifetime":{"kind":"until_changed"}},{"property":"fuel","value":{"amount":10,"unit":"litre"},"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"4"}}]}],
        "actions":[{"name":"burn fuel","introduce":true,"scope":"universe","effects":[{"role":"craft","property":"fuel","change":{"kind":"delta","amount":-2,"minimum":0,"maximum":20,"unit":"litre"},"lifetime":{"kind":"until_changed"}}]}],
        "constraints":[{"kind":"resource_accounting","name":"fuel accounting","property":"fuel","scope":"universe"}]
    });
    let checked = c.call(tool("universe_check_changes", args)).await.unwrap();
    assert_eq!(
        checked["result"]["status"], "checked_candidate",
        "{checked}"
    );
    let candidate: ProposalId =
        serde_json::from_value(checked["result"]["candidate_handle"].clone()).unwrap();
    assert!(c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: candidate.clone(),
                label: "Units".into(),
                text: "The author declares units and fuel mechanics.".into()
            }
        })
        .await
        .is_err());
    let review=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::PrepareContracts{candidate,label:"Explicit unit declarations".into(),text:"Metre and other length have length dimension and m symbol; litre has volume dimension and L symbol, with no conversions. Craft is 1.2300 metres high and has ten litres until day 4; burning consumes two litres within zero to twenty.".into()}}).await.unwrap();
    assert_eq!(review["publishable"], true, "{review}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(review["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                review["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "quantity-contracts".into(),
        },
    })
    .await
    .unwrap();
    let old_context = context(&mut c, &u, "Alpha").await;
    let read = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":old_context,"object_names":["Craft"]}),
        ))
        .await
        .unwrap();
    let height = read["result"]["objects"][0]["facts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["property"] == "height")
        .unwrap();
    assert_eq!(height["value"]["amount"].to_string(), "1.2300");
    assert_eq!(height["value"]["unit"], "metre");
    assert_eq!(height["unit"], "metre");
    assert_eq!(height["unsupported_plain_value"], false);
    let roundtrip: universe_protocol::writing::FactValue =
        serde_json::from_value(height["value"].clone()).unwrap();
    assert!(matches!(
        roundtrip,
        universe_protocol::writing::FactValue::Quantity { .. }
    ));
    let unchanged=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":old_context,"changes":[{"name":"Craft","facts":[{"property":"height","value":height["value"],"scope":"universe","at_tick":"0","lifetime":{"kind":"until_changed"}}]}]}))).await.unwrap();
    assert_eq!(unchanged["result"]["status"], "no_changes", "{unchanged}");
    for unit in ["litre", "other length", "m", "missing unit"] {
        let held=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":old_context,"changes":[{"name":"Craft","facts":[{"property":"height","value":{"amount":2,"unit":unit},"scope":"universe"}]}]}))).await.unwrap();
        assert_eq!(held["result"]["status"], "needs_clarification", "{held}");
        assert!(held["result"]["candidate_handle"].is_null());
    }
    let metadata = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":old_context}),
        ))
        .await
        .unwrap();
    assert_eq!(metadata["result"]["units"].as_array().unwrap().len(), 3);
    assert!(metadata["result"]["units"]
        .as_array()
        .unwrap()
        .iter()
        .all(|u| u["conversion_declared"] == false));
    assert_eq!(
        metadata["result"]["actions"][0]["effects"][0]["change"]["unit"],
        "litre"
    );
    let corrected=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":old_context,"corrections":[{"fact_handle":height["fact_handle"],"value":{"amount":serde_json::from_str::<serde_json::Number>("1.2500").unwrap(),"unit":"metre"},"reason":"Author corrects the height measurement."}]}))).await.unwrap();
    assert_eq!(
        corrected["result"]["status"], "checked_candidate",
        "{corrected}"
    );
    publish_plain(
        &mut c,
        &corrected,
        "Correction: Craft's height was 1.2500 metres.",
        "height-correction",
    )
    .await;
    let old = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":old_context,"object_names":["Craft"]}),
        ))
        .await
        .unwrap();
    assert!(old["result"]["objects"][0]["facts"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["property"] == "height"
            && f["value"]["amount"].as_number().unwrap().as_str() == "1.2300"));
    let fresh = context(&mut c, &u, "Alpha").await;
    let burned=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"events":[{"action":"burn fuel","participants":{"craft":"Craft"},"at_tick":"4"}]}))).await.unwrap();
    assert_eq!(burned["result"]["status"], "checked_candidate", "{burned}");
    publish_plain(
        &mut c,
        &burned,
        "At day 4 Craft burned two litres of fuel.",
        "quantity-consumption",
    )
    .await;
    let at=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":read["result"]["clocks"][0]["calendar_id"],"value":"5"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let now=c.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"object_names":["Craft"]}))).await.unwrap();
    assert!(
        now["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "height"
                && f["value"]["amount"].as_number().unwrap().as_str() == "1.2500"
                && f["value"]["unit"] == "metre"
                && f["state"] == "supported"),
        "{now}"
    );
    assert!(
        now["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "fuel"
                && f["value"]["amount"] == 8
                && f["value"]["unit"] == "litre"
                && f["state"] == "supported"),
        "{now}"
    );
    stop.cancel();
    server.await.unwrap().unwrap();
}
