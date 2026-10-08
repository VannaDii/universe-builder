//! Explicit event proposals from an existing action contract; no balance inference.
use crate::action_editor::{FixedValue, ValueControls};
use dioxus::prelude::*;
use serde_json::{json, Value};
use std::collections::BTreeSet;
use universe_domain::{
    chronology::Chronology,
    consequences::ConsequenceContract,
    ids::{RecordId, WorldId},
    records::DomainOperation,
    Frame,
};
fn action<'a>(choices: &'a [Value], id: &str) -> Result<&'a Value, String> {
    choices
        .iter()
        .find(|c| c["kind"] == "action_definition" && c["record_id"] == id)
        .map(|c| &c["definition"])
        .ok_or_else(|| "Choose a returned action definition.".into())
}
fn rr(frame: &Frame, id: &str) -> Result<Value, String> {
    Ok(json!({"universe":frame.universe,"record":RecordId::parse(id).map_err(|e|e.to_string())?}))
}
#[derive(Clone, Default, PartialEq)]
struct EffectForm {
    slot: String,
    include: String,
    source: String,
    proposition: String,
    value: FixedValue,
    balance: String,
    polarity: String,
    end_kind: String,
    end: String,
    order: String,
}
#[derive(Clone, Default)]
struct Form {
    title: String,
    action: String,
    occurrence: String,
    start: String,
    context: String,
    applicability: String,
    worlds: Vec<String>,
    region: String,
    roles: Vec<(String, String)>,
    effects: Vec<EffectForm>,
}
impl Form {
    fn select(&mut self, id: String, choices: &[Value]) -> Result<(), String> {
        let a = action(choices, &id)?;
        let _: ConsequenceContract = serde_json::from_value(a["consequenceContract"].clone())
            .map_err(|_| "This action has no supported consequence contract.")?;
        let slots = a["consequenceContract"]["slots"]
            .as_array()
            .ok_or("Action slots unavailable.")?;
        let mut names = BTreeSet::new();
        for r in a["requirements"].as_array().into_iter().flatten() {
            if let Some(role) = r["role"].as_str() {
                names.insert(role.to_string());
            }
        }
        for s in slots {
            names.insert(
                s["target"]["role"]
                    .as_str()
                    .ok_or("Slot role unavailable.")?
                    .into(),
            );
            if s["condition"]["kind"] == "attribute_equals" {
                names.insert(
                    s["condition"]["role"]
                        .as_str()
                        .ok_or("Condition role unavailable.")?
                        .into(),
                );
            }
        }
        self.roles = names.into_iter().map(|r| (r, String::new())).collect();
        self.effects = slots
            .iter()
            .map(|s| EffectForm {
                slot: s["slot"].as_str().unwrap_or_default().into(),
                ..Default::default()
            })
            .collect();
        self.action = id;
        self.context.clear();
        self.applicability.clear();
        self.worlds.clear();
        Ok(())
    }
    fn build(
        &self,
        frame: &Frame,
        clock: Option<&Chronology>,
        choices: &[Value],
    ) -> Result<Vec<Value>, String> {
        if self.title.trim().is_empty() {
            return Err("Name the event.".into());
        }
        let a = action(choices, &self.action)?;
        let _: ConsequenceContract =
            serde_json::from_value(a["consequenceContract"].clone()).map_err(|e| e.to_string())?;
        let clock = clock.ok_or("An authored clock is required.")?;
        if self.start.trim().is_empty() {
            return Err("Enter an authored event timestamp.".into());
        }
        let start = clock.coordinate(&self.start)?;
        let context = rr(frame, &self.context)?;
        if context != a["scope"]["context"] {
            return Err("Choose the action's declared represented context.".into());
        }
        let worlds = match self.applicability.as_str() {
            "universe_wide" => {
                if !self.worlds.is_empty() {
                    return Err("Clear selected worlds before choosing universe wide.".into());
                }
                vec![]
            }
            "worlds" => {
                if self.worlds.is_empty() {
                    return Err("Select at least one event world.".into());
                }
                self.worlds
                    .iter()
                    .map(|id| WorldId::parse(id).map_err(|e| e.to_string()))
                    .collect::<Result<Vec<_>, _>>()?
            }
            _ => return Err("Choose event scope explicitly.".into()),
        };
        let scope = json!({"context":context,"applicability":if worlds.is_empty(){json!({"kind":"universe_wide"})}else{json!({"kind":"worlds","world_ids":worlds})}});
        let mut participants = Vec::new();
        let mut names = BTreeSet::new();
        for (role, id) in &self.roles {
            if role.trim().is_empty() || !names.insert(role) {
                return Err("Participant roles must be nonempty and unique.".into());
            }
            if !choices
                .iter()
                .any(|c| c["kind"] == "entity" && c["record_id"] == *id)
            {
                return Err(format!("Choose an entity for role {role}."));
            }
            participants.push(json!({"record":rr(frame,id)?,"role":role}));
        }
        let slots = a["consequenceContract"]["slots"]
            .as_array()
            .ok_or("Slots unavailable.")?;
        if slots.len() != self.effects.len() {
            return Err("The action contract changed. Select the action again.".into());
        }
        let mut ops = Vec::new();
        let mut effects = Vec::new();
        for (slot, input) in slots.iter().zip(&self.effects) {
            if slot["slot"] != input.slot {
                return Err("The action contract changed. Select it again.".into());
            }
            match input.include.as_str() {
                "no" => continue,
                "yes" => {}
                _ => return Err(format!("Choose whether to propose effect {}.", input.slot)),
            };
            let role = slot["target"]["role"]
                .as_str()
                .ok_or("Slot role unavailable.")?;
            let owner = self
                .roles
                .iter()
                .find(|(r, _)| r == role)
                .ok_or("Assign the slot's owning role.")?;
            let predicate = slot["target"]["predicate"]["record"]
                .as_str()
                .ok_or("Slot target unavailable.")?;
            let prop=match input.source.as_str(){
                "existing"=>{let p=choices.iter().find(|c|c["kind"]=="proposition"&&c["record_id"]==input.proposition).ok_or("Choose a returned effect proposition.")?;
                    if p["definition"]["subject"]!=rr(frame,&owner.1)?||p["definition"]["predicate"]!=slot["target"]["predicate"]||p["definition"]["context"]!=context||p["definition"]["value"].is_null(){return Err("Effect proposition must have this owner, property, context and an explicit value.".into());}rr(frame,&input.proposition)?},
                "new"=>{
                    let value=if slot["change"]["kind"]=="delta"{
                        let typed:universe_domain::consequences::ConsequenceInteger=serde_json::from_value(json!(input.balance)).map_err(|e|e.to_string())?;
                        let integer=json!({"kind":"integer","digits":typed.get().to_string()});
                        if slot["change"]["unit"].is_null(){integer}else{json!({"kind":"quantity","value":integer,"unit":slot["change"]["unit"]})}
                    }else{input.value.build(frame,choices,predicate)?};
                    let id=RecordId::generate(&mut rand::rng());ops.push(json!({"kind":"define_proposition","client_ref":id,"record":{"subject":rr(frame,&owner.1)?,"predicate":slot["target"]["predicate"],"value":value,"context":context,"quantification":"particular"}}));rr(frame,id.as_str())?
                },_=>return Err("Choose a new explicit value or existing proposition for every included effect.".into())};
            let end = match input.end_kind.as_str() {
                "unbounded" => json!({"kind":"unbounded"}),
                "exact" => {
                    if input.end.trim().is_empty() {
                        return Err("Enter the effect's exclusive end.".into());
                    }
                    let end = clock.coordinate(&input.end)?;
                    if end.parse::<i128>().map_err(|e| e.to_string())?
                        <= start.parse::<i128>().map_err(|e| e.to_string())?
                    {
                        return Err("Effect end must follow the event.".into());
                    }
                    json!({"kind":"exact","value":end})
                }
                _ => return Err("Choose each effect's authored end.".into()),
            };
            effects.push(json!({"slot":input.slot,"proposition":prop,"polarity":input.polarity,"scope":scope,"validity":{"kind":"calendar_interval","calendar":clock.calendar,"start":{"kind":"exact","value":start},"end":end},"order":input.order.parse::<usize>().map_err(|_|"Enter the declared effect order.")?}));
        }
        ops.push(json!({"kind":"record_event","client_ref":RecordId::generate(&mut rand::rng()),"record":{"occurrence":self.occurrence,"action":rr(frame,&self.action)?,"time":{"kind":"exact","calendar":clock.calendar,"value":start},"worlds":worlds,"region":if self.region.is_empty(){Value::Null}else{rr(frame,&self.region)?},"participants":participants,"effects":effects,"labels":{"en":self.title}}}));
        ops.into_iter()
            .map(|op| {
                let typed: DomainOperation =
                    serde_json::from_value(op).map_err(|e| e.to_string())?;
                serde_json::to_value(typed).map_err(|e| e.to_string())
            })
            .collect()
    }
}
#[component]
fn EffectControls(
    id: String,
    slot: Value,
    input: EffectForm,
    choices: Vec<Value>,
    disabled: bool,
    onchange: EventHandler<EffectForm>,
) -> Element {
    let predicate = slot["target"]["predicate"]["record"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    rsx! {fieldset{legend{{format!("Effect {} · {} · role {} · order {}",input.slot,slot["presence"].as_str().unwrap_or("unknown"),slot["target"]["role"].as_str().unwrap_or("unknown"),slot["order"])}}
            details{summary{"Declared target, condition, change and lifetime"}super::readable::ReadValue{value:slot.clone()}}
    label{r#for:"{id}-include","Propose this effect"}super::select::RichSelect{id:format!("{id}-include"),disabled,value:input.include.clone(),options:super::select::choices(&[("","Choose explicitly"),("yes","Include this effect"),("no","Omit this effect; validation checks whether it is required")]),onchange:{let v=input.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.include=e.value();onchange.call(v);}}}
    if input.include=="yes"{
    label{r#for:"{id}-source","Effect proposition"}super::select::RichSelect{id:format!("{id}-source"),disabled,value:input.source.clone(),options:super::select::choices(&[("","Choose a source"),("new","Author a new proposition and value"),("existing","Use an existing proposition")]),onchange:{let v=input.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.source=e.value();onchange.call(v);}}}
    if input.source=="existing"{
    label{r#for:"{id}-proposition","Existing effect proposition"}super::select::RichSelect{id:format!("{id}-proposition"),disabled,value:input.proposition.clone(),options:super::select::record_choices(&choices,&["proposition"],"Choose returned proposition"),onchange:{let v=input.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.proposition=e.value();onchange.call(v);}}}
    }
    if input.source=="new"{
    if slot["change"]["kind"]=="delta"{
    p{"Enter the post-event balance from authored facts. No balance is computed or filled in. Quantity values retain the contract’s exact unit."}
    label{r#for:"{id}-balance","Proposed post-event whole-number balance"}input{id:"{id}-balance",disabled,value:input.balance.clone(),oninput:{let v=input.clone();move|e|{let mut v=v.clone();v.balance=e.value();onchange.call(v);}}}
    }else{ValueControls{id:format!("{id}-value"),value:input.value.clone(),predicate,choices:choices.clone(),disabled,onchange:{let v=input.clone();move|value|{let mut v=v.clone();v.value=value;onchange.call(v);}}}}
    }
    label{r#for:"{id}-polarity","Effect evidence"}super::select::RichSelect{id:format!("{id}-polarity"),disabled,value:input.polarity.clone(),options:super::select::choices(&[("","Choose polarity"),("support","Support"),("refutation","Refutation")]),onchange:{let v=input.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.polarity=e.value();onchange.call(v);}}}
    label{r#for:"{id}-end_kind","Effect validity ends"}super::select::RichSelect{id:format!("{id}-end_kind"),disabled,value:input.end_kind.clone(),options:super::select::choices(&[("","Choose explicitly"),("unbounded","Until changed, no scheduled end"),("exact","At an authored exclusive timestamp")]),onchange:{let v=input.clone();move|e:super::select::SelectionEvent|{let mut v=v.clone();v.end_kind=e.value();onchange.call(v);}}}
    if input.end_kind=="exact"{
    label{r#for:"{id}-end","Exclusive end in the event calendar"}input{id:"{id}-end",disabled,value:input.end.clone(),oninput:{let v=input.clone();move|e|{let mut v=v.clone();v.end=e.value();onchange.call(v);}}}
    }
    label{r#for:"{id}-order","Authored effect order (must match the slot)"}input{id:"{id}-order",disabled,value:input.order.clone(),oninput:{let v=input.clone();move|e|{let mut v=v.clone();v.order=e.value();onchange.call(v);}}}
    }
    }}
}
#[component]
pub(super) fn ConsequenceEventEditor(
    frame: Frame,
    clock: Option<Chronology>,
    choices: Vec<Value>,
    disabled: bool,
    onadd: EventHandler<Vec<Value>>,
) -> Element {
    let mut form = use_signal(Form::default);
    let mut error = use_signal(String::new);
    let definition = action(&choices, &form.read().action)
        .cloned()
        .unwrap_or(Value::Null);
    let slots = definition["consequenceContract"]["slots"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    rsx! {details{summary{"Record an event with declared consequences"}
        p{"Choose an action, assign its roles and explicitly propose each effect. Validation checks required effects, authored conditions, exact values, resource balances, scope, validity and order. Plans and reports do not establish objective effects."}
        label{r#for:"event-title","Event name"}input{id:"event-title",disabled,value:form.read().title.clone(),oninput:move|e|form.write().title=e.value()}
        label{r#for:"event-action","Declared action"}super::select::RichSelect{id:"event-action",disabled,value:form.read().action.clone(),options:super::select::record_choices(&choices.iter().filter(|c|c["kind"]=="action_definition"&&!c["definition"]["consequenceContract"].is_null()).cloned().collect::<Vec<_>>(),&["action_definition"],"Choose a contract-bearing action"),onchange:{let choices=choices.clone();move|e:super::select::SelectionEvent|{match form.write().select(e.value(),&choices){Ok(())=>error.set(String::new()),Err(e)=>error.set(e)}}}}
        label{r#for:"event-occurrence","Occurrence"}super::select::RichSelect{id:"event-occurrence",disabled,value:form.read().occurrence.clone(),options:super::select::choices(&[("","Choose occurrence"),("occurred","Occurred"),("planned","Planned"),("reported","Reported"),("hypothetical","Hypothetical"),("predicted","Predicted")]),onchange:move|e:super::select::SelectionEvent|form.write().occurrence=e.value()}
        label{r#for:"event-start","Authored event timestamp"}input{id:"event-start",disabled,value:form.read().start.clone(),oninput:move|e|form.write().start=e.value()}
        label{r#for:"event-context","Represented context (must match the action)"}super::select::RichSelect{id:"event-context",disabled,value:form.read().context.clone(),options:{let mut opts=super::select::record_choices(&choices,&["represented_context"],"Choose context explicitly");if !opts.iter().any(|c|c.value==frame.context.record.as_str()){opts.push(super::select::Choice::new(frame.context.record.to_string(),"Current pinned context"));}opts},onchange:move|e:super::select::SelectionEvent|form.write().context=e.value()}
        label{r#for:"event-scope","Event and effect scope"}super::select::RichSelect{id:"event-scope",disabled,value:form.read().applicability.clone(),options:super::select::choices(&[("","Choose scope"),("universe_wide","Universe wide"),("worlds","Selected worlds")]),onchange:move|e:super::select::SelectionEvent|form.write().applicability=e.value()}
        if form.read().applicability=="worlds"{fieldset{legend{"Event worlds"}for world in choices.iter().filter(|c|c["kind"]=="world").cloned(){label{class:"check-label",input{r#type:"checkbox",disabled,checked:form.read().worlds.contains(&world["record_id"].as_str().unwrap_or_default().replacen("rec_","wld_",1)),onchange:{let id=world["record_id"].as_str().unwrap_or_default().replacen("rec_","wld_",1);move|e|{if e.checked(){form.write().worlds.push(id.clone());}else{form.write().worlds.retain(|w|w!=&id);}}}}{world["label"].as_str().unwrap_or("World").to_string()}}}}}
        label{r#for:"event-region","Region (optional)"}super::select::RichSelect{id:"event-region",disabled,value:form.read().region.clone(),options:super::select::record_choices(&choices,&["entity","realm"],"No region"),onchange:move|e:super::select::SelectionEvent|form.write().region=e.value()}
        fieldset{legend{"Participant roles"}
            for(i,(role,entity))in form.read().roles.clone().into_iter().enumerate(){div{key:"{i}",
                label{r#for:"event-role-{i}","Role"}input{id:"event-role-{i}",disabled,value:role,oninput:move|e|form.write().roles[i].0=e.value()}
                label{r#for:"event-participant-{i}","Entity filling this role"}super::select::RichSelect{id:format!("event-participant-{i}"),disabled,value:entity,options:super::select::record_choices(&choices,&["entity"],"Choose an owning entity"),onchange:move|e:super::select::SelectionEvent|form.write().roles[i].1=e.value()}
                button{class:"secondary",disabled,onclick:move|_|{form.write().roles.remove(i);},"Remove participant role"}
            }}
            button{class:"secondary",disabled,onclick:move|_|form.write().roles.push((String::new(),String::new())),"Add participant role"}
        }
        for(i,input)in form.read().effects.clone().into_iter().enumerate(){EffectControls{key:"{i}",id:format!("event-effect-{i}"),slot:slots.get(i).cloned().unwrap_or(Value::Null),input,choices:choices.clone(),disabled,onchange:move|v|form.write().effects[i]=v}}
        if !error().is_empty(){p{role:"alert","{error}"}}
        button{disabled,onclick:move|_|match form.read().build(&frame,clock.as_ref(),&choices){Ok(ops)=>{onadd.call(ops);error.set(String::new());},Err(e)=>error.set(e)},"Add event and explicit effects to draft"}
    }}
}
#[cfg(test)]
#[path = "consequence_event_tests.rs"]
mod tests;
