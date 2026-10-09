//! Author-only bridge from ordinary writing candidates to exact source review.
use crate::author::{send, tool};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_protocol::{
    installation::{AuthorWritingAction, EngineRequest},
    request::Selector,
};

fn action(universe: &str, action: AuthorWritingAction) -> EngineRequest {
    EngineRequest::AuthorWriting {
        universe: Selector(universe.into()),
        action,
    }
}
fn commit_key(candidate: &Value, run: &Value) -> Result<String, String> {
    Ok(format!(
        "native-writing-commit-{}-{}",
        candidate["digest"]
            .as_str()
            .ok_or("Missing exact candidate digest")?,
        run.as_str().ok_or("Missing exact validation run")?
    ))
}
fn publication(
    universe: &str,
    candidate: &Value,
    run: &Value,
    base: &Value,
) -> Result<EngineRequest, String> {
    tool(
        "universe_commit",
        json!({"universe":universe,"proposal_reference":candidate,"expected_base_revision":base,"validation_run":run,"idempotency_key":commit_key(candidate, run)?}),
    )
}
fn receipt(value: &Value, candidate: &Value) -> Result<String, String> {
    let actual = &value["result"];
    if actual["proposal_id"] != candidate["proposal_id"] {
        return Err("Publication receipt does not match the selected proposal.".into());
    }
    universe_domain::ids::OperationId::parse(
        actual["operation_id"]
            .as_str()
            .ok_or("Missing publication operation")?,
    )
    .map_err(|e| e.to_string())?;
    let revision = actual["revision"]
        .as_str()
        .ok_or("Publication has no successful commit receipt; recover the original operation.")?;
    universe_domain::ids::RevisionId::parse(revision).map_err(|e| e.to_string())?;
    Ok(revision.to_owned())
}
async fn refresh(root: &str, profile: &str, universe: &str) -> Result<Value, String> {
    send(
        root.into(),
        profile.into(),
        EngineRequest::Library {
            universe: Selector(universe.into()),
        },
    )
    .await
}
#[component]
pub(crate) fn WritingReview(root: String, profile: String, universe: String) -> Element {
    let mut library = use_signal(Value::default);
    let mut selected = use_signal(String::new);
    let mut label = use_signal(String::new);
    let mut text = use_signal(String::new);
    let mut review = use_signal(Value::default);
    let mut approved = use_signal(Value::default);
    let mut busy = use_signal(|| false);
    let mut status =
        use_signal(|| "Load pending writing to select a proposal by its description.".to_string());
    let mut acceptance = use_signal(String::new);
    let mut reason = use_signal(String::new);
    let mut recovery = use_signal(String::new);
    let row = library()["writing"]["proposals"]
        .as_array()
        .and_then(|rows| {
            rows.iter()
                .find(|r| r["candidate"]["proposal_id"] == selected())
                .cloned()
        })
        .unwrap_or(Value::Null);
    rsx! { section { class:"panel", "aria-label":"Writing proposal review", h2{"Writing proposals"}
        p{"Attach your exact passage, review the findings, then approve and publish separately. Canon is unchanged until publication succeeds."}
        button {disabled:busy(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u)=(r.clone(),p.clone(),u.clone());spawn(async move{match send(r,p,EngineRequest::Library{universe:Selector(u)}).await {Ok(v)=>{library.set(v);status.set("Proposal choices refreshed.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Load writing proposals"}
        label{r#for:"writing-choice","Pending proposal"}
        crate::select::RichSelect{id:"writing-choice",value:selected(),disabled:busy(),options:std::iter::once(crate::select::Choice::described("","Choose a proposal","No proposal selected")).chain(library()["writing"]["proposals"].as_array().into_iter().flatten().enumerate().map(|(i,r)|crate::select::Choice::described(r["candidate"]["proposal_id"].as_str().unwrap_or_default(),format!("{}. {}",i+1,r["label"].as_str().unwrap_or("Writing changes")),format!("{} · version {}",r["submission"],r["candidate"]["version"])))).collect(),onchange:move|e:crate::select::SelectionEvent|{selected.set(e.value());label.set(String::new());text.set(String::new());review.set(Value::Null);approved.set(Value::Null);acceptance.set(String::new());reason.set(String::new());}}
        label{r#for:"writing-source-label","Passage title"}input{id:"writing-source-label",value:label,disabled:busy(),oninput:move|e|{label.set(e.value());review.set(Value::Null);approved.set(Value::Null);}}
        label{r#for:"writing-source-text","Exact passage"}textarea{id:"writing-source-text",rows:6,value:text,disabled:busy(),oninput:move|e|{text.set(e.value());review.set(Value::Null);approved.set(Value::Null);}}
        for contracts in [false,true] {button{disabled:busy()||row.is_null()||text().trim().is_empty()||row["submission"]!="draft",onclick:{let(r,p,u,id)=(root.clone(),profile.clone(),universe.clone(),row["candidate"]["proposal_id"].clone());move|_|{busy.set(true);approved.set(Value::Null);review.set(Value::Null);let(r,p,u,id,l,t)=(r.clone(),p.clone(),u.clone(),id.clone(),label(),text());spawn(async move{let result=async{let candidate=serde_json::from_value(id).map_err(|e|e.to_string())?;send(r.clone(),p.clone(),action(&u,if contracts{AuthorWritingAction::PrepareContracts{candidate,label:l,text:t}}else{AuthorWritingAction::Prepare{candidate,label:l,text:t}})).await}.await;match result{Ok(v)=>{acceptance.set(String::new());review.set(v);status.set("Read the exact staged changes and findings. Approval is separate.".into());if let Ok(v)=refresh(&r,&p,&u).await{library.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}},if contracts{"Declare contracts and review exact passage"}else{"Attach passage and review factual changes"}}}
        button{disabled:busy()||row.is_null()||row["submission"]!="submitted",onclick:{let(r,p,u,c)=(root.clone(),profile.clone(),universe.clone(),row["candidate"].clone());move|_|{busy.set(true);approved.set(Value::Null);review.set(Value::Null);let(r,p,u,c)=(r.clone(),p.clone(),u.clone(),c.clone());spawn(async move{let result=async{send(r.clone(),p.clone(),action(&u,AuthorWritingAction::Inspect{candidate:serde_json::from_value(c).map_err(|e|e.to_string())?})).await}.await;match result{Ok(v)=>{acceptance.set(String::new());review.set(v);status.set("Existing source-bound review reopened with fresh checks; source was not restaged.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Reopen prepared review"}
        button{disabled:busy()||row.is_null(),onclick:{let(r,p,u,id)=(root.clone(),profile.clone(),universe.clone(),row["candidate"]["proposal_id"].clone());move|_|{busy.set(true);let(r,p,u,id)=(r.clone(),p.clone(),u.clone(),id.clone());spawn(async move{let result=async{send(r.clone(),p.clone(),action(&u,AuthorWritingAction::Reject{candidate:serde_json::from_value(id).map_err(|e|e.to_string())?})).await}.await;match result{Ok(_)=>{review.set(Value::Null);approved.set(Value::Null);status.set("Proposal rejected; canon is unchanged.".into());if let Ok(v)=refresh(&r,&p,&u).await{library.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}},"Reject selected proposal"}
        if !review().is_null() {
            h3{"Exact review"}
            for op in review()["review"]["proposal"]["operations"].as_array().into_iter().flatten().filter(|op|op["kind"]=="add_source_anchor") { details{open:true,summary{"Exact staged passage"}pre{{op["record"]["excerpt"].as_str().unwrap_or_default()}}} }
            for line in review()["summary"].as_array().into_iter().flatten(){p{"{line.as_str().unwrap_or_default()}"}}
            crate::readable::ValidationReview{value:review()["validation"].clone(),choices:vec![]}
            p{{format!("Impact coverage: {}; {} related records.",review()["impact"]["coverage"].as_str().unwrap_or("unknown"),review()["impact"]["records"].as_array().map_or(0,Vec::len))}}
            crate::readable::ReadValue{value:review()["review"]["footprint"].clone()}
            crate::readable::OperationReview{operations:review()["review"]["proposal"]["operations"].clone()}
            if review()["acceptance_options"].as_array().is_some_and(|v|!v.is_empty()) {
                label{r#for:"writing-acceptance","Unexplained resource finding"}
                crate::select::RichSelect{id:"writing-acceptance",value:acceptance(),disabled:busy(),options:std::iter::once(crate::select::Choice::described("","Choose a finding","No acceptance selected")).chain(review()["acceptance_options"].as_array().into_iter().flatten().enumerate().map(|(i,_)|crate::select::Choice::described(i.to_string(),format!("Unexplained resource finding {}",i+1),"Acceptance leaves arrival unexplained and does not waive other constraints"))).collect(),onchange:move|e:crate::select::SelectionEvent|acceptance.set(e.value())}
                label{r#for:"writing-accept-reason","Reason for scoped creative acceptance"}textarea{id:"writing-accept-reason",value:reason,oninput:move|e|reason.set(e.value())}
                button{disabled:busy()||acceptance().is_empty()||reason().trim().is_empty(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);approved.set(Value::Null);let(r,p,u,v,a,why)=(r.clone(),p.clone(),u.clone(),review(),acceptance(),reason());spawn(async move{let result=async{let option=v["acceptance_options"].get(a.parse::<usize>().map_err(|e|e.to_string())?).ok_or("Choose a current finding")?;send(r.clone(),p.clone(),action(&u,AuthorWritingAction::Accept{candidate:serde_json::from_value(v["candidate"].clone()).map_err(|e|e.to_string())?,fingerprint:serde_json::from_value(option["fingerprint"].clone()).map_err(|e|e.to_string())?,scope:option["scope"].as_str().ok_or("Missing scope")?.into(),rationale:why})).await}.await;match result{Ok(v)=>{review.set(v);acceptance.set(String::new());status.set("Scoped acceptance reviewed again; approval remains separate.".into());if let Ok(v)=refresh(&r,&p,&u).await{library.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}},"Accept this exact unexplained count"}
            }
            button{disabled:busy()||review()["publishable"]!=true||!approved().is_null(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u,v)=(r.clone(),p.clone(),u.clone(),review());spawn(async move{let result=async{send(r.clone(),p.clone(),EngineRequest::Approve{universe:Selector(u.clone()),proposal_reference:serde_json::from_value(v["candidate"].clone()).map_err(|e|e.to_string())?,validation_run:serde_json::from_value(v["validation"]["execution"]["run_id"].clone()).map_err(|e|e.to_string())?}).await}.await;match result{Ok(v)=>{approved.set(v);status.set("Exact changes approved. Publish separately.".into());if let Ok(v)=refresh(&r,&p,&u).await{library.set(v);}},Err(e)=>status.set(e)}busy.set(false);});}},"Approve exact reviewed changes"}
            button{disabled:busy()||approved().is_null(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u,v,a)=(r.clone(),p.clone(),u.clone(),review(),approved());spawn(async move{let result=async{let req=publication(&u,&a["approved"],&a["validation_run"],&v["review"]["proposal"]["base_frame"]["revision"])?;receipt(&send(r.clone(),p.clone(),req).await?, &a["approved"])}.await;match result{Ok(revision)=>{approved.set(Value::Null);status.set(format!("Published revision {revision}. Open current revision before continuing."));review.set(Value::Null);if let Ok(v)=refresh(&r,&p,&u).await{library.set(v);}},Err(e)=>status.set(format!("{e}. Recover using the original approval below."))}busy.set(false);});}},"Publish approved writing"}
        }
        details{summary{"Recover an approved publication"}p{"Reload choices after reopening. Recovery uses the original approval and publication key; it never grants a new approval."}
            crate::select::RichSelect{id:"writing-recovery",value:recovery(),disabled:busy(),options:std::iter::once(crate::select::Choice::described("","Choose an approval","No recovery selected")).chain(library()["writing"]["approved"].as_array().into_iter().flatten().map(|a|crate::select::Choice::described(commit_key(&a["candidate"],&a["validation_run"]).unwrap_or_default(),format!("{} · version {}",a["label"].as_str().unwrap_or("Approved writing"),a["candidate"]["version"]),"Retry original publication, preserving its exact approval"))).collect(),onchange:move|e:crate::select::SelectionEvent|recovery.set(e.value())}
            button{disabled:busy()||recovery().is_empty(),onclick:{let(r,p,u)=(root.clone(),profile.clone(),universe.clone());move|_|{busy.set(true);let(r,p,u,v,index)=(r.clone(),p.clone(),u.clone(),library(),recovery());spawn(async move{let result=async{let a=v["writing"]["approved"].as_array().and_then(|rows|rows.iter().find(|a|commit_key(&a["candidate"],&a["validation_run"]).ok().as_deref()==Some(index.as_str()))).ok_or("Choose an existing approval")?;let candidate=&a["candidate"];let exact=send(r.clone(),p.clone(),tool("universe_get_proposal",json!({"universe":u,"proposal_id":candidate["proposal_id"],"version":candidate["version"]}))?).await?;if exact["result"]["digest"]!=candidate["digest"]{return Err("Original proposal changed".into());}receipt(&send(r.clone(),p.clone(),publication(&u,candidate,&a["validation_run"],&exact["result"]["base_frame"]["revision"])?).await?, candidate)}.await;match result{Ok(revision)=>status.set(format!("Original publication recovered: revision {revision}. Open current revision before continuing.")),Err(e)=>status.set(e)}busy.set(false);});}},"Recover original publication"}
        }
        p{role:"status","{status}"}
    }}
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity_editor::workflow::{connect, open, tool as call};
    use tokio_util::sync::CancellationToken;
    #[test]
    fn writing_review_controls_mount() {
        let mut dom = VirtualDom::new_with_props(
            WritingReview,
            WritingReviewProps {
                root: String::new(),
                profile: String::new(),
                universe: "Alpha".into(),
            },
        );
        assert!(!dom.rebuild_to_vec().edits.is_empty());
    }
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn writing_panel_selects_stages_approves_and_recovers_exact_publication() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("install");
        let author = universe_service::runtime::initialize(&root).unwrap();
        let stop = CancellationToken::new();
        let (r, s) = (root.clone(), stop.clone());
        let server = tokio::spawn(async move { universe_service::runtime::serve(&r, s).await });
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
        let check=call(&mut c,"universe_check_changes",json!({"universe":"Alpha","context_id":opened["result"]["context_id"],"changes":[{"name":"Mara","introduce":true,"facts":[{"property":"age","value":30}]}]})).await;
        let lib = c
            .call(EngineRequest::Library {
                universe: Selector("Alpha".into()),
            })
            .await
            .unwrap();
        let row = lib["writing"]["proposals"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["candidate"]["proposal_id"] == check["result"]["candidate_handle"])
            .unwrap();
        assert!(row["label"].as_str().unwrap().contains("Mara"));
        let candidate = serde_json::from_value(row["candidate"]["proposal_id"].clone()).unwrap();
        let source = "Mara is thirty.\nExact UTF-8: café.";
        let prepared = c
            .call(action(
                "Alpha",
                AuthorWritingAction::Prepare {
                    candidate,
                    label: "Opening".into(),
                    text: source.into(),
                },
            ))
            .await
            .unwrap();
        assert_eq!(prepared["publishable"], true);
        assert!(prepared["review"]["proposal"]["operations"]
            .as_array()
            .unwrap()
            .iter()
            .any(|op| op["kind"] == "add_source_anchor" && op["record"]["excerpt"] == source));
        assert!(
            c.call(action(
                "Alpha",
                AuthorWritingAction::Prepare {
                    candidate: serde_json::from_value(prepared["candidate"]["proposal_id"].clone())
                        .unwrap(),
                    label: "Changed".into(),
                    text: "Different source bytes".into()
                }
            ))
            .await
            .is_err(),
            "Frozen review cannot silently adopt changed source"
        );
        let reopened = c
            .call(action(
                "Alpha",
                AuthorWritingAction::Inspect {
                    candidate: serde_json::from_value(prepared["candidate"].clone()).unwrap(),
                },
            ))
            .await
            .unwrap();
        assert_eq!(reopened["candidate"], prepared["candidate"]);
        assert!(reopened["summary"]
            .to_string()
            .contains("Exact author source"));
        let candidate = &reopened["candidate"];
        let run = &reopened["validation"]["execution"]["run_id"];
        let base = &reopened["review"]["proposal"]["base_frame"]["revision"];
        assert!(
            c.call(publication("Alpha", candidate, run, base).unwrap())
                .await
                .is_err(),
            "UI publication cannot manufacture approval"
        );
        c.call(EngineRequest::Approve {
            universe: Selector("Alpha".into()),
            proposal_reference: serde_json::from_value(candidate.clone()).unwrap(),
            validation_run: serde_json::from_value(run.clone()).unwrap(),
        })
        .await
        .unwrap();
        let lib = c
            .call(EngineRequest::Library {
                universe: Selector("Alpha".into()),
            })
            .await
            .unwrap();
        let approval = lib["writing"]["approved"]
            .as_array()
            .unwrap()
            .iter()
            .find(|a| a["candidate"] == *candidate)
            .unwrap();
        assert_eq!(approval["validation_run"], *run);
        let request = publication("Alpha", candidate, run, base).unwrap();
        let published = c.call(request.clone()).await.unwrap();
        assert!(!receipt(&published, candidate).unwrap().is_empty());
        let refreshed = c
            .call(EngineRequest::Library {
                universe: Selector("Alpha".into()),
            })
            .await
            .unwrap();
        assert!(!refreshed["writing"]["proposals"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["candidate"] == *candidate));
        assert!(receipt(
            &json!({"result":{"revision":published["result"]["revision"]}}),
            candidate
        )
        .is_err());
        let mut wrong = published.clone();
        wrong["result"]["proposal_id"] = json!("prop_000000000000000000000001");
        assert!(receipt(&wrong, candidate).is_err());
        drop(c);
        let mut c = connect(&root, &author).await;
        let replay = c.call(request).await.unwrap();
        assert_eq!(published["result"], replay["result"]);
        let agent = c.call(EngineRequest::Enroll).await.unwrap();
        let profile = serde_json::from_value(agent["profile_id"].clone()).unwrap();
        let mut a = connect(&root, &profile).await;
        assert!(a
            .call(EngineRequest::Library {
                universe: Selector("Alpha".into())
            })
            .await
            .is_err());
        assert!(receipt(&json!({"approved":true}), candidate).is_err());
        let current = open(&mut c, &u).await;
        let named = call(&mut c, "universe_search", json!({"universe":"Alpha","context_id":current["result"]["context_id"],"query":"Mara","typed_filters":{"record_kinds":["entity"]},"limit":100})).await;
        assert_eq!(named["result"]["hits"][0]["label"], "Mara");
        let facts = call(&mut c, "universe_read_facts", json!({"universe":"Alpha","context_id":current["result"]["context_id"],"object_names":["Mara"]})).await;
        let pending=call(&mut c,"universe_check_changes",json!({"universe":"Alpha","context_id":current["result"]["context_id"],"corrections":[{"fact_handle":facts["result"]["objects"][0]["facts"][0]["fact_handle"],"value":31,"reason":"Correct original age"}]})).await;
        let pending_library = c
            .call(EngineRequest::Library {
                universe: Selector("Alpha".into()),
            })
            .await
            .unwrap();
        let named_correction = pending_library["writing"]["proposals"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["candidate"]["proposal_id"] == pending["result"]["candidate_handle"])
            .unwrap();
        assert!(named_correction["label"]
            .as_str()
            .unwrap()
            .contains("Mara — age"));
        c.call(action(
            "Alpha",
            AuthorWritingAction::Reject {
                candidate: serde_json::from_value(pending["result"]["candidate_handle"].clone())
                    .unwrap(),
            },
        ))
        .await
        .unwrap();
        let lib = c
            .call(EngineRequest::Library {
                universe: Selector("Alpha".into()),
            })
            .await
            .unwrap();
        assert!(!lib["writing"]["proposals"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["candidate"]["proposal_id"] == pending["result"]["candidate_handle"]));

        stop.cancel();
        server.await.unwrap().unwrap();
    }
}
