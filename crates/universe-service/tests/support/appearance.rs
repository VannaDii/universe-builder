use super::*;
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn universal_appearance_context_temporal_revision_and_image_authority() {
    let d = tempfile::tempdir().unwrap();
    let root = d.path().join("install");
    let author = runtime::initialize(&root).unwrap();
    let stop = CancellationToken::new();
    let (r, s) = (root.clone(), stop.clone());
    let server = tokio::spawn(async move { runtime::serve(&r, s).await });
    let mut c = connect(&root, &author).await;
    let u = c
        .call(EngineRequest::CreateUniverse {
            name: "Alpha".into(),
            start: universe_domain::chronology::UniverseStart::Fictional {
                calendar_name: "Story".into(),
                initial_tick: "0".into(),
                tick_label: "day".into(),
                ticks_per_month: Some(30),
            },
        })
        .await
        .unwrap();
    let ctx = context(&mut c, &u, "Alpha").await;
    let clock=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":ctx,"record_ids":[u["context_id"]],"field_groups":[]}))).await.unwrap()["result"]["records"][0]["payload"]["chronology"]["calendar"].clone();
    // A complete one-pixel PNG generated in the test source; no external image service.
    let image = d.path().join("reference.png");
    let png: [u8; 68] = [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 4,
        0, 0, 0, 181, 28, 12, 2, 0, 0, 0, 11, 73, 68, 65, 84, 120, 218, 99, 100, 248, 15, 0, 1, 5,
        1, 1, 39, 24, 227, 102, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
    ];
    std::fs::write(&image, png).unwrap();
    let staged = c
        .call(EngineRequest::StageImage {
            universe: Selector("Alpha".into()),
            source: image.clone(),
        })
        .await
        .unwrap();
    std::fs::remove_file(image).unwrap();
    assert_eq!(staged["canonical"], false);
    let rr = |id: Value| json!({"universe":u["universe_id"],"record":id});
    let entity_id = "rec_000000000000000000000081";
    let world_id = "rec_000000000000000000000082";
    let look_id = "rec_000000000000000000000083";
    let appearance = |target: Value, label: &str| json!({"target":target,"label":label,"physical_description":"Brushed brass with cobalt enamel","atmosphere":"Cold metal and a faint hum","images":[{"asset":rr(staged["asset_id"].clone()),"caption":"Preserve the cobalt dial","purpose":"detail"}],"links":[],"validity":{"kind":"unspecified"}});
    let mut entry = appearance(
        json!({"kind":"entry","entry":rr(json!(entity_id))}),
        "Instrument before the fire",
    );
    entry["validity"] = json!({"kind":"calendar_interval","calendar":clock,"start":{"kind":"exact","value":"0"},"end":{"kind":"exact","value":"10"}});
    entry["links"] = json!([{"entry":rr(json!(world_id)),"relationship":"complements","note":"The world's cobalt palette"}]);
    let mut ops = staged["operations"].as_array().unwrap().clone();
    ops.extend([entity("Instrument",entity_id),world("Workshop",world_id),json!({"kind":"create_appearance","client_ref":look_id,"record":entry}),json!({"kind":"create_appearance","client_ref":"rec_000000000000000000000084","record":appearance(json!({"kind":"universe"}),"Universe palette")}),json!({"kind":"create_appearance","client_ref":"rec_000000000000000000000085","record":appearance(json!({"kind":"entry","entry":rr(json!(world_id))}),"Workshop light")})]);
    let mut later = appearance(
        json!({"kind":"entry","entry":rr(json!(entity_id))}),
        "Instrument after the fire",
    );
    later["physical_description"] = json!("Blackened brass; the cobalt enamel has dulled");
    later["images"] = json!([]);
    later["validity"] = json!({"kind":"calendar_interval","calendar":clock,"start":{"kind":"exact","value":"10"},"end":{"kind":"unbounded"}});
    ops.push(json!({"kind":"create_appearance","client_ref":"rec_000000000000000000000087","record":later}));
    let p = proposal(&mut c, &ctx, ops, "looks").await;
    publish_proposal(&mut c, &ctx, &p, "looks-commit").await;
    let pinned = context(&mut c, &u, "Alpha").await;
    let brief=c.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":pinned,"focus_ids":[entity_id],"purpose":"Describe the instrument consistently","byte_budget":65536}))).await.unwrap();
    let records = brief["result"]["records"].as_array().unwrap();
    assert!(records
        .iter()
        .any(|r| r["identity"]["record_id"] == look_id));
    assert!(records
        .iter()
        .any(|r| r["payload"]["label"] == "Workshop light"));
    assert!(records
        .iter()
        .any(|r| r["payload"]["label"] == "Universe palette"));
    let preview = c
        .call(EngineRequest::ImagePreview {
            universe: Selector("Alpha".into()),
            context_id: serde_json::from_value(pinned.clone()).unwrap(),
            asset: serde_json::from_value(staged["asset_id"].clone()).unwrap(),
        })
        .await
        .unwrap();
    assert!(preview["preview"]
        .as_str()
        .unwrap()
        .starts_with("data:image/jpeg;base64,"));
    let at=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":"10"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone();
    let timed=c.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":at,"focus_ids":[entity_id],"purpose":"After the fire","byte_budget":65536}))).await.unwrap();
    assert!(!timed["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["identity"]["record_id"] == look_id));
    assert!(timed["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["payload"]["physical_description"]
            == "Blackened brass; the cobalt enamel has dulled"));
    let before=c.call(tool("universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock,"value":"9"}},"temporal_systems":[],"perspective":"author"}))).await.unwrap()["result"]["context_id"].clone();
    let earlier=c.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":before,"focus_ids":[entity_id],"purpose":"Before the fire","byte_budget":65536}))).await.unwrap();
    assert!(earlier["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["identity"]["record_id"] == look_id));
    assert!(!earlier["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["payload"]["label"] == "Instrument after the fire"));
    let original = records
        .iter()
        .find(|r| r["identity"]["record_id"] == look_id)
        .unwrap();
    let mut replacement = entry;
    replacement["physical_description"] = json!("Blackened brass");
    let changed=proposal(&mut c,&pinned,vec![json!({"kind":"revise_appearance","record":rr(json!(look_id)),"expected_version":original["record_version_id"],"replacement":replacement})],"revise-look").await;
    publish_proposal(&mut c, &pinned, &changed, "revise-look-commit").await;
    let historical=c.call(tool("universe_get",json!({"universe":"Alpha","context_id":pinned,"record_ids":[look_id],"field_groups":[]}))).await.unwrap();
    assert_eq!(
        historical["result"]["records"][0]["payload"]["physical_description"],
        "Brushed brass with cobalt enamel"
    );
    let current = context(&mut c, &u, "Alpha").await;
    let mut forged = staged["operations"][0].clone();
    forged["client_ref"] = json!("rec_000000000000000000000086");
    let bad = proposal(&mut c, &current, vec![forged], "forged-image").await;
    assert!(c.call(tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":current,"proposal_reference":reference(&bad),"check_scope":"universe"}))).await.is_err());
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
            protected: false,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let mut other = connect(&root, &agent).await;
    assert!(other
        .call(EngineRequest::StageImage {
            universe: Selector("Alpha".into()),
            source: d.path().join("unavailable.png")
        })
        .await
        .is_err());
    assert!(other
        .call(EngineRequest::ImagePreview {
            universe: Selector("Alpha".into()),
            context_id: serde_json::from_value(pinned.clone()).unwrap(),
            asset: serde_json::from_value(staged["asset_id"].clone()).unwrap()
        })
        .await
        .is_err());
    c.call(EngineRequest::Grant {
        grant: GrantSpec {
            profile_id: agent,
            universe_id: serde_json::from_value(u["universe_id"].clone()).unwrap(),
            worlds: Some(vec![
                WorldId::parse(&world_id.replacen("rec_", "wld_", 1)).unwrap()
            ]),
            propose: true,
            edit: true,
            protected: false,
            limits: Default::default(),
        },
    })
    .await
    .unwrap();
    let scoped = context(&mut other, &u, "Alpha").await;
    let restricted=other.call(tool("universe_get_context",json!({"universe":"Alpha","context_id":scoped,"focus_ids":[world_id],"purpose":"Scoped appearance","byte_budget":65536}))).await.unwrap();
    assert_eq!(restricted["result"]["coverage"], "partial");
    assert!(!restricted["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["payload"]["record_kind"] == "image_asset"));
    drop(other);
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
