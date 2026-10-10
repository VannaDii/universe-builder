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

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_knowledge_policies_and_explicit_author_decision() {
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
    let setup=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":ctx,"changes":[{"name":"Holder","introduce":true},{"name":"Office","introduce":true,"facts":[{"property":"code","value":"green","scope":"universe","at_tick":"0","lifetime":{"kind":"until_changed"}},{"property":"locked","value":true,"negated":true,"scope":"universe","at_tick":"0","lifetime":{"kind":"until_changed"}}]}],"actions":[{"name":"open","introduce":true,"scope":"universe"}],"knowledge_policies":[{"kind":"knowledge","name":"Authored knowledge","mode":"author_established"},{"kind":"channel","name":"Radio timing","channel":"radio","forward_only":true,"minimum_delay":"0","maximum_delay":"10"}]}))).await.unwrap();
    assert_eq!(setup["result"]["status"], "checked_candidate", "{setup}");
    let candidate: ProposalId =
        serde_json::from_value(setup["result"]["candidate_handle"].clone()).unwrap();
    assert!(c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: candidate.clone(),
                label: "policy".into(),
                text: "Declared policy".into()
            }
        })
        .await
        .is_err());
    let review=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::PrepareContracts{candidate,label:"policy".into(),text:"The author explicitly establishes knowledge in this context. Radio receipt takes zero to ten forward ticks.".into()}}).await.unwrap();
    assert_eq!(review["publishable"], true, "{review}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(review["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                review["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "knowledge-policy".into(),
        },
    })
    .await
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
            limits: GrantLimits {
                allow_shared: true,
                ..Default::default()
            },
        },
    })
    .await
    .unwrap();
    let mut a = connect(&root, &agent).await;
    let selected = context(&mut a, &u, "Alpha").await;
    let ordinary=a.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":selected,"attitudes":[{"holder":"Holder","claim":{"subject":"Office","property":"code","value":"green"},"attitude":"knows","at_tick":"1","lifetime":{"kind":"until_changed"}}]}))).await.unwrap();
    assert_eq!(ordinary["result"]["status"], "needs_clarification");
    assert!(ordinary["result"]["candidate_handle"].is_null());
    let declaration=serde_json::from_value(json!({"holder":"Holder","claim":{"subject":"Office","property":"code","value":"green"},"at_tick":"1","lifetime":{"kind":"until","end_tick":"10"}})).unwrap();
    let decision=EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::EstablishKnowledge{context_id:serde_json::from_value(selected.clone()).unwrap(),declaration,rationale:"I explicitly establish that Holder knows this code from tick one through before ten.".into(),label:"Author knowledge".into(),text:"Holder knows the office code is green during that interval.".into()}};
    assert!(a.call(decision.clone()).await.is_err());
    let established = c.call(decision.clone()).await.unwrap();
    assert_eq!(established["publishable"], true, "{established}");
    assert_eq!(
        c.call(decision).await.unwrap()["candidate"],
        established["candidate"]
    );
    let raw=c.call(tool("universe_get_proposal",json!({"universe":"Alpha","proposal_id":established["candidate"]["proposal_id"],"version":established["candidate"]["version"]}))).await.unwrap();
    let mut invented = raw["result"]["operations"]
        .as_array()
        .unwrap()
        .iter()
        .find(|op| op["kind"] == "add_belief")
        .unwrap()
        .clone();
    invented["client_ref"] = json!("rec_999999999999999999999999");
    let forged=a.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":selected,"operations":[invented],"submission":"submitted","rationale":"Agent inline author decision is not a private author establishment.","idempotency_key":"forged-knowledge"}))).await.unwrap()["result"].clone();
    let forged_validation=a.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":selected,"proposal_reference":reference(&forged),"check_scope":"universe"}))).await;
    assert!(
        forged_validation
            .as_ref()
            .is_err_and(|e| e.to_string().contains("author-origin")),
        "{forged_validation:?}"
    );
    let forged_publication = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Publish {
                candidate: reference(&forged),
                validation_run: serde_json::from_value(
                    established["validation"]["execution"]["run_id"].clone(),
                )
                .unwrap(),
                idempotency_key: "forged-knowledge-publish".into(),
            },
        })
        .await;
    assert!(forged_publication.is_err(),"Agent-authored knowledge must not publish through ordinary approval: {forged_publication:?}");
    invented["client_ref"] = json!("rec_888888888888888888888888");
    let draft=a.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":selected,"operations":[invented],"submission":"draft","rationale":"Unsubmitted inline author decision","idempotency_key":"raw-knowledge-draft"}))).await.unwrap()["result"].clone();
    let raw_prepare = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: serde_json::from_value(draft["proposal_id"].clone()).unwrap(),
                label: "Agent's request".into(),
                text: "An agent supplies inline author basis.".into(),
            },
        })
        .await;
    assert!(
        raw_prepare
            .as_ref()
            .is_err_and(|e| e.to_string().contains("Source preparation")),
        "{raw_prepare:?}"
    );
    let before=a.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":selected,"events":[{"action":"open","participants":{"actor":"Holder"},"at_tick":"2","requires_knowledge":[{"holder":"Holder","claim":{"subject":"Office","property":"code","value":"green"}}]}]}))).await.unwrap();
    assert_ne!(before["result"]["status"], "checked_candidate", "{before}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(established["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                established["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "author-knows".into(),
        },
    })
    .await
    .unwrap();
    let fresh = context(&mut a, &u, "Alpha").await;
    let after=a.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"events":[{"action":"open","participants":{"actor":"Holder"},"at_tick":"2","requires_knowledge":[{"holder":"Holder","claim":{"subject":"Office","property":"code","value":"green"}}]}]}))).await.unwrap();
    assert_eq!(after["result"]["status"], "checked_candidate", "{after}");
    let expired=a.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"events":[{"action":"open","participants":{"actor":"Holder"},"at_tick":"11","requires_knowledge":[{"holder":"Holder","claim":{"subject":"Office","property":"code","value":"green"}}]}]}))).await.unwrap();
    assert_ne!(
        expired["result"]["status"], "checked_candidate",
        "{expired}"
    );
    // An author-established attitude does not assert its content as objective truth.
    let contrary=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::EstablishKnowledge{context_id:serde_json::from_value(fresh.clone()).unwrap(),declaration:serde_json::from_value(json!({"holder":"Holder","claim":{"subject":"Office","property":"locked","value":true},"at_tick":"2","lifetime":{"kind":"until_changed"}})).unwrap(),rationale:"I explicitly establish this attitude, without changing the objective locked evidence.".into(),label:"Separate attitude".into(),text:"Holder is attributed knowledge that the office is locked; objective narration still refutes that claim.".into()}}).await.unwrap();
    assert_eq!(contrary["publishable"], true, "{contrary}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(contrary["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                contrary["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "attributed-not-objective".into(),
        },
    })
    .await
    .unwrap();
    let head = context(&mut a, &u, "Alpha").await;
    let truth = a
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":head,"object_names":["Office"]}),
        ))
        .await
        .unwrap();
    assert!(
        truth["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "locked" && f["value"] == true && f["state"] == "refuted"),
        "{truth}"
    );
    assert!(
        !truth["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "locked" && f["value"] == true && f["state"] == "supported"),
        "{truth}"
    );
    let read = a
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":fresh}),
        ))
        .await
        .unwrap();
    assert_eq!(
        read["result"]["knowledge_policies"][0]["mode"], "author_established",
        "{read}"
    );
    let head = context(&mut a, &u, "Alpha").await;
    let attitudes = a
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":head}),
        ))
        .await
        .unwrap();
    let known = attitudes["result"]["attitudes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["claim"]["property"] == "code")
        .unwrap();
    let patch = json!({"attitude_handle":known["attitude_handle"],"end_tick":"8","reason":"Explicitly end the recorded author-established knowledge at eight."});
    let held = a
        .call(tool(
            "universe_check_changes",
            json!({"universe":"Alpha","context_id":head,"attitude_corrections":[patch]}),
        ))
        .await
        .unwrap();
    assert_eq!(held["result"]["status"], "needs_clarification");
    assert!(held["result"]["candidate_handle"].is_null());
    let knowledge_id = raw["result"]["operations"]
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["kind"] == "add_belief")
        .unwrap()["client_ref"]
        .clone();
    let author_ctx = context(&mut c, &u, "Alpha").await;
    let old=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":author_ctx,"record_ids":[knowledge_id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0].clone();
    let mut replacement = old["payload"].clone();
    replacement.as_object_mut().unwrap().remove("record_kind");
    replacement["validity"]["end"]["value"] = json!("8");
    let op = json!({"kind":"revise_attitude","record":{"universe":u["universe_id"],"record":knowledge_id},"expected_version":old["record_version_id"],"replacement":replacement,"rationale":"An agent explanation cannot grant author origin."});
    let forged=a.call(tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":head,"operations":[op],"submission":"draft","rationale":"Agent attempted author-established duration correction","idempotency_key":"forged-attitude-revision"}))).await.unwrap()["result"].clone();
    let denied=a.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":head,"proposal_reference":reference(&forged),"check_scope":"universe"}))).await;
    assert!(
        denied
            .as_ref()
            .is_err_and(|e| e.to_string().contains("author-origin")),
        "{denied:?}"
    );
    assert!(c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: serde_json::from_value(forged["proposal_id"].clone()).unwrap(),
                label: "Forbidden adoption".into(),
                text: "A generic review cannot manufacture an author knowledge decision.".into()
            }
        })
        .await
        .is_err());
    let edit = EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::EditKnowledge {
            context_id: serde_json::from_value(head.clone()).unwrap(),
            correction: serde_json::from_value(patch.clone()).unwrap(),
            label: "Explicit knowledge ending".into(),
            text: "Holder's recorded knowledge ends at eight; its original acquisition remains."
                .into(),
        },
    };
    assert!(a.call(edit.clone()).await.is_err());
    let reviewed = c.call(edit).await.unwrap();
    assert_eq!(reviewed["publishable"], true, "{reviewed}");
    c.call(EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(reviewed["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                reviewed["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "author-knowledge-ending".into(),
        },
    })
    .await
    .unwrap();
    let new_ctx = context(&mut c, &u, "Alpha").await;
    let current=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":new_ctx,"record_ids":[knowledge_id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0].clone();
    assert_eq!(
        current["payload"]["acquisition"],
        old["payload"]["acquisition"]
    );
    assert_eq!(current["payload"]["basis"], old["payload"]["basis"]);
    assert_eq!(current["payload"]["validity"]["end"]["value"], "8");
    assert_ne!(current["record_version_id"], old["record_version_id"]);
    assert_eq!(c.call(tool("universe_get",json!({"universe":"Alpha","context_id":author_ctx,"record_ids":[knowledge_id],"field_groups":["payload"]}))).await.unwrap()["result"]["records"][0]["payload"]["validity"]["end"]["value"],"10");
    let stale = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::EditKnowledge {
                context_id: serde_json::from_value(new_ctx).unwrap(),
                correction: serde_json::from_value(patch).unwrap(),
                label: "Stale version".into(),
                text: "An old handle cannot revise current knowledge.".into(),
            },
        })
        .await;
    assert!(stale.is_err());
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_perspective_changes_do_not_reveal_hidden_identities() {
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
    let id = |n| format!("rec_{n:024x}");
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    admit(&mut c,&ctx,vec![entity("Mara",&id(101)),entity("Hidden citizen",&id(102)),json!({"kind":"record_narrative_reference","client_ref":id(103),"record":"represented_context","payload":{"record_kind":"represented_context","universe":u["universe_id"],"kind":{"kind":"character","holder":rr(101)},"labels":{}}})],"perspective-setup").await;
    let ctx=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":id(103),"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone();
    admit(&mut c,&ctx,vec![
        json!({"kind":"define_relation","client_ref":id(104),"record":{"namespace":"private","key":"ownership","labels":{},"roles":[{"name":"owner","participantTypes":[],"multiplicity":"single","ordered":false}]}}),
        json!({"kind":"record_relation","client_ref":id(105),"proposition":{"subject":rr(101),"predicate":rr(104),"roles":[{"role":"owner","participant":rr(101)}],"quantification":"particular","context":rr(103)},"assertion":{"attributeMode":"instance","proposition":rr(105),"polarity":"support","scope":{"context":rr(103),"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unspecified"},"persistence":"unspecified","precision":"exact","basis":{"kind":"author_decision","note":"Attributed relationship fixture"}}})
    ],"perspective-relationship").await;
    let opened=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":id(103),"temporal_query":{"kind":"timeless"},"temporal_systems":[],"perspective":{"character":id(101)}}))).await.unwrap();
    let selected = opened["result"]["context_id"].clone();
    let restricted = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":selected}),
        ))
        .await
        .unwrap();
    assert_eq!(restricted["result"]["coverage"], "restricted");
    assert_eq!(restricted["result"]["relationships"], json!([]));
    assert!(
        !restricted.to_string().contains("Hidden citizen"),
        "{restricted}"
    );
    let read = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":selected,"object_names":["Hidden citizen"]}),
        ))
        .await
        .unwrap();
    assert_eq!(read["result"]["objects"][0]["identity"], "not_found");
    let check = c
        .call(tool(
            "universe_check_changes",
            json!({"universe":"Alpha","context_id":selected,"changes":[{"name":"Hidden citizen"}]}),
        ))
        .await
        .unwrap();
    assert_eq!(check["result"]["status"], "needs_clarification", "{check}");
    assert!(check["result"]["candidate_handle"].is_null());
    let absent=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":selected,"changes":[{"name":"Never authored"}],"properties":[{"name":"Secret guessed key","value_type":"text","single_value":false,"persistence":"unspecified"}]}))).await.unwrap();
    assert_eq!(
        check["result"], absent["result"],
        "Hidden and absent identities/fields must produce the same neutral held result."
    );
    assert!(check["result"]["validation"].is_null() && check["result"]["impact"].is_null());
    let hidden_alias=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":selected,"aliases":[{"object":"Hidden citizen","text":"Secret alias"}]}))).await.unwrap();
    let absent_alias=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":selected,"aliases":[{"object":"Never authored","text":"Secret alias"}]}))).await.unwrap();
    assert_eq!(hidden_alias["result"], absent_alias["result"]);
    assert!(hidden_alias["result"]["candidate_handle"].is_null());
    assert!(read["result"]["objects"][0].get("names").is_none());
    let contracts = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":selected}),
        ))
        .await
        .unwrap();
    assert_eq!(contracts["result"]["coverage"], "restricted", "{contracts}");
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_world_flashback_and_stale_publication_keep_exact_frames() {
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
    let id = |n| format!("rec_{n:024x}");
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let mut traveler = entity("Traveler", &id(101));
    traveler["record"]["worldAssociations"] = json!([{"world":format!("wld_{:024x}",130),"role":"setting","validity":{"kind":"unspecified"},"qualifiers":{}}]);
    let mut hidden = entity("Lunar resident", &id(102));
    hidden["record"]["worldAssociations"] = json!([{"world":format!("wld_{:024x}",131),"role":"setting","validity":{"kind":"unspecified"},"qualifiers":{}}]);
    let fact = |n, world, value: &str, start: &str, end: &str| json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(101),"predicate":rr(103),"value":{"kind":"text","text":value},"context":{"universe":u["universe_id"],"record":u["context_id"]},"quantification":"particular"},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":{"context":{"universe":u["universe_id"],"record":u["context_id"]},"applicability":{"kind":"worlds","world_ids":[format!("wld_{world:024x}")]}},"validity":{"kind":"calendar_interval","calendar":cal,"start":{"kind":"exact","value":start},"end":{"kind":"exact","value":end}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Explicit scoped timeline"}}});
    admit(&mut c,&ctx,vec![world("Terra",&id(130)),world("Luna",&id(131)),traveler,hidden,json!({"kind":"define_property","client_ref":id(103),"record":{"namespace":"story","key":"colour","labels":{},"subjectTypes":[],"value":{"kind":"text"},"multiplicity":"multiple","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}}),fact(110,130,"old red","0","5"),fact(112,130,"present blue","5","20"),fact(114,131,"lunar silver","0","20")],"scoped-timeline").await;
    let open = |revision: Value, tick: &str| {
        tool(
            "universe_open_context",
            json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":revision,"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":cal,"value":tick}},"temporal_systems":[],"perspective":"author"}),
        )
    };
    let flash = c.call(open(json!({"kind":"head"}), "2")).await.unwrap();
    let now = c.call(open(json!({"kind":"head"}), "6")).await.unwrap();
    let read = |context: &Value, world: &str| {
        tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":context,"world":world,"object_names":["Traveler"]}),
        )
    };
    let old = c
        .call(read(&flash["result"]["context_id"], "Terra"))
        .await
        .unwrap();
    let current = c
        .call(read(&now["result"]["context_id"], "Terra"))
        .await
        .unwrap();
    let lunar = c
        .call(read(&now["result"]["context_id"], "Luna"))
        .await
        .unwrap();
    let supported = |r: &Value, value: &str| {
        r["result"]["objects"][0]["facts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["property"] == "colour" && f["value"] == value && f["state"] == "supported")
    };
    assert!(supported(&old, "old red"), "{old}");
    assert!(!supported(&old, "present blue"));
    assert!(supported(&current, "present blue"), "{current}");
    assert!(supported(&lunar, "lunar silver"), "{lunar}");
    assert_eq!(old["world_focus"], format!("wld_{:024x}", 130));
    assert!(
        c.call(read(&now["result"]["context_id"], "Alpha"))
            .await
            .is_err(),
        "Universe name must not imply a world."
    );
    let edit=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":flash["result"]["context_id"],"changes":[{"name":"Traveler","facts":[{"property":"remembered","value":true,"scope":"Terra","when":"scene","lifetime":{"kind":"until","end_tick":"3"}}]}]}))).await.unwrap();
    assert_eq!(edit["result"]["status"], "checked_candidate", "{edit}");
    let review = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: serde_json::from_value(edit["result"]["candidate_handle"].clone())
                    .unwrap(),
                label: "Flashback".into(),
                text: "At tick two in Terra the Traveler remembered.".into(),
            },
        })
        .await
        .unwrap();
    assert_eq!(review["publishable"], true, "{review}");
    let fresh = context(&mut c, &u, "Alpha").await;
    let advance=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":fresh,"changes":[{"name":"Witness","introduce":true}]}))).await.unwrap();
    publish_plain(
        &mut c,
        &advance,
        "A new witness is established.",
        "advance-head",
    )
    .await;
    let stale = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Publish {
                candidate: serde_json::from_value(review["candidate"].clone()).unwrap(),
                validation_run: serde_json::from_value(
                    review["validation"]["execution"]["run_id"].clone(),
                )
                .unwrap(),
                idempotency_key: "stale-flashback".into(),
            },
        })
        .await;
    assert!(stale.is_err());
    let retained = c
        .call(read(&flash["result"]["context_id"], "Terra"))
        .await
        .unwrap();
    assert!(supported(&retained, "old red"));
    assert_eq!(retained["frame"]["revision"], old["frame"]["revision"]);
    let historical=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":flash["result"]["context_id"],"changes":[{"name":"Traveler","facts":[{"property":"another memory","value":true,"scope":"Terra","when":"scene"}]}]}))).await;
    assert!(
        historical.is_err(),
        "Old revision must not silently rebase a new candidate."
    );
    let agent: ProfileId =
        serde_json::from_value(c.call(EngineRequest::Enroll).await.unwrap()["profile_id"].clone())
            .unwrap();
    c.call(EngineRequest::Grant {
        grant: GrantSpec {
            profile_id: agent.clone(),
            universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
            worlds: Some(vec![WorldId::parse(&format!("wld_{:024x}", 130)).unwrap()]),
            propose: true,
            edit: true,
            protected: true,
            limits: GrantLimits {
                allow_shared: true,
                ..Default::default()
            },
        },
    })
    .await
    .unwrap();
    let mut a = connect(&root, &agent).await;
    let selected = a.call(open(json!({"kind":"head"}), "6")).await.unwrap();
    let scoped = a
        .call(read(&selected["result"]["context_id"], "Terra"))
        .await
        .unwrap();
    assert_eq!(scoped["result"]["coverage"], "restricted");
    assert!(!scoped.to_string().contains("lunar silver"));
    assert!(a
        .call(read(&selected["result"]["context_id"], "Luna"))
        .await
        .is_err());
    let unseen=a.call(tool("universe_read_facts",json!({"universe":"Alpha","context_id":selected["result"]["context_id"],"world":"Terra","object_names":["Lunar resident"]}))).await.unwrap();
    assert_eq!(unseen["result"]["objects"][0]["identity"], "not_found");
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_exhaustive_sets_preserve_open_history_and_protect_declarations() {
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
    let initial=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":ctx,"properties":[{"name":"entrance","introduce":true,"value_type":"object","single_value":false,"persistence":"unspecified"}],"changes":[{"name":"Courtyard","introduce":true},{"name":"Main gate","introduce":true},{"name":"Side gate","introduce":true}]}))).await.unwrap();
    assert_eq!(
        initial["result"]["status"], "checked_candidate",
        "{initial}"
    );
    publish_plain(
        &mut c,
        &initial,
        "A courtyard and two distinct gates exist.",
        "boundary-identities",
    )
    .await;
    let old = context(&mut c, &u, "Alpha").await;
    let clocks = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":old,"object_names":["Courtyard"]}),
        ))
        .await
        .unwrap();
    let at=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"5"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let member = json!({"universe":"Alpha","context_id":at["result"]["context_id"],"changes":[{"name":"Courtyard","facts":[{"property":"entrance","value":{"object":"Side gate"},"scope":"universe","at_tick":"5"}]}]});
    let open = c
        .call(tool("universe_check_changes", member.clone()))
        .await
        .unwrap();
    assert_eq!(open["result"]["status"], "checked_candidate", "{open}");
    let declaration = json!({"universe":"Alpha","context_id":at["result"]["context_id"],"exhaustive_sets":[{"subject":"Courtyard","property":"entrance","members":["Main gate"],"scope":"universe","at_tick":"5","lifetime":{"kind":"until","end_tick":"10"}}]});
    let mut unknown = declaration.clone();
    unknown["exhaustive_sets"][0]["members"] = json!(["Unknown gate"]);
    let held = c
        .call(tool("universe_check_changes", unknown))
        .await
        .unwrap();
    assert!(held["result"]["candidate_handle"].is_null(), "{held}");
    for (field, value) in [
        ("scope", json!("Missing world")),
        ("scope", json!("unspecified")),
    ] {
        let mut unresolved = declaration.clone();
        unresolved["exhaustive_sets"][0][field] = value;
        let held = c
            .call(tool("universe_check_changes", unresolved))
            .await
            .unwrap();
        assert_eq!(held["result"]["status"], "needs_clarification", "{held}");
        assert!(held["result"]["candidate_handle"].is_null(), "{held}");
    }
    let mut omitted = declaration.clone();
    omitted["exhaustive_sets"][0]
        .as_object_mut()
        .unwrap()
        .remove("members");
    assert!(Request::from_tool("universe_check_changes", omitted).is_err());
    let checked = c
        .call(tool("universe_check_changes", declaration))
        .await
        .unwrap();
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
                label: "Boundary".into(),
                text: "Only the main gate is an entrance from day 5 until day 10.".into()
            }
        })
        .await
        .is_err());
    let review = c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::PrepareContracts {
                candidate,
                label: "Boundary".into(),
                text: "Only the main gate is an entrance from day 5 until day 10.".into(),
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
            idempotency_key: "boundary-publication".into(),
        },
    })
    .await
    .unwrap();
    let current = context(&mut c, &u, "Alpha").await;
    let read = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":current}),
        ))
        .await
        .unwrap();
    assert_eq!(
        read["result"]["exhaustive_sets"][0]["members"],
        json!(["Main gate"]),
        "{read}"
    );
    assert_eq!(read["result"]["exhaustive_sets"][0]["kind"], "objective");
    let historical = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":old}),
        ))
        .await
        .unwrap();
    assert_eq!(historical["result"]["exhaustive_sets"], json!([]));
    let current_at=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"5"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let mut closed = member;
    closed["context_id"] = current_at["result"]["context_id"].clone();
    match c.call(tool("universe_check_changes", closed)).await {
        Ok(result) => {
            assert_eq!(result["result"]["status"], "conflict", "{result}");
            assert!(
                result["result"]["validation"]["execution"]["findings"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|finding| finding["outcome"] == "conflicting"),
                "{result}"
            );
        }
        Err(error) => panic!("Expected actual checked conflict, got {error}"),
    }
    let mut allowed = json!({"universe":"Alpha","context_id":current_at["result"]["context_id"],"changes":[{"name":"Courtyard","facts":[{"property":"entrance","value":{"object":"Main gate"},"scope":"universe","at_tick":"5"}]}]});
    let legal = c
        .call(tool("universe_check_changes", allowed.clone()))
        .await
        .unwrap();
    assert_eq!(legal["result"]["status"], "checked_candidate", "{legal}");
    allowed["changes"][0]["facts"][0]["value"] = json!({"object":"Side gate"});
    allowed["changes"][0]["facts"][0]["at_tick"] = json!("11");
    let outside = c
        .call(tool("universe_check_changes", allowed))
        .await
        .unwrap();
    assert_eq!(
        outside["result"]["status"], "checked_candidate",
        "{outside}"
    );
    let empty=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":current,"exhaustive_sets":[{"subject":"Courtyard","property":"entrance","members":[],"scope":"universe","at_tick":"11"}]}))).await.unwrap();
    assert_eq!(empty["result"]["status"], "checked_candidate", "{empty}");
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ordinary_relationship_limits_check_ownership_time_scope_and_review() {
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
    admit(
        &mut c,
        &ctx,
        vec![
            world("North", &format!("rec_{:024x}", 90001)),
            world("South", &format!("rec_{:024x}", 90002)),
        ],
        "relationship-worlds",
    )
    .await;
    let ctx = context(&mut c, &u, "Alpha").await;
    let setup=c.call(tool("universe_check_changes",json!({"universe":"Alpha","context_id":ctx,
        "changes":[{"name":"Pistol","introduce":true},{"name":"Mara","introduce":true},{"name":"Leon","introduce":true}],
        "relation_definitions":[{"name":"ownership","introduce":true,"roles":[{"name":"item","multiple":false},{"name":"owner","multiple":false}]}],
        "relation_limits":[{"name":"one owner in North","relation":"ownership","grouping":{"kind":"role","role":"item"},"counted_role":"owner","maximum":1,"scope":"North","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}}],
        "relationships":[{"relation":"ownership","subject":"Pistol","participants":{"item":["Pistol"],"owner":["Mara"]},"scope":"North","at_tick":"0","lifetime":{"kind":"until","end_tick":"10"}}]
    }))).await.unwrap();
    assert_eq!(setup["result"]["status"], "checked_candidate", "{setup}");
    let handle: ProposalId =
        serde_json::from_value(setup["result"]["candidate_handle"].clone()).unwrap();
    assert!(c
        .call(EngineRequest::AuthorWriting {
            universe: Selector("Alpha".into()),
            action: AuthorWritingAction::Prepare {
                candidate: handle.clone(),
                label: "Ownership".into(),
                text: "Ownership declaration".into()
            }
        })
        .await
        .is_err());
    let review=c.call(EngineRequest::AuthorWriting{universe:Selector("Alpha".into()),action:AuthorWritingAction::PrepareContracts{candidate:handle,label:"Ownership".into(),text:"In North only one owner may hold a pistol at a time through day 20. Mara owns this pistol before day 10.".into()}}).await.unwrap();
    assert_eq!(review["publishable"], true, "{review}");
    assert!(
        review["summary"].as_array().unwrap().iter().any(|s| s
            .as_str()
            .is_some_and(|s| s.contains("Mara") && s.contains("owner"))),
        "{review}"
    );
    let publish = EngineRequest::AuthorWriting {
        universe: Selector("Alpha".into()),
        action: AuthorWritingAction::Publish {
            candidate: serde_json::from_value(review["candidate"].clone()).unwrap(),
            validation_run: serde_json::from_value(
                review["validation"]["execution"]["run_id"].clone(),
            )
            .unwrap(),
            idempotency_key: "ownership-declarations".into(),
        },
    };
    let receipt = c.call(publish.clone()).await.unwrap();
    assert_eq!(c.call(publish).await.unwrap()["result"], receipt["result"]);
    let old = context(&mut c, &u, "Alpha").await;
    let read = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":old}),
        ))
        .await
        .unwrap();
    assert_eq!(read["result"]["relations"][0]["name"], "ownership");
    assert_eq!(read["result"]["relation_limits"][0]["maximum"], 1);
    assert_eq!(
        read["result"]["relationships"][0]["participants"][1]["object"], "Mara",
        "{read}"
    );
    let same = json!({"universe":"Alpha","context_id":old,"relationships":[{"relation":"ownership","subject":"Pistol","participants":{"item":["Pistol"],"owner":["Mara"]},"scope":"North","at_tick":"0","lifetime":{"kind":"until","end_tick":"10"}}]});
    let unchanged = c.call(tool("universe_check_changes", same)).await.unwrap();
    assert_eq!(unchanged["result"]["status"], "no_changes", "{unchanged}");
    let mut next = json!({"universe":"Alpha","context_id":old,"relationships":[{"relation":"ownership","subject":"Pistol","participants":{"item":["Pistol"],"owner":["Leon"]},"scope":"North","at_tick":"5","lifetime":{"kind":"until","end_tick":"15"}}]});
    let conflicting = c
        .call(tool("universe_check_changes", next.clone()))
        .await
        .unwrap();
    assert_eq!(conflicting["result"]["status"], "conflict", "{conflicting}");
    assert!(
        conflicting["result"]["validation"]["execution"]["findings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["outcome"] == "refuted"),
        "{conflicting}"
    );
    next["relationships"][0]["participants"]["undeclared"] = json!(["Mara"]);
    let held = c
        .call(tool("universe_check_changes", next.clone()))
        .await
        .unwrap();
    assert!(held["result"]["candidate_handle"].is_null(), "{held}");
    next["relationships"][0]["participants"]
        .as_object_mut()
        .unwrap()
        .remove("undeclared");
    next["relationships"][0]["scope"] = json!("South");
    let scoped = c
        .call(tool("universe_check_changes", next.clone()))
        .await
        .unwrap();
    assert_eq!(scoped["result"]["status"], "checked_candidate", "{scoped}");
    next["relationships"][0]["scope"] = json!("North");
    next["relationships"][0]["at_tick"] = json!("10");
    next["relationships"][0]["lifetime"]["end_tick"] = json!("20");
    let sequential = c.call(tool("universe_check_changes", next)).await.unwrap();
    assert_eq!(
        sequential["result"]["status"], "checked_candidate",
        "{sequential}"
    );
    let library = c
        .call(EngineRequest::Library {
            universe: Selector("Alpha".into()),
        })
        .await
        .unwrap();
    assert!(
        library["writing"]["proposals"]
            .as_array()
            .unwrap()
            .iter()
            .any(
                |p| p["candidate"]["proposal_id"] == sequential["result"]["candidate_handle"]
                    && p["label"]
                        .as_str()
                        .is_some_and(|label| label.contains("Pistol — ownership"))
            ),
        "{library}"
    );
    publish_plain(
        &mut c,
        &sequential,
        "In North Leon owns the pistol from day 10 until day 20.",
        "sequential-owner",
    )
    .await;
    let current = context(&mut c, &u, "Alpha").await;
    let after = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":current}),
        ))
        .await
        .unwrap();
    assert_eq!(
        after["result"]["relationships"].as_array().unwrap().len(),
        2,
        "{after}"
    );
    let history = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":old}),
        ))
        .await
        .unwrap();
    assert_eq!(
        history["result"]["relationships"].as_array().unwrap().len(),
        1
    );
    let clocks = c
        .call(tool(
            "universe_read_facts",
            json!({"universe":"Alpha","context_id":current,"object_names":["Pistol"]}),
        ))
        .await
        .unwrap();
    let dated=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clocks["result"]["clocks"][0]["calendar_id"],"value":"15"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap();
    let dated = c
        .call(tool(
            "universe_read_contracts",
            json!({"universe":"Alpha","context_id":dated["result"]["context_id"]}),
        ))
        .await
        .unwrap();
    assert_eq!(
        dated["result"]["relationships"].as_array().unwrap().len(),
        1,
        "{dated}"
    );
    assert!(
        dated["result"]["relationships"][0]["participants"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["role"] == "owner" && p["object"] == "Leon"),
        "{dated}"
    );
    stop.cancel();
    server.await.unwrap().unwrap();
}
