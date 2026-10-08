//! Explicit reviewed initialization; source versions remain pinned in saved drafts.
use dioxus::prelude::*;
use serde_json::{json, Value};
use universe_domain::{chronology::Chronology, ids::*, records::DomainOperation, Frame};
#[derive(Clone, Default)]
struct Form {
    instance: String,
    start: String,
    source: String,
    applicability: String,
    worlds: Vec<String>,
    duration: String,
    end: String,
}
impl Form {
    fn operation(
        &self,
        frame: &Frame,
        clock: Option<&Chronology>,
        event: &Value,
        source: &Value,
    ) -> Result<Value, String> {
        let instance = RecordId::parse(&self.instance).map_err(|_| "Choose an instance.")?;
        let start = RecordId::parse(&self.start).map_err(|_| "Choose an occurred start.")?;
        let definition =
            RecordId::parse(&self.source).map_err(|_| "Choose an initial-value assertion.")?;
        let rr = |id: &RecordId| json!({"universe":frame.universe,"record":id});
        if event["identity"]["record_id"] != self.start
            || event["payload"]["record_kind"] != "event"
            || event["payload"]["occurrence"] != "occurred"
            || event["payload"]["time"]["kind"] != "exact"
            || !event["payload"]["participants"]
                .as_array()
                .is_some_and(|ps| ps.iter().any(|p| p["record"] == rr(&instance)))
        {
            return Err("Select an exact occurred event containing this instance.".into());
        }
        if source["identity"]["record_id"] != self.source
            || source["payload"]["record_kind"] != "assertion"
            || source["payload"]["attributeMode"] != "initial_value"
        {
            return Err("Select an approved initial-value assertion version.".into());
        }
        let version =
            RecordVersionId::parse(source["record_version_id"].as_str().unwrap_or_default())
                .map_err(|_| "Source version is missing.")?;
        let calendar = CalendarId::parse(
            event["payload"]["time"]["calendar"]
                .as_str()
                .unwrap_or_default(),
        )
        .map_err(|_| "Start calendar is missing.")?;
        let coordinate = event["payload"]["time"]["value"]
            .as_str()
            .ok_or("Start coordinate is missing.")?;
        let end = match self.duration.as_str() {
            "unbounded" => json!({"kind":"unbounded"}),
            "exact" => {
                let value = if let Some(c) = clock.filter(|c| c.calendar == calendar) {
                    c.coordinate(&self.end)?
                } else {
                    self.end
                        .parse::<i128>()
                        .map_err(|_| "Enter an exact end coordinate.")?
                        .to_string()
                };
                if value.parse::<i128>().map_err(|_| "Invalid end.")?
                    <= coordinate.parse::<i128>().map_err(|_| "Invalid start.")?
                {
                    return Err("Exclusive end must follow the start.".into());
                }
                json!({"kind":"exact","value":value})
            }
            _ => return Err("Choose an exclusive end or explicitly unbounded validity.".into()),
        };
        let applicability = match self.applicability.as_str() {
            "universe_wide" => json!({"kind":"universe_wide"}),
            "worlds" if !self.worlds.is_empty() => {
                json!({"kind":"worlds","world_ids":self.worlds.iter().map(|id| WorldId::parse(id).map_err(|e| e.to_string())).collect::<Result<Vec<_>,_>>()?})
            }
            _ => return Err("Choose an explicit applicable scope.".into()),
        };
        let op: DomainOperation = serde_json::from_value(json!({"kind":"initialize_instance","client_ref":RecordId::generate(&mut rand::rng()),"instance":rr(&instance),"start":rr(&start),"definition":{"universe":frame.universe,"record":definition,"version":version},"scope":{"context":frame.context,"applicability":applicability},"validity":{"kind":"calendar_interval","calendar":calendar,"start":{"kind":"exact","value":coordinate},"end":end}})).map_err(|e|e.to_string())?;
        serde_json::to_value(op).map_err(|e| e.to_string())
    }
}
fn starting_fact(operation: &Value, proposition: &Value) -> Value {
    json!({"subject":operation["instance"],"predicate":proposition["payload"]["predicate"],"value":proposition["payload"]["value"],"scope":operation["scope"],"validity":operation["validity"],"source_assertion_version":operation["definition"]})
}
#[component]
pub fn InitializationEditor(
    root: String,
    profile: String,
    universe: String,
    context: ContextId,
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Value>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut preview = use_signal(Value::default);
    let mut error = use_signal(String::new);
    let mut loading = use_signal(|| false);
    let locked = disabled || loading();
    rsx! {details{summary{"Initialize an instance through review"}
        p{"Choose an approved initial-value assertion and an exact occurred start. Initialization creates separate instance facts once; it never refills stock. Load more explorer records to find starts and assertions."}
        label{r#for:"initialize-instance","Instance"}super::select::RichSelect{id:"initialize-instance",disabled:locked,value:form.read().instance.clone(),options:super::select::record_choices(&choices,&["entity"],"Choose an instance"),onchange:move|e:super::select::SelectionEvent|{form.write().instance=e.value();preview.set(Value::Null);}}
        label{r#for:"initialize-start","Exact occurred start event"}super::select::RichSelect{id:"initialize-start",disabled:locked,value:form.read().start.clone(),options:super::select::record_choices(&choices,&["event"],"Choose a start event"),onchange:move|e:super::select::SelectionEvent|{form.write().start=e.value();preview.set(Value::Null);}}
        label{r#for:"initialize-source","Source initial-value assertion (current approved version)"}super::select::RichSelect{id:"initialize-source",disabled:locked,value:form.read().source.clone(),options:super::select::record_choices(&choices,&["assertion"],"Choose an assertion to inspect"),onchange:move|e:super::select::SelectionEvent|{form.write().source=e.value();preview.set(Value::Null);}}
        label{r#for:"initialize-scope","Applicable scope"}super::select::RichSelect{id:"initialize-scope",disabled:locked,value:form.read().applicability.clone(),options:super::select::choices(&[("","Choose scope"),("universe_wide","Universe wide"),("worlds","Selected worlds")]),onchange:move|e:super::select::SelectionEvent|{form.write().applicability=e.value();preview.set(Value::Null);}}
        if form.read().applicability=="worlds"{fieldset{legend{"Worlds"}for world in choices.iter().filter(|r|r["kind"]=="world").cloned(){label{input{r#type:"checkbox",disabled:locked,checked:form.read().worlds.contains(&world["record_id"].as_str().unwrap_or_default().replacen("rec_","wld_",1)),onchange:{let id=world["record_id"].as_str().unwrap_or_default().replacen("rec_","wld_",1);move|e|{if e.checked(){form.write().worlds.push(id.clone());}else{form.write().worlds.retain(|w|w!=&id);}preview.set(Value::Null);}}}{world["label"].as_str().unwrap_or("World").to_string()}}}}}
        p{"Validity begins at the selected event’s exact time in its calendar and uses this workspace’s represented context."}
        label{r#for:"initialize-duration","Starting fact validity"}super::select::RichSelect{id:"initialize-duration",disabled:locked,value:form.read().duration.clone(),options:super::select::choices(&[("","Choose explicitly"),("unbounded","Unbounded end"),("exact","Exact exclusive end")]),onchange:move|e:super::select::SelectionEvent|{form.write().duration=e.value();preview.set(Value::Null);}}
        if form.read().duration=="exact"{label{r#for:"initialize-end","Exclusive end (story timestamp or fictional tick)"}input{id:"initialize-end",disabled:locked,value:form.read().end.clone(),oninput:move|e|{form.write().end=e.value();preview.set(Value::Null);}}}
        button{disabled:locked,onclick:move|_|{
            let f=form.read().clone();let(r,p,u,ctx,frame,clock)=(root.clone(),profile.clone(),universe.clone(),context.clone(),frame.clone(),clock.clone());loading.set(true);preview.set(Value::Null);error.set(String::new());
            spawn(async move{
                let outcome=async{
                    let get=|ids:Vec<String>|super::author::tool("universe_get",json!({"universe":u,"context_id":ctx,"record_ids":ids,"field_groups":[]}));
                    let records=super::author::send(r.clone(),p.clone(),get(vec![f.start.clone(),f.source.clone()])?).await?;
                    let rows=records["result"]["records"].as_array().ok_or("Missing records")?;
                    let find=|id:&str|rows.iter().find(|row|row["identity"]["record_id"]==id).ok_or("Selected record is unavailable");
                    let(event,source)=(find(&f.start)?,find(&f.source)?);
                    let operation=f.operation(&frame,clock.as_ref(),event,source)?;
                    let prop=source["payload"]["proposition"]["record"].as_str().ok_or("Missing source proposition")?;
                    let proposition=super::author::send(r.clone(),p.clone(),get(vec![prop.into()])?).await?;
                    let opened=super::author::send(r.clone(),p.clone(),super::author::tool("universe_open_context",json!({"universe":u,"continuity_id":frame.continuity,"revision":{"kind":"exact","revision_id":frame.revision},"represented_context":frame.context.record,"temporal_query":{"kind":"at","time":event["payload"]["time"]},"temporal_systems":[],"perspective":"author"}))?).await?;
                    let jurisdictions=if f.applicability=="worlds" {
                        let worlds=super::author::send(r.clone(),p.clone(),get(f.worlds.iter().map(|w|w.replacen("wld_","rec_",1)).collect())?).await?;
                        worlds["result"]["records"].as_array().ok_or("Missing selected worlds")?.iter().map(|w|Ok((w["payload"]["selector"].as_str().ok_or("Missing world selector")?.to_string(),w["identity"]["record_id"].as_str().ok_or("Missing world identity")?.replacen("rec_","wld_",1)))).collect::<Result<Vec<_>,String>>()?
                    }else{vec![("Universe wide".to_string(),String::new())]};
                    let mut objects=Vec::new();
                    for (name,id) in jurisdictions {
                        let mut args=json!({"universe":u,"context_id":opened["result"]["context_id"],"entity_ids":[f.instance],"predicate_filters":[]});
                        if !id.is_empty(){args["world"]=json!(name);args["world_id"]=json!(id);}
                        let state=super::author::send(r.clone(),p.clone(),super::author::tool("universe_get_state",args)?).await?;
                        objects.push(json!({"scope":name,"object":state["result"]["objects"][0]}));
                    }
                    Ok::<_,String>(json!({"operation":operation,"starting_fact":starting_fact(&operation,&proposition["result"]["records"][0]),"objects":objects,"start":event}))
                }.await;
                match outcome{Ok(v)=>preview.set(v),Err(e)=>error.set(e)}loading.set(false);
            });
        },"Preview starting facts"}
        if !preview().is_null(){
            h4{"Proposed starting instance fact"}super::readable::ReadValue{value:preview()["starting_fact"].clone()}
            for row in preview()["objects"].as_array().cloned().unwrap_or_default(){
                h4{{row["scope"].as_str().unwrap_or("Scope").to_string()}}
                h4{"Shared definition attributes"}super::readable::ReadValue{value:row["object"]["shared_attributes"].clone()}
                h4{"Existing instance facts"}super::readable::ReadValue{value:row["object"]["instance_facts"].clone()}
                h4{"Initial-value candidates and unresolved conflicts"}super::readable::ReadValue{value:json!({"candidates":row["object"]["initial_value_candidates"],"conflicts":row["object"]["conflicts"],"unknowns":row["object"]["unknowns"],"receipts":row["object"]["initialization_receipts"]})}
            }
            p{"This preview does not admit the change. Normal proposal validation, exact review and author approval still apply."}
            button{disabled:locked,onclick:move|_|{onadd.call(preview()["operation"].clone());preview.set(Value::Null);},"Add initialization to draft"}
        }
        if !error().is_empty(){p{role:"alert","{error}"}}
    }}
}

#[cfg(test)]
#[path = "initialization_workflow.rs"]
mod workflow;
