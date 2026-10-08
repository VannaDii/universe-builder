//! Native form operations exercised through normal authenticated admission.
use super::*;
use crate::{
    definitions::DefinitionForm,
    identity_editor::workflow::{connect, open, publish, read, tool},
};
use tokio_util::sync::CancellationToken;
use universe_protocol::{
    installation::*,
    request::{ProposalRef, Selector},
};
use universe_service::runtime;
fn definition(name: &str, parent: &str, applicability: &str) -> DefinitionForm {
    let mut f = DefinitionForm::default();
    f.kind = "type".into();
    f.namespace = "native".into();
    f.key = name.into();
    f.label = name.into();
    f.parent = parent.into();
    f.applicability = applicability.into();
    f.classification = "true".into();
    f
}
fn attribute(subject: &str, predicate: &str, mode: &str, value: &str) -> Form {
    Form {
        subject: subject.into(),
        predicate: predicate.into(),
        attribute_mode: mode.into(),
        kind: "integer".into(),
        value: value.into(),
        precision: "exact".into(),
        polarity: "support".into(),
        applicability: "universe_wide".into(),
        validity: "interval".into(),
        start_kind: "exact".into(),
        end_kind: "unbounded".into(),
        when: "0".into(),
        note: "Authored reusable attribute".into(),
        ..Default::default()
    }
}
fn frame() -> Frame {
    serde_json::from_value(json!({"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"})).unwrap()
}
#[test]
fn definition_choices_and_owned_attributes_preserve_explicit_unknowns() {
    let mut f = definition("Root", "none", "unspecified");
    f.classification = "false".into();
    let op = f.operation().unwrap();
    assert_eq!(op["kind"], "introduce_definition");
    assert!(op["parent"].is_null());
    assert_eq!(op["applicability"]["kind"], "unspecified");
    assert_eq!(op["classification_executable"], false);
    for field in ["parent", "applicability", "classification"] {
        let mut f = definition("Root", "none", "universe_wide");
        match field {
            "parent" => f.parent.clear(),
            "applicability" => f.applicability.clear(),
            _ => f.classification.clear(),
        };
        assert!(f.operation().is_err());
    }
    f.parent = "rec_000000000000000000000010".into();
    f.applicability = "worlds".into();
    f.worlds = vec![];
    let child = f.operation().unwrap();
    assert_eq!(child["parent"], f.parent);
    assert_eq!(child["applicability"]["world_ids"], json!([]));
    let choices = crate::author::choices(&[], &[], &json!([op, child]).to_string());
    assert_eq!(choices[0]["kind"], "entity_type");
    assert_eq!(choices[0]["label"], "Root (draft)");
    assert_eq!(choices[1]["definition"]["parent"], f.parent);
    let mut a = attribute(
        "rec_000000000000000000000002",
        "rec_000000000000000000000003",
        "shared",
        "12345678901234567890.0010",
    );
    a.kind = "decimal".into();
    a.validity = "unknown".into();
    a.applicability = "unspecified".into();
    a.precision = "unresolved".into();
    a.polarity = "refutation".into();
    for mode in ["instance", "shared", "initial_value"] {
        a.attribute_mode = mode.into();
        let op = serde_json::to_value(a.build(&frame(), None).unwrap()).unwrap();
        assert_eq!(op["assertion"]["attributeMode"], mode);
        assert_eq!(op["proposition"]["value"]["digits"], a.value);
        assert_eq!(
            op["assertion"]["scope"]["applicability"]["kind"],
            "unspecified"
        );
        assert_eq!(op["assertion"]["validity"]["kind"], "unknown");
        assert_eq!(op["assertion"]["precision"], "unresolved");
        assert_eq!(op["assertion"]["polarity"], "refutation");
        assert_eq!(op["assertion"]["basis"]["note"], a.note);
    }
    a.kind = "relationship".into();
    assert!(a.build(&frame(), None).is_err());
}
#[test]
fn reusable_definition_and_attribute_controls_mount() {
    fn fixture() -> Element {
        rsx! {crate::definitions::DefinitionEditor{namespaces:vec![],choices:vec![],disabled:false,onadd:move |_|{}} ClaimEditor{frame:frame(),clock:None,choices:vec![],disabled:false,onadd:move |_|{}}}
    }
    let mut dom = dioxus::core::VirtualDom::new(fixture);
    assert!(!dom.rebuild_to_vec().edits.is_empty());
}
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn native_definitions_attributes_admit_inherit_conflict_and_recover() {
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
    let id = |n: u64| format!("rec_{:024x}", 71000 + n);
    let world = |n, name: &str| json!({"kind":"create_world","client_ref":id(n),"record":{"selector":name,"labels":{"en":name},"metadata":{}}});
    publish(
        &mut c,
        &opened,
        json!([world(1, "A"), world(2, "B")]),
        "definition-worlds",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let clock: universe_domain::chronology::Chronology = serde_json::from_value(
        read(&mut c, &opened, &u["context_id"]).await["payload"]["chronology"].clone(),
    )
    .unwrap();
    let mut parent_form = definition("Device", "none", "worlds");
    parent_form.worlds = vec![id(1).replacen("rec_", "wld_", 1)];
    let parent = parent_form.operation().unwrap();
    let parent_id = parent["client_ref"].as_str().unwrap();
    let child = definition("Lamp", parent_id, "universe_wide")
        .operation()
        .unwrap();
    let child_id = child["client_ref"].as_str().unwrap();
    let property = |n, key: &str| json!({"kind":"define_property","client_ref":id(n),"record":{"namespace":"native","key":key,"labels":{},"subjectTypes":[],"value":{"kind":"integer"},"multiplicity":"single","persistence":"explicit_interval","exclusive":true,"symmetric":false,"transitive":false}});
    let entity = json!({"kind":"introduce_instance","client_ref":id(10),"name":{"text":"One lamp","validity":{"kind":"unspecified"}},"classification":child_id,"world_associations":[]});
    let mut shared_form = attribute(parent_id, &id(20), "shared", "10");
    shared_form.calendar = clock.calendar.to_string();
    shared_form.applicability = "worlds".into();
    shared_form.worlds = id(1).replacen("rec_", "wld_", 1);
    let shared = serde_json::to_value(shared_form.build(&frame, Some(&clock)).unwrap()).unwrap();
    let mut initial_form = attribute(parent_id, &id(21), "initial_value", "8");
    initial_form.calendar = clock.calendar.to_string();
    initial_form.applicability = "worlds".into();
    initial_form.worlds = id(1).replacen("rec_", "wld_", 1);
    let initial = serde_json::to_value(initial_form.build(&frame, Some(&clock)).unwrap()).unwrap();
    let operations = json!([
        parent,
        child,
        property(20, "capacity"),
        property(21, "charge"),
        entity,
        shared,
        initial
    ]);
    let operations =
        serde_json::to_value(serde_json::from_value::<Vec<DomainOperation>>(operations).unwrap())
            .unwrap();
    let saved = c
        .call(EngineRequest::SaveDraft {
            universe: Selector("Alpha".into()),
            continuity_id: frame.continuity.clone(),
            expected_version: 0,
            content: DraftContent {
                proposal: None,
                base_revision: frame.revision.clone(),
                represented_context: frame.context.record.clone(),
                operations: serde_json::from_value(operations.clone()).unwrap(),
                rationale: "Reusable device definitions and owned attributes".into(),
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
    assert_eq!(recovered, saved);
    assert_eq!(recovered["content"]["operations"], operations);
    let choices = crate::author::choices(&[], &[], &recovered["content"]["operations"].to_string());
    assert!(choices
        .iter()
        .any(|r| r["kind"] == "entity_type" && r["record_id"] == child_id));
    let opened = open(&mut c, &u).await;
    publish(
        &mut c,
        &opened,
        recovered["content"]["operations"].clone(),
        "recovered-definitions",
    )
    .await;
    let opened = open(&mut c, &u).await;
    let stored_parent = read(&mut c, &opened, &parent["client_ref"]).await;
    assert!(stored_parent["payload"]["parent"].is_null());
    assert_eq!(
        stored_parent["payload"]["applicability"],
        parent["applicability"]
    );
    assert_eq!(
        read(&mut c, &opened, &child["client_ref"]).await["payload"]["parent"],
        parent["client_ref"]
    );
    let at=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock.calendar,"value":"5"}},"temporal_systems":[],"perspective":"author"})).await;
    for (world, expected) in [("A", true), ("B", false)] {
        let state=tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"world":world,"entity_ids":[id(10)],"predicate_filters":[]})).await;
        let object = &state["result"]["objects"][0];
        assert_eq!(object["ancestry"].as_array().unwrap().len(), 2);
        assert_eq!(object["instance_facts"], json!([]));
        assert_eq!(object["initialization_receipts"], json!([]));
        for lane in ["shared_attributes", "initial_value_candidates"] {
            assert_eq!(
                object[lane].as_array().unwrap().len(),
                usize::from(expected),
                "{state}"
            );
            if expected {
                assert_eq!(object[lane][0]["applicability"], true, "{state}");
            }
        }
    }
    let mut outside = attribute(parent_id, &id(20), "shared", "10");
    outside.calendar = clock.calendar.to_string();
    outside.applicability = "worlds".into();
    outside.worlds = id(2).replacen("rec_", "wld_", 1);
    let outside = serde_json::to_value(outside.build(&frame, Some(&clock)).unwrap()).unwrap();
    let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[outside],"submission":"submitted","rationale":"Cannot widen inherited definition scope","idempotency_key":"outside-definition-scope"})).await["result"].clone();
    let reference: ProposalRef = serde_json::from_value(
        json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
    )
    .unwrap();
    let error=c.call(crate::author::tool("universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).unwrap()).await.unwrap_err();
    assert!(
        error.to_string().contains("outside its definition"),
        "{error}"
    );
    // A current instance value remains independent of its initialization candidate.
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let mut own = attribute(&id(10), &id(21), "instance", "4");
    own.calendar = clock.calendar.to_string();
    own.applicability = "worlds".into();
    own.worlds = id(1).replacen("rec_", "wld_", 1);
    let own = serde_json::to_value(own.build(&frame, Some(&clock)).unwrap()).unwrap();
    publish(&mut c, &opened, json!([own]), "instance-stock").await;
    let opened = open(&mut c, &u).await;
    let frame: Frame = serde_json::from_value(opened["frame"].clone()).unwrap();
    let at=tool(&mut c,"universe_open_context",json!({"universe":"Alpha","continuity_id":u["continuity_id"],"revision":{"kind":"head"},"represented_context":u["context_id"],"temporal_query":{"kind":"at","time":{"kind":"exact","calendar":clock.calendar,"value":"5"}},"temporal_systems":[],"perspective":"author"})).await;
    let state=tool(&mut c,"universe_get_state",json!({"universe":"Alpha","context_id":at["result"]["context_id"],"world":"A","entity_ids":[id(10)],"predicate_filters":[]})).await;
    let object = &state["result"]["objects"][0];
    assert_eq!(object["instance_facts"].as_array().unwrap().len(), 1);
    assert_eq!(
        object["instance_facts"][0]["record"]["payload"]["proposition"]["record"],
        own["client_ref"]
    );
    assert_eq!(
        object["initial_value_candidates"].as_array().unwrap().len(),
        1
    );
    assert_eq!(object["initialization_receipts"], json!([]));
    for (subject, predicate, mode, value) in [
        (child_id, id(20), "shared", "20"),
        (parent_id, id(21), "initial_value", "9"),
        (id(10).as_str(), id(21), "instance", "6"),
    ] {
        // Inherited shared values and exact owned values cannot be silently overridden.
        // Inherited shared values cannot silently be overridden by a descendant.
        let mut conflict = attribute(subject, &predicate, mode, value);
        conflict.calendar = clock.calendar.to_string();
        conflict.applicability = "worlds".into();
        conflict.worlds = id(1).replacen("rec_", "wld_", 1);
        let conflict = serde_json::to_value(conflict.build(&frame, Some(&clock)).unwrap()).unwrap();
        let p=tool(&mut c,"universe_propose",json!({"action":"create","universe":"Alpha","context_id":opened["result"]["context_id"],"operations":[conflict],"submission":"submitted","rationale":"Conflicting inherited value","idempotency_key":format!("definition-conflict-{mode}")})).await["result"].clone();
        let reference: ProposalRef = serde_json::from_value(
            json!({"proposal_id":p["proposal_id"],"version":p["version"],"digest":p["digest"]}),
        )
        .unwrap();
        let v=tool(&mut c,"universe_validate",json!({"mode":"proposal","universe":"Alpha","context_id":opened["result"]["context_id"],"proposal_reference":reference,"check_scope":"universe"})).await["result"].clone();
        assert!(
            v["execution"]["findings"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f["outcome"] == "conflicting"),
            "{v}"
        );
        assert!(c
            .call(EngineRequest::Approve {
                universe: Selector("Alpha".into()),
                proposal_reference: reference,
                validation_run: serde_json::from_value(v["execution"]["run_id"].clone()).unwrap()
            })
            .await
            .is_err());
    }
    drop(c);
    stop.cancel();
    server.await.unwrap().unwrap();
}
