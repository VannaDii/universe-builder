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
pub(super) struct EffectForm {
    pub(super) slot: String,
    pub(super) include: String,
    pub(super) source: String,
    pub(super) proposition: String,
    pub(super) value: FixedValue,
    pub(super) balance: String,
    pub(super) polarity: String,
    pub(super) end_kind: String,
    pub(super) end: String,
    pub(super) order: String,
}
#[derive(Clone, Default)]
pub(super) struct Form {
    pub(super) original: Value,
    pub(super) title: String,
    pub(super) action: String,
    pub(super) occurrence: String,
    pub(super) start: String,
    pub(super) context: String,
    pub(super) applicability: String,
    pub(super) worlds: Vec<String>,
    pub(super) region: String,
    pub(super) roles: Vec<(String, String)>,
    pub(super) effects: Vec<EffectForm>,
}
impl Form {
    pub(super) fn load(
        original: Value,
        frame: &Frame,
        clock: Option<&Chronology>,
        choices: &[Value],
    ) -> Result<Self, String> {
        let event = &original["payload"];
        let _: universe_domain::ids::RecordVersionId =
            serde_json::from_value(original["record_version_id"].clone())
                .map_err(|e| e.to_string())?;
        if event["record_kind"] != "event"
            || original["identity"]["universe_id"] != json!(frame.universe)
        {
            return Err("Load an event from this pinned universe.".into());
        }
        let clock = clock.ok_or("The event needs its authored clock.")?;
        if event["time"]["kind"] != "exact" || event["time"]["calendar"] != json!(clock.calendar) {
            return Err("This editor requires the event's exact named calendar; its original fields remain intact.".into());
        }
        let display = |value: &str| {
            if matches!(
                clock.system,
                universe_domain::chronology::ClockSystem::Gregorian { .. }
            ) {
                clock.display(value)
            } else {
                Ok(value.to_string())
            }
        };
        let mut f = Self::default();
        f.select(
            event["action"]["record"]
                .as_str()
                .ok_or("The event's action is unavailable.")?
                .into(),
            choices,
        )?;
        f.title = event["labels"]["en"].as_str().unwrap_or_default().into();
        f.occurrence = event["occurrence"].as_str().unwrap_or("descriptive").into();
        f.start = display(
            event["time"]["value"]
                .as_str()
                .ok_or("Event time unavailable.")?,
        )?;
        f.context = action(choices, &f.action)?["scope"]["context"]["record"]
            .as_str()
            .ok_or("Action context unavailable.")?
            .into();
        f.worlds = event["worlds"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|w| w.as_str().unwrap_or_default().into())
            .collect();
        f.applicability = if f.worlds.is_empty() {
            "universe_wide"
        } else {
            "worlds"
        }
        .into();
        f.region = event["region"]["record"]
            .as_str()
            .unwrap_or_default()
            .into();
        f.roles = event["participants"]
            .as_array()
            .ok_or("Participants unavailable.")?
            .iter()
            .map(|p| {
                Ok((
                    p["role"]
                        .as_str()
                        .ok_or("Participant role unavailable.")?
                        .into(),
                    p["record"]["record"]
                        .as_str()
                        .ok_or("Participant unavailable.")?
                        .into(),
                ))
            })
            .collect::<Result<Vec<_>, String>>()?;
        for input in &mut f.effects {
            if let Some(effect) = event["effects"]
                .as_array()
                .into_iter()
                .flatten()
                .find(|e| e["slot"] == input.slot)
            {
                input.include = "yes".into();
                input.source = "existing".into();
                input.proposition = effect["proposition"]["record"]
                    .as_str()
                    .ok_or("Effect proposition unavailable.")?
                    .into();
                input.polarity = effect["polarity"].as_str().unwrap_or_default().into();
                input.order = effect["order"].to_string();
                if effect["validity"]["kind"] != "calendar_interval"
                    || effect["validity"]["calendar"] != event["time"]["calendar"]
                    || effect["validity"]["start"]["value"] != event["time"]["value"]
                {
                    return Err("Effect validity cannot be represented by these controls; the original event is preserved.".into());
                }
                input.end_kind = effect["validity"]["end"]["kind"]
                    .as_str()
                    .unwrap_or_default()
                    .into();
                input.end = if input.end_kind == "exact" {
                    display(
                        effect["validity"]["end"]["value"]
                            .as_str()
                            .ok_or("Effect end unavailable.")?,
                    )?
                } else {
                    String::new()
                };
            } else {
                input.include = "no".into();
            }
        }
        if event["effects"].as_array().is_some_and(|rows| {
            rows.iter()
                .any(|e| !f.effects.iter().any(|i| e["slot"] == i.slot))
        }) {
            return Err("An event effect is outside the returned contract. Preserve it and retrieve the matching action before editing.".into());
        }
        f.original = original;
        Ok(f)
    }
    pub(super) fn select(&mut self, id: String, choices: &[Value]) -> Result<(), String> {
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
    pub(super) fn build(
        &self,
        frame: &Frame,
        clock: Option<&Chronology>,
        choices: &[Value],
    ) -> Result<Vec<Value>, String> {
        if self.original.is_null() && self.title.trim().is_empty() {
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
        for (role, id) in &self.roles {
            if role.trim().is_empty() {
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
        let mut replacement = json!({"occurrence":self.occurrence,"action":rr(frame,&self.action)?,"time":{"kind":"exact","calendar":clock.calendar,"value":start},"worlds":worlds,"region":if self.region.is_empty(){Value::Null}else{rr(frame,&self.region)?},"participants":participants,"effects":effects,"labels":{"en":self.title}});
        if self.original.is_null() {
            ops.push(json!({"kind":"record_event","client_ref":RecordId::generate(&mut rand::rng()),"record":replacement}));
        } else {
            let mut preserved = self.original["payload"].clone();
            preserved
                .as_object_mut()
                .ok_or("Original event unavailable.")?
                .remove("record_kind");
            for field in [
                "occurrence",
                "action",
                "time",
                "worlds",
                "region",
                "participants",
                "effects",
            ] {
                if field == "occurrence" && self.occurrence == "descriptive" {
                    continue;
                }
                preserved[field] = replacement[field].take();
            }
            if self.title
                != self.original["payload"]["labels"]["en"]
                    .as_str()
                    .unwrap_or_default()
            {
                preserved["labels"]["en"] = json!(self.title);
            }
            // Keep authored effect array order, even when contract slot order differs.
            let old = self.original["payload"]["effects"]
                .as_array()
                .ok_or("Original effects unavailable.")?;
            preserved["effects"]
                .as_array_mut()
                .unwrap()
                .sort_by_key(|e| {
                    old.iter()
                        .position(|o| o["slot"] == e["slot"])
                        .unwrap_or(old.len())
                });
            ops.push(json!({"kind":"revise_event","record":rr(frame,self.original["identity"]["record_id"].as_str().ok_or("Event identity unavailable.")?)?,"expected_version":self.original["record_version_id"],"replacement":preserved}));
        }
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
    #[props(default)] original: Value,
) -> Element {
    let initial = if original.is_null() {
        Ok(Form::default())
    } else {
        Form::load(original.clone(), &frame, clock.as_ref(), &choices)
    };
    let load_error = initial.as_ref().err().cloned().unwrap_or_default();
    let mut form = use_signal(|| initial.unwrap_or_default());
    let mut error = use_signal(String::new);
    let definition = action(&choices, &form.read().action)
        .cloned()
        .unwrap_or(Value::Null);
    let slots = definition["consequenceContract"]["slots"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    rsx! {details{summary{if original.is_null(){"Record an event with declared consequences"}else{"Correct this event and its consequences"}}
        if !original.is_null(){details{summary{"Original event and exact version binding"}super::readable::ReadValue{value:original.clone()}}}
        if !load_error.is_empty(){p{role:"alert","{load_error}"}}
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
        button{disabled:disabled||!load_error.is_empty(),onclick:move|_|match form.read().build(&frame,clock.as_ref(),&choices){Ok(ops)=>{onadd.call(ops);error.set(String::new());},Err(e)=>error.set(e)},if original.is_null(){"Add event and explicit effects to draft"}else{"Add version-bound event correction to draft"}}
    }}
}
#[cfg(test)]
#[path = "consequence_event_tests.rs"]
mod tests;
