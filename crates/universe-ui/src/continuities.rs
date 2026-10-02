//! Pinned forks and explicit, reviewable adoption. No cross-branch live inheritance.
use super::author::send;
use dioxus::prelude::*;
use serde_json::Value;
use universe_domain::{ids::*, Frame};
use universe_protocol::{installation::EngineRequest, request::Selector};
#[component]
pub fn Continuities(
    root: String,
    profile: String,
    universe: String,
    frame: Frame,
    heads: Vec<Value>,
    disabled: bool,
    onfork: EventHandler<String>,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut name = use_signal(String::new);
    let mut source = use_signal(String::new);
    let mut differences = use_signal(Vec::<Value>::new);
    let mut selected = use_signal(Vec::<RecordId>::new);
    let mut source_revision = use_signal(|| None::<RevisionId>);
    let mut busy = use_signal(|| false);
    let mut status = use_signal(String::new);
    rsx! {details{class:"panel",summary{"Continuities · fork, compare and adopt"}
        p{"A fork starts from this exact revision. Later parent changes do not enter it automatically. Adoption adds selected historical changes to the current draft for full review."}
        label{r#for:"continuity-name","New continuity name"}input{id:"continuity-name",disabled:disabled||busy(),value:name,oninput:move|e|name.set(e.value())}
        button{disabled:disabled||busy()||name().trim().is_empty(),onclick:{let(r,p,u,f)=(root.clone(),profile.clone(),universe.clone(),frame.clone());move|_|{busy.set(true);let(r,p,u,f,label)=(r.clone(),p.clone(),u.clone(),f.clone(),name());spawn(async move{let id=ContinuityId::generate(&mut rand::rng());let result=send(r,p,EngineRequest::ForkContinuity{universe:Selector(u),name:label,continuity_id:id.clone(),source:f.continuity,revision:f.revision}).await;match result{Ok(_)=>onfork.call(id.to_string()),Err(e)=>status.set(e)}busy.set(false);});}},"Create fork from pinned revision"}
        label{r#for:"continuity-source","Source for comparison"}super::select::RichSelect{id:"continuity-source",disabled:disabled||busy(),value:source(),options:std::iter::once(super::select::Choice::new("","Choose a continuity")).chain(heads.iter().filter(|h|h["id"]!=frame.continuity.as_str()).map(|h|super::select::Choice::described(h["id"].as_str().unwrap_or_default(),h["name"].as_str().unwrap_or("Continuity"),"Compare the exact revision listed when this library was opened."))).collect(),onchange:move|e:super::select::SelectionEvent|{source.set(e.value());differences.set(vec![]);selected.set(vec![]);source_revision.set(None);}}
        button{disabled:disabled||busy()||source().is_empty(),onclick:{let(r,p,u,f,heads)=(root.clone(),profile.clone(),universe.clone(),frame.clone(),heads.clone());move|_|{let Some(head)=heads.iter().find(|h|h["id"]==source())else{return;};let Ok(revision)=serde_json::from_value::<RevisionId>(head["revision"].clone())else{return;};let Ok(src)=ContinuityId::parse(&source())else{return;};busy.set(true);let(r,p,u,f)=(r.clone(),p.clone(),u.clone(),f.clone());spawn(async move{match send(r,p,EngineRequest::CompareContinuities{universe:Selector(u),target:f.continuity,target_revision:f.revision,source:src,source_revision:revision.clone()}).await{Ok(v)=>{differences.set(v["differences"].as_array().cloned().unwrap_or_default());source_revision.set(Some(revision));selected.set(vec![]);status.set("Comparison loaded. Select records; dependent records may also be required. Generated assertions are adopted through their events.".into());},Err(e)=>status.set(e)}busy.set(false);});}},"Compare pinned revisions"}
        for row in differences(){label{class:"check-label",input{r#type:"checkbox",disabled:disabled||busy(),checked:selected().iter().any(|id|row["record_id"]==id.as_str()),onchange:{let id=row["record_id"].as_str().and_then(|s|RecordId::parse(s).ok());move|e|{if let Some(id)=&id{if e.checked(){selected.write().push(id.clone());}else{selected.write().retain(|x|x!=id);}}}}}{format!("{} · {} · {}",super::readable::caption(row["kind"].as_str().unwrap_or("record")),row["record_id"].as_str().unwrap_or_default(),if row["source_version"].is_null(){"Absent in source — proposes removal"}else if row["target_version"].is_null(){"New in source"}else{"Different in source"})}}}
        button{disabled:disabled||busy()||selected().is_empty()||selected().len()>100,onclick:move|_|{let Some(revision)=source_revision()else{return;};let Ok(src)=ContinuityId::parse(&source())else{return;};busy.set(true);let(r,p,u,f,ids)=(root.clone(),profile.clone(),universe.clone(),frame.clone(),selected());spawn(async move{match send(r,p,EngineRequest::PrepareAdoption{universe:Selector(u),target:f.continuity,target_revision:f.revision,source:src,source_revision:revision,record_ids:ids}).await{Ok(v)=>{onadd.call(v["operations"].as_array().cloned().unwrap_or_default());status.set("Selected changes added to draft. Canon is unchanged until reviewed commit.".into());},Err(e)=>status.set(e)}busy.set(false);});},"Add selected adoption to draft"}
        p{role:"status","{status}"}
    }}
}
