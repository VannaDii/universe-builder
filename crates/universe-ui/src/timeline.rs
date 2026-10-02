//! Scrollable, revision-pinned chronology. State comparisons use public MCP tools.
use super::author::{send, tool};
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, Frame};
#[component]
pub fn Timeline(
    root: String,
    profile: String,
    universe: String,
    context: Value,
    frame: Frame,
    choices: Vec<Value>,
    clock: Option<Chronology>,
) -> Element {
    let mut events = use_signal(Vec::<Value>::new);
    let mut world = use_signal(String::new);
    let mut region = use_signal(String::new);
    let mut entity = use_signal(String::new);
    let mut status = use_signal(String::new);
    let mut busy = use_signal(|| false);
    let mut comparison = use_signal(Value::default);
    let visible: Vec<_> = events()
        .into_iter()
        .filter(|r| {
            (world().is_empty()
                || r["payload"]["worlds"]
                    .as_array()
                    .is_some_and(|w| w.iter().any(|x| x == &world())))
                && (region().is_empty() || r["payload"]["region"]["record"] == region())
        })
        .collect();
    rsx! {details{class:"panel",summary{"Timeline · fictional change events"}
        p{"Events are grouped by their own calendars and exact times. World and region filters use declared event locations. Select an entity to compare its evidence and item powers immediately before and after an occurred event."}
        button{disabled:busy(),onclick:{let(root,profile,u,ctx,f)=(root.clone(),profile.clone(),universe.clone(),context.clone(),frame.clone());move|_|{busy.set(true);let(root,profile,u,ctx,f)=(root.clone(),profile.clone(),u.clone(),ctx.clone(),f.clone());spawn(async move{
            let result=async{let mut cursor=Value::Null;let mut loaded=Vec::new();loop{
                let mut args=json!({"universe":u,"universe_id":f.universe,"context_id":ctx,"query":"","typed_filters":{"record_kinds":["event"]},"limit":100});if !cursor.is_null(){args["cursor"]=cursor;}
                let found=send(root.clone(),profile.clone(),tool("universe_search",args)?).await?;
                let ids:Vec<_>=found["result"]["hits"].as_array().into_iter().flatten().map(|h|h["record_id"].clone()).collect();
                if !ids.is_empty(){let read=send(root.clone(),profile.clone(),tool("universe_get",json!({"universe":u,"universe_id":f.universe,"context_id":ctx,"record_ids":ids,"field_groups":[]}))?).await?;loaded.extend(read["result"]["records"].as_array().cloned().unwrap_or_default());}
                cursor=found["delivery"]["cursor"].clone();if cursor.is_null(){break;}
                if loaded.len()>=1000{return Err("Timeline exceeds the 1,000-event interactive limit; narrow the canon before loading this view.".to_string());}
            }
            loaded.sort_by_key(|r|{let t=&r["payload"]["time"];(t["calendar"].as_str().unwrap_or_default().to_string(),t["value"].as_str().and_then(|v|v.parse::<i128>().ok()),r["identity"]["record_id"].to_string())});Ok::<_,String>(loaded)}.await;
            match result{Ok(v)=>{status.set(format!("{} events loaded at the pinned revision. Independent calendars are not synchronized.",v.len()));events.set(v);},Err(e)=>status.set(e)}busy.set(false);
        });}},"Load pinned timeline"}
        label{r#for:"timeline-world","World filter"}super::select::RichSelect{id:"timeline-world",disabled:busy(),value:world(),options:super::select::typed_id_choices(&choices,"world","wld_","All worlds"),onchange:move|e:super::select::SelectionEvent|{world.set(e.value());comparison.set(Value::Null);}}
        label{r#for:"timeline-region","Region filter"}super::select::RichSelect{id:"timeline-region",disabled:busy(),value:region(),options:super::select::record_choices(&choices,&["entity","realm"],"All regions"),onchange:move|e:super::select::SelectionEvent|{region.set(e.value());comparison.set(Value::Null);}}
        label{r#for:"timeline-entity","Inspect state of"}super::select::RichSelect{id:"timeline-entity",disabled:busy(),value:entity(),options:super::select::record_choices(&choices,&["entity"],"Choose an entity"),onchange:move|e:super::select::SelectionEvent|{entity.set(e.value());comparison.set(Value::Null);}}
        p{role:"status","{status}"}
        div{style:"max-height:32rem;overflow-y:auto",tabindex:"0","aria-label":"Scrollable fictional events",
            for event in visible{article{class:"panel",key:"{event}",
                h3{{event["payload"]["labels"]["en"].as_str().unwrap_or("Event").to_string()}}
                p{{let t=&event["payload"]["time"];let coordinate=t["value"].as_str().unwrap_or("Unresolved time");let date=clock.as_ref().filter(|c|t["calendar"]==c.calendar.as_str()).and_then(|c|c.display(coordinate).ok()).unwrap_or_else(||format!("{coordinate} · {}",t["calendar"]));format!("{date} · {}",event["payload"]["occurrence"].as_str().unwrap_or("descriptive"))}}
                button{disabled:busy()||entity().is_empty()||event["payload"]["occurrence"]!="occurred",onclick:{let(root,profile,u,ctx,f,id)=(root.clone(),profile.clone(),universe.clone(),context.clone(),frame.clone(),event["identity"]["record_id"].clone());move|_|{busy.set(true);comparison.set(Value::Null);let(root,profile,u,ctx,f,id,who)=(root.clone(),profile.clone(),u.clone(),ctx.clone(),f.clone(),id.clone(),entity());spawn(async move{
                    let result=async{let mut pair=json!({});for side in ["before","after"]{let state=send(root.clone(),profile.clone(),tool("universe_get_state",json!({"universe":u,"universe_id":f.universe,"context_id":ctx,"entity_ids":[who],"predicate_filters":[],"event":id,"event_side":side}))?).await?;pair[side]=state["result"].clone();}Ok::<_,String>(pair)}.await;match result{Ok(v)=>comparison.set(v),Err(e)=>status.set(e)}busy.set(false);
                });}},"Compare before and after"}
            }}
        }
        if !comparison().is_null(){h3{"Before and after · same pinned revision"}super::readable::ReadValue{value:comparison()}}
    }}
}
