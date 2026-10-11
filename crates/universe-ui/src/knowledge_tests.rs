use super::*;
fn frame() -> Frame {
    serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
}
fn clock() -> Chronology {
    universe_domain::chronology::UniverseStart::Fictional {
        calendar_name: "Days".into(),
        initial_tick: "0".into(),
        tick_label: "days".into(),
        ticks_per_month: None,
    }
    .build(universe_domain::ids::CalendarId::parse("cal_000000000000000000000001").unwrap())
    .unwrap()
    .0
}
fn form() -> Form {
    Form {
        holder: "rec_000000000000000000000002".into(),
        proposition: "rec_000000000000000000000003".into(),
        attitude: "knows".into(),
        start: "4".into(),
        lasting: true,
        basis: "Explicit interpretation".into(),
        context: frame().context.record.to_string(),
        acquired: "4".into(),
        mode: "author_established".into(),
        ..Default::default()
    }
}
#[test]
fn acquisition_paths_are_explicit_and_other_attitudes_remain_separate() {
    let mut f = form();
    let op = f.build(&frame(), Some(&clock()), &[]).unwrap();
    assert_eq!(
        op["record"]["acquisition"]["basis"]["kind"],
        "author_established"
    );
    assert_eq!(op["record"]["acquisition"]["time"]["value"], "4");
    f.mode = "communication_receipt".into();
    assert!(f.build(&frame(), Some(&clock()), &[]).is_err());
    f.communication = "rec_000000000000000000000004".into();
    let choices = vec![json!({"kind":"communication","record_id":f.communication})];
    assert!(f.build(&frame(), Some(&clock()), &choices).is_err());
    f.interpretation = f.proposition.clone();
    let op = f.build(&frame(), Some(&clock()), &choices).unwrap();
    assert_eq!(
        op["record"]["acquisition"]["basis"]["interpretation"]["record"],
        f.proposition
    );
    f.acquired = "5".into();
    assert!(f.build(&frame(), Some(&clock()), &choices).is_err());
    f.acquired = "4".into();
    f.context.clear();
    assert!(f.build(&frame(), Some(&clock()), &choices).is_err());
    for attitude in ["believes", "suspects", "rejects", "remembers"] {
        f.attitude = attitude.into();
        let op = f.build(&frame(), Some(&clock()), &[]).unwrap();
        assert_eq!(op["record"]["attitude"], attitude);
        assert!(op["record"].get("acquisition").is_none());
    }
}
#[test]
fn pending_messages_and_propositions_are_selectable() {
    let ops = json!([{"kind":"record_communication","client_ref":"message","record":{"channel":"radio"}},{"kind":"assert_proposition","client_ref":"claim","proposition":{"subject":"holder"}}]);
    let choices = crate::author::choices(&[], &[], &ops.to_string());
    assert_eq!(choices[0]["kind"], "communication");
    assert_eq!(choices[1]["kind"], "proposition");
    assert_eq!(choices[1]["definition"]["subject"], "holder");
}
fn review_text(value: Value, choices: Vec<Value>) -> String {
    let mut dom = dioxus::core::VirtualDom::new_with_props(
        crate::readable::ValidationReview,
        crate::readable::ValidationReviewProps { value, choices },
    );
    dom.rebuild_to_vec()
        .edits
        .into_iter()
        .filter_map(|m| match m {
            dioxus::core::Mutation::CreateTextNode { value, .. } => Some(value),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join(" ")
}
#[test]
fn repair_review_labels_dependencies_and_conceals_restricted_fields() {
    let op = form().build(&frame(), Some(&clock()), &[]).unwrap();
    let choices = crate::author::choices(
        &[json!({"kind":"entity","record_id":form().holder,"label":"Mara"})],
        &[],
        &json!([op]).to_string(),
    );
    let record = choices
        .iter()
        .find(|r| r["kind"] == "epistemic_attitude")
        .unwrap()["record_id"]
        .clone();
    let report = json!({"kind":"evaluated","execution":{"coverage":"complete","findings":[{"rule_id":"policy-id","outcome":"not_established","message":"Correct supporting truth at acquisition.","coverage":"complete","records":[{"record":record}],"evidence":["exact-version"]}],"unsupported_capabilities":["knowledge.acquisition.v1"]}});
    let text = review_text(report.clone(), choices.clone());
    for expected in [
        "Correct supporting truth",
        "Holder: Entity: Mara",
        "Proposition:",
        "policy-id",
        "exact-version",
        "knowledge.acquisition.v1",
    ] {
        assert!(text.contains(expected), "missing {expected}: {text}");
    }
    let clean = review_text(json!({"kind":"restricted"}), vec![]);
    let mut restricted = report;
    restricted["kind"] = json!("restricted");
    assert_eq!(review_text(restricted, choices), clean);
    assert!(!clean.contains("Mara"));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn native_receipt_form_repairs_after_earlier_truth_correction() {
    use crate::identity_editor::workflow::{connect, open, publish, read, tool};
    use tokio_util::sync::CancellationToken;
    use universe_protocol::{
        installation::*,
        request::{ProposalRef, Selector},
    };
    use universe_service::runtime;
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
    let ctx_record = read(&mut c, &opened, &u["context_id"]).await;
    let clock: Chronology =
        serde_json::from_value(ctx_record["payload"]["chronology"].clone()).unwrap();
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let id = |n: u64| format!("rec_{:024x}", 68000 + n);
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let scope = json!({"context":frame.context,"applicability":{"kind":"universe_wide"}});
    let interval = |t: i32| json!({"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":t.to_string()},"end":{"kind":"exact","value":"20"}});
    let time = |t: i32| json!({"kind":"exact","calendar":clock.calendar,"value":t.to_string()});
    let policy = |n, cap: &str| json!({"kind":"define_rule","client_ref":id(n),"record":{"namespace":"native","key":cap,"labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":[cap],"executable":true,"validity":{"kind":"unspecified"}}});
    let mut chronology = policy(50, "communications.chronology.v1");
    chronology["record"]["channelChronology"] = json!({"channel":"radio","forwardOnly":true});
    let mut knowledge_policy = policy(51, "knowledge.acquisition.v1");
    knowledge_policy["record"]["knowledgePolicy"] =
        json!({"context":frame.context,"mode":"justified"});
    let entity = |n, name: &str| json!({"kind":"introduce_instance","client_ref":id(n),"name":{"text":name,"validity":interval(0)},"world_associations":[]});
    publish(&mut c,&opened,json!([entity(10,"Code"),entity(11,"Sender"),entity(12,"Mara"),chronology,knowledge_policy,
        {"kind":"define_property","client_ref":id(21),"record":{"namespace":"native","key":"code","labels":{},"subjectTypes":[],"value":{"kind":"boolean"},"multiplicity":"single","persistence":"explicit_interval","exclusive":false,"symmetric":false,"transitive":false}},
        {"kind":"assert_proposition","client_ref":id(20),"proposition":{"subject":rr(10),"predicate":rr(21),"value":{"kind":"boolean","value":true},"quantification":"particular","context":frame.context},"assertion":{"attributeMode":"instance","proposition":rr(20),"polarity":"support","scope":scope,"validity":interval(0),"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Authored code"}}}]),"knowledge-seed").await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let boundary_form = crate::policy_editor::factual::Form {
        namespace: "native".into(),
        key: "Mara not informed".into(),
        holder: id(12),
        proposition: id(20),
        context: frame.context.record.to_string(),
        applicability: "universe_wide".into(),
        validity: "interval".into(),
        start: "0".into(),
        end: "4".into(),
        ..Default::default()
    };
    let boundary_choices = vec![
        json!({"kind":"entity","record_id":id(12)}),
        json!({"kind":"proposition","record_id":id(20)}),
    ];
    let boundary = boundary_form
        .build(
            "knowledge_boundary",
            &frame,
            Some(&clock),
            &boundary_choices,
        )
        .unwrap();
    publish(
        &mut c,
        &opened,
        json!([boundary]),
        "explicit-native-knowledge-boundary",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let message = json!({"kind":"record_communication","client_ref":id(30),"record":{"sender":rr(11),"intendedRecipients":[rr(12)],"actualRecipients":[rr(12)],"content":[rr(20)],"channel":"radio","sentAt":time(1),"receivedAt":time(3),"distorted":false}});
    let choices = crate::author::choices(
        &[
            json!({"kind":"entity","record_id":id(12),"label":"Mara"}),
            json!({"kind":"proposition","record_id":id(20),"label":"Code"}),
        ],
        &[],
        &json!([message]).to_string(),
    );
    let mut f = Form {
        holder: id(12),
        proposition: id(20),
        attitude: "knows".into(),
        start: "4".into(),
        end: "20".into(),
        basis: "Mara interprets the received code".into(),
        context: frame.context.record.to_string(),
        acquired: "4".into(),
        mode: "communication_receipt".into(),
        communication: id(30),
        interpretation: id(20),
        ..Default::default()
    };
    let knowledge = f.build(&frame, Some(&clock), &choices).unwrap();
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[message,knowledge],"submission":"submitted","rationale":"Message interpreted by Mara","idempotency_key":"connected-native"})).await["result"].clone();
    let reference: ProposalRef = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"].clone();
    assert!(v["execution"]["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference.clone(),
        validation_run: serde_json::from_value(v["execution"]["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    let hits=tool(&mut c,"universe_search",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"query":"","typed_filters":{"record_kinds":["assertion"]},"limit":100})).await;
    let assertion_id = hits["result"]["hits"][0]["record_id"].clone();
    let assertion = read(&mut c, &opened, &assertion_id).await;
    let mut replacement = assertion["payload"].clone();
    replacement.as_object_mut().unwrap().remove("record_kind");
    replacement["validity"] = interval(6);
    publish(&mut c,&opened,json!([{"kind":"supersede_assertion","record":{"universe":u["universe_id"],"record":assertion_id},"expected_version":assertion["record_version_id"],"replacement":replacement,"rationale":"Code becomes true later"}]),"earlier-truth-correction").await;
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference.clone(),
            validation_run: serde_json::from_value(v["execution"]["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let bad = f.build(&frame, Some(&clock), &choices).unwrap();
    let p=tool(&mut c,"universe_propose",json!({"action":"revise","proposal_reference":reference,"universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[message,bad],"submission":"submitted","rationale":"Rebased knowledge","idempotency_key":"rebased-native"})).await["result"].clone();
    let reference: ProposalRef = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"].clone();
    let text = review_text(
        v.clone(),
        crate::author::choices(&choices, &[], &json!([bad]).to_string()),
    );
    assert!(text.contains("supporting truth"), "{text}");
    assert!(text.contains("Mara"));
    assert!(text.contains(&id(30)));
    assert!(text.contains(&id(20)));
    assert!(text.contains(&id(51)));
    assert!(c
        .call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: reference.clone(),
            validation_run: serde_json::from_value(v["execution"]["run_id"].clone()).unwrap()
        })
        .await
        .is_err());
    f.acquired = "7".into();
    f.start = "7".into();
    let repaired = f.build(&frame, Some(&clock), &choices).unwrap();
    // The existing native remove/add path replaces the affected operation before
    // exact proposal review. Publishing uses the same service approval path.
    let p=tool(&mut c,"universe_propose",json!({"action":"revise","proposal_reference":reference,"universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[message,repaired],"submission":"submitted","rationale":"Correct knowledge acquisition after truth starts","idempotency_key":"repaired-native"})).await["result"].clone();
    let reference: ProposalRef = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let review = c
        .call(EngineRequest::Review {
            universe: Selector("Alpha".into()),
            proposal_reference: reference.clone(),
        })
        .await
        .unwrap();
    assert!(!review["diff"].is_null());
    let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"].clone();
    assert!(v["execution"]["findings"]
        .as_array()
        .unwrap()
        .iter()
        .all(|f| f["outcome"] == "supported"));
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference.clone(),
        validation_run: serde_json::from_value(v["execution"]["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    tool(&mut c,"universe_commit",json!({"universe":"Alpha","proposal_reference":reference,"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["execution"]["run_id"],"idempotency_key":"commit-repaired-native"})).await;
    let opened = open(&mut c, &u).await;
    let stored = read(&mut c, &opened, &repaired["client_ref"]).await;
    assert_eq!(
        stored["payload"]["acquisition"],
        repaired["record"]["acquisition"]
    );
    let historical = opened.clone();
    let end = crate::inspector_editor::operation(
        &frame,
        &stored,
        "attitude_end",
        "10",
        "Explicit knowledge duration ending",
        Some(&clock),
    )
    .unwrap();
    assert_eq!(
        end["replacement"]["acquisition"],
        stored["payload"]["acquisition"]
    );
    assert_eq!(end["replacement"]["basis"], stored["payload"]["basis"]);
    publish(&mut c, &opened, json!([end]), "manual-knowledge-ending").await;
    let opened = open(&mut c, &u).await;
    let current = read(&mut c, &opened, &repaired["client_ref"]).await;
    assert_eq!(current["payload"]["validity"]["end"]["value"], "10");
    assert_eq!(
        read(&mut c, &historical, &repaired["client_ref"]).await["payload"]["validity"],
        stored["payload"]["validity"]
    );
    let original_message = read(&mut c, &opened, &message["client_ref"]).await;
    let corrected_message = crate::inspector_editor::operation(
        &frame,
        &original_message,
        "message_received",
        "6",
        "Correct the historical receipt time",
        Some(&clock),
    )
    .unwrap();
    publish(
        &mut c,
        &opened,
        json!([corrected_message]),
        "manual-message-correction",
    )
    .await;
    let message_context = open(&mut c, &u).await;
    assert_eq!(
        read(&mut c, &message_context, &message["client_ref"]).await["payload"]["receivedAt"]
            ["value"],
        "6"
    );
    assert_eq!(
        read(&mut c, &opened, &message["client_ref"]).await["payload"],
        original_message["payload"]
    );
    let opened = message_context;
    f.attitude = "believes".into();
    let belief = f.build(&frame, Some(&clock), &choices).unwrap();
    publish(&mut c, &opened, json!([belief]), "manual-belief").await;
    let opened = open(&mut c, &u).await;
    let original = read(&mut c, &opened, &belief["client_ref"]).await;
    let proposition = read(&mut c, &opened, &json!(f.proposition)).await;
    let correction = crate::inspector_editor::attitude_value_operations(
        &frame,
        &original,
        &[proposition],
        "false",
        "Correct the recorded belief only",
        Some(&clock),
    )
    .unwrap();
    publish(
        &mut c,
        &opened,
        json!(correction),
        "manual-belief-correction",
    )
    .await;
    let current_context = open(&mut c, &u).await;
    let changed = read(&mut c, &current_context, &belief["client_ref"]).await;
    assert_eq!(changed["payload"]["attitude"], "believes");
    assert_eq!(changed["payload"]["holder"], original["payload"]["holder"]);
    let changed_claim = read(
        &mut c,
        &current_context,
        &changed["payload"]["proposition"]["record"],
    )
    .await;
    assert_eq!(changed_claim["payload"]["value"]["value"], false);
    assert_eq!(
        read(&mut c, &opened, &belief["client_ref"]).await["payload"],
        original["payload"]
    );
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[test]
fn knowledge_form_mounts_and_selected_context_requires_its_own_clock() {
    fn fixture() -> Element {
        rsx! {KnowledgeEditor{frame:frame(),clock:Some(clock()),choices:vec![],disabled:false,onadd:move |_|{}}}
    }
    let mut dom = dioxus::core::VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
    let mut f = form();
    f.context = "rec_000000000000000000000009".into();
    let choices = vec![json!({"kind":"represented_context","record_id":f.context})];
    assert!(f.build(&frame(), Some(&clock()), &choices).is_err());
    let mut other = clock();
    other.calendar =
        universe_domain::ids::CalendarId::parse("cal_000000000000000000000009").unwrap();
    let choices = vec![
        json!({"kind":"represented_context","record_id":f.context,"definition":{"chronology":other}}),
    ];
    let op = f.build(&frame(), Some(&clock()), &choices).unwrap();
    assert_eq!(
        op["record"]["acquisition"]["time"]["calendar"],
        "cal_000000000000000000000009"
    );
    assert_eq!(
        op["record"]["validity"]["calendar"],
        "cal_000000000000000000000009"
    );
    f.mode.clear();
    assert!(f.build(&frame(), Some(&clock()), &choices).is_err());
}
#[test]
fn repair_review_identifies_authored_relation_dependencies() {
    let choices = vec![
        json!({"kind":"rule","record_id":"count-policy","label":"Maximum two","definition":{"relationCardinality":{"relation":{"record":"succession"}}}}),
        json!({"kind":"relation","record_id":"succession","label":"Successors"}),
    ];
    let text = review_text(
        json!({"kind":"evaluated","execution":{"coverage":"complete","findings":[{"rule_id":"count-policy","outcome":"refuted","message":"Correct simultaneous participants.","records":[{"record":"count-policy"}]}]}}),
        choices,
    );
    assert!(text.contains("Policy: Rule: Maximum two"));
    assert!(text.contains("Relation: Relation: Successors"));
}
