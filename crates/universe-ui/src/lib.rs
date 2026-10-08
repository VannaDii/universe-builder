//! App-owned native feasibility controls. All records and proposals use IPC.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_client::{Client, ClientConfig, ConnectedClient};
use universe_protocol::{examples, response::SearchHit, Request, Response};
const STYLE: &str = include_str!("fixture.css");
mod administration;
mod chronology;
mod claim_editor;
mod definitions;
mod history;
mod inspector_editor;
mod readable;
mod select;
mod state_view;
mod transfer;
async fn call(c: &ConnectedClient, name: &str, args: Value) -> Result<Response, String> {
    c.send(Request::from_tool(name, args).map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())
}

#[component]
pub fn App() -> Element {
    let mut persistent = use_signal(|| false);
    let mut universe = use_signal(|| "The Ashen Cycle".to_owned());
    let mut world = use_signal(String::new);
    let mut generation = use_signal(|| 0u64);
    let mut status = use_signal(|| "Open a universe to load its fixture records.".to_owned());
    let mut hits = use_signal(Vec::<SearchHit>::new);
    let mut client = use_signal(|| None::<ConnectedClient>);
    let mut context = use_signal(String::new);
    let mut filter = use_signal(String::new);
    let mut name = use_signal(String::new);
    let mut value_state = use_signal(|| "unspecified".to_owned());
    let mut review = use_signal(|| None::<(String, String, String)>);
    let mut busy = use_signal(|| false);
    let visible: Vec<_> = hits()
        .into_iter()
        .filter(|h| h.label.to_lowercase().contains(&filter().to_lowercase()))
        .collect();
    if persistent() {
        return rsx! { EngineApp {} };
    }
    rsx! {
     style {"{STYLE}"}
     main {
      button {class:"secondary", onclick:move |_|persistent.set(true),"Open persistent author workspace"}
      header {p {class:"eyebrow","UNIVERSE BUILDER"} h1 {"Keep worlds distinct. Keep canon deliberate."} p {"Feasibility fixture · Read and propose · Canon commits unavailable"}}
      section {class:"scope","aria-label":"Universe scope",
       div {label {r#for:"universe","Universe"}select::RichSelect {id:"universe",value:universe(),disabled:busy(),onchange:move |e: crate::select::SelectionEvent|{universe.set(e.value());world.set(String::new());generation+=1;hits.clear();context.set(String::new());status.set("Scope changed. Open universe to load records.".into());},
        options:select::choices(&[("The Ashen Cycle","The Ashen Cycle"),("The Glass Archive","The Glass Archive")])}}
       div {label {r#for:"world","World focus"}select::RichSelect {id:"world",value:world(),disabled:busy(),onchange:move |e: crate::select::SelectionEvent|{world.set(e.value());generation+=1;hits.clear();context.set(String::new());status.set("Scope changed. Open universe to load records.".into());},
        options:{let mut v=select::choices(&[("","All universe content"),("Aster","Aster")]);if universe()=="The Ashen Cycle"{v.push(select::Choice::described("Nacre","Nacre","The second world in the Ashen Cycle fixture."));}v}}}
       button {disabled:busy(),onclick:move |_|{
        let u=universe();let w=world();let g=generation();busy.set(true);status.set("Connecting to the bundled fixture…".into());
        spawn(async move {
         let outcome=async {
          let socket=std::env::var_os("UNIVERSE_FIXTURE_SOCKET").ok_or("fixture socket missing")?;
          let c=Client::with_config(ClientConfig::default().with_socket_path(std::path::PathBuf::from(socket))).connect_with_retry().await.map_err(|e|e.to_string())?;
          let mut args=examples::valid()[1].1.clone();args["universe"]=json!(u);
          let Response::OpenContext(opened)=call(&c,"universe_open_context",args).await? else{return Err("unexpected context result".into())};
          let mut args=examples::valid()[2].1.clone();args["universe"]=json!(u);args["context_id"]=json!(opened.result.context_id);args["query"]=json!("");if !w.is_empty(){args["world"]=json!(w);}
          let Response::Search(result)=call(&c,"universe_search",args).await? else{return Err("unexpected research result".into())};
          Ok::<_,String>((c,opened.result.context_id.0,result.result.hits))
         }.await;
         if generation()==g {match outcome {Ok((c,ctx,rows))=>{client.set(Some(c));context.set(ctx);hits.set(rows);status.set("Connected · main continuity · revision 1 · timeless author frame".into());},Err(e)=>status.set(e)}busy.set(false);}
        });
       },if busy(){"Loading…"}else{"Open universe"}}
      }
      p {class:"status",role:"status","aria-live":"polite","{status}"}
      div {class:"workspace",
       section {class:"panel",h2 {"Explore fixture records"}label {r#for:"filter","Filter by name"} input {id:"filter",r#type:"search",value:"{filter}",oninput:move |e|filter.set(e.value()),placeholder:"Search the loaded records"}
        table {caption {"Records in the selected universe"}thead {tr {th {scope:"col","Name"}th {scope:"col","World associations"}}}tbody {
         for hit in visible {tr {key:"{hit.record_id.0}",td {strong {"{hit.label}"}small {"{hit.record_id.0}"}}td {if hit.world_ids.is_empty(){"Unassigned"}else{for w in hit.world_ids {span {class:"badge","{w.0}"}}}}}}
        }
        }
        if hits().is_empty(){p {class:"hint","No fixture records loaded."}}
       }
       section {class:"panel",h2 {"Draft a qualified value"}p {"This control preserves an explicit value state. It creates a proposal for review; it does not establish a fact."}
        label {r#for:"name","Entity label"}input {id:"name",value:"{name}",oninput:move |e|name.set(e.value()),placeholder:"The Lantern House"}
        label {r#for:"state","Value state"}select::RichSelect {id:"state",value:value_state(),onchange:move |e: crate::select::SelectionEvent|value_state.set(e.value()),options:select::choices(&[("unspecified","Unspecified"),("explicit_absence","Explicit absence"),("known","Known text")])}
        p {class:"hint","Blank input stays blank. Missing information is never converted to false or zero."}
        button {id:"review-button",disabled:context().is_empty()||name().trim().is_empty()||busy(),onclick:move |_|review.set(Some((universe(),context(),name()))),"Review proposal"}
        hr {}h3 {"Native adapters"}
        label {r#for:"source-file","Choose a source file (selection only)"}input {id:"source-file",r#type:"file",onchange:move |e|status.set(if e.files().is_empty(){"No source selected. No import performed.".into()}else{"Source selected locally. No import or canon change performed.".into()})}
        button {class:"secondary",onclick:move |_|{
         use std::io::Write;
         let text="Universe Builder feasibility fixture — no canon commits";
         match std::process::Command::new("/usr/bin/pbcopy").stdin(std::process::Stdio::piped()).spawn(){Ok(mut child)=>{let result=child.stdin.take().ok_or("clipboard unavailable").and_then(|mut i|i.write_all(text.as_bytes()).map_err(|_|"clipboard write failed"));let exit=child.wait();status.set(if result.is_ok()&&exit.is_ok_and(|s|s.success()){ "Fixture label copied.".into()}else{"Clipboard failed.".into()});},Err(e)=>status.set(e.to_string())}
        },"Copy fixture label"}
       }
      }
      footer {"Disposable test data. Closing the fixture ends its engine and discards proposals. Production storage, approvals, and continuity validation remain unavailable."}
      if let Some((u,ctx,label))=review() {
       dialog {id:"proposal-dialog",class:"dialog",onmounted:move |_|{let _=document::eval("document.getElementById('proposal-dialog').showModal();");},onkeydown:move |e|{if e.key()==Key::Escape {e.prevent_default();if !busy() {review.set(None);let _=document::eval("requestAnimationFrame(() => document.getElementById('review-button').focus());");}}},"aria-labelledby":"review-title",
         h2 {id:"review-title","Review noncanonical proposal"}p {"Universe: {u}"}p {"Create entity: {label}"}p {"Value state: {value_state}"}p {"World applicability remains unspecified. A world focus does not establish location or truth."}
         button {autofocus:true,class:"secondary",disabled:busy(),onclick:move |_|{review.set(None);let _=document::eval("requestAnimationFrame(() => document.getElementById('review-button').focus());");},"Back to draft"}
         button {disabled:busy(),onclick:move |_|{
          let Some(c)=client() else{return};let u=u.clone();let ctx=ctx.clone();let label=label.clone();let g=generation();let state=value_state();busy.set(true);
          spawn(async move {
           let mut args=examples::valid()[7].1.clone();args["universe"]=json!(u);args["context_id"]=json!(ctx);args["operations"][0]["record"]["labels"]["en"]=json!(label);args["operations"][0]["record"]["metadata"]["draft_value_state"]=json!({"kind":"text","text":state});args["rationale"]=json!("Native feasibility proposal; no asserted fact or canon change");args["idempotency_key"]=json!(format!("desktop-{}",std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos()));
           let result=call(&c,"universe_propose",args).await;
           if generation()==g {status.set(match result {Ok(Response::Propose(p))=>match p.result {universe_protocol::response::ProposalOutcome::Proposal(p)=>format!("Draft saved · {} · noncanonical · no approval or commit",p.proposal_id.0),universe_protocol::response::ProposalOutcome::AssessmentSelection(_)=>"Unexpected assessment result".into()},Ok(_)=>"Unexpected result".into(),Err(e)=>e});busy.set(false);review.set(None);let _=document::eval("requestAnimationFrame(() => document.getElementById('review-button').focus());");}
          });
         },"Save noncanonical proposal"}
       }
      }
     }
    }
}

mod author;
pub use author::AuthorApp as EngineApp;

mod identity_editor;

mod event_editor;
mod timeline;

mod continuities;

mod pack_editor;

mod knowledge_editor;

mod exception_editor;

mod policy_editor;

mod appearance_editor;

mod initialization_editor;
mod resource_acceptance;

mod communication_editor;

mod effective_object_view;

mod action_editor;
