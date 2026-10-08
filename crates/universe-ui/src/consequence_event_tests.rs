use super::*;
use crate::identity_editor::workflow::{connect, open, publish, read, tool};
use tokio_util::sync::CancellationToken;
use universe_protocol::{installation::*, request::Selector};
use universe_service::runtime;
fn id(n: u64) -> String {
    format!("rec_{n:024x}")
}
fn frame() -> Frame {
    serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":id(9)},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
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
fn slot(f: &Frame, name: &str, role: &str, delta: &str, order: u8) -> Value {
    json!({"slot":name,"order":order,"presence":"required","target":{"role":role,"predicate":{"universe":f.universe,"record":id(1)}},"condition":{"kind":"always"},"change":{"kind":"delta","delta":delta,"minimum":"0","maximum":"3","unit":null},"lifetime":{"kind":"until_changed"}})
}
fn definition(f: &Frame, key: &str, slots: Vec<Value>) -> Value {
    json!({"namespace":"event-actions","key":key,"labels":{"en":key},"requirements":[],"consequenceContract":{"kind":"action_consequences","slots":slots},"scope":{"context":f.context,"applicability":{"kind":"universe_wide"}},"validity":{"kind":"unspecified"}})
}
fn choices(f: &Frame) -> Vec<Value> {
    vec![
        json!({"kind":"property","record_id":id(1),"label":"Stock","definition":{"value":{"kind":"integer"},"multiplicity":"single"}}),
        json!({"kind":"property","record_id":id(2),"label":"Enabled","definition":{"value":{"kind":"boolean"},"multiplicity":"single"}}),
        json!({"kind":"entity","record_id":id(10),"label":"Weapon"}),
        json!({"kind":"entity","record_id":id(11),"label":"Reserve"}),
        json!({"kind":"action_definition","record_id":id(20),"label":"Consume","definition":definition(f,"consume",vec![slot(f,"consume","weapon","-1",0)])}),
        json!({"kind":"action_definition","record_id":id(21),"label":"Reload","definition":definition(f,"reload",vec![slot(f,"load","weapon","2",0),slot(f,"debit","reserve","-2",1)])}),
        json!({"kind":"action_definition","record_id":id(22),"label":"Enable","definition":definition(f,"enable",vec![json!({"slot":"enable","order":0,"presence":"required","target":{"role":"weapon","predicate":{"universe":f.universe,"record":id(2)}},"condition":{"kind":"always"},"change":{"kind":"set","polarity":"support","value":{"kind":"boolean","value":true}},"lifetime":{"kind":"ticks","count":"3"}})])}),
        json!({"kind":"action_definition","record_id":id(23),"label":"Walk","definition":definition(f,"walk",vec![])}),
    ]
}
fn form(f: &Frame, c: &[Value], which: u64, time: &str, balances: &[&str]) -> Form {
    let mut form = Form::default();
    form.select(id(which), c).unwrap();
    form.title = "Authored event".into();
    form.occurrence = "occurred".into();
    form.start = time.into();
    form.context = f.context.record.to_string();
    form.applicability = "universe_wide".into();
    for (role, entity) in &mut form.roles {
        *entity = if role == "reserve" { id(11) } else { id(10) };
    }
    for (i, e) in form.effects.iter_mut().enumerate() {
        e.include = "yes".into();
        e.source = "new".into();
        e.balance = balances.get(i).unwrap_or(&"").to_string();
        e.polarity = "support".into();
        e.order = i.to_string();
        e.end_kind = "unbounded".into();
    }
    form
}
#[test]
fn roles_effects_scope_validity_and_post_values_are_explicit() {
    let f = frame();
    let c = choices(&f);
    let clock = clock();
    let mut form = form(&f, &c, 21, "2", &["3", "1"]);
    let ops = form.build(&f, Some(&clock), &c).unwrap();
    assert_eq!(ops.len(), 3);
    assert_eq!(ops[0]["record"]["value"]["digits"], "3");
    assert_eq!(ops[1]["record"]["subject"]["record"], id(11));
    assert_eq!(ops[2]["record"]["effects"][1]["order"], 1);
    assert_eq!(
        ops[2]["record"]["effects"][1]["scope"]["context"],
        json!(f.context)
    );
    form.effects[1].include.clear();
    assert!(form.build(&f, Some(&clock), &c).is_err());
    form.effects[1].include = "no".into();
    assert_eq!(
        form.build(&f, Some(&clock), &c).unwrap().last().unwrap()["record"]["effects"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    form.select(id(20), &c).unwrap();
    assert!(form.roles.iter().all(|(_, e)| e.is_empty()));
    assert!(form
        .effects
        .iter()
        .all(|e| e.include.is_empty() && e.balance.is_empty()));
    assert!(form.context.is_empty());
}
#[test]
fn fixed_existing_quantity_values_and_ordinary_actions_preserve_contracts() {
    let f = frame();
    let mut c = choices(&f);
    let clock = clock();
    let mut fixed = form(&f, &c, 22, "4", &[]);
    fixed.effects[0].value = FixedValue {
        source: "literal".into(),
        value: "true".into(),
        ..Default::default()
    };
    fixed.effects[0].end_kind = "exact".into();
    fixed.effects[0].end = "7".into();
    let ops = fixed.build(&f, Some(&clock), &c).unwrap();
    assert_eq!(ops[0]["record"]["value"]["value"], true);
    assert_eq!(
        ops[1]["record"]["effects"][0]["validity"]["end"]["value"],
        "7"
    );
    let mut p = ops[0]["record"].clone();
    c.push(json!({"kind":"proposition","record_id":id(30),"label":"Existing fixed effect","definition":p}));
    fixed.effects[0].source = "existing".into();
    fixed.effects[0].proposition = id(30);
    assert_eq!(fixed.build(&f, Some(&clock), &c).unwrap().len(), 1);
    p["subject"]["record"] = json!(id(11));
    c.last_mut().unwrap()["definition"] = p;
    assert!(fixed.build(&f, Some(&clock), &c).is_err());
    let unit = "unit_000000000000000000000004";
    c[4]["definition"]["consequenceContract"]["slots"][0]["change"]["unit"] = json!(unit);
    c[0]["definition"]["value"] = json!({"kind":"quantity","unit":unit});
    let quantity = form(&f, &c, 20, "1", &["9007199254740993"])
        .build(&f, Some(&clock), &c)
        .unwrap();
    assert_eq!(
        quantity[0]["record"]["value"],
        json!({"kind":"quantity","value":{"kind":"integer","digits":"9007199254740993"},"unit":unit})
    );
    let ordinary = form(&f, &c, 23, "1", &[])
        .build(&f, Some(&clock), &c)
        .unwrap();
    assert_eq!(ordinary.len(), 1);
    assert_eq!(ordinary[0]["record"]["effects"], json!([]));
}
#[test]
fn controls_mount_for_declared_slots_and_power_authoring() {
    fn fixture() -> Element {
        let f = frame();
        let c = choices(&f);
        let form = form(&f, &c, 21, "2", &["3", "1"]);
        rsx! {crate::event_editor::EventEditor{frame:f.clone(),clock:Some(clock()),choices:c.clone(),disabled:false,onadd:move |_|{}}EffectControls{id:"slot-render",slot:c[5]["definition"]["consequenceContract"]["slots"][0].clone(),input:form.effects[0].clone(),choices:c,disabled:false,onchange:move |_|{}}}
    }
    let mut dom = VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
async fn reject(
    c: &mut universe_client::installation::EngineClient,
    opened: &Value,
    ops: Vec<Value>,
    key: &str,
    reason: &str,
) {
    let request=crate::author::tool("universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":ops,"submission":"submitted","rationale":"Authored candidate for validation","idempotency_key":key})).unwrap();
    let p = match c.call(request).await {
        Ok(p) => p["result"].clone(),
        Err(e) => {
            assert!(e.to_string().contains(reason), "{key}: {e}");
            return;
        }
    };
    let reference =
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]});
    let request=crate::author::tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).unwrap();
    let error = c.call(request).await.unwrap_err().to_string();
    assert!(error.contains(reason), "{key}: {error}");
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn consumption_reload_reserve_debit_rejections_exhaustion_and_recovery() {
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
    let f: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    let mut choice = choices(&f);
    let mut seed = vec![];
    for (n, key, shape) in [(1, "stock", "integer"), (2, "enabled", "boolean")] {
        seed.push(json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"events","key":key,"labels":{},"subjectTypes":[],"value":{"kind":shape},"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}}));
    }
    for n in [10, 11] {
        seed.push(json!({"kind":"create_entity","client_ref":id(n),"record":{"names":[],"classificationResolution":"unclassified","worldAssociations":[],"labels":{},"metadata":{}}}));
    }
    for n in 20..=23 {
        seed.push(json!({"kind":"define_action","client_ref":id(n),"record":action(&choice,&id(n)).unwrap()}));
    }
    let clock: Chronology = serde_json::from_value(
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"].clone(),
    )
    .unwrap();
    for (n, subject, digits, end) in [(40, 10, "2", "1"), (41, 11, "3", "2")] {
        let rr = |n| json!({"universe":f.universe,"record":id(n)});
        seed.push(json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(subject),"predicate":rr(1),"value":{"kind":"integer","digits":digits},"context":f.context,"quantification":"particular"},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":{"context":f.context,"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":"0"},"end":{"kind":"exact","value":end}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Explicit initial stock"}}}));
    }
    publish(&mut c, &opened, json!(seed), "event-fixture").await;
    let opened = open(&mut c, &u).await;
    let f: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    for n in 20..=23 {
        let r = read(&mut c, &opened, &json!(id(n))).await;
        choice.iter_mut().find(|c| c["record_id"] == id(n)).unwrap()["definition"] =
            r["payload"].clone();
    }
    let consume = form(&f, &choice, 20, "1", &["1"]);
    let ops = consume.build(&f, Some(&clock), &choice).unwrap();
    c.call(EngineRequest::SaveDraft {
        universe: Selector("Alpha".into()),
        continuity_id: f.continuity.clone(),
        expected_version: 0,
        content: DraftContent {
            proposal: None,
            base_revision: f.revision.clone(),
            represented_context: f.context.record.clone(),
            operations: serde_json::from_value(json!(ops)).unwrap(),
            rationale: "Explicit consuming event".into(),
        },
    })
    .await
    .unwrap();
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let recovered = c
        .call(EngineRequest::LoadDraft {
            universe: Selector("Alpha".into()),
            continuity_id: f.continuity.clone(),
        })
        .await
        .unwrap();
    assert_eq!(recovered["content"]["operations"], json!(ops));
    let opened = open(&mut c, &u).await;
    publish(
        &mut c,
        &opened,
        recovered["content"]["operations"].clone(),
        "consume-recovered",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let reload = form(&f, &choice, 21, "2", &["3", "1"]);
    let mut omitted = reload.clone();
    omitted.effects[1].include = "no".into();
    reject(
        &mut c,
        &opened,
        omitted.build(&f, Some(&clock), &choice).unwrap(),
        "omit-reserve",
        "missing mandatory effect",
    )
    .await;
    let mut forged = reload.clone();
    forged.effects[0].balance = "2".into();
    reject(
        &mut c,
        &opened,
        forged.build(&f, Some(&clock), &choice).unwrap(),
        "forged-reload",
        "post-value does not equal",
    )
    .await;
    publish(
        &mut c,
        &opened,
        json!(reload.build(&f, Some(&clock), &choice).unwrap()),
        "reload-with-reserve",
    )
    .await;
    for (time, balance) in [("3", "2"), ("4", "1"), ("5", "0")] {
        let opened = open(&mut c, &u).await;
        publish(
            &mut c,
            &opened,
            json!(form(&f, &choice, 20, time, &[balance])
                .build(&f, Some(&clock), &choice)
                .unwrap()),
            &format!("consume-{time}"),
        )
        .await;
    }
    let opened = open(&mut c, &u).await;
    reject(
        &mut c,
        &opened,
        form(&f, &choice, 20, "6", &["-1"])
            .build(&f, Some(&clock), &choice)
            .unwrap(),
        "exhausted",
        "underflow or overflow",
    )
    .await;
    let mut fixed = form(&f, &choice, 22, "7", &[]);
    fixed.effects[0].value = FixedValue {
        source: "literal".into(),
        value: "true".into(),
        ..Default::default()
    };
    fixed.effects[0].end_kind = "exact".into();
    fixed.effects[0].end = "10".into();
    let mut forged = fixed.clone();
    forged.effects[0].value.value = "false".into();
    reject(
        &mut c,
        &opened,
        forged.build(&f, Some(&clock), &choice).unwrap(),
        "forged-fixed",
        "polarity/value does not match",
    )
    .await;
    publish(
        &mut c,
        &opened,
        json!(fixed.build(&f, Some(&clock), &choice).unwrap()),
        "fixed-effect",
    )
    .await;
    let at=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock.calendar,"value":"8"}},"temporal_systems":[],"perspective":"author"})).await;
    let state=tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"entity_ids":[id(10),id(11)],"predicate_filters":[]})).await;
    for (entity, expected) in [(10, "0"), (11, "1")] {
        let object = state["result"]["objects"]
            .as_array()
            .unwrap()
            .iter()
            .find(|o| o["identity"]["identity"]["record_id"] == id(entity))
            .unwrap();
        let balances: Vec<_> = object["instance_facts"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|row| row["applicability"] == true)
            .filter_map(|row| {
                let proposition = object["dependencies"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|p| {
                        p["identity"]["record_id"]
                            == row["record"]["payload"]["proposition"]["record"]
                    })?;
                (proposition["payload"]["predicate"]["record"] == id(1)).then(|| {
                    proposition["payload"]["value"]["digits"]
                        .as_str()
                        .unwrap()
                        .to_string()
                })
            })
            .collect();
        assert_eq!(balances, vec![expected.to_string()]);
    }
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn version_bound_corrections_recompile_dependents_and_preserve_history() {
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
    let f: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    let mut choice = choices(&f);
    let mut seed = vec![];
    for (n, key, shape) in [(1, "stock", "integer"), (2, "enabled", "boolean")] {
        seed.push(json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"events","key":key,"labels":{},"subjectTypes":[],"value":{"kind":shape},"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}}));
    }
    for n in [10, 11] {
        seed.push(json!({"kind":"create_entity","client_ref":id(n),"record":{"names":[],"classificationResolution":"unclassified","worldAssociations":[],"labels":{},"metadata":{}}}));
    }
    for n in 20..=23 {
        seed.push(json!({"kind":"define_action","client_ref":id(n),"record":action(&choice,&id(n)).unwrap()}));
    }
    let clock: Chronology = serde_json::from_value(
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"].clone(),
    )
    .unwrap();
    for (n, subject, digits, end) in [(40, 10, "2", "1"), (41, 11, "3", "2")] {
        let rr = |n| json!({"universe":f.universe,"record":id(n)});
        seed.push(json!({"kind":"assert_proposition","client_ref":id(n),"proposition":{"subject":rr(subject),"predicate":rr(1),"value":{"kind":"integer","digits":digits},"context":f.context,"quantification":"particular"},"assertion":{"attributeMode":"instance","proposition":rr(n),"polarity":"support","scope":{"context":f.context,"applicability":{"kind":"universe_wide"}},"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":"0"},"end":{"kind":"exact","value":end}},"persistence":"explicit_interval","precision":"exact","basis":{"kind":"author_decision","note":"Explicit initial stock"}}}));
    }
    publish(&mut c, &opened, json!(seed), "event-fixture").await;
    let opened = open(&mut c, &u).await;
    let f: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    for n in 20..=23 {
        let r = read(&mut c, &opened, &json!(id(n))).await;
        choice.iter_mut().find(|c| c["record_id"] == id(n)).unwrap()["definition"] =
            r["payload"].clone();
    }

    let mut burst = choice.iter().find(|c| c["record_id"] == id(20)).unwrap()["definition"].clone();
    burst.as_object_mut().unwrap().remove("record_kind");
    burst["key"] = json!("burst");
    burst["consequenceContract"]["slots"][0]["change"]["delta"] = json!("-2");
    publish(
        &mut c,
        &opened,
        json!([{"kind":"define_action","client_ref":id(24),"record":burst}]),
        "correction-burst",
    )
    .await;
    choice.push(
        json!({"kind":"action_definition","record_id":id(24),"label":"Burst","definition":burst}),
    );
    let opened = open(&mut c, &u).await;
    let mut first_ops = form(&f, &choice, 20, "1", &["1"])
        .build(&f, Some(&clock), &choice)
        .unwrap();
    let first_id = first_ops.last().unwrap()["client_ref"].clone();
    let event = first_ops.last_mut().unwrap();
    event["record"]["labels"]["fr"] = json!("Tir");
    event["record"]["sequence"] = json!("authored-sequence");
    event["record"]["occurrenceId"] = json!("first-occurrence");
    event["record"]["preconditions"] = json!([{"kind":"lit","value":true}]);
    publish(&mut c, &opened, json!(first_ops), "correction-first").await;
    let opened = open(&mut c, &u).await;
    let second_ops = form(&f, &choice, 21, "2", &["3", "1"])
        .build(&f, Some(&clock), &choice)
        .unwrap();
    let second_id = second_ops.last().unwrap()["client_ref"].clone();
    publish(&mut c, &opened, json!(second_ops), "correction-reload").await;
    let old = open(&mut c, &u).await;
    let first = read(&mut c, &old, &first_id).await;
    let second = read(&mut c, &old, &second_id).await;
    for event in [&first, &second] {
        for effect in event["payload"]["effects"].as_array().unwrap() {
            let p = read(&mut c, &old, &effect["proposition"]["record"]).await;
            choice.extend(crate::author::choices(&[], &[p], "[]"));
        }
    }
    let (loaded, related) = crate::event_correction::load(
        root.to_string_lossy().into(),
        author.to_string(),
        "Alpha".into(),
        old["result"]["context_id"].clone(),
        &first,
    )
    .await
    .unwrap();
    assert!(loaded.iter().any(|c| c["record_id"] == id(20)));
    assert!(!related["result"].is_null());
    Form::load(first.clone(), &f, Some(&clock), &loaded)
        .unwrap()
        .build(&f, Some(&clock), &loaded)
        .unwrap();
    let unchanged = Form::load(first.clone(), &f, Some(&clock), &choice)
        .unwrap()
        .build(&f, Some(&clock), &choice)
        .unwrap();
    let expected: universe_domain::records::Event = serde_json::from_value({
        let mut p = first["payload"].clone();
        p.as_object_mut().unwrap().remove("record_kind");
        p
    })
    .unwrap();
    let roundtrip: universe_domain::records::Event =
        serde_json::from_value(unchanged[0]["replacement"].clone()).unwrap();
    assert_eq!(roundtrip, expected);
    let mut earlier = Form::load(first.clone(), &f, Some(&clock), &choice).unwrap();
    earlier.action = id(24);
    earlier.effects[0].source = "new".into();
    earlier.effects[0].balance = "0".into();
    let first_change = earlier.build(&f, Some(&clock), &choice).unwrap();
    reject(
        &mut c,
        &old,
        first_change.clone(),
        "isolated-earlier-correction",
        "post-value does not equal",
    )
    .await;
    let mut dependent = Form::load(second.clone(), &f, Some(&clock), &choice).unwrap();
    dependent.effects[0].source = "new".into();
    dependent.effects[0].balance = "2".into();
    let mut coherent = earlier.build(&f, Some(&clock), &choice).unwrap();
    coherent.extend(dependent.build(&f, Some(&clock), &choice).unwrap());
    // Normal review includes recompiled generated assertions alongside the event replacements.
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":old["result"]["context_id"],"operations":coherent,"submission":"submitted","rationale":"Correct earlier event and dependent balance together","idempotency_key":"coherent-event-review"})).await["result"].clone();
    let reference = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let review = c
        .call(EngineRequest::Review {
            universe: Selector("Alpha".into()),
            proposal_reference: reference,
        })
        .await
        .unwrap();
    assert!(review.to_string().contains("establishedBy"));
    assert!(review.to_string().contains(first_id.as_str().unwrap()));
    assert!(review.to_string().contains(second_id.as_str().unwrap()));
    let reference = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":old["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"]["execution"].clone();
    assert_eq!(v["coverage"], "complete");
    c.call(EngineRequest::Approve {
        universe: Selector("Alpha".into()),
        proposal_reference: reference,
        validation_run: serde_json::from_value(v["run_id"].clone()).unwrap(),
    })
    .await
    .unwrap();
    tool(&mut c,"universe_commit",json!({"universe":"Alpha","proposal_reference":{"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]},"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["run_id"],"idempotency_key":"coherent-event-correction"})).await;
    let current = open(&mut c, &u).await;
    let corrected = read(&mut c, &current, &first_id).await;
    assert_ne!(corrected["record_version_id"], first["record_version_id"]);
    assert_eq!(corrected["payload"]["labels"]["fr"], "Tir");
    assert_eq!(
        corrected["payload"]["preconditions"],
        first["payload"]["preconditions"]
    );
    assert_eq!(corrected["payload"]["occurrenceId"], "first-occurrence");
    assert_eq!(corrected["payload"]["sequence"], "authored-sequence");
    reject(
        &mut c,
        &current,
        {let mut payload=corrected["payload"].clone();payload.as_object_mut().unwrap().remove("record_kind");vec![json!({"kind":"revise_event","record":{"universe":f.universe,"record":first_id},"expected_version":first["record_version_id"],"replacement":payload})]},
        "stale-event-correction",
        "version",
    )
    .await;
    assert_eq!(read(&mut c, &old, &first_id).await, first);
    assert_eq!(read(&mut c, &old, &second_id).await, second);
    let before = read(
        &mut c,
        &old,
        &second["payload"]["effects"][0]["proposition"]["record"],
    )
    .await;
    assert_eq!(before["payload"]["value"]["digits"], "3");
    let new_second = read(&mut c, &current, &second_id).await;
    let after = read(
        &mut c,
        &current,
        &new_second["payload"]["effects"][0]["proposition"]["record"],
    )
    .await;
    assert_eq!(after["payload"]["value"]["digits"], "2");
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
#[test]
fn correction_roundtrip_preserves_gregorian_fields_and_blocks_generated_edits() {
    let f = frame();
    let c = choices(&f);
    let calendar = universe_domain::ids::CalendarId::parse("cal_000000000000000000000001").unwrap();
    let (clock, _) = universe_domain::chronology::UniverseStart::Gregorian {
        timestamp: "2026-10-08T10:00:00-07:00".into(),
    }
    .build(calendar)
    .unwrap();
    let mut event_form = form(&f, &c, 22, "2026-10-08T10:00:00-07:00", &[]);
    event_form.effects[0].value = FixedValue {
        source: "literal".into(),
        value: "true".into(),
        ..Default::default()
    };
    event_form.effects[0].end_kind = "exact".into();
    event_form.effects[0].end = "2026-10-08T10:00:03-07:00".into();
    let ops = event_form.build(&f, Some(&clock), &c).unwrap();
    let mut c = c;
    c.extend(crate::author::choices(
        &[],
        &[],
        &serde_json::to_string(&ops).unwrap(),
    ));
    let mut payload = ops.last().unwrap()["record"].clone();
    payload["record_kind"] = json!("event");
    payload["labels"]["fr"] = json!("Événement");
    payload["preconditions"] = json!([{"kind":"lit","value":true}]);
    payload["sequence"] = json!("retained sequence");
    payload["occurrenceId"] = json!("retained occurrence");
    let original = json!({"identity":{"universe_id":f.universe,"record_id":id(99)},"record_version_id":"ver_000000000000000000000099","payload":payload});
    let loaded = Form::load(original.clone(), &f, Some(&clock), &c).unwrap();
    let revised = loaded.build(&f, Some(&clock), &c).unwrap();
    let mut payload = payload;
    payload.as_object_mut().unwrap().remove("record_kind");
    let before: universe_domain::records::Event = serde_json::from_value(payload).unwrap();
    let after: universe_domain::records::Event =
        serde_json::from_value(revised[0]["replacement"].clone()).unwrap();
    assert_eq!(before, after);
    assert_eq!(
        revised[0]["expected_version"],
        original["record_version_id"]
    );
    let assertion = json!({"payload":{"record_kind":"assertion","establishedBy":{"event":{"record":id(99)},"slot":"enable"}}});
    assert!(crate::inspector_editor::operation(
        &f,
        &assertion,
        "retract_assertion",
        "",
        "Correction",
        Some(&clock)
    )
    .unwrap_err()
    .contains("establishing event"));
    fn fixture() -> Element {
        rsx! {crate::event_correction::EventCorrection{root:"unused",profile:"unused",universe:"Alpha",context:Value::Null,frame:frame(),original:Value::Null,clock:Some(crate::consequence_event::tests::clock()),disabled:false,onadd:move |_|{}}}
    }
    let mut dom = VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
