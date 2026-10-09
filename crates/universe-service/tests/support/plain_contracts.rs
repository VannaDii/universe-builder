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
        "actions":[{"name":"fire","introduce":true,"scope":"universe","requirements":[{"role":"pistol","property":"ready","value":true}],"effects":[{"role":"pistol","property":"rounds","change":{"kind":"delta","amount":-1,"minimum":0,"maximum":6},"lifetime":{"kind":"until_changed"}}]},{"name":"replenish","introduce":true,"scope":"universe","effects":[{"role":"pistol","property":"rounds","change":{"kind":"delta","amount":1,"minimum":0,"maximum":6},"lifetime":{"kind":"until_changed"}}]}],
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
    assert_eq!(read["result"]["actions"].as_array().unwrap().len(), 2);
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
    stop.cancel();
    server.await.unwrap().unwrap();
}
