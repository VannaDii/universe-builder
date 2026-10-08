use super::*;
use crate::identity_editor::workflow::{connect, open, publish, read, tool};
use tokio_util::sync::CancellationToken;
use universe_protocol::{
    installation::*,
    request::{ProposalRef, Selector},
};
use universe_service::runtime;
fn id(n: u64) -> String {
    format!("rec_{n:024x}")
}
fn choices() -> Vec<Value> {
    (1..=4).map(|n|json!({"kind":if n==4{"proposition"}else{"entity"},"record_id":id(n),"label":format!("Record {n}")})).collect()
}
fn form() -> Form {
    Form {
        sender: id(1),
        intended: vec![id(2)],
        actual: vec![id(3)],
        content: vec![id(4)],
        channel: "radio".into(),
        sent_known: true,
        sent: "2".into(),
        receipt: "exact".into(),
        received: "3".into(),
        ..Default::default()
    }
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
#[test]
fn communication_form_preserves_explicit_delivery_time_content_and_distortion() {
    let mut f = form();
    let op = f.build(&frame(), Some(&clock()), &choices()).unwrap();
    assert_eq!(op["kind"], "record_communication");
    assert_eq!(op["record"]["intendedRecipients"][0]["record"], id(2));
    assert_eq!(op["record"]["actualRecipients"][0]["record"], id(3));
    assert_eq!(op["record"]["content"][0]["record"], id(4));
    assert_eq!(op["record"]["receivedAt"]["value"], "3");
    f.distorted = true;
    assert_eq!(
        f.build(&frame(), Some(&clock()), &choices()).unwrap()["record"]["distorted"],
        true
    );
    f.received = "1".into();
    assert!(f.build(&frame(), Some(&clock()), &choices()).is_ok()); // An authored channel may permit reverse chronology.
    f.received = String::new();
    assert!(f.build(&frame(), Some(&clock()), &choices()).is_err());
    f.receipt = String::new();
    assert!(f.build(&frame(), Some(&clock()), &choices()).is_err());
    f.actual.clear();
    f.sent_known = false;
    f.channel.clear();
    let unreceived = f.build(&frame(), None, &choices()).unwrap();
    assert_eq!(unreceived["record"]["actualRecipients"], json!([]));
    assert!(unreceived["record"]["receivedAt"].is_null());
    assert!(unreceived["record"]["channel"].is_null());
    assert_eq!(unreceived["record"]["sentAt"]["kind"], "unspecified");
    f.actual = vec![id(3)];
    f.receipt = "unspecified".into();
    assert_eq!(
        f.build(&frame(), None, &choices()).unwrap()["record"]["receivedAt"]["kind"],
        "unspecified"
    );
    f.content = vec![id(1)];
    assert!(f.build(&frame(), None, &choices()).is_err());
    f.content = vec![id(4)];
    f.sender = id(4);
    assert!(f.build(&frame(), None, &choices()).is_err());
}
#[test]
fn communication_controls_mount() {
    fn fixture() -> Element {
        rsx! {CommunicationEditor{frame:frame(),clock:Some(clock()),choices:choices(),disabled:false,onadd:move |_|{}}}
    }
    let mut dom = VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
fn reference(p: &Value) -> ProposalRef {
    serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap()
}
async fn exercise(with_policy: bool) {
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
    let rr = |n| json!({"universe":u["universe_id"],"record":id(n)});
    let mut seed:Vec<Value>=(1..=3).map(|n|json!({"kind":"create_entity","client_ref":id(n),"record":{"names":[],"classificationResolution":"unclassified","worldAssociations":[],"labels":{"en":format!("Character {n}")},"metadata":{}}})).collect();
    seed.push(json!({"kind":"define_property","client_ref":id(5),"record":{"namespace":"story","key":"code","labels":{},"subjectTypes":[],"value":{"kind":"text"},"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}}));
    seed.push(json!({"kind":"define_proposition","client_ref":id(4),"record":{"subject":rr(1),"predicate":rr(5),"value":{"kind":"text","text":"cairn"},"context":{"universe":u["universe_id"],"record":u["context_id"]},"quantification":"particular"}}));
    if with_policy {
        seed.push(json!({"kind":"define_rule","client_ref":id(6),"record":{"namespace":"story","key":"radio","labels":{},"kind":"physical_constraint","commitPolicy":"always_block","applicability":{"kind":"universe_wide"},"subjectTypes":[],"targetPredicates":[],"expression":{"kind":"lit","value":true},"capabilities":["communications.chronology.v1"],"executable":true,"validity":{"kind":"unspecified"},"channelChronology":{"channel":"radio","forwardOnly":true,"minimumDelay":"0","maximumDelay":"10"}}}));
    }
    publish(&mut c, &opened, json!(seed), "seed").await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["result"]["frame"].clone()).unwrap();
    let clock: Chronology = serde_json::from_value(
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"].clone(),
    )
    .unwrap();
    let mut f = form();
    if !with_policy {
        f.actual.clear();
        f.receipt.clear();
    }
    let op = f.build(&frame, Some(&clock), &choices()).unwrap();
    let message = op["client_ref"].clone();
    c.call(EngineRequest::SaveDraft {
        universe: Selector("Alpha".into()),
        continuity_id: frame.continuity.clone(),
        expected_version: 0,
        content: DraftContent {
            proposal: None,
            base_revision: frame.revision.clone(),
            represented_context: frame.context.record.clone(),
            operations: serde_json::from_value(json!([op.clone()])).unwrap(),
            rationale: "Authored delivery, no inferred knowledge".into(),
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
            continuity_id: frame.continuity.clone(),
        })
        .await
        .unwrap();
    assert_eq!(recovered["content"]["operations"], json!([op.clone()]));
    let opened = open(&mut c, &u).await;
    publish(
        &mut c,
        &opened,
        recovered["content"]["operations"].clone(),
        "message",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let published = read(&mut c, &opened, &message).await;
    assert_eq!(
        published["payload"]["actualRecipients"],
        op["record"]["actualRecipients"]
    );
    assert_eq!(
        published["payload"]["receivedAt"],
        op["record"]["receivedAt"]
    );
    let described=tool(&mut c,"universe_describe",json!({"mode":"definitions","universe":"Alpha","context_id":opened["result"]["context_id"]})).await;
    assert!(described["result"]["definition_ids"]
        .as_array()
        .unwrap()
        .contains(&message));
    let options = crate::author::choices(&[], &[published], "[]");
    assert!(options[0]["label"].as_str().unwrap().contains("radio"));
    assert!(
        crate::select::record_choices(&options, &["communication"], "Choose a message")
            .iter()
            .any(|o| o.value == message.as_str().unwrap())
    );
    let attitudes=tool(&mut c,"universe_search",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"query":"","typed_filters":{"record_kinds":["epistemic_attitude"]},"limit":100})).await;
    assert!(attitudes["result"]["hits"].as_array().unwrap().is_empty());
    if with_policy {
        for (key, receipt) in [("reverse", "exact"), ("unreceived", "none")] {
            let mut bad = form();
            bad.received = "1".into();
            bad.receipt = receipt.into();
            if receipt == "none" {
                bad.actual.clear();
            }
            let bad = bad.build(&frame, Some(&clock), &choices()).unwrap();
            let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[bad],"submission":"submitted","rationale":"Test explicit unresolved delivery","idempotency_key":key})).await["result"].clone();
            let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference(&p),"check_scope":"universe"})).await["result"].clone();
            assert!(v["execution"]["findings"]
                .as_array()
                .unwrap()
                .iter()
                .any(|r| r["outcome"]
                    == if receipt == "none" {
                        "not_established"
                    } else {
                        "refuted"
                    }));
            assert!(c
                .call(EngineRequest::Approve {
                    universe: Selector("Alpha".into()),
                    proposal_reference: reference(&p),
                    validation_run: serde_json::from_value(v["execution"]["run_id"].clone())
                        .unwrap()
                })
                .await
                .is_err());
            assert!(c.call(crate::author::tool("universe_commit",json!({"universe":"Alpha","proposal_reference":reference(&p),"expected_base_revision":p["base_frame"]["revision"],"validation_run":v["execution"]["run_id"],"idempotency_key":format!("deny-{key}")})).unwrap()).await.is_err());
            assert_eq!(
                open(&mut c, &u).await["result"]["frame"]["revision"],
                opened["result"]["frame"]["revision"]
            );
        }
    }
    stop.cancel();
    server.await.unwrap().unwrap();
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn delivery_draft_recovery_review_publication_and_chronology_rejection() {
    exercise(true).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn unreceived_message_publishes_without_inferred_receipt_or_knowledge() {
    exercise(false).await;
}
