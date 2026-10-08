//! Read-only state queries use the same pinned service frame as MCP clients.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, Frame};

#[component]
pub fn StateView(
    root: String,
    profile: String,
    universe: String,
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    world: String,
) -> Element {
    let mut perspective = use_signal(|| "author".to_string());
    let mut represented = use_signal(|| frame.context.record.to_string());
    let mut holder = use_signal(String::new);
    let mut scene = use_signal(String::new);
    let mut entity = use_signal(String::new);
    let mut calendar = use_signal(|| {
        clock
            .as_ref()
            .map(|c| c.calendar.to_string())
            .unwrap_or_default()
    });
    let mut query = use_signal(String::new);
    let mut mode = use_signal(|| {
        if clock.is_some() {
            "current".to_string()
        } else {
            "all".to_string()
        }
    });
    let mut result = use_signal(Value::default);
    let mut error = use_signal(String::new);
    let mut busy = use_signal(|| false);
    rsx! {details{class:"panel",summary{"Inspect state at an authored time"}
        p{"Query this pinned revision. Unknown timing stays visible; an empty result never establishes absence. This view does not advance story time."}
        label{r#for:"state-perspective","Perspective"}super::select::RichSelect{id:"state-perspective",disabled:busy(),value:perspective(),options:super::select::choices(&[("author","Author"),("character","Character"),("narrator","Narrator"),("reader","Reader")]),onchange:move|e:super::select::SelectionEvent|{perspective.set(e.value());result.set(Value::Null);}}
        label{r#for:"state-context","Represented context"}super::select::RichSelect{id:"state-context",disabled:busy(),value:represented(),options:super::select::record_choices(&choices,&["represented_context"],"Choose an authored context"),onchange:move|e:super::select::SelectionEvent|{represented.set(e.value());result.set(Value::Null);}}
        if perspective()=="character"||perspective()=="narrator" {
            label{r#for:"state-holder","Character or narrator owning this context"}super::select::RichSelect{id:"state-holder",disabled:busy(),value:holder(),options:super::select::record_choices(&choices,&["entity"],"Choose the perspective holder"),onchange:move|e:super::select::SelectionEvent|{holder.set(e.value());result.set(Value::Null);}}
        }
        if perspective()=="reader" {
            label{r#for:"state-scene","Reader disclosure scene"}super::select::RichSelect{id:"state-scene",disabled:busy(),value:scene(),options:super::select::record_choices(&choices,&["scene_ref"],"Find scenes in the explorer, then select one"),onchange:move|e:super::select::SelectionEvent|{scene.set(e.value());result.set(Value::Null);}}
            p{"Uses only explicit disclosures through this scene in its bound edition. Depicted events alone do not establish reader or character knowledge."}
        }
        label{r#for:"state-entity","Entity"}super::select::RichSelect{id:"state-entity",disabled:busy(),value:entity(),options:super::select::record_choices(&choices,&["entity"],"Choose an entity"),onchange:move|e:super::select::SelectionEvent|{entity.set(e.value());result.set(Value::Null);error.set(String::new());}}
        label{r#for:"state-time-mode","Time frame"}super::select::RichSelect{id:"state-time-mode",disabled:busy(),value:mode(),options:{let mut v=vec![super::select::Choice::described("all","All authored validities","Read evidence without making a claim about when it is true."),super::select::Choice::described("at","An explicit time","Evaluate an exact coordinate in the selected calendar.")];if clock.is_some(){v.push(super::select::Choice::described("current","Current authored story time","Use the current date stored in this revision, never the computer clock."));}v},onchange:move|e:super::select::SelectionEvent|{mode.set(e.value());result.set(Value::Null);error.set(String::new());}}
        if mode()=="at"{
            label{r#for:"state-calendar","Calendar"}super::select::RichSelect{id:"state-calendar",disabled:busy(),value:calendar(),options:super::select::typed_id_choices(&choices,"calendar","cal_","Choose a calendar"),onchange:move|e:super::select::SelectionEvent|{calendar.set(e.value());result.set(Value::Null);error.set(String::new());}}
            label{r#for:"state-time","Fictional timestamp (Gregorian RFC3339, or exact fictional tick)"}input{id:"state-time",disabled:busy(),value:query,oninput:move|e|{query.set(e.value());result.set(Value::Null);error.set(String::new());}}
        }
        button{disabled:busy()||entity().is_empty()||represented().is_empty()||((perspective()=="character"||perspective()=="narrator")&&holder().is_empty())||(perspective()=="reader"&&scene().is_empty()),onclick:move|_|{
            let time=match mode().as_str(){
                "all"=>Ok(json!({"kind":"timeless"})),
                "current"=>clock.as_ref().map(|c|json!({"kind":"at","time":{"kind":"exact","calendar":c.calendar,"value":c.current}})).ok_or("No authored clock".to_string()),
                _=>{let value=if let Some(c)=clock.as_ref().filter(|c|c.calendar.as_str()==calendar()){c.coordinate(&query())}else{query().parse::<i128>().map(|v|v.to_string()).map_err(|_|"Enter an exact coordinate for this clock.".into())};value.map(|v|json!({"kind":"at","time":{"kind":"exact","calendar":calendar(),"value":v}}))},
            };
            let time=match time{Ok(t)=>t,Err(e)=>{error.set(e);return;}};
            busy.set(true);result.set(Value::Null);error.set(String::new());
            let(root,profile,u,f,w,id)=(root.clone(),profile.clone(),universe.clone(),frame.clone(),world.clone(),entity());
            let (view,represented,holder,scene)=(perspective(),represented(),holder(),scene());
            spawn(async move{
                let outcome=async{
                    let perspective=match view.as_str(){"character"=>json!({"character":holder}),"narrator"=>json!({"narrator":holder}),"reader"=>json!("reader"),_=>json!("author")};
                    let mut opening=json!({"universe":u,"universe_id":f.universe,"continuity_id":f.continuity,"revision":{"kind":"exact","revision_id":f.revision},"represented_context":represented,"temporal_query":time,"temporal_systems":[],"perspective":perspective});
                    if view=="reader" {opening["reader_scene"]=json!(scene);}
                    let opened=super::author::send(root.clone(),profile.clone(),super::author::tool("universe_open_context",opening)?).await?;
                    let mut args=json!({"universe":u,"universe_id":f.universe,"context_id":opened["result"]["context_id"],"entity_ids":[id],"predicate_filters":[]});if !w.is_empty(){args["world"]=json!(w);}
                    super::author::send(root,profile,super::author::tool("universe_get_state",args)?).await
                }.await;
                match outcome{Ok(v)=>result.set(v),Err(e)=>error.set(e)}busy.set(false);
            });
        },"Evaluate state"}
        if !error().is_empty(){p{role:"alert","{error}"}}
        if !result().is_null(){super::effective_object_view::EffectiveState{response:result()}}
    }}
}
